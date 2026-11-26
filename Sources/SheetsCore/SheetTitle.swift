import Foundation

/// What a sheet's title bar says: the title the pane shows, the same one its row shows.
///
/// Every sheet above the sidebar has one title bar, drawn by the stack rather than by the
/// pane's content, so it is the same height for every kind of pane and stays still while a
/// swap changes what is under it. Only its words change, and they fade in place.
public struct SheetTitle: Hashable, Sendable {
    public let title: String

    public init(title: String) {
        self.title = title
    }

    /// The title bar for a pane. A terminal shows the title its shell set, unless the person
    /// named the pane by hand. See `Pane.shownTitle(sessionTitle:)`.
    public init(pane: Pane, sessionTitle: String? = nil) {
        self.init(title: pane.shownTitle(sessionTitle: sessionTitle))
    }

    /// The height of every sheet's title bar, in points, above its dividing line.
    public static let barHeight: CGFloat = 32
}
