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
    /// The app's settings, and each of its sections. Settings is a pane like any other, so it
    /// opens as a sheet over the sidebar and each section opens as a sheet over it. See
    /// `SettingsSection`.
    case settings
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

extension Pane {
    /// The short line under a pane's title in a list: what it is and what is under it, such as
    /// "2 panes" for a group or "Terminal · 1 page" for a terminal a page was opened from.
    public var summary: String {
        switch kind {
        case .group:
            return children.isEmpty ? "Empty" : Self.count(children.count, "pane")
        case .terminal, .page:
            let name = kind == .terminal ? "Terminal" : "Page"
            guard !children.isEmpty else { return name }
            let allPages = children.allSatisfy { $0.kind == .page }
            return name + " · " + Self.count(children.count, allPages ? "page" : "pane")
        case .settings:
            if let section = SettingsSection(paneID: id) { return section.summary }
            return Self.count(children.count, "section")
        }
    }

    /// "1 pane", "2 panes".
    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
