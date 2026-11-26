import Testing
@testable import SheetsCore

@Suite struct SheetStackChangeTests {
    typealias ID = SamplePanes.ID
    let tree = SamplePanes.tree.addingSettings()
    let settings = SettingsSection.settingsID
    let general = SettingsSection.general.paneID
    let experiments = SettingsSection.experiments.paneID
    let debugging = SettingsSection.debugging.paneID

    func change(_ old: [PaneID], _ new: [PaneID]) -> SheetStackChange {
        SheetStackChange(from: SheetStack(old), to: SheetStack(new), in: tree)
    }

    @Test func noChangeIsNone() {
        #expect(change([ID.acmeWeb], [ID.acmeWeb]) == .none)
        #expect(change([], []) == .none)
    }

    @Test func sheetsOpeningOverTheOnesShowingIsAnOpen() {
        #expect(change([], [ID.acmeWeb]) == .open)
        #expect(change([ID.acmeWeb], [ID.acmeWeb, ID.devServer, ID.localhost]) == .open)
        #expect(change([settings], [settings, general]) == .open)
    }

    @Test func sheetsClosingOffTheTopIsABack() {
        #expect(change([ID.acmeWeb, ID.devServer], [ID.acmeWeb]) == .back)
        #expect(change([ID.acmeWeb, ID.devServer, ID.localhost], []) == .back)
    }

    @Test func aLowerSiblingComesInFromBelow() {
        #expect(change([settings, general], [settings, experiments]) == .swap(depth: 2, direction: .fromBelow))
        #expect(change([settings, general], [settings, debugging]) == .swap(depth: 2, direction: .fromBelow))
        #expect(change([ID.acmeWeb, ID.devServer], [ID.acmeWeb, ID.claude]) == .swap(depth: 2, direction: .fromBelow))
    }

    @Test func aHigherSiblingComesInFromAbove() {
        #expect(change([settings, debugging], [settings, general]) == .swap(depth: 2, direction: .fromAbove))
        #expect(change([ID.acmeWeb, ID.claude], [ID.acmeWeb, ID.devServer]) == .swap(depth: 2, direction: .fromAbove))
    }

    @Test func topLevelPanesAreSiblingsInSidebarOrder() {
        // Settings is added at the end of the top level, as the sidebar pins it at the foot.
        #expect(change([ID.acmeWeb], [ID.homelab]) == .swap(depth: 1, direction: .fromBelow))
        #expect(change([ID.scratch], [ID.acmeAPI]) == .swap(depth: 1, direction: .fromAbove))
        #expect(change([ID.scratch], [settings]) == .swap(depth: 1, direction: .fromBelow))
    }

    @Test func aSwapUnderDeeperSheetsDropsThem() {
        // dev server had a page open over it. Picking claude from the group's strip swaps the
        // terminal and closes the page.
        var stack = SheetStack([ID.acmeWeb, ID.devServer, ID.localhost])
        let old = stack
        stack.clickStrip(at: 1, on: ID.claude)
        #expect(stack.entries == [ID.acmeWeb, ID.claude])
        #expect(SheetStackChange(from: old, to: stack, in: tree) == .swap(depth: 2, direction: .fromBelow))
    }

    @Test func aSwapCanOpenNewSheetsAboveIt() {
        // From the sidebar: the page under acme-web replaces the group homelab.
        let old = SheetStack([ID.homelab])
        let new = SheetStack(showing: ID.localhost, in: tree)!
        #expect(SheetStackChange(from: old, to: new, in: tree) == .swap(depth: 1, direction: .fromAbove))
    }

    @Test func aPaneMissingFromTheTreeOnlyFades() {
        #expect(change([ID.acmeWeb], ["missing"]) == .swap(depth: 1, direction: .inPlace))
        #expect(change(["gone", "gone/a"], ["gone", "gone/b"]) == .swap(depth: 2, direction: .inPlace))
    }

    @Test func swapDepthAndDirectionAreOnlyForASwap() {
        let swap = SheetStackChange.swap(depth: 2, direction: .fromAbove)
        #expect(swap.swapDepth == 2)
        #expect(swap.swapDirection == .fromAbove)
        for other in [SheetStackChange.none, .open, .back] {
            #expect(other.swapDepth == nil)
            #expect(other.swapDirection == nil)
        }
    }

    @Test func newContentFromBelowStartsLowAndTheOldLeavesUpward() {
        #expect(SheetSwapDirection.fromBelow.offset(entering: true, distance: 10) == 10)
        #expect(SheetSwapDirection.fromBelow.offset(entering: false, distance: 10) == -10)
        #expect(SheetSwapDirection.fromAbove.offset(entering: true, distance: 10) == -10)
        #expect(SheetSwapDirection.fromAbove.offset(entering: false, distance: 10) == 10)
        #expect(SheetSwapDirection.inPlace.offset(entering: true) == 0)
        #expect(SheetSwapDirection.inPlace.offset(entering: false) == 0)
    }

    @Test func aSwapIsQuickerAndSmallerThanASlide() {
        #expect(SheetMotion.swapDuration < SheetMotion.slideDuration)
        #expect((8...12).contains(SheetMotion.swapDistance))
        #expect((0.15...0.2).contains(SheetMotion.swapDuration))
    }
}
