import Foundation
import Testing
@testable import SheetsCore

@MainActor
@Suite(.serialized) struct ConfigStoreTests {
    /// A folder of its own for each test, removed afterward by the caller.
    func makeFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "ConfigStoreTests-\(UUID().uuidString)")
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Waits up to a few seconds for a condition, letting the main queue run.
    func wait(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<120 where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    @Test func aMissingFileIsDefaultsAndIsNotMadeUntilASettingChanges() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "sheets/config")
        let store = ConfigStore(path: file.path, watches: false)
        #expect(store.config == .defaults)
        #expect(store.issues.isEmpty)
        #expect(!store.fileExists)
        #expect(store.fileError == nil)
        try store.remove(ConfigKeys.fontSize)
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        try store.set(ConfigKeys.fontSize, to: .integer(14))
        #expect(store.fileExists)
        #expect(try read(file) == "terminal.font-size = 14\n")
        #expect(store.config.number(ConfigKeys.fontSize) == 14)
    }

    @Test func setAndRemoveChangeOnlyThatLine() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "config")
        let original = "# mine\nterminal.font-size = 12 # small\nsomething.else = 1\n"
        try original.write(to: file, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: file.path, watches: false)
        #expect(store.issues.map(\.line) == [3])

        try store.set(ConfigKeys.fontSize, to: .integer(16))
        #expect(try read(file) == "# mine\nterminal.font-size = 16 # small\nsomething.else = 1\n")
        try store.set(ConfigKeys.bell, to: .string("none"))
        try store.remove(ConfigKeys.fontSize)
        #expect(try read(file) == "# mine\nsomething.else = 1\nterminal.bell = \"none\"\n")
        #expect(store.config.terminalBehavior.bell == .none)
        #expect(store.config.number(ConfigKeys.fontSize) == 12)
    }

    @Test func aValueTheKeyDoesNotTakeIsRefusedAndNotWritten() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigStore(path: folder.appending(path: "config").path, watches: false)
        #expect(throws: ConfigStoreError.notAllowed(key: "terminal.font-size", expected: "a number from 6 to 72")) {
            try store.set(ConfigKeys.fontSize, to: .integer(500))
        }
        #expect(!store.fileExists)
    }

    @Test func theAppsOwnWriteIsAppliedOnceAndReadingItBackChangesNothing() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ConfigStore(path: folder.appending(path: "config").path, watches: false)
        var changes: [Config] = []
        store.changed = { _, new in changes.append(new) }
        try store.set(ConfigKeys.cursorBlink, to: .bool(false))
        #expect(changes.count == 1)
        store.reload()
        store.reload()
        #expect(changes.count == 1)
    }

    @Test func aBadEditKeepsTheLastGoodValue() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "config")
        try "terminal.font-size = 15\n".write(to: file, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: file.path, watches: false)
        try "terminal.font-size = 15pt\n".write(to: file, atomically: true, encoding: .utf8)
        store.reload()
        #expect(store.config.number(ConfigKeys.fontSize) == 15)
        #expect(store.issues.map(\.line) == [1])
        try FileManager.default.removeItem(at: file)
        store.reload()
        #expect(store.config == .defaults)
        #expect(store.issues.isEmpty)
        #expect(!store.fileExists)
    }

    @Test func anEditFromOutsideIsReadWhileWatching() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "config")
        try "terminal.font-size = 13\n".write(to: file, atomically: false, encoding: .utf8)
        let store = ConfigStore(path: file.path)

        // Written in place.
        try "terminal.font-size = 14\n".write(to: file, atomically: false, encoding: .utf8)
        #expect(try await wait { store.config.number(ConfigKeys.fontSize) == 14 })

        // Saved the way many editors do: a new file renamed over the old one.
        let temporary = folder.appending(path: "config.tmp")
        try "terminal.font-size = 15\n".write(to: temporary, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temporary)
        #expect(try await wait { store.config.number(ConfigKeys.fontSize) == 15 })

        // And again, to show the watch moved to the new file.
        try "terminal.font-size = 16\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await wait { store.config.number(ConfigKeys.fontSize) == 16 })
    }

    @Test func aFileMadeLaterInAFolderMadeLaterIsSeen() async throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "sheets/config")
        let store = ConfigStore(path: file.path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(300))
        try "terminal.bell = \"none\"\n".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await wait { store.config.terminalBehavior.bell == TerminalBell.none })
    }

    @Test func createIfMissingWritesTheReferenceOnce() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "config")
        let store = ConfigStore(path: file.path, watches: false)
        try store.createIfMissing()
        #expect(try read(file) == ConfigReference.sampleFile())
        #expect(store.config == .defaults)
        try store.set(ConfigKeys.fontSize, to: .integer(13))
        try store.createIfMissing()
        #expect(try read(file).hasSuffix("terminal.font-size = 13\n"))
    }

    @Test func aLinkedFileStaysALink() throws {
        let folder = makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: "kept-elsewhere")
        try "# linked\n".write(to: target, atomically: true, encoding: .utf8)
        let link = folder.appending(path: "config")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = ConfigStore(path: link.path, watches: false)
        try store.set(ConfigKeys.fontSize, to: .integer(13))
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try read(target) == "# linked\nterminal.font-size = 13\n")
    }
}
