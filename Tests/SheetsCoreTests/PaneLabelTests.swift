import Foundation
import Observation
import Testing
@testable import SheetsCore

@Suite struct PaneLabelTests {
    typealias ID = SamplePanes.ID
    let home = "/home/someone"

    // MARK: The title

    @Test func aTerminalIsTitledByWhatItsShellSet() {
        let pane = Pane(id: "t", kind: .terminal, title: "dev server", folder: home)
        #expect(PaneLabel(pane: pane, sessionTitle: "npm run dev", folder: home, home: home).title == "npm run dev")
    }

    @Test func aTerminalWithNoTitleFromItsShellShowsItsName() {
        let pane = Pane(id: "t", kind: .terminal, title: "dev server", folder: home)
        #expect(PaneLabel(pane: pane, folder: home, home: home).title == "dev server")
        #expect(PaneLabel(pane: pane, sessionTitle: "", folder: home, home: home).title == "dev server")
        #expect(PaneLabel(pane: pane, sessionTitle: " \n", folder: home, home: home).title == "dev server")
    }

    @Test func aNameTypedByHandWinsOverTheShellsTitle() {
        let pane = Pane(id: "t", kind: .terminal, title: "assistant", folder: home, isNamedByHand: true)
        #expect(PaneLabel(pane: pane, sessionTitle: "npm run dev", folder: home, home: home).title == "assistant")
    }

    @Test func otherPanesKeepTheirNameAndSummary() {
        for id in [ID.acmeWeb, ID.acmeAPI, ID.localhost] {
            let pane = SamplePanes.tree.pane(id)!
            let label = PaneLabel(pane: pane, sessionTitle: "ignored", folder: "/somewhere", home: home)
            #expect(label == PaneLabel(title: pane.title, subtitle: pane.summary))
            #expect(label.folder == nil)
        }
        let settings = SettingsSection.pane
        #expect(PaneLabel(pane: settings, sessionTitle: "ignored", home: home).subtitle == settings.summary)
    }

    // MARK: The second line

    @Test func aTerminalsSecondLineIsItsFolder() {
        let pane = Pane(id: "t", kind: .terminal, title: "t")
        let label = PaneLabel(pane: pane, folder: home + "/dev/acme-web", home: home)
        #expect(label.subtitle == "~/dev/acme-web")
        #expect(label.folder == "~/dev/acme-web")
        #expect(label.folderDetail == nil)
    }

    @Test func aTerminalsChildrenAreCountedAfterItsFolder() {
        let pane = SamplePanes.tree.pane(ID.devServer)!
        let label = PaneLabel(pane: pane, folder: home + "/dev/acme-web", home: home)
        #expect(label.subtitle == "~/dev/acme-web · 1 page")
        #expect(label.folder == "~/dev/acme-web")
        #expect(label.folderDetail == "1 page")
    }

    @Test func aTerminalWithNoFolderKeepsItsSummary() {
        let pane = SamplePanes.tree.pane(ID.devServer)!
        for folder in [nil, ""] as [String?] {
            let label = PaneLabel(pane: pane, folder: folder, home: home)
            #expect(label.subtitle == "Terminal · 1 page")
            #expect(label.folder == nil)
        }
    }

    @Test func theHomeFolderIsWrittenAsATilde() {
        #expect(PaneLabel.shortened(home, home: home) == "~")
        #expect(PaneLabel.shortened(home + "/", home: home) == "~")
        #expect(PaneLabel.shortened(home + "/dev/acme-web/", home: home + "/") == "~/dev/acme-web")
        // Only a whole folder name matches the home folder.
        #expect(PaneLabel.shortened("/home/someone-else/dev", home: home) == "/home/someone-else/dev")
        #expect(PaneLabel.shortened("/usr/local/bin", home: home) == "/usr/local/bin")
        #expect(PaneLabel.shortened("/", home: home) == "/")
        // A home folder of `/` would make every path start with `~`, so it is left alone.
        #expect(PaneLabel.shortened("/usr", home: "/") == "/usr")
    }
}

@MainActor
@Suite struct PaneLabelFromSessionsTests {
    typealias ID = SamplePanes.ID
    let tree = SamplePanes.tree
    let home = SamplePanes.home

    func store() -> TerminalSessionStore {
        TerminalSessionStore(engines: TerminalEngineRegistry([FakeTerminalEngine()])) { pane in
            // As the real launch does when a pane has no folder: the home folder.
            TerminalLaunch(executable: "/bin/zsh", folder: pane.folder ?? SamplePanes.home, environment: [:])
        }
    }

    @Test func beforeItsSessionStartsATerminalShowsItsNameAndOwnFolder() {
        let label = store().label(for: tree.pane(ID.claude)!, home: home)
        #expect(label == PaneLabel(pane: tree.pane(ID.claude)!, folder: home + "/dev/acme-web", home: home))
        #expect(label.title == "claude")
        #expect(label.subtitle == "~/dev/acme-web")
    }

    @Test func aStartedTerminalShowsTheFolderItWasLaunchedIn() {
        let store = store()
        let pane = Pane(id: "t", kind: .terminal, title: "~")
        store.start(pane)
        // The pane has no folder of its own. Its session started in the home folder.
        #expect(store.label(for: pane, home: home).subtitle == "~")
    }

    @Test func whatTheShellReportsShowsAndFollowsChanges() {
        let store = store()
        let pane = tree.pane(ID.devServer)!
        let session = store.start(pane)!.session
        session.events?(.titleChanged("npm run dev"))
        session.events?(.folderChanged(home + "/dev/acme-web/packages/storefront"))
        var label = store.label(for: pane, home: home)
        #expect(label.title == "npm run dev")
        #expect(label.subtitle == "~/dev/acme-web/packages/storefront · 1 page")

        session.events?(.titleChanged(""))
        session.events?(.folderChanged(nil))
        label = store.label(for: pane, home: home)
        #expect(label.title == "dev server")
        #expect(label.subtitle == "~/dev/acme-web · 1 page")
    }

    @Test func aTerminalNamedByHandShowsItsNameButStillItsFolder() {
        let store = store()
        var tree = tree
        tree.rename(ID.claude, to: "assistant")
        let pane = tree.pane(ID.claude)!
        let session = store.start(pane)!.session
        session.events?(.titleChanged("vim notes.txt"))
        session.events?(.folderChanged(home + "/notes"))
        let label = store.label(for: pane, home: home)
        #expect(label.title == "assistant")
        #expect(label.subtitle == "~/notes")
    }

    @Test func readingALabelObservesTheSession() {
        let store = store()
        let pane = tree.pane(ID.scratch)!
        let session = store.start(pane)!.session
        for event in [TerminalEvent.titleChanged("top"), .folderChanged("/tmp")] {
            let changes = Counter()
            withObservationTracking {
                _ = store.label(for: pane, home: home)
            } onChange: {
                changes.increment()
            }
            session.events?(event)
            #expect(changes.value == 1)
        }
    }
}

/// Counts calls from an observation's change handler.
private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() { value += 1 }
}
