import AppKit
import SheetsCore
import Testing
@testable import sheets

/// Every terminal pane the window shows runs a shell in its sheet, however it got there. These
/// drive the model the way the menus, keys, sidebar, and sheets do, with the window drawn
/// offscreen and changes animated as in the app.
@MainActor
@Suite(.serialized) struct TerminalSessionsOnScreenTests {
    typealias ID = SamplePanes.ID

    // MARK: Starting

    @Test func theFirstLaunchTerminalShowsItsShell() throws {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        let first = try #require(window.model.stack.top)
        #expect(window.showsShell(first))
    }

    /// New Terminal from the File menu and Command-T both call `add(.terminal)`.
    @Test func aNewTerminalFromTheMenuShowsItsShell() throws {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        window.model.add(.terminal)
        window.settle()
        let added = try #require(window.model.stack.top)
        #expect(window.model.tree.pane(added)?.kind == .terminal)
        #expect(window.session(added)?.launches.count == 1)
        #expect(window.showsShell(added))
    }

    @Test func aNewTerminalInAGroupShowsItsShell() throws {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.acmeWeb]))
        defer { window.close() }
        window.model.add(.terminal)
        window.settle()
        let added = try #require(window.model.stack.top)
        #expect(window.model.tree.parent(of: added) == ID.acmeWeb)
        #expect(window.showsShell(added))
    }

    /// New Terminal from a row's context menu, and from a group's sheet.
    @Test func aNewTerminalFromAContextMenuShowsItsShell() throws {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack())
        defer { window.close() }
        window.model.add(.terminal, near: ID.claude)
        window.settle()
        let besideClaude = try #require(window.model.stack.top)
        #expect(window.model.tree.parent(of: besideClaude) == ID.acmeWeb)
        #expect(window.showsShell(besideClaude))

        window.model.add(.terminal, near: ID.homelab)
        window.settle()
        let inHomelab = try #require(window.model.stack.top)
        #expect(window.model.tree.parent(of: inHomelab) == ID.homelab)
        #expect(window.showsShell(inHomelab))
    }

    @Test func aNewTerminalOverSettingsShowsItsShell() throws {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        window.model.openSettings()
        window.settle()
        window.model.add(.terminal)
        window.settle()
        let added = try #require(window.model.stack.top)
        #expect(window.showsShell(added))
    }

    @Test func aTerminalShownFromTheSidebarShowsItsShell() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack())
        defer { window.close() }
        window.model.show(ID.scratch)
        window.settle()
        #expect(window.showsShell(ID.scratch))
    }

    @Test func aSiblingSwappedInShowsItsShell() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        defer { window.close() }
        #expect(window.showsShell(ID.devServer))
        window.model.open(ID.claude, from: 1)
        window.settle()
        #expect(window.showsShell(ID.claude))
    }

    @Test func aCoveredTerminalShowsItsShell() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.acmeWeb]))
        defer { window.close() }
        window.model.show(ID.localhost)
        window.settle()
        #expect(window.model.stack.entries == [ID.acmeWeb, ID.devServer, ID.localhost])
        #expect(window.showsShell(ID.devServer))
    }

    @Test func aTerminalOpenedFromACoveredStripShowsItsShell() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        defer { window.close() }
        window.model.clickStrip(at: 1, on: ID.claude)
        window.settle()
        #expect(window.showsShell(ID.claude))
    }

    @Test func everyTerminalShownHasOneSession() {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        let model = window.model
        model.add(.terminal)
        model.add(.group)
        model.cancelRenaming()
        model.add(.terminal)
        model.add(.terminal)
        window.settle()
        model.add(.page)
        model.add(.terminal, near: nil)
        window.settle()

        let terminals = window.terminalIDs
        #expect(terminals.count == 5)
        #expect(window.sessionIDs == Set(terminals))
        #expect(window.engine.made.count == terminals.count)
        #expect(window.engine.made.allSatisfy { $0.launches.count == 1 })
        // Going back to each one shows the shell it already had.
        for id in terminals {
            model.show(id)
            window.settle()
            #expect(window.showsShell(id))
        }
        #expect(window.engine.made.count == terminals.count)
    }

    // MARK: When there is no session

    @Test func withNoEngineATerminalSaysWhyAndStartsNothing() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.scratch]), engines: [])
        defer { window.close() }
        #expect(window.model.terminals?.record(for: ID.scratch) == nil)
        #expect(window.model.whyTerminalHasNoSession(ID.scratch) != nil)
        window.model.restartTerminal(ID.scratch)
        #expect(window.model.terminals?.record(for: ID.scratch) == nil)
    }

    @Test func startTriesAgainForATerminalWithNoSession() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.scratch]))
        defer { window.close() }
        window.model.terminals?.end(ID.scratch)
        window.settle()
        #expect(!window.showsShell(ID.scratch))
        #expect(window.model.whyTerminalHasNoSession(ID.scratch) == nil)

        window.model.restartTerminal(ID.scratch)
        window.settle()
        #expect(window.showsShell(ID.scratch))
    }

    // MARK: Ending

    @Test func closingATerminalEndsItsShell() throws {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        window.model.add(.terminal)
        window.settle()
        let added = try #require(window.model.stack.top)
        let session = try #require(window.session(added))
        window.model.close(added)
        window.settle()
        #expect(session.endCount == 1)
        #expect(window.model.terminals?.record(for: added) == nil)
        #expect(window.model.terminals?.records.count == 1)
    }

    @Test func closingAGroupEndsTheShellsUnderIt() {
        let window = WindowHarness(tree: SamplePanes.tree, stack: SheetStack([ID.acmeWeb, ID.devServer]))
        defer { window.close() }
        window.model.open(ID.claude, from: 1)
        window.model.show(ID.scratch)
        window.settle()
        let under = [window.session(ID.devServer), window.session(ID.claude)]
        let outside = window.session(ID.scratch)
        window.model.close(ID.acmeWeb)
        window.settle()
        #expect(under.map { $0?.endCount } == [1, 1])
        #expect(outside?.endCount == 0)
        #expect(window.sessionIDs == [ID.scratch])
    }

    @Test func quittingEndsEveryShell() {
        let window = WindowHarness.firstLaunch()
        defer { window.close() }
        window.model.add(.terminal)
        window.model.add(.terminal)
        window.settle()
        let sessions = window.engine.made
        #expect(sessions.count == 3)
        window.model.endTerminalsOnQuit()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        #expect(sessions.map(\.endCount) == [1, 1, 1])
        #expect(window.model.terminals?.records.isEmpty == true)
    }
}
