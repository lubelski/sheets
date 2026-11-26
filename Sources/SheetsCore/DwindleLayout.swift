import CoreGraphics
import Foundation

/// Panes docked beside each other as splits, placed by "dwindle", as in the Hyprland window
/// manager.
///
/// The splits form a binary tree. A new pane takes half of the focused pane's rectangle: the
/// focused pane's leaf becomes a split, with the focused pane first and the new pane second.
///
/// The tree does not store which way each split runs. The layout decides from the shape of the
/// rectangle each split gets: wider than tall splits left and right, anything else splits top
/// and bottom. The second pane gets the second half, the right or the bottom. So a split can
/// turn the other way when the window changes shape, which is what Hyprland does by default.
public indirect enum SplitTree: Hashable, Sendable, Codable {
    /// One pane, filling the rectangle it gets.
    case pane(PaneID)
    /// A rectangle split in half. `first` gets the left or top half, `second` the right or
    /// bottom half.
    case split(first: SplitTree, second: SplitTree)

    /// Builds the tree by adding panes in order, each new pane split off from the one added just
    /// before it. This is dwindle's usual spiral, where focus follows the newest pane. Nil for an
    /// empty list.
    public init?(dwindling panes: [PaneID]) {
        guard var tree = panes.first.map(SplitTree.pane) else { return nil }
        for (focused, new) in zip(panes, panes.dropFirst()) {
            tree = tree.inserting(new, beside: focused)
        }
        self = tree
    }

    /// Every pane, in order: first halves before second halves.
    public var panes: [PaneID] {
        switch self {
        case .pane(let id): [id]
        case .split(let first, let second): first.panes + second.panes
        }
    }

    /// True when the tree has this pane.
    public func contains(_ id: PaneID) -> Bool {
        switch self {
        case .pane(let pane): pane == id
        case .split(let first, let second): first.contains(id) || second.contains(id)
        }
    }

    /// The tree with a new pane split off from the focused one. The focused pane keeps the first
    /// half and the new pane takes the second. When the focused pane is not in the tree, or the
    /// new pane already is, nothing changes.
    public func inserting(_ new: PaneID, beside focused: PaneID) -> SplitTree {
        guard !contains(new) else { return self }
        switch self {
        case .pane(let id):
            return id == focused ? .split(first: .pane(id), second: .pane(new)) : self
        case .split(let first, let second):
            return .split(
                first: first.inserting(new, beside: focused), second: second.inserting(new, beside: focused))
        }
    }

    /// The tree without a pane. The pane's sibling takes the whole of their split. Nil when the
    /// removed pane was the only one.
    public func removing(_ id: PaneID) -> SplitTree? {
        switch self {
        case .pane(let pane):
            return pane == id ? nil : self
        case .split(let first, let second):
            let keptFirst = first.removing(id)
            let keptSecond = second.removing(id)
            switch (keptFirst, keptSecond) {
            case let (first?, second?): return .split(first: first, second: second)
            case let (only?, nil), let (nil, only?): return only
            case (nil, nil): return nil
            }
        }
    }
}

/// Turns a split tree into a rectangle for each pane.
public enum DwindleLayout {
    /// The space between two panes, and around the outside once there is more than one pane,
    /// in points.
    public static let gutter: CGFloat = 6

    /// Which way a rectangle splits: wider than tall splits left and right, otherwise top and
    /// bottom. A square splits top and bottom.
    public static func splitsSideBySide(_ rect: CGRect) -> Bool {
        rect.width > rect.height
    }

    /// The rectangle of each pane in an area.
    ///
    /// A single pane fills the whole area, with no gutter. With more than one, the area is first
    /// inset by a gutter on every side, and each split leaves a gutter between its two halves.
    ///
    /// The area's origin is its top leading corner, with y growing downward, as in SwiftUI.
    public static func frames(for tree: SplitTree, in area: CGRect, gutter: CGFloat = gutter) -> [PaneID: CGRect] {
        var frames: [PaneID: CGRect] = [:]
        switch tree {
        case .pane(let id):
            frames[id] = area
        case .split:
            place(tree, in: area.insetBy(dx: gutter, dy: gutter), gutter: gutter, into: &frames)
        }
        return frames
    }

    private static func place(_ tree: SplitTree, in rect: CGRect, gutter: CGFloat, into frames: inout [PaneID: CGRect]) {
        switch tree {
        case .pane(let id):
            frames[id] = rect
        case .split(let first, let second):
            let (a, b) = halves(of: rect, gutter: gutter)
            place(first, in: a, gutter: gutter, into: &frames)
            place(second, in: b, gutter: gutter, into: &frames)
        }
    }

    /// Splits a rectangle into two equal halves with a gutter between them: left and right when
    /// it is wider than tall, otherwise top and bottom.
    static func halves(of rect: CGRect, gutter: CGFloat) -> (CGRect, CGRect) {
        if splitsSideBySide(rect) {
            let width = max(0, (rect.width - gutter) / 2)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height),
                CGRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height))
        } else {
            let height = max(0, (rect.height - gutter) / 2)
            return (
                CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: height),
                CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height))
        }
    }
}
