import Foundation
import Testing
@testable import SheetsCore

@Suite struct SettingsTests {
    typealias ID = SamplePanes.ID

    /// A throwaway defaults suite, empty to start with.
    private func freshDefaults() -> UserDefaults {
        let name = "SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func debuggingIsAlwaysLastAndExperimentsSecondToLast() {
        let sections = SettingsSection.allCases
        #expect(sections.first == .general)
        #expect(sections.last == .debugging)
        #expect(sections.dropLast().last == .experiments)
    }

    @Test func settingsIsAPaneWithASectionChildEach() {
        let pane = SettingsSection.pane
        #expect(pane.id == SettingsSection.settingsID)
        #expect(pane.kind == .settings)
        #expect(pane.children.map(\.id) == SettingsSection.allCases.map(\.paneID))
        #expect(pane.children.allSatisfy { $0.kind == .settings })
        for section in SettingsSection.allCases {
            #expect(SettingsSection(paneID: section.paneID) == section)
        }
        #expect(SettingsSection(paneID: SettingsSection.settingsID) == nil)
        #expect(SettingsSection(paneID: ID.acmeWeb) == nil)
    }

    @Test func addingSettingsPutsItLastOnce() {
        let tree = SamplePanes.tree.addingSettings()
        #expect(tree.roots.last?.id == SettingsSection.settingsID)
        #expect(tree.roots.count == SamplePanes.tree.roots.count + 1)
        #expect(tree.addingSettings() == tree)
        #expect(tree.path(to: SettingsSection.debugging.paneID) == [SettingsSection.settingsID, SettingsSection.debugging.paneID])
    }

    @Test func theSidebarPinsSettingsApartFromTheTree() {
        let tree = SamplePanes.tree.addingSettings()
        #expect(tree.sidebarRows().map(\.id) == SamplePanes.tree.sidebarRows().map(\.id))
        #expect(!tree.sidebarRows().contains { $0.kind == .settings })
        #expect(tree.pinnedRows().map(\.id) == [SettingsSection.settingsID])
        #expect(SamplePanes.tree.pinnedRows().isEmpty)
    }

    @Test func settingsOpensOverTheSidebarWithNoSectionTheFirstTime() {
        let memory = SettingsSectionMemory(defaults: freshDefaults())
        #expect(memory.section == nil)
        let stack = memory.stack(openingSettingsFrom: SheetStack([ID.acmeWeb, ID.devServer]))
        #expect(stack.entries == [SettingsSection.settingsID])
    }

    @Test func settingsReopensToTheLastSection() {
        let memory = SettingsSectionMemory(defaults: freshDefaults())
        memory.note(SheetStack([SettingsSection.settingsID, SettingsSection.debugging.paneID]))
        #expect(memory.section == .debugging)

        // Leaving Settings keeps it.
        memory.note(SheetStack([ID.acmeWeb]))
        memory.note(SheetStack())
        #expect(memory.section == .debugging)
        #expect(memory.stack(openingSettingsFrom: SheetStack([ID.acmeWeb])).entries
            == [SettingsSection.settingsID, SettingsSection.debugging.paneID])
    }

    @Test func closingTheSectionForgetsIt() {
        let memory = SettingsSectionMemory(defaults: freshDefaults())
        memory.note(SheetStack([SettingsSection.settingsID, SettingsSection.general.paneID]))
        memory.note(SheetStack([SettingsSection.settingsID]))
        #expect(memory.section == nil)
    }

    @Test func openingSettingsWhileItIsOpenChangesNothing() {
        let memory = SettingsSectionMemory(defaults: freshDefaults())
        memory.note(SheetStack([SettingsSection.settingsID, SettingsSection.general.paneID]))
        let open = SheetStack([SettingsSection.settingsID])
        #expect(memory.stack(openingSettingsFrom: open) == open)
    }

    @Test func anUnknownRememberedSectionCountsAsNone() {
        let defaults = freshDefaults()
        defaults.set("no-such-section", forKey: SettingsSectionMemory.key)
        #expect(SettingsSectionMemory(defaults: defaults).section == nil)
    }

    @Test func experimentsAreOffUntilTurnedOn() {
        let defaults = freshDefaults()
        #expect(Experiment.allCases == [.dragToMove])
        #expect(Experiment.allCases.allSatisfy { !$0.isOn(in: defaults) })
        defaults.set(true, forKey: Experiment.dragToMove.key)
        #expect(Experiment.dragToMove.isOn(in: defaults))
        #expect(Set(Experiment.allCases.map(\.key)).count == Experiment.allCases.count)
    }

    @Test func signingIsDescribedInWords() {
        #expect(BuildInfo.describeSigning(isSigned: false, isAdHoc: false, teamID: nil) == "Not signed")
        #expect(BuildInfo.describeSigning(isSigned: true, isAdHoc: true, teamID: nil) == "Signed ad hoc")
        #expect(BuildInfo.describeSigning(isSigned: true, isAdHoc: false, teamID: "TEAM123456") == "Signed by team TEAM123456")
        #expect(BuildInfo.describeSigning(isSigned: true, isAdHoc: false, teamID: nil) == "Signed")
    }

    @Test func buildInfoReadsTheCommitKeyThatBundleWrites() {
        // scripts/bundle.sh writes this key. A bundle without an Info.plist reads as unknown.
        #expect(BuildInfo.commitKey == "SheetsGitCommit")
        let info = BuildInfo.current(bundle: Bundle(url: URL(fileURLWithPath: NSTemporaryDirectory()))!)
        #expect(info.commit == "unknown")
        #expect(info.version == "unknown")
    }
}

@Suite struct PaneSummaryTests {
    typealias ID = SamplePanes.ID

    @Test func summariesSayWhatAPaneIsAndHoldsInWords() {
        let tree = SamplePanes.tree
        #expect(tree.pane(ID.acmeWeb)?.summary == "2 panes")
        #expect(tree.pane(ID.acmeAPI)?.summary == "Empty")
        #expect(tree.pane(ID.devServer)?.summary == "Terminal · 1 page")
        #expect(tree.pane(ID.claude)?.summary == "Terminal")
        #expect(tree.pane(ID.localhost)?.summary == "Page")
        #expect(SettingsSection.pane.summary == "3 sections")
        #expect(SettingsSection.pane.children[0].summary == SettingsSection.general.summary)
    }

    @Test func aTerminalWithMixedChildrenCountsPanes() {
        let pane = Pane(id: "t", kind: .terminal, title: "t", children: [
            Pane(id: "p", kind: .page, title: "p"), Pane(id: "q", kind: .terminal, title: "q"),
        ])
        #expect(pane.summary == "Terminal · 2 panes")
    }

    @Test func sidebarRowsCarryTheSummary() {
        let rows = SamplePanes.tree.sidebarRows()
        #expect(rows.first { $0.id == ID.acmeWeb }?.summary == "2 panes")
    }
}
