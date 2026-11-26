import CoreGraphics
import Foundation

/// The sheets on screen: the panes stacked above the sidebar, in order.
///
/// The sidebar is the bottom sheet and is always there. Each entry opens one more sheet over
/// the one before it, such as a group, then a terminal in it, then a page from that terminal.
/// A covered sheet keeps its layout. It is only covered, leaving a strip of its leading edge
/// in view.
///
/// Depth counts sheets above the sidebar: depth 0 is the sidebar alone, and depth 2 is the
/// sidebar with two sheets over it, the second of which is on top.
///
/// The stack holds only ids. It does not check them against a pane tree. Use
/// `SheetStack(showing:in:)` to make one from a tree.
///
/// Ported from `PaneStackPath` in mac-os-agent, with pane ids in place of strings.
public struct SheetStack: Hashable, Sendable, Codable, CustomStringConvertible {
    /// The open panes, bottom first. `entries[0]` is the sheet just above the sidebar.
    public private(set) var entries: [PaneID]

    public init(_ entries: [PaneID] = []) {
        self.entries = entries
    }

    /// The stack that shows a pane on top, with every pane above it in the tree under it. Nil
    /// when the tree has no such pane.
    public init?(showing id: PaneID, in tree: PaneTree) {
        guard let path = tree.path(to: id) else { return nil }
        self.init(path)
    }

    /// How many sheets are open above the sidebar.
    public var depth: Int { entries.count }

    /// True when only the sidebar shows.
    public var isAtSidebar: Bool { entries.isEmpty }

    /// The pane on top, or nil when only the sidebar shows.
    public var top: PaneID? { entries.last }

    /// The pane whose sheet is at a depth, or nil for the sidebar (depth 0) and for a depth
    /// that is not open.
    public func entry(at depth: Int) -> PaneID? {
        guard depth >= 1, depth <= entries.count else { return nil }
        return entries[depth - 1]
    }

    /// The pane opened from the sheet at a depth, which that sheet's row marks as open. Nil when
    /// nothing is open from it, as on the top sheet.
    public func opened(from depth: Int) -> PaneID? {
        entry(at: depth + 1)
    }

    /// The stack up to a depth: what shows when the sheet at that depth is on top.
    public func prefix(_ depth: Int) -> SheetStack {
        SheetStack(Array(entries.prefix(max(0, depth))))
    }

    /// Opens a pane from the sheet at a depth: every sheet above that depth closes and the
    /// pane's sheet goes on top. From the top sheet this pushes one more. From a covered sheet
    /// it replaces everything above it.
    public mutating func open(_ id: PaneID, from depth: Int) {
        entries = Array(entries.prefix(max(0, depth))) + [id]
    }

    /// Opens a pane over the top sheet, one level deeper.
    public mutating func open(_ id: PaneID) {
        open(id, from: depth)
    }

    /// Closes the top sheet, going back one. Returns false when only the sidebar shows, so
    /// there was nothing to close.
    @discardableResult
    public mutating func goBack() -> Bool {
        guard !entries.isEmpty else { return false }
        entries.removeLast()
        return true
    }

    /// Closes every sheet above a depth, so the sheet at that depth is on top. This is what a
    /// click on a covered strip does. A depth at or above the top changes nothing.
    public mutating func goBack(to depth: Int) {
        if depth < entries.count { entries = Array(entries.prefix(max(0, depth))) }
    }

    /// A click on a covered sheet's strip. On a row other than the one already open from that
    /// sheet, it opens that row's pane instead, closing everything above the sheet. Anywhere
    /// else, the open row included, it goes back to that sheet.
    ///
    /// The sidebar is not handled here. Its rows show the whole tree, so a click on one shows
    /// that pane's path with `SheetStack(showing:in:)`.
    public mutating func clickStrip(at depth: Int, on row: PaneID?) {
        if let row, row != opened(from: depth) {
            open(row, from: depth)
        } else {
            goBack(to: depth)
        }
    }

    /// The ids joined by `/`, for logs and test messages.
    public var description: String { entries.map(\.rawValue).joined(separator: "/") }
}

/// Where each sheet sits on screen.
///
/// Each covered sheet shows a strip at its leading edge, the part the sheet above it does not
/// cover. Each sheet also sits a little lower than the one under it, so the stack reads as
/// sheets laid over each other. A sheet's leading edge is the sum of the strips under it, and
/// its top edge is one drop per sheet under it.
///
/// When the window is too narrow for every strip, they narrow. See `stripWidths`.
public enum SheetStackLayout {
    /// The width of the sidebar's strip, which is the whole sidebar column. It does not narrow.
    public static let sidebarWidth: CGFloat = 240
    /// The width a covered sheet's strip asks for, above the sidebar.
    public static let stripWidth: CGFloat = 64
    /// The top sheet's minimum width before the strips under it narrow.
    public static let minimumTopWidth: CGFloat = 320
    /// The width of a strip that has narrowed to a sliver.
    public static let collapsedWidth: CGFloat = 20

    /// The width of each covered sheet's strip, the sidebar's first, for a stack this deep.
    ///
    /// The sidebar keeps its whole width, since it is the way to everything else. The other
    /// strips ask for `stripWidth` each. When that leaves the top sheet less than its minimum,
    /// they give way oldest first:
    ///
    /// 1. Each older strip narrows to a sliver, starting with the one just above the sidebar.
    /// 2. If that is not enough, slivers go away entirely, again oldest first.
    /// 3. Only then does the strip just under the top sheet shrink to what is left. It is the
    ///    usual way back, so it keeps its width longest.
    ///
    /// A strip that narrows only shows less of its sheet. The sheet itself keeps its layout.
    ///
    /// - Parameters:
    ///   - depth: How many sheets are open above the sidebar.
    ///   - available: The width of the whole stack, the sidebar included.
    public static func stripWidths(
        depth: Int, available: CGFloat, sidebarWidth: CGFloat = sidebarWidth, stripWidth: CGFloat = stripWidth,
        minimumTopWidth: CGFloat = minimumTopWidth, collapsedWidth: CGFloat = collapsedWidth
    ) -> [CGFloat] {
        guard depth > 0 else { return [] }
        var widths = Array(repeating: max(0, stripWidth), count: depth - 1)
        let budget = max(0, available - sidebarWidth - minimumTopWidth)
        func fits() -> Bool { widths.reduce(0, +) <= budget }
        if !fits() {
            for index in widths.indices.dropLast() where !fits() {
                widths[index] = min(widths[index], collapsedWidth)
            }
            for index in widths.indices.dropLast() where !fits() {
                widths[index] = 0
            }
            if !fits(), let last = widths.indices.last {
                widths[last] = max(0, budget - widths.dropLast().reduce(0, +))
            }
        }
        return [sidebarWidth] + widths
    }

    /// How far each sheet sits below the one under it, in points.
    public static let drop: CGFloat = 10

    /// Where each sheet's leading edge sits, from the sidebar (at 0) to the top sheet.
    ///
    /// - Parameter stripWidths: The width of each covered sheet's strip, the sidebar's first.
    ///   There is one fewer than there are sheets, since the top sheet is not covered.
    public static func leadingEdges(stripWidths: [CGFloat]) -> [CGFloat] {
        stripWidths.reduce(into: [0]) { edges, width in edges.append(edges.last! + max(0, width)) }
    }

    /// Where each sheet's top edge sits, from the sidebar (at 0) to the top sheet. Each sheet is
    /// one drop lower than the one under it.
    ///
    /// - Parameter sheetCount: How many sheets there are, the sidebar included.
    public static func topEdges(sheetCount: Int, drop: CGFloat = drop) -> [CGFloat] {
        (0..<max(0, sheetCount)).map { CGFloat($0) * drop }
    }

    /// The rectangle of each sheet, from the sidebar to the top sheet, inside an area. Each sheet
    /// runs from its leading and top edges to the area's trailing and bottom edges, so a covered
    /// sheet keeps the size it had when it was on top.
    ///
    /// The area's origin is its top leading corner, with y growing downward, as in SwiftUI.
    public static func frames(stripWidths: [CGFloat], in area: CGRect, drop: CGFloat = drop) -> [CGRect] {
        let leading = leadingEdges(stripWidths: stripWidths)
        let tops = topEdges(sheetCount: leading.count, drop: drop)
        return zip(leading, tops).map { x, y in
            CGRect(
                x: area.minX + x, y: area.minY + y,
                width: max(0, area.width - x), height: max(0, area.height - y))
        }
    }
}
