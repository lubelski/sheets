import CoreGraphics
import Testing
@testable import SheetsCore

@Suite struct DwindleLayoutTests {
    /// Wider than tall.
    let wide = CGRect(x: 0, y: 0, width: 1000, height: 600)
    /// Taller than wide.
    let tall = CGRect(x: 0, y: 0, width: 600, height: 1000)

    func frames(_ panes: [PaneID], in area: CGRect) -> [PaneID: CGRect] {
        DwindleLayout.frames(for: SplitTree(dwindling: panes)!, in: area)
    }

    @Test func emptyListMakesNoTree() {
        #expect(SplitTree(dwindling: []) == nil)
    }

    @Test func onePaneFillsTheAreaWithNoGutter() {
        #expect(frames(["a"], in: wide) == ["a": wide])
    }

    @Test func twoPanesInAWideAreaSitSideBySide() {
        // Inset by 6 on every side: 988 by 588. Two halves of (988 - 6) / 2 = 491.
        #expect(frames(["a", "b"], in: wide) == [
            "a": CGRect(x: 6, y: 6, width: 491, height: 588),
            "b": CGRect(x: 503, y: 6, width: 491, height: 588),
        ])
    }

    @Test func twoPanesInATallAreaStack() {
        #expect(frames(["a", "b"], in: tall) == [
            "a": CGRect(x: 6, y: 6, width: 588, height: 491),
            "b": CGRect(x: 6, y: 503, width: 588, height: 491),
        ])
    }

    @Test func aSquareSplitsTopAndBottom() {
        let square = CGRect(x: 0, y: 0, width: 506, height: 506)
        #expect(frames(["a", "b"], in: square) == [
            "a": CGRect(x: 6, y: 6, width: 494, height: 244),
            "b": CGRect(x: 6, y: 256, width: 494, height: 244),
        ])
    }

    @Test func threePanesSplitTheNewestHalfTheOtherWay() {
        // b's half is 491 by 588, taller than wide, so c goes under it.
        #expect(frames(["a", "b", "c"], in: wide) == [
            "a": CGRect(x: 6, y: 6, width: 491, height: 588),
            "b": CGRect(x: 503, y: 6, width: 491, height: 291),
            "c": CGRect(x: 503, y: 303, width: 491, height: 291),
        ])
    }

    @Test func fivePanesSpiral() {
        // c's quarter is 491 by 291, wide, so d goes beside it. d's piece is 242.5 by 291,
        // tall, so e goes under it.
        #expect(frames(["a", "b", "c", "d", "e"], in: wide) == [
            "a": CGRect(x: 6, y: 6, width: 491, height: 588),
            "b": CGRect(x: 503, y: 6, width: 491, height: 291),
            "c": CGRect(x: 503, y: 303, width: 242.5, height: 291),
            "d": CGRect(x: 751.5, y: 303, width: 242.5, height: 142.5),
            "e": CGRect(x: 751.5, y: 451.5, width: 242.5, height: 142.5),
        ])
    }

    @Test func gutterSeparatesEveryPaneAndRingsTheOutside() {
        let result = frames(["a", "b", "c", "d", "e"], in: wide)
        let inner = wide.insetBy(dx: DwindleLayout.gutter, dy: DwindleLayout.gutter)
        for (id, rect) in result {
            #expect(inner.contains(rect), "\(id) leaves the inset area")
        }
        let rects = Array(result.values)
        for i in rects.indices {
            for j in rects.indices where j > i {
                // Grown by just under half a gutter on each side, no two panes touch.
                let grown = rects[i].insetBy(dx: -2.9, dy: -2.9)
                #expect(!grown.intersects(rects[j].insetBy(dx: -2.9, dy: -2.9)))
            }
        }
    }

    @Test func insertingBesideAnOlderPaneSplitsThatPane() {
        // Three panes, then a new one split off from a, which is focused.
        let tree = SplitTree(dwindling: ["a", "b", "c"])!.inserting("d", beside: "a")
        #expect(tree.panes == ["a", "d", "b", "c"])
        #expect(DwindleLayout.frames(for: tree, in: wide) == [
            "a": CGRect(x: 6, y: 6, width: 491, height: 291),
            "d": CGRect(x: 6, y: 303, width: 491, height: 291),
            "b": CGRect(x: 503, y: 6, width: 491, height: 291),
            "c": CGRect(x: 503, y: 303, width: 491, height: 291),
        ])
    }

    @Test func insertingIgnoresAMissingFocusOrARepeatedPane() {
        let tree = SplitTree(dwindling: ["a", "b"])!
        #expect(tree.inserting("c", beside: "missing") == tree)
        #expect(tree.inserting("b", beside: "a") == tree)
    }

    @Test func removingAPaneGivesItsSiblingTheWholeSplit() {
        let tree = SplitTree(dwindling: ["a", "b", "c"])!
        #expect(tree.removing("b") == SplitTree(dwindling: ["a", "c"]))
        #expect(tree.removing("a") == SplitTree(dwindling: ["b", "c"]))
        #expect(SplitTree.pane("a").removing("a") == nil)
        #expect(tree.removing("missing") == tree)
    }

    @Test func splitsTurnWhenTheAreaChangesShape() {
        // The same tree, drawn in a tall area, stacks a over b.
        let result = frames(["a", "b"], in: tall)
        #expect(result["a"]!.maxY < result["b"]!.minY)
        #expect(result["a"]!.minX == result["b"]!.minX)
    }
}
