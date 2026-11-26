import CoreGraphics
import Foundation

/// What a change from one stack to another does, so the view can pick its motion.
///
/// Opening sheets over the ones showing and closing sheets off the top are moves across the
/// stack, and slide from the trailing edge. A swap is neither: the pane open at some depth is
/// replaced by another pane from the same list, its sibling, and any sheets above that depth
/// close. The swapped sheet stays where it is, and only what is on it changes, moving up or
/// down by the two panes' order in their list.
public enum SheetStackChange: Hashable, Sendable {
    /// The stack did not change.
    case none
    /// Sheets opened over the ones already showing, which stay as they were.
    case open
    /// Sheets closed off the top, and the ones left are as they were.
    case back
    /// The pane at `depth` was replaced by a sibling. Sheets above that depth closed, and any
    /// the new stack has above it are new.
    case swap(depth: Int, direction: SheetSwapDirection)

    /// What changed from one stack to another.
    ///
    /// Two panes at the same depth after the same sheets below always share a parent, the
    /// pane of the sheet under them, or the top level for the sheet just above the sidebar. The
    /// direction follows their order among that parent's children in `tree`, which is the
    /// order the parent's sheet and the sidebar list them in.
    public init(from old: SheetStack, to new: SheetStack, in tree: PaneTree) {
        guard old != new else { self = .none; return }
        let shared = zip(old.entries, new.entries).prefix { $0 == $1 }.count
        if shared == old.depth { self = .open; return }
        if shared == new.depth { self = .back; return }

        // Both stacks have an entry just past the ones they share, and the two differ.
        let siblings = shared == 0
            ? tree.roots.map(\.id)
            : (tree.pane(old.entries[shared - 1])?.children.map(\.id) ?? [])
        let depth = shared + 1
        guard let from = siblings.firstIndex(of: old.entries[shared]),
              let to = siblings.firstIndex(of: new.entries[shared]) else {
            self = .swap(depth: depth, direction: .inPlace)
            return
        }
        self = .swap(depth: depth, direction: to > from ? .fromBelow : .fromAbove)
    }

    /// The depth a swap replaced, or nil for any other change.
    public var swapDepth: Int? {
        if case .swap(let depth, _) = self { depth } else { nil }
    }

    /// Which way a swap's new content comes in, or nil for any other change.
    public var swapDirection: SheetSwapDirection? {
        if case .swap(_, let direction) = self { direction } else { nil }
    }
}

/// Which way a swap's new content comes in.
public enum SheetSwapDirection: Hashable, Sendable {
    /// The new pane is lower in the list, so its content rises from below and the old content
    /// rises out.
    case fromBelow
    /// The new pane is higher in the list, so its content comes down from above and the old
    /// content drops out.
    case fromAbove
    /// A pane is not in the list, so there is no order to follow. The content only fades.
    case inPlace

    /// How far content sits from its place, in points, as it comes in (`entering`) or once it
    /// has left. Positive is down. Content coming in from below starts below its place, and the
    /// content it replaces leaves upward.
    public func offset(entering: Bool, distance: CGFloat = SheetMotion.swapDistance) -> CGFloat {
        let along: CGFloat = entering ? distance : -distance
        switch self {
        case .fromBelow: return along
        case .fromAbove: return -along
        case .inPlace: return 0
        }
    }
}

/// Every duration and distance the stack moves by, in one place, so they are tuned together.
public enum SheetMotion {
    /// How long a sheet takes to slide in from the trailing edge or back out, in seconds.
    public static let slideDuration: Double = 0.24
    /// How long a swap takes, in seconds. It is quicker than a slide, since it moves less.
    public static let swapDuration: Double = 0.18
    /// How far a swap's content moves up or down while it crossfades, in points.
    public static let swapDistance: CGFloat = 10
    /// How long any change takes with Reduce Motion on, where sheets and swaps only fade.
    public static let reduceMotionFadeDuration: Double = 0.2
}
