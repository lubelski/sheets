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
}
