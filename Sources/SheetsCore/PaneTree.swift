import Foundation

/// Every pane the app has, as the tree the sidebar shows.
///
/// Panes at the top level have no parent. Each id appears once in the whole tree.
public struct PaneTree: Hashable, Sendable, Codable {
    /// The top-level panes, in sidebar order.
    public private(set) var roots: [Pane]

    /// Makes a tree from top-level panes. The caller keeps ids unique.
    public init(roots: [Pane] = []) {
        self.roots = roots
    }

    // MARK: Finding

    /// The pane with an id, or nil when the tree has none.
    public func pane(_ id: PaneID) -> Pane? {
        func search(_ panes: [Pane]) -> Pane? {
            for pane in panes {
                if pane.id == id { return pane }
                if let found = search(pane.children) { return found }
            }
            return nil
        }
        return search(roots)
    }

    /// True when the tree has a pane with this id.
    public func contains(_ id: PaneID) -> Bool {
        pane(id) != nil
    }

    /// The ids from a top-level pane down to this one, both included. Nil when the tree has no
    /// such pane. This is the path the screen shows as a stack of sheets.
    public func path(to id: PaneID) -> [PaneID]? {
        func search(_ panes: [Pane], above: [PaneID]) -> [PaneID]? {
            for pane in panes {
                let here = above + [pane.id]
                if pane.id == id { return here }
                if let found = search(pane.children, above: here) { return found }
            }
            return nil
        }
        return search(roots, above: [])
    }

    /// The id of the pane directly above this one. Nil for a top-level pane or a missing one.
    public func parent(of id: PaneID) -> PaneID? {
        guard let path = path(to: id), path.count >= 2 else { return nil }
        return path[path.count - 2]
    }

    // MARK: Changing

    /// Adds a pane as the last child of a parent, or at the end of the top level when the
    /// parent is nil. Returns false and changes nothing when the parent is missing or when any
    /// id in the new pane is already in the tree.
    @discardableResult
    public mutating func add(_ pane: Pane, under parent: PaneID?) -> Bool {
        guard Self.ids(in: [pane]).allSatisfy({ !contains($0) }) else { return false }
        guard let parent else {
            roots.append(pane)
            return true
        }
        return Self.edit(parent, in: &roots) { $0.children.append(pane) }
    }

    /// Removes a pane and everything under it. Returns the removed pane, or nil when the tree
    /// has no such pane.
    @discardableResult
    public mutating func remove(_ id: PaneID) -> Pane? {
        func remove(from panes: inout [Pane]) -> Pane? {
            if let index = panes.firstIndex(where: { $0.id == id }) {
                return panes.remove(at: index)
            }
            for index in panes.indices {
                if let removed = remove(from: &panes[index].children) { return removed }
            }
            return nil
        }
        return remove(from: &roots)
    }

    /// Changes one pane in place, such as to rename it. Returns false when there is no such pane.
    /// The change should not add children whose ids are already in the tree. Use `add` for that.
    @discardableResult
    public mutating func update(_ id: PaneID, _ change: (inout Pane) -> Void) -> Bool {
        Self.edit(id, in: &roots, change)
    }

    // MARK: The sidebar

    /// One line of the sidebar.
    public struct Row: Hashable, Sendable, Identifiable {
        public let id: PaneID
        public let kind: PaneKind
        public let title: String
        /// The short line under the title. See `Pane.summary`.
        public let summary: String
        /// How far the row is indented: 0 for a top-level pane, 1 for its children, and so on.
        public let depth: Int
        /// True when the pane has children, so the row can show a fold control.
        public let hasChildren: Bool
        /// True when the pane has children and they are hidden.
        public let isFolded: Bool
    }

    /// The sidebar's rows, top to bottom: each pane, then its children, depth first. The
    /// children of a folded pane are left out, and so is everything under them. Folding a pane
    /// without children changes nothing.
    ///
    /// Settings is left out, with its sections. The sidebar pins it at the bottom instead. See
    /// `pinnedRows`.
    public func sidebarRows(folded: Set<PaneID> = []) -> [Row] {
        var rows: [Row] = []
        func visit(_ panes: [Pane], depth: Int) {
            for pane in panes where pane.kind != .settings {
                let isFolded = !pane.children.isEmpty && folded.contains(pane.id)
                rows.append(Self.row(pane, depth: depth, isFolded: isFolded))
                if !isFolded { visit(pane.children, depth: depth + 1) }
            }
        }
        visit(roots, depth: 0)
        return rows
    }

    /// The rows pinned at the bottom of the sidebar, apart from the tree above them: the
    /// top-level Settings pane, without its sections, which open from its own sheet.
    public func pinnedRows() -> [Row] {
        roots.filter { $0.kind == .settings }.map { Self.row($0, depth: 0, isFolded: true) }
    }

    private static func row(_ pane: Pane, depth: Int, isFolded: Bool) -> Row {
        Row(
            id: pane.id, kind: pane.kind, title: pane.title, summary: pane.summary, depth: depth,
            hasChildren: !pane.children.isEmpty, isFolded: isFolded)
    }

    // MARK: Helpers

    /// Every id in some panes and everything under them.
    private static func ids(in panes: [Pane]) -> [PaneID] {
        panes.flatMap { [$0.id] + ids(in: $0.children) }
    }

    /// Finds a pane anywhere under some panes and changes it. False when it is not there.
    private static func edit(_ id: PaneID, in panes: inout [Pane], _ change: (inout Pane) -> Void) -> Bool {
        for index in panes.indices {
            if panes[index].id == id {
                change(&panes[index])
                return true
            }
            if edit(id, in: &panes[index].children, change) { return true }
        }
        return false
    }
}
