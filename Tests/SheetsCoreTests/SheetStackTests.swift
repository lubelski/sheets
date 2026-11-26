import CoreGraphics
import Testing
@testable import SheetsCore

@Suite struct SheetStackTests {
    typealias ID = SamplePanes.ID

    @Test func startsAtTheSidebar() {
        let stack = SheetStack()
        #expect(stack.depth == 0)
        #expect(stack.isAtSidebar)
        #expect(stack.top == nil)
        #expect(stack.entry(at: 0) == nil)
    }

    @Test func showingAPaneStacksEveryPaneAboveIt() {
        let stack = SheetStack(showing: ID.localhost, in: SamplePanes.tree)
        #expect(stack?.entries == [ID.acmeWeb, ID.devServer, ID.localhost])
        #expect(stack?.top == ID.localhost)
        #expect(SheetStack(showing: "missing", in: SamplePanes.tree) == nil)
    }

    @Test func openPushesOverTheTop() {
        var stack = SheetStack()
        stack.open(ID.acmeWeb)
        stack.open(ID.devServer)
        #expect(stack.entries == [ID.acmeWeb, ID.devServer])
        #expect(stack.depth == 2)
        #expect(stack.entry(at: 1) == ID.acmeWeb)
        #expect(stack.entry(at: 2) == ID.devServer)
        #expect(stack.entry(at: 3) == nil)
    }

    @Test func openFromACoveredSheetReplacesEverythingAboveIt() {
        var stack = SheetStack([ID.acmeWeb, ID.devServer, ID.localhost])
        stack.open(ID.claude, from: 1)
        #expect(stack.entries == [ID.acmeWeb, ID.claude])

        // From the sidebar, it starts a new path.
        stack.open(ID.scratch, from: 0)
        #expect(stack.entries == [ID.scratch])
    }

    @Test func goBackClosesTheTopSheet() {
        var stack = SheetStack([ID.acmeWeb, ID.devServer])
        let closedFirst = stack.goBack()
        #expect(closedFirst)
        #expect(stack.entries == [ID.acmeWeb])
        let closedSecond = stack.goBack()
        #expect(closedSecond)
        #expect(stack.isAtSidebar)
        // Nothing left to close.
        let closedNothing = stack.goBack()
        #expect(!closedNothing)
    }

    @Test func goBackToADepthIsAClickOnACoveredStrip() {
        var stack = SheetStack([ID.acmeWeb, ID.devServer, ID.localhost])
        stack.goBack(to: 1)
        #expect(stack.entries == [ID.acmeWeb])

        // At or above the top changes nothing.
        stack.goBack(to: 1)
        stack.goBack(to: 5)
        #expect(stack.entries == [ID.acmeWeb])

        stack.goBack(to: 0)
        #expect(stack.isAtSidebar)
    }

    @Test func openedFromASheetIsTheOneAboveIt() {
        let stack = SheetStack([ID.acmeWeb, ID.devServer])
        #expect(stack.opened(from: 0) == ID.acmeWeb)
        #expect(stack.opened(from: 1) == ID.devServer)
        #expect(stack.opened(from: 2) == nil)
        #expect(stack.prefix(1).entries == [ID.acmeWeb])
        #expect(stack.prefix(0).isAtSidebar)
        #expect(stack.prefix(5) == stack)
    }

    @Test func aClickOnACoveredStripGoesBackOrOpensAnotherRow() {
        let start = SheetStack([ID.acmeWeb, ID.devServer, ID.localhost])

        // Off any row: back to that sheet.
        var stack = start
        stack.clickStrip(at: 1, on: nil)
        #expect(stack.entries == [ID.acmeWeb])

        // On the row already open from it: back to that sheet too.
        stack = start
        stack.clickStrip(at: 1, on: ID.devServer)
        #expect(stack.entries == [ID.acmeWeb])

        // On another row: that row's pane opens in place of everything above.
        stack = start
        stack.clickStrip(at: 1, on: ID.claude)
        #expect(stack.entries == [ID.acmeWeb, ID.claude])
    }

    /// Clicking one row over and over toggles its sheet every time, with no click that does
    /// nothing. A row on the top sheet opens its pane. Once that pane covers the row's sheet,
    /// the row is in a covered strip, and a click there goes back.
    @Test func clickingTheSameRowAgainAndAgainTogglesItsSheetEveryTime() {
        let settings = SettingsSection.settingsID
        let general = SettingsSection.general.paneID
        var stack = SheetStack([settings])
        func click() {
            // What the views call: the row's own action on the top sheet, the strip's on a
            // covered one.
            if stack.depth == 1 { stack.open(general, from: 1) } else { stack.clickStrip(at: 1, on: general) }
        }
        click()
        #expect(stack.entries == [settings, general])
        click()
        #expect(stack.entries == [settings])
        click()
        #expect(stack.entries == [settings, general])
        click()
        #expect(stack.entries == [settings])

        // A click on the strip that lands after the sheet already closed, as while it is still
        // sliding away, opens the row again rather than doing nothing.
        stack.clickStrip(at: 1, on: general)
        #expect(stack.entries == [settings, general])
    }

    @Test func descriptionJoinsTheIDs() {
        #expect(SheetStack(["a", "b"]).description == "a/b")
    }

    // MARK: Layout

    @Test func leadingEdgesAddUpTheStrips() {
        #expect(SheetStackLayout.leadingEdges(stripWidths: []) == [0])
        #expect(SheetStackLayout.leadingEdges(stripWidths: [220, 48, 48]) == [0, 220, 268, 316])
    }

    @Test func eachSheetSitsTenPointsLower() {
        #expect(SheetStackLayout.drop == 10)
        #expect(SheetStackLayout.topEdges(sheetCount: 4) == [0, 10, 20, 30])
        #expect(SheetStackLayout.topEdges(sheetCount: 1) == [0])
        #expect(SheetStackLayout.topEdges(sheetCount: 0) == [])
    }

    @Test func framesRunToTheTrailingAndBottomEdges() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let frames = SheetStackLayout.frames(stripWidths: [220, 48], in: area)
        #expect(frames == [
            CGRect(x: 0, y: 0, width: 1000, height: 600),
            CGRect(x: 220, y: 10, width: 780, height: 590),
            CGRect(x: 268, y: 20, width: 732, height: 580),
        ])
    }

    @Test func framesFollowTheAreaOrigin() {
        let area = CGRect(x: 5, y: 7, width: 100, height: 100)
        let frames = SheetStackLayout.frames(stripWidths: [30], in: area)
        #expect(frames == [
            CGRect(x: 5, y: 7, width: 100, height: 100),
            CGRect(x: 35, y: 17, width: 70, height: 90),
        ])
    }

    // MARK: Strip widths

    @Test func theSidebarIsTheOnlyStripAtOneSheetUp() {
        #expect(SheetStackLayout.stripWidths(depth: 0, available: 1000) == [])
        #expect(SheetStackLayout.stripWidths(depth: 1, available: 1000) == [240])
    }

    @Test func eachCoveredSheetAboveTheSidebarAsksForTheSameStrip() {
        #expect(SheetStackLayout.stripWidths(depth: 3, available: 1000) == [240, 64, 64])
    }

    @Test func olderStripsGiveWayFirstWhenTheWindowIsNarrow() {
        // 660 wide leaves 100 for strips above the sidebar. Two strips of 64 do not fit, so
        // the older one narrows to a sliver and the nearest keeps its width.
        #expect(SheetStackLayout.stripWidths(depth: 3, available: 660) == [240, 20, 64])
        // At 640 the sliver does not fit either, so it goes. Narrower still, the nearest
        // strip shrinks.
        #expect(SheetStackLayout.stripWidths(depth: 3, available: 640) == [240, 0, 64])
        #expect(SheetStackLayout.stripWidths(depth: 3, available: 600) == [240, 0, 40])
        #expect(SheetStackLayout.stripWidths(depth: 3, available: 500) == [240, 0, 0])
    }

    @Test func theSidebarNeverNarrows() {
        #expect(SheetStackLayout.stripWidths(depth: 4, available: 300).first == 240)
    }
}
