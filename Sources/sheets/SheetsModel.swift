import AppKit
import Observation
import SheetsCore
import SwiftUI

/// The window's state: the pane tree and the stack of sheets on screen. The sidebar, the
/// sheets, and the menu commands all change the tree and the stack through here, so every
/// change animates the same way and Settings remembers its section.
@MainActor
@Observable
final class SheetsModel {
    private(set) var tree: PaneTree
    private(set) var stack: SheetStack
    /// The pane whose sidebar row is being renamed in place, if any.
    var renaming: PaneID?
    /// A pane with children waiting for the person to confirm closing it, if any.
    var pendingClose: PaneID?
    /// Where a new terminal starts when no group above it has a folder.
    @ObservationIgnored let homeFolder: String
    @ObservationIgnored private let settingsMemory: SettingsSectionMemory
    /// Whether changes animate. Off for renders, which draw one state each.
    @ObservationIgnored private let animates: Bool
    /// The last change made here, and the stack it led to. Not observed: it is set with the
    /// stack, and the sheets' transitions read it while they come and go.
    @ObservationIgnored private var recorded = (change: SheetStackChange.none, stack: SheetStack())

    /// `defaults` is where Settings keeps its open section. `tree` gets Settings added if it
    /// does not have it.
    init(
        tree: PaneTree, defaults: UserDefaults = .standard, stack: SheetStack = SheetStack(), animates: Bool = true,
        homeFolder: String = NSHomeDirectory()
    ) {
        self.tree = tree.addingSettings()
        self.stack = stack
        self.homeFolder = homeFolder
        self.settingsMemory = SettingsSectionMemory(defaults: defaults)
        self.animates = animates
    }

    /// A click on a sidebar row: the screen shows that pane's whole path.
    func show(_ id: PaneID) {
        guard let shown = SheetStack(showing: id, in: tree) else { return }
        change { $0 = shown }
    }

    /// A row in a sheet at a depth opens its pane over that sheet.
    func open(_ id: PaneID, from depth: Int) {
        change { $0.open(id, from: depth) }
    }

    /// A click on a covered sheet's strip, on a row or not.
    func clickStrip(at depth: Int, on row: PaneID?) {
        if depth == 0 {
            if let row { show(row) } else { change { $0.goBack(to: 0) } }
        } else {
            change { $0.clickStrip(at: depth, on: row) }
        }
    }

    /// Escape: closes the top sheet.
    func goBack() {
        change { _ = $0.goBack() }
    }

    /// Command-comma and the pinned Settings row: Settings opens over the sidebar, with the
    /// section that was open last.
    func openSettings() {
        let memory = settingsMemory
        change { $0 = memory.stack(openingSettingsFrom: $0) }
    }

    /// A model that starts the way the app does the first time: one terminal in the home
    /// folder, open.
    static func firstLaunch(defaults: UserDefaults = .standard, homeFolder: String = NSHomeDirectory()) -> SheetsModel {
        let start = PaneEditor.firstLaunch(homeFolder: homeFolder)
        return SheetsModel(tree: start.tree, defaults: defaults, stack: start.stack, homeFolder: homeFolder)
    }

    // MARK: Editing the tree

    /// The pane new panes are placed near, and Close and Rename act on: the top sheet's.
    var selection: PaneID? { stack.top }

    /// New Terminal, New Group, New Page: adds a pane near a row, or near the top sheet's pane
    /// from the menu, and opens it. A new group starts with its name being edited.
    func add(_ kind: PaneKind, near row: PaneID? = nil) {
        renaming = nil
        let home = homeFolder
        let near = row ?? selection
        var added: PaneID?
        edit { added = $0.add(kind, near: near, homeFolder: home) }
        if kind == .group, let added { renaming = added }
    }

    /// Close, from a menu or a context menu. A pane with children asks first. Settings and its
    /// sections cannot be closed.
    func requestClose(_ id: PaneID) {
        guard tree.canEdit(id) else { return }
        if PaneEditor(tree: tree).closingNeedsConfirmation(id) {
            pendingClose = id
        } else {
            close(id)
        }
    }

    /// Closes a pane and everything under it, without asking.
    func close(_ id: PaneID) {
        pendingClose = nil
        if let renaming, tree.isPane(renaming, within: id) { self.renaming = nil }
        edit { $0.close(id) }
    }

    /// Command-W. With sheets open it closes the top sheet's pane, or for Settings, which
    /// cannot be closed, just its sheet. With only the sidebar showing it closes the window.
    func closeTop() {
        guard let top = stack.top else {
            NSApp.keyWindow?.performClose(nil)
            return
        }
        if tree.canEdit(top) { requestClose(top) } else { goBack() }
    }

    /// Starts renaming a pane in its sidebar row.
    func startRenaming(_ id: PaneID) {
        guard tree.canEdit(id) else { return }
        renaming = id
    }

    /// Ends renaming with a new title. A blank title keeps the old one.
    func finishRenaming(_ id: PaneID, to title: String) {
        if renaming == id { renaming = nil }
        edit { $0.rename(id, to: title) }
    }

    /// Ends renaming without changing the title.
    func cancelRenaming() {
        renaming = nil
    }

    /// Moves a pane to a place, such as where a dragged row was dropped.
    func move(_ id: PaneID, to place: PanePlace) {
        edit { $0.move(id, to: place) }
    }

    /// Changes the tree and the stack together, with the stack's change animating as any
    /// other does.
    private func edit(_ mutate: (inout PaneEditor) -> Void) {
        var editor = PaneEditor(tree: tree, stack: stack)
        mutate(&editor)
        guard editor.tree != tree || editor.stack != stack else { return }
        let change = SheetStackChange(from: stack, to: editor.stack, in: editor.tree)
        settingsMemory.note(editor.stack)
        recorded = (change, editor.stack)
        guard animates, change != .none else {
            tree = editor.tree
            stack = editor.stack
            return
        }
        withAnimation(Self.animation(for: change)) {
            tree = editor.tree
            stack = editor.stack
        }
    }

    // MARK: How the stack changed

    /// What the change that led to the current stack was, so the sheets can pick their motion.
    /// A stack this model did not change, such as the one it started with, reads as no change.
    var change: SheetStackChange {
        recorded.stack == stack ? recorded.change : .none
    }

    private func change(_ mutate: (inout SheetStack) -> Void) {
        var new = stack
        mutate(&new)
        let change = SheetStackChange(from: stack, to: new, in: tree)
        guard change != .none else { return }
        settingsMemory.note(new)
        recorded = (change, new)
        guard animates else {
            stack = new
            return
        }
        withAnimation(Self.animation(for: change)) { stack = new }
    }

    /// A short slide, a quicker swap, or a fade with Reduce Motion on. The sheets pick their
    /// transitions to match, from the same setting and the recorded change.
    static func animation(for change: SheetStackChange) -> Animation {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            .easeInOut(duration: SheetMotion.reduceMotionFadeDuration)
        } else if change.swapDepth != nil {
            .easeOut(duration: SheetMotion.swapDuration)
        } else {
            .easeOut(duration: SheetMotion.slideDuration)
        }
    }
}
