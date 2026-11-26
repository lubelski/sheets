import Testing
@testable import SheetsCore

@Suite struct SheetTitleTests {
    @Test func keepsADetailThatSaysSomethingMore() {
        let title = SheetTitle(title: "dev server", detail: "npm run dev")
        #expect(title.title == "dev server")
        #expect(title.detail == "npm run dev")
    }

    @Test func dropsAnEmptyOrRepeatedDetail() {
        #expect(SheetTitle(title: "dev server").detail == nil)
        #expect(SheetTitle(title: "dev server", detail: "").detail == nil)
        #expect(SheetTitle(title: "dev server", detail: "dev server").detail == nil)
    }

    @Test func aTerminalShowsTheTitleItsShellSet() {
        let pane = Pane(id: "t", kind: .terminal, title: "scratch")
        #expect(SheetTitle(pane: pane, shellTitle: "vim notes.txt") == SheetTitle(title: "scratch", detail: "vim notes.txt"))
        #expect(SheetTitle(pane: pane).detail == nil)
    }

    @Test func otherPanesShowOnlyTheirName() {
        for kind in [PaneKind.group, .page, .settings] {
            let pane = Pane(id: "p", kind: kind, title: "Something")
            #expect(SheetTitle(pane: pane, shellTitle: "ignored") == SheetTitle(title: "Something"))
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
