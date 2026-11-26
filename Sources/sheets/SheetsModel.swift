import AppKit
import Observation
import SheetsCore
import SwiftUI

/// The window's state: the pane tree, the stack of sheets on screen, and the terminals' live
/// sessions. The sidebar, the sheets, and the menu commands all change the tree and the stack
/// through here, so every change animates the same way, Settings remembers its section, and
/// the sessions follow the tree.
@MainActor
@Observable
final class SheetsModel {
    private(set) var tree: PaneTree
    private(set) var stack: SheetStack
    /// The pane whose sidebar row is being renamed in place, if any.
    var renaming: PaneID?
    /// A pane with children waiting for the person to confirm closing it, if any.
    var pendingClose: PaneID?
    /// One live session per terminal pane, or nil when there is no way to run one, and a
    /// terminal's sheet says so. See `TerminalSessionStore` for when sessions start and end.
    let terminals: TerminalSessionStore?
    /// The config file: the terminals' look and behavior, the starting folder, and the
    /// experiments' switches. A change to it, from Settings or from anywhere else, reaches the
    /// terminals straight away.
    let config: ConfigStore
    /// The home folder, which a terminal's name is relative to.
    @ObservationIgnored let homeFolder: String
    @ObservationIgnored private let settingsMemory: SettingsSectionMemory
    /// Whether changes animate. Off for renders, which draw one state each.
    @ObservationIgnored private let animates: Bool
    /// The last change made here, and the stack it led to. Not observed: it is set with the
    /// stack, and the sheets' transitions read it while they come and go.
    @ObservationIgnored private var recorded = (change: SheetStackChange.none, stack: SheetStack())

    @ObservationIgnored private var quitObserver: NSObjectProtocol?

    /// `defaults` is where Settings keeps its open section. `tree` gets Settings added if it
    /// does not have it. `terminals` runs the terminals' shells. Without it, a terminal's sheet
    /// says its terminal could not be started. `config` is the config file, whose settings the
    /// terminals take.
    init(
        tree: PaneTree, defaults: UserDefaults = .standard, stack: SheetStack = SheetStack(), animates: Bool = true,
        homeFolder: String = NSHomeDirectory(), terminals: TerminalSessionStore? = nil, config: ConfigStore
    ) {
        self.tree = tree.addingSettings()
        self.stack = stack
        self.homeFolder = homeFolder
        self.config = config
        self.settingsMemory = SettingsSectionMemory(defaults: defaults)
        self.animates = animates
        self.terminals = terminals
        terminals?.linkClicked = { _, link, session in
            // A clicked link opens in the default browser for now, after the engine's own
            // checks. This is where a page will slide over its terminal instead.
            session.openWithDefaultHandler(link)
        }
        terminals?.appearance = config.config.terminalAppearance
        terminals?.behavior = config.config.terminalBehavior
        config.changed = { [weak terminals] _, new in
            terminals?.appearance = new.terminalAppearance
            terminals?.behavior = new.terminalBehavior
        }
        terminals?.sync(tree: self.tree, stack: stack)
    }

    /// Where a new terminal starts when no group above it has a folder: the config file's
    /// starting folder, or the home folder.
    var startingFolder: String {
        config.config.startingFolder(home: homeFolder)
    }

    /// How terminals look now.
    var terminalAppearance: TerminalAppearance {
        config.config.terminalAppearance
    }

    /// Whether an experiment's switch is on in the config file.
    func isOn(_ experiment: Experiment) -> Bool {
        experiment.isOn(in: config.config)
    }

    /// Ends every shell when the app quits. Only the app's own model does this, not one made
    /// for a render.
    func endTerminalsOnQuit() {
        guard quitObserver == nil, let terminals else { return }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { terminals.endAll() }
        }
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

    /// A model that starts the way the app does the first time: one terminal in the starting
    /// folder, open, running the person's login shell, or the shell the config file names.
    static func firstLaunch(
        defaults: UserDefaults = .standard, homeFolder: String = NSHomeDirectory(),
        config: ConfigStore = ConfigStore(path: ConfigFileLocation.current())
    ) -> SheetsModel {
        Experiment.moveSwitchesFromDefaults(defaults, to: config)
        let start = PaneEditor.firstLaunch(
            homeFolder: homeFolder, startingFolder: config.config.startingFolder(home: homeFolder))
        let version = BuildInfo.current().version
        // Read when each shell starts, so a change to the shell applies to the next terminal.
        let terminals = TerminalSessionStore(engines: TerminalEngines.registry()) { [weak config] pane in
            let settings = config?.config ?? .defaults
            return TerminalLaunch.loginShell(
                in: pane.folder, shell: settings.shell, arguments: settings.shellArguments, programVersion: version)
        }
        let model = SheetsModel(
            tree: start.tree, defaults: defaults, stack: start.stack, homeFolder: homeFolder, terminals: terminals,
            config: config)
        model.endTerminalsOnQuit()
        return model
    }

    // MARK: Terminals

    /// True when Escape belongs to the terminal on top, so it does not close the sheet. See
    /// `TerminalSessionStore.escapeGoesToTerminal(top:)`.
    var escapeGoesToTerminal: Bool {
        terminals?.escapeGoesToTerminal(top: stack.top) ?? false
    }

    /// Starts a terminal's shell again after it exited, or for the first time when it has no
    /// session.
    func restartTerminal(_ id: PaneID) {
        guard let pane = tree.pane(id) else { return }
        terminals?.restart(pane)
    }

    /// Why a terminal pane has no session, when that is known: there is no engine to run it.
    func whyTerminalHasNoSession(_ id: PaneID) -> String? {
        guard let terminals else { return "There is no terminal engine." }
        let engine = tree.pane(id).flatMap { terminals.engines.engine(for: $0.engine) }
        return engine == nil ? "There is no terminal engine." : nil
    }

    // MARK: Editing the tree

    /// The pane new panes are placed near, and Close and Rename act on: the top sheet's.
    var selection: PaneID? { stack.top }

    /// New Terminal, New Group, New Page: adds a pane near a row, or near the top sheet's pane
    /// from the menu, and opens it. A new group starts with its name being edited.
    func add(_ kind: PaneKind, near row: PaneID? = nil) {
        renaming = nil
        let home = homeFolder
        let start = startingFolder
        let near = row ?? selection
        var added: PaneID?
        edit { added = $0.add(kind, near: near, homeFolder: home, startingFolder: start) }
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
        publish(editor.tree, editor.stack, change: change)
    }

    /// Puts a new tree and stack on screen, with the terminals' sessions following them.
    ///
    /// Every terminal the new stack shows gets its session before the stack is set. With the
    /// session started after, a sheet put on screen by an animated change was drawn without
    /// its session and not drawn again when the session arrived, so it showed no shell.
    /// Sessions whose panes are gone end after, once their sheets have started to leave.
    private func publish(_ newTree: PaneTree, _ newStack: SheetStack, change: SheetStackChange) {
        terminals?.startSessions(shownIn: newStack, in: newTree)
        settingsMemory.note(newStack)
        recorded = (change, newStack)
        let set = {
            // A change to the stack alone leaves the tree as it is, so views of it do not redraw.
            if self.tree != newTree { self.tree = newTree }
            self.stack = newStack
        }
        if animates, change != .none {
            withAnimation(Self.animation(for: change), set)
        } else {
            set()
        }
        terminals?.endSessions(notIn: newTree)
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
        publish(tree, new, change: change)
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
