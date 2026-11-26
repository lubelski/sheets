import Foundation

/// Names one pane. It stays the same for the pane's whole life, whatever its title becomes.
public struct PaneID: Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public var description: String { rawValue }
}

/// What a pane is.
public enum PaneKind: String, Sendable, Codable, CaseIterable {
    /// A folder of other panes. It has no screen of its own: it shows a summary of its children.
    case group
    /// A terminal.
    case terminal
    /// A browser page, such as one opened from a link in a terminal.
    case page
}

/// One pane and everything under it.
///
/// Everything in the app is a pane, and any pane can have children, whatever its kind. A page
/// opened from a link in a terminal is a child of that terminal.
public struct Pane: Identifiable, Hashable, Sendable, Codable {
    public let id: PaneID
    public var kind: PaneKind
    public var title: String
    /// The panes under this one, in the order the sidebar lists them.
    public var children: [Pane]

    public init(id: PaneID, kind: PaneKind, title: String, children: [Pane] = []) {
        self.id = id
        self.kind = kind
        self.title = title
        self.children = children
    }
}
