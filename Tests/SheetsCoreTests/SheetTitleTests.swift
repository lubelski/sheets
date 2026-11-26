import Testing
@testable import SheetsCore

@Suite struct SheetTitleTests {
    @Test func aTerminalShowsTheTitleItsShellSetInPlaceOfItsName() {
        let pane = Pane(id: "t", kind: .terminal, title: "scratch")
        #expect(SheetTitle(pane: pane, sessionTitle: "vim notes.txt") == SheetTitle(title: "vim notes.txt"))
        #expect(SheetTitle(pane: pane) == SheetTitle(title: "scratch"))
        #expect(SheetTitle(pane: pane, sessionTitle: "  ") == SheetTitle(title: "scratch"))
    }

    @Test func aTerminalNamedByHandKeepsItsName() {
        let pane = Pane(id: "t", kind: .terminal, title: "assistant", isNamedByHand: true)
        #expect(SheetTitle(pane: pane, sessionTitle: "vim notes.txt") == SheetTitle(title: "assistant"))
    }

    @Test func otherPanesShowOnlyTheirName() {
        for kind in [PaneKind.group, .page, .settings] {
            let pane = Pane(id: "p", kind: kind, title: "Something")
            #expect(SheetTitle(pane: pane, sessionTitle: "ignored") == SheetTitle(title: "Something"))
        }
    }

    @Test func settingsSectionsAreTitledByTheirSection() {
        for section in SettingsSection.allCases {
            let pane = SettingsSection.pane.children.first { $0.id == section.paneID }
            #expect(pane.map { SheetTitle(pane: $0).title } == section.title)
        }
    }

    @Test func everyTitleBarIsOneHeight() {
        #expect(SheetTitle.barHeight == 32)
    }
}
