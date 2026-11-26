import AppKit
import Observation
import SheetsCore
import SwiftUI

/// The window's state: the pane tree and the stack of sheets on screen. The sidebar, the
/// sheets, and the menu commands all change the stack through here, so every change animates
/// the same way and Settings remembers its section.
@MainActor
@Observable
final class SheetsModel {
    let tree: PaneTree
    private(set) var stack: SheetStack
    @ObservationIgnored private let settingsMemory: SettingsSectionMemory
    /// Whether changes animate. Off for renders, which draw one state each.
    @ObservationIgnored private let animates: Bool

    /// `defaults` is where Settings keeps its open section. `tree` gets Settings added if it
    /// does not have it.
    init(tree: PaneTree, defaults: UserDefaults = .standard, stack: SheetStack = SheetStack(), animates: Bool = true) {
        self.tree = tree.addingSettings()
        self.stack = stack
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

    private func change(_ mutate: (inout SheetStack) -> Void) {
        var new = stack
        mutate(&new)
        guard new != stack else { return }
        settingsMemory.note(new)
        guard animates else {
            stack = new
            return
        }
        withAnimation(Self.animation) { stack = new }
    }

    /// A short slide, or a fade with Reduce Motion on. The sheets pick their transition to
    /// match, from the same setting.
    static var animation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeInOut(duration: 0.2)
            : .easeOut(duration: 0.24)
    }
}
