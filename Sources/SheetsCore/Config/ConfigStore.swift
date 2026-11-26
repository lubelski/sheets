import Foundation
import Observation

/// The config file on disk: the settings it holds, its issues, and the one way the app
/// changes it.
///
/// - It reads the file when made. A missing file is every key at its default, with no issue,
///   and is not made until a setting is first changed.
/// - While it watches, a change to the file from anywhere is read again after a short pause,
///   so a burst of writes is read once. It watches the file and its folder, so an editor that
///   saves by writing a new file and renaming it over the old one is seen too.
/// - `set` and `remove` change only that key's line (see `ConfigEditor`), write the file
///   atomically, and apply the change at once. Reading the file back afterward finds the same
///   text and changes nothing, so the app's own writes do not flicker or loop.
@MainActor
@Observable
public final class ConfigStore {
    /// The config file's path.
    public let path: String
    /// The path as Settings shows it.
    public var displayPath: String
    public private(set) var config: Config
    public private(set) var issues: [ConfigIssue]
    /// True when the file exists.
    public private(set) var fileExists: Bool
    /// What went wrong the last time the file could not be read or written, if it was the
    /// last thing that happened.
    public private(set) var fileError: String?

    /// Called after the settings in effect change, with the old and the new.
    @ObservationIgnored public var changed: ((Config, Config) -> Void)?

    /// The text last read or written, or nil when there was no file.
    @ObservationIgnored private var text: String?
    @ObservationIgnored private var watcher: ConfigFileWatcher?

    /// Reads the file at a path. With `watches`, it reads it again whenever it changes.
    public init(path: String, displayPath: String? = nil, watches: Bool = true) {
        self.path = path
        self.displayPath = displayPath ?? ConfigFileLocation.displayPath(path, home: NSHomeDirectory())
        self.config = .defaults
        self.issues = []
        self.fileExists = false
        reload()
        if watches {
            watcher = ConfigFileWatcher(path: path) { [weak self] in self?.reload() }
        }
    }

    /// Reads the file again, if its text changed since it was last read or written.
    public func reload() {
        let url = URL(filePath: path)
        let newText: String?
        do {
            newText = try String(contentsOf: url, encoding: .utf8)
            fileError = nil
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            newText = nil
            fileError = nil
        } catch {
            // Keep what was read last. The file may be half written, or not text.
            fileError = "Could not read the file: \(error.localizedDescription)"
            return
        }
        guard newText != text else { return }
        apply(newText)
    }

    /// Sets a key to a value in the file. Throws when the value is not allowed for the key, or
    /// the file cannot be written.
    public func set(_ definition: ConfigKeyDefinition, to value: ConfigValue) throws {
        if case .failure(let problem) = definition.check(value) {
            throw ConfigStoreError.notAllowed(key: definition.key, expected: problem.expected)
        }
        try write(ConfigEditor.setting(definition.key, to: value, in: text ?? ""))
    }

    /// Removes a key's lines from the file, so it goes back to its default.
    public func remove(_ definition: ConfigKeyDefinition) throws {
        guard let text else { return }
        let new = ConfigEditor.removing(definition.key, from: text)
        guard new != text else { return }
        try write(new)
    }

    /// Makes the file with the reference in it, every key commented out at its default, when it
    /// does not exist. For opening it in an editor.
    public func createIfMissing() throws {
        guard text == nil, !FileManager.default.fileExists(atPath: path) else { return }
        try write(ConfigReference.sampleFile())
    }

    private func write(_ new: String) throws {
        // Write through a symbolic link to the file it points to, so a config file kept with
        // other dotfiles stays a link.
        let url = URL(filePath: path).resolvingSymlinksInPath()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(new.utf8).write(to: url, options: .atomic)
            fileError = nil
        } catch {
            fileError = "Could not write the file: \(error.localizedDescription)"
            throw ConfigStoreError.couldNotWrite(error.localizedDescription)
        }
        apply(new)
    }

    private func apply(_ newText: String?) {
        text = newText
        fileExists = newText != nil
        let loaded = Config.load(newText ?? "", previous: config)
        if loaded.issues != issues { issues = loaded.issues }
        guard loaded.config != config else { return }
        let old = config
        config = loaded.config
        changed?(old, loaded.config)
    }
}

public enum ConfigStoreError: Error, LocalizedError, Equatable {
    case notAllowed(key: String, expected: String)
    case couldNotWrite(String)

    public var errorDescription: String? {
        switch self {
        case .notAllowed(let key, let expected): "\(key) must be \(expected)."
        case .couldNotWrite(let reason): "Could not write the config file: \(reason)"
        }
    }
}

/// Watches a file and its folder, and calls back on the main queue a short while after either
/// changes. When the folder does not exist yet, it watches the nearest folder above it that
/// does, and moves down as folders appear.
@MainActor
final class ConfigFileWatcher {
    private let path: String
    private let changed: @MainActor () -> Void
    private let delay: Duration
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    init(path: String, delay: Duration = .milliseconds(150), changed: @escaping @MainActor () -> Void) {
        self.path = path
        self.delay = delay
        self.changed = changed
        arm()
    }

    isolated deinit {
        stop()
    }

    func stop() {
        pending?.cancel()
        for source in sources { source.cancel() }
        sources = []
    }

    /// Watches the file, if it is there, and the nearest folder that holds it.
    private func arm() {
        stop()
        var folder = (path as NSString).deletingLastPathComponent
        while !folder.isEmpty, folder != "/", !FileManager.default.fileExists(atPath: folder) {
            folder = (folder as NSString).deletingLastPathComponent
        }
        watch(path, events: [.write, .extend, .delete, .rename, .revoke, .attrib])
        watch(folder.isEmpty ? "/" : folder, events: [.write, .delete, .rename, .revoke])
    }

    private func watch(_ path: String, events: DispatchSource.FileSystemEvent) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        sources.append(source)
    }

    /// Reads after a pause, so a burst of changes is read once. The file is watched again
    /// first, since an editor that replaces the file leaves the old watch on a file that is
    /// gone.
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.arm()
                self.changed()
            }
        }
        pending = item
        let nanoseconds = delay.components.seconds * 1_000_000_000 + delay.components.attoseconds / 1_000_000_000
        DispatchQueue.main.asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds)), execute: item)
    }
}
