import Foundation
import Testing
@testable import SheetsCore

@MainActor
@Suite struct TerminalSessionStoreTests {
    typealias ID = SamplePanes.ID
    let tree = SamplePanes.tree.addingSettings()
    let engine = FakeTerminalEngine()

    func store(_ engines: [any TerminalEngine]? = nil) -> TerminalSessionStore {
        TerminalSessionStore(engines: TerminalEngineRegistry(engines ?? [engine])) { pane in
            TerminalLaunch(executable: "/bin/zsh", folder: pane.folder ?? "/home/someone", environment: [:])
        }
    }

    func fake(_ store: TerminalSessionStore, _ id: PaneID) -> FakeTerminalSession? {
        store.record(for: id)?.session as? FakeTerminalSession
    }

    // MARK: Starting

    @Test func aSessionStartsWhenItsTerminalIsShownAndNotBefore() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb]))
        #expect(store.records.isEmpty)

        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        #expect(Set(store.records.keys) == [ID.devServer])
        #expect(fake(store, ID.devServer)?.launches.count == 1)
    }

    @Test func aCoveredTerminalHasASessionToo() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer, ID.localhost]))
        #expect(Set(store.records.keys) == [ID.devServer])
    }

    @Test func onlyTerminalsGetSessions() {
        let store = store()
        #expect(store.start(tree.pane(ID.acmeWeb)!) == nil)
        #expect(store.start(tree.pane(ID.localhost)!) == nil)
        #expect(store.start(tree.pane(SettingsSection.settingsID)!) == nil)
        #expect(engine.made.isEmpty)
    }

    @Test func aSessionGetsTheAppearanceBeforeItStarts() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        #expect(fake(store, ID.scratch)?.appearances == [.standard])
    }

    @Test func startingTheShownSessionsEndsNone() {
        let store = store()
        var editor = PaneEditor(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        store.sync(tree: editor.tree, stack: editor.stack)
        editor.close(ID.devServer)
        let added = editor.add(.terminal, near: ID.scratch, homeFolder: "/home/someone")

        // Before the new stack is on screen: the new terminal starts, the closed one stays.
        store.startSessions(shownIn: editor.stack, in: editor.tree)
        #expect(Set(store.records.keys) == [ID.devServer, added!])
        #expect(fake(store, ID.devServer)?.endCount == 0)

        // After: the closed one ends.
        store.endSessions(notIn: editor.tree)
        #expect(Set(store.records.keys) == [added!])
    }

    // MARK: Keeping

    @Test func goingToASiblingAndBackKeepsTheSameSession() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        let first = store.record(for: ID.devServer)

        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.claude]))
        #expect(store.record(for: ID.devServer) === first)
        #expect(fake(store, ID.devServer)?.endCount == 0)

        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        #expect(store.record(for: ID.devServer) === first)
        #expect(engine.made.count == 2)
    }

    @Test func goingBackToTheSidebarKeepsSessions() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        store.sync(tree: tree, stack: SheetStack())
        #expect(fake(store, ID.scratch)?.isRunning == true)
    }

    @Test func movingAPaneKeepsItsSession() {
        let store = store()
        var editor = PaneEditor(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        store.sync(tree: editor.tree, stack: editor.stack)
        let first = store.record(for: ID.devServer)

        let moved = editor.move(ID.devServer, to: PanePlace(parent: nil, index: 0))
        #expect(moved)
        store.sync(tree: editor.tree, stack: editor.stack)
        #expect(store.record(for: ID.devServer) === first)
        #expect(fake(store, ID.devServer)?.endCount == 0)
    }

    @Test func renamingAPaneKeepsItsSession() {
        let store = store()
        var editor = PaneEditor(tree: tree, stack: SheetStack([ID.scratch]))
        store.sync(tree: editor.tree, stack: editor.stack)
        let first = store.record(for: ID.scratch)
        editor.rename(ID.scratch, to: "renamed")
        store.sync(tree: editor.tree, stack: editor.stack)
        #expect(store.record(for: ID.scratch) === first)
    }

    // MARK: Ending

    @Test func closingAPaneEndsItsSession() {
        let store = store()
        var editor = PaneEditor(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        store.sync(tree: editor.tree, stack: editor.stack)
        let session = fake(store, ID.devServer)

        editor.close(ID.devServer)
        store.sync(tree: editor.tree, stack: editor.stack)
        #expect(store.records.isEmpty)
        #expect(session?.endCount == 1)
    }

    @Test func closingAParentEndsTheSessionsUnderIt() {
        let store = store()
        var editor = PaneEditor(tree: tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        store.sync(tree: editor.tree, stack: editor.stack)
        store.sync(tree: editor.tree, stack: SheetStack([ID.acmeWeb, ID.claude]))
        store.sync(tree: editor.tree, stack: SheetStack([ID.scratch]))
        let underGroup = [fake(store, ID.devServer), fake(store, ID.claude)]
        let outside = fake(store, ID.scratch)

        editor.close(ID.acmeWeb)
        store.sync(tree: editor.tree, stack: editor.stack)
        #expect(Set(store.records.keys) == [ID.scratch])
        #expect(underGroup.map { $0?.endCount } == [1, 1])
        #expect(outside?.endCount == 0)
    }

    @Test func quittingEndsEverySession() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        store.sync(tree: tree, stack: SheetStack([ID.acmeWeb, ID.claude]))
        let sessions = engine.made
        store.endAll()
        #expect(store.records.isEmpty)
        #expect(sessions.map(\.endCount) == [1, 1])
    }

    @Test func anEndedSessionSaysNothingMore() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        let session = fake(store, ID.scratch)!
        store.end(ID.scratch)
        #expect(session.events == nil)
        store.end(ID.scratch)
        #expect(session.endCount == 1)
    }

    // MARK: Exiting and starting again

    @Test func aShellThatExitsKeepsItsSessionUntilRestarted() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        let record = store.record(for: ID.scratch)!
        fake(store, ID.scratch)?.emit(.exited(status: 0))
        #expect(record.status == .exited(status: 0))

        // Showing it again does not start it again by itself.
        store.sync(tree: tree, stack: SheetStack())
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        #expect(store.record(for: ID.scratch) === record)
        #expect(engine.made.count == 1)

        let restarted = store.restart(tree.pane(ID.scratch)!)
        #expect(restarted !== record)
        #expect(restarted?.status == .running)
        #expect(engine.made.count == 2)
        #expect(engine.made[0].endCount == 1)
    }

    @Test func aShellEndedByASignalHasNoStatus() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        fake(store, ID.scratch)?.emit(.exited(status: nil))
        #expect(store.record(for: ID.scratch)?.status == .exited(status: nil))
    }

    @Test func aShellThatCannotStartSaysWhy() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        fake(store, ID.scratch)?.emit(.failedToStart("no such file"))
        #expect(store.record(for: ID.scratch)?.status == .failedToStart("no such file"))
        #expect(store.escapeGoesToTerminal(top: ID.scratch) == false)
    }

    @Test func aReplacedSessionCannotChangeTheNewOne() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        let old = fake(store, ID.scratch)!
        let events = old.events
        store.restart(tree.pane(ID.scratch)!)
        events?(.exited(status: 1))
        events?(.titleChanged("old"))
        #expect(store.record(for: ID.scratch)?.status == .running)
        #expect(store.record(for: ID.scratch)?.title == nil)
    }

    // MARK: What the shell reports

    @Test func theShellsTitleAndFolderAreKeptAndThePaneIsNotRenamed() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        let session = fake(store, ID.scratch)
        session?.emit(.titleChanged("vim notes.txt"))
        session?.emit(.folderChanged("/home/someone/projects"))
        let record = store.record(for: ID.scratch)
        #expect(record?.title == "vim notes.txt")
        #expect(record?.folder == "/home/someone/projects")
        #expect(tree.pane(ID.scratch)?.title == "scratch")

        session?.emit(.titleChanged(""))
        #expect(record?.title == nil)
    }

    @Test func aClickedLinkGoesToTheHookWithItsPane() {
        let store = store()
        var clicks: [(PaneID, TerminalLink)] = []
        store.linkClicked = { pane, link, session in
            clicks.append((pane, link))
            session.openWithDefaultHandler(link)
        }
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        let link = TerminalLink(target: "https://example.com/docs")
        fake(store, ID.scratch)?.emit(.linkClicked(link))
        #expect(clicks.map(\.0) == [ID.scratch])
        #expect(clicks.map(\.1) == [link])
        #expect(fake(store, ID.scratch)?.opened == [link])
    }

    @Test func aNewAppearanceReachesEverySession() {
        let store = store()
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        var bigger = TerminalAppearance.standard
        bigger.fontSize = 16
        store.appearance = bigger
        #expect(fake(store, ID.scratch)?.appearances == [.standard, bigger])
        store.appearance = bigger
        #expect(fake(store, ID.scratch)?.appearances.count == 2)
    }

    // MARK: Escape

    @Test func escapeGoesToARunningTerminalOnTop() {
        let store = store()
        #expect(store.escapeGoesToTerminal(top: nil) == false)
        #expect(store.escapeGoesToTerminal(top: ID.scratch) == false)

        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        #expect(store.escapeGoesToTerminal(top: ID.scratch))
        #expect(store.escapeGoesToTerminal(top: ID.acmeWeb) == false)

        fake(store, ID.scratch)?.emit(.exited(status: 0))
        #expect(store.escapeGoesToTerminal(top: ID.scratch) == false)
    }

    // MARK: Engines

    @Test func aPaneRunsInTheEngineItNamesOrElseTheFallback() {
        let other = FakeTerminalEngine(id: "other")
        let store = store([engine, other])
        let named = Pane(id: "named", kind: .terminal, title: "named", engine: "other")
        let unknown = Pane(id: "unknown", kind: .terminal, title: "unknown", engine: "missing")
        let plain = Pane(id: "plain", kind: .terminal, title: "plain")
        #expect(store.start(named)?.engine == "other")
        #expect(store.start(unknown)?.engine == .standard)
        #expect(store.start(plain)?.engine == .standard)
        #expect(other.made.count == 1)
        #expect(engine.made.count == 2)
    }

    @Test func withNoEnginesNothingStarts() {
        let store = store([])
        store.sync(tree: tree, stack: SheetStack([ID.scratch]))
        #expect(store.records.isEmpty)
    }

    @Test func theRegistryFallsBackToTheFirstEngineWhenItsFallbackIsMissing() {
        let other = FakeTerminalEngine(id: "other")
        let registry = TerminalEngineRegistry([other], fallback: .standard)
        #expect(registry.engine(for: nil)?.id == "other")
        #expect(registry.ids == ["other"])
    }

    @Test func anEngineIDIsSavedAsAPlainString() throws {
        let pane = Pane(id: "t", kind: .terminal, title: "t", engine: .swiftTerm)
        let data = try JSONEncoder().encode(pane)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""engine":"swiftterm""#))
        #expect(try JSONDecoder().decode(Pane.self, from: data) == pane)
    }

    @Test func aPaneSavedWithoutAnEngineUsesTheStandardOne() throws {
        // A pane saved before panes had engines has no engine key at all.
        let data = try JSONEncoder().encode(Pane(id: "t", kind: .terminal, title: "t"))
        #expect(String(data: data, encoding: .utf8)?.contains("engine") == false)
        let pane = try JSONDecoder().decode(Pane.self, from: data)
        #expect(pane.engine == nil)
        #expect(TerminalEngineRegistry([engine]).engine(for: pane.engine)?.id == .standard)
    }
}
