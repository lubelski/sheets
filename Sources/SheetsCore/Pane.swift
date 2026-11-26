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
    /// A folder on disk, as a path. A terminal starts in its folder. A group's folder is where
    /// new terminals under it start. Nil when the pane has none, and always nil for a page.
    public var folder: String?
    /// The engine a terminal runs in. Nil for the standard engine, and always nil for other
    /// kinds. See `TerminalEngineRegistry`.
    public var engine: TerminalEngineID?
    /// True once the person has given the pane a name of their own by renaming it. A terminal
    /// named by hand shows that name rather than the title its shell sets. See
    /// `shownTitle(sessionTitle:)`.
    public var isNamedByHand: Bool

    public init(
        id: PaneID, kind: PaneKind, title: String, children: [Pane] = [], folder: String? = nil,
        engine: TerminalEngineID? = nil, isNamedByHand: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.children = children
        self.folder = folder
        self.engine = engine
        self.isNamedByHand = isNamedByHand
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, title, children, folder, engine, isNamedByHand
    }

    /// Reads a pane. Fields added after the first version are optional, so a pane saved
    /// without them reads as it did then: no folder, the standard engine, and not named by
    /// hand.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PaneID.self, forKey: .id)
        kind = try container.decode(PaneKind.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        children = try container.decodeIfPresent([Pane].self, forKey: .children) ?? []
        folder = try container.decodeIfPresent(String.self, forKey: .folder)
        engine = try container.decodeIfPresent(TerminalEngineID.self, forKey: .engine)
        isNamedByHand = try container.decodeIfPresent(Bool.self, forKey: .isNamedByHand) ?? false
    }

    /// True for Settings and its sections. They are part of the app, not the person's own
    /// panes, so they cannot be closed, renamed, or moved, and nothing can be added under them.
    public var isFixed: Bool { kind == .settings }
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
            return childrenCount.map { name + " · " + $0 } ?? name
        case .settings:
            if let section = SettingsSection(paneID: id) { return section.summary }
            return Self.count(children.count, "section")
        }
    }

    /// How many panes are under a terminal or a page, such as "1 page" or "2 panes", or nil
    /// when there are none. "page" when every one is a page.
    var childrenCount: String? {
        guard !children.isEmpty else { return nil }
        let allPages = children.allSatisfy { $0.kind == .page }
        return Self.count(children.count, allPages ? "page" : "pane")
    }

    /// "1 pane", "2 panes".
    static func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
