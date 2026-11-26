import Foundation

// Commands that change the pane tree: add, close, rename, and move. Each is pure and returns
// whether it did anything. Settings and its sections are fixed: none of these touch them, and
// nothing goes under them. See `Pane.isFixed`.

extension PaneID {
    /// A new id that no other pane has. It never changes, whatever the pane is renamed to or
    /// wherever it moves, so a saved tree can refer to it.
    public static func unique() -> PaneID {
        PaneID(UUID().uuidString.lowercased())
    }
}

/// A position in the tree: a parent, or the top level when it is nil, and an index among its
/// children.
public struct PanePlace: Hashable, Sendable {
    public var parent: PaneID?
    public var index: Int

    public init(parent: PaneID?, index: Int) {
        self.parent = parent
        self.index = index
    }
}

/// Where a dragged row lands on another row: above it, on it, or below it.
public enum PaneDropZone: Hashable, Sendable {
    case before
    case into
    case after
}

extension PaneTree {
    // MARK: Asking

    /// The children of a pane, or the top level when the parent is nil. Nil when the tree has
    /// no such pane.
    public func children(of parent: PaneID?) -> [Pane]? {
        guard let parent else { return roots }
        return pane(parent)?.children
    }

    /// The pane's index among its parent's children.
    func index(of id: PaneID) -> Int? {
        children(of: parent(of: id))?.firstIndex { $0.id == id }
    }

    /// How many top-level places come before Settings, which stays last.
    var topLevelEnd: Int {
        roots.firstIndex { $0.isFixed } ?? roots.count
    }

    /// True when a pane can be added under this parent: the top level, or any pane that is not
    /// fixed.
    public func canAdd(under parent: PaneID?) -> Bool {
        guard let parent else { return true }
        return pane(parent).map { !$0.isFixed } ?? false
    }

    /// True when the pane is in the tree and can be closed, renamed, and moved.
    public func canEdit(_ id: PaneID) -> Bool {
        pane(id).map { !$0.isFixed } ?? false
    }

    /// True when `id` is `ancestor` or anywhere under it.
    public func isPane(_ id: PaneID, within ancestor: PaneID) -> Bool {
        path(to: id)?.contains(ancestor) ?? false
    }

    // MARK: Where things go

    /// Where a new pane goes, from what is selected.
    ///
    /// - A group: the new pane is its last child.
    /// - A terminal or a page: the new pane is its next sibling, just after it.
    /// - Nothing, Settings, or a pane the tree does not have: the end of the top level, above
    ///   Settings.
    public func placeForNewPane(near selection: PaneID?) -> PanePlace {
        guard let selection, let pane = pane(selection), !pane.isFixed else {
            return PanePlace(parent: nil, index: topLevelEnd)
        }
        if pane.kind == .group {
            return PanePlace(parent: selection, index: pane.children.count)
        }
        return PanePlace(parent: parent(of: selection), index: (index(of: selection) ?? 0) + 1)
    }

    /// Where a row dropped on another row goes, or nil when it cannot go there.
    ///
    /// Before puts it just above the row, as its sibling. Into makes it the row's last child.
    /// After puts it just below the row: as the row's first child when the row's children show
    /// under it, since that is where the gap below the row is, or else as its next sibling.
    public func place(forDropOn row: PaneID, zone: PaneDropZone, childrenShown: Bool = true) -> PanePlace? {
        guard let pane = pane(row), !pane.isFixed, let index = index(of: row) else { return nil }
        switch zone {
        case .into:
            return PanePlace(parent: row, index: pane.children.count)
        case .after where childrenShown && !pane.children.isEmpty:
            return PanePlace(parent: row, index: 0)
        case .before:
            return PanePlace(parent: parent(of: row), index: index)
        case .after:
            return PanePlace(parent: parent(of: row), index: index + 1)
        }
    }

    /// The folder a new terminal at a place starts in: the folder of the nearest group above
    /// it that has one. Nil when none does, and the caller falls back to the home folder.
    public func folder(forNewPaneUnder parent: PaneID?) -> String? {
        guard let parent, let path = path(to: parent) else { return nil }
        for id in path.reversed() {
            if let pane = pane(id), pane.kind == .group, let folder = pane.folder { return folder }
        }
        return nil
    }

    /// The name a terminal gets from its folder: `~` for the home folder, or else the folder's
    /// own name.
    public static func title(forFolder folder: String, home: String) -> String {
        let standard = (folder as NSString).standardizingPath
        if standard == (home as NSString).standardizingPath { return "~" }
        let name = (standard as NSString).lastPathComponent
        return name.isEmpty ? standard : name
    }

    // MARK: Changing

    /// Puts a pane at a place. An index past the end puts it last, and at the top level never
    /// below Settings. Returns false and changes nothing when the parent is missing or fixed,
    /// when the new pane is itself fixed, or when any id in it is already in the tree.
    @discardableResult
    public mutating func insert(_ pane: Pane, at place: PanePlace) -> Bool {
        guard canAdd(under: place.parent), !pane.isFixed, Self.allIDs(in: [pane]).allSatisfy({ !contains($0) })
        else { return false }
        guard let parent = place.parent else {
            roots.insert(pane, at: min(max(0, place.index), topLevelEnd))
            return true
        }
        return update(parent) { $0.children.insert(pane, at: min(max(0, place.index), $0.children.count)) }
    }

    /// Closes a pane and everything under it, and returns it. Nil, and nothing changes, when the
    /// pane is missing or fixed.
    @discardableResult
    public mutating func close(_ id: PaneID) -> Pane? {
        guard canEdit(id) else { return nil }
        return remove(id)
    }

    /// Gives a pane a new title, without spaces at either end. Returns false, and nothing
    /// changes, when the pane is missing or fixed or the title is blank.
    @discardableResult
    public mutating func rename(_ id: PaneID, to title: String) -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit(id), !title.isEmpty else { return false }
        return update(id) { $0.title = title }
    }

    /// Moves a pane, with everything under it, to a place.
    ///
    /// The index counts places in the destination as it is before the move, the way a line
    /// drawn between two rows does. Moving a pane to just above or just below itself leaves it
    /// where it is.
    ///
    /// Returns false, and nothing changes, when the pane is missing or fixed, when the
    /// destination is missing or fixed, or when the destination is the pane itself or under it.
    @discardableResult
    public mutating func move(_ id: PaneID, to place: PanePlace) -> Bool {
        guard canEdit(id), canAdd(under: place.parent) else { return false }
        if let parent = place.parent, isPane(parent, within: id) { return false }
        var index = place.index
        if parent(of: id) == place.parent, let old = self.index(of: id), old < index {
            index -= 1
        }
        guard let pane = remove(id) else { return false }
        return insert(pane, at: PanePlace(parent: place.parent, index: index))
    }

    /// Every id in some panes and everything under them.
    static func allIDs(in panes: [Pane]) -> [PaneID] {
        panes.flatMap { [$0.id] + allIDs(in: $0.children) }
    }
}

extension SheetStack {
    /// The stack after the tree changed under it, so it is still a path through the tree.
    ///
    /// When the top pane is still there, the stack is its path, which follows it if it moved.
    /// When it is gone, as when it or a pane above it closed, the stack keeps the sheets from
    /// the bottom that are still a path and closes the rest.
    public func following(_ tree: PaneTree) -> SheetStack {
        if let top, let path = tree.path(to: top) { return SheetStack(path) }
        var kept: [PaneID] = []
        for id in entries {
            guard let children = tree.children(of: kept.last), children.contains(where: { $0.id == id }) else { break }
            kept.append(id)
        }
        return SheetStack(kept)
    }
}

/// The pane tree and the stack of sheets on screen, changed together by the commands that
/// edit the tree, so the stack always shows panes that are there.
///
/// Only `tree` is the person's own data. The stack is what is on screen now.
public struct PaneEditor: Hashable, Sendable {
    public var tree: PaneTree
    public var stack: SheetStack

    public init(tree: PaneTree, stack: SheetStack = SheetStack()) {
        self.tree = tree
        self.stack = stack
    }

    /// What the app starts with the first time: one terminal in the starting folder, which is
    /// the home folder unless the config file names another, open.
    public static func firstLaunch(homeFolder: String, startingFolder: String? = nil, id: PaneID = .unique()) -> PaneEditor {
        let folder = startingFolder ?? homeFolder
        let terminal = Pane(
            id: id, kind: .terminal, title: PaneTree.title(forFolder: folder, home: homeFolder),
            folder: folder)
        let tree = PaneTree(roots: [terminal])
        return PaneEditor(tree: tree, stack: SheetStack([id]))
    }

    /// The title a new pane of a kind starts with.
    public static func newTitle(for kind: PaneKind, folder: String?, homeFolder: String) -> String {
        switch kind {
        case .terminal: PaneTree.title(forFolder: folder ?? homeFolder, home: homeFolder)
        case .group: "New Group"
        case .page: "New Page"
        case .settings: "Settings"
        }
    }

    /// Adds a new pane near what is selected (see `PaneTree.placeForNewPane(near:)`) and opens
    /// it as a sheet. Returns its id.
    @discardableResult
    public mutating func add(
        _ kind: PaneKind, near selection: PaneID?, homeFolder: String, startingFolder: String? = nil,
        id: PaneID = .unique()
    ) -> PaneID? {
        add(kind, at: tree.placeForNewPane(near: selection), homeFolder: homeFolder, startingFolder: startingFolder, id: id)
    }

    /// Adds a new pane at a place and opens it as a sheet, with every pane above it under it.
    /// A new terminal starts in its nearest group's folder, or else the starting folder, which
    /// is the home folder unless the config file names another, and is named for that folder.
    /// Returns its id, or nil when nothing can go there.
    @discardableResult
    public mutating func add(
        _ kind: PaneKind, at place: PanePlace, homeFolder: String, startingFolder: String? = nil,
        id: PaneID = .unique()
    ) -> PaneID? {
        guard kind != .settings else { return nil }
        let fallback = startingFolder ?? homeFolder
        let folder = kind == .terminal ? (tree.folder(forNewPaneUnder: place.parent) ?? fallback) : nil
        let pane = Pane(
            id: id, kind: kind, title: Self.newTitle(for: kind, folder: folder, homeFolder: homeFolder),
            folder: folder)
        guard tree.insert(pane, at: place), let shown = SheetStack(showing: id, in: tree) else { return nil }
        stack = shown
        return id
    }

    /// True when closing the pane closes others with it, so the app asks first.
    public func closingNeedsConfirmation(_ id: PaneID) -> Bool {
        tree.canEdit(id) && !(tree.pane(id)?.children.isEmpty ?? true)
    }

    /// Closes a pane and everything under it. Its sheet closes if it is open, and so does every
    /// sheet above it.
    @discardableResult
    public mutating func close(_ id: PaneID) -> Pane? {
        guard let closed = tree.close(id) else { return nil }
        stack = stack.following(tree)
        return closed
    }

    /// Renames a pane. The stack does not change.
    @discardableResult
    public mutating func rename(_ id: PaneID, to title: String) -> Bool {
        tree.rename(id, to: title)
    }

    /// Moves a pane. When it, or a pane under it, is on top of the stack, the stack follows it
    /// to its new path.
    @discardableResult
    public mutating func move(_ id: PaneID, to place: PanePlace) -> Bool {
        guard tree.move(id, to: place) else { return false }
        stack = stack.following(tree)
        return true
    }
}
