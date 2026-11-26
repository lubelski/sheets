import Foundation

/// What a sheet's title bar says: the pane's name, and a detail after it, such as the title a
/// terminal's shell set.
///
/// Every sheet above the sidebar has one title bar, drawn by the stack rather than by the
/// pane's content, so it is the same height for every kind of pane and stays still while a
/// swap changes what is under it. Only its words change, and they fade in place.
public struct SheetTitle: Hashable, Sendable {
    /// The pane's own name.
    public let title: String
    /// What follows the name, lighter, or nil when there is nothing more to say. Never empty and
    /// never the same as `title`.
    public let detail: String?

    public init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = (detail?.isEmpty ?? true) || detail == title ? nil : detail
    }

    /// The title bar for a pane. A terminal's detail is the title its shell set, if any. Other
    /// kinds of pane have none.
    public init(pane: Pane, shellTitle: String? = nil) {
        self.init(title: pane.title, detail: pane.kind == .terminal ? shellTitle : nil)
    }

    /// The height of every sheet's title bar, in points, above its dividing line.
    public static let barHeight: CGFloat = 32
}
