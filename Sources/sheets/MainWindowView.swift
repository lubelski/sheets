import SheetsCore
import SwiftUI

/// The main window: the stack of sheets, with the sidebar as the bottom sheet.
struct MainWindowView: View {
    let model: SheetsModel
    let updater: AppUpdater
    var buildInfo = BuildInfo.current()

    var body: some View {
        SheetStackView(model: model) { level in
            content(level)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(CloseConfirmation(model: model))
    }

    @ViewBuilder
    private func content(_ level: SheetLevel) -> some View {
        let open = { (id: PaneID) in model.open(id, from: level.depth) }
        if let pane = level.pane {
            switch pane.kind {
            case .group:
                GroupSheet(model: model, pane: pane, openedID: level.openedID, open: open)
            case .terminal:
                TerminalSheet(model: model, pane: pane, isTop: !level.isCovered)
            case .page:
                PlaceholderSheet(pane: pane)
            case .settings:
                if let section = SettingsSection(paneID: pane.id) {
                    SettingsSectionSheet(
                        section: section, updater: updater, buildInfo: buildInfo, config: model.config)
                } else {
                    SettingsSheet(openedID: level.openedID, open: open)
                }
            }
        } else {
            SidebarSheet(model: model, isCovered: level.isCovered)
        }
    }
}

/// The bottom sheet: the pane tree as a column of rows, with Settings pinned at its foot.
/// With nothing open over it, the rest of the sheet says so.
struct SidebarSheet: View {
    let model: SheetsModel
    let isCovered: Bool
    /// The row being dragged, and where it would land, while the drag experiment is on.
    @State private var dragged: PaneID?
    @State private var dropTarget: SidebarDropTarget?

    var body: some View {
        let rows = model.tree.sidebarRows()
        let pinned = model.tree.pinnedRows()
        // The row to mark: the deepest open pane the sidebar lists, or Settings while it or
        // one of its sections is open.
        let listed = Set((rows + pinned).map(\.id))
        let selected = model.stack.entries.last { listed.contains($0) }
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            SidebarRow(
                                model: model, row: row, isSelected: row.id == selected,
                                isRenaming: model.renaming == row.id
                            ) { model.show(row.id) }
                            .contextMenu { PaneContextMenu(model: model, id: row.id) }
                            .modifier(SidebarRowDragging(
                                model: model, row: row, isOn: model.isOn(.dragToMove), dragged: $dragged, target: $dropTarget))
                        }
                    }
                    .padding(.vertical, 8)
                }
                // A right click below the rows adds at the top level.
                .contextMenu { NewPaneMenuItems(model: model, near: nil) }
                .overlay {
                    if rows.isEmpty {
                        Text("No panes. Press ⌘T for a terminal.")
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }
                Divider().opacity(0.6)
                ForEach(pinned) { row in
                    SidebarRow(model: model, row: row, isSelected: row.id == selected) { model.openSettings() }
                }
                .padding(.vertical, 4)
            }
            .frame(width: SheetStackLayout.sidebarWidth)
            Divider().opacity(0.6)
            Text("Choose a pane in the sidebar")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(.rect)
        // A click on the covered sidebar away from its rows goes back to it, as on any strip.
        .onTapGesture { if isCovered && model.renaming == nil { model.clickStrip(at: 0, on: nil) } }
    }
}

/// One sidebar row: a small optional icon in line with a larger title, over a smaller, grayer
/// line saying what the pane is, or for a terminal, where it is. Indented by its depth in the
/// tree. What it says comes from `SheetsModel.label(for:)`, read here so that a terminal's new
/// title or folder draws only its own row again.
struct SidebarRow: View {
    let model: SheetsModel
    let row: PaneTree.Row
    let isSelected: Bool
    /// True while this row's title is being edited in place.
    var isRenaming = false
    let select: () -> Void

    var body: some View {
        if isRenaming {
            // Not a button while its title is a field, so clicks in the field stay there.
            label(renaming: true)
                .background { RowSelection(isSelected: isSelected) }
        } else {
            Button(action: select) { label(renaming: false) }
                .buttonStyle(.plain)
                .background { RowSelection(isSelected: isSelected) }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private func label(renaming: Bool) -> some View {
        let pane = model.tree.pane(row.id)
        let shown = pane.map(model.label(for:))
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The icon's column is kept for rows without one, so titles at the same depth
            // line up.
            Image(systemName: symbol ?? "circle")
                .font(.system(size: 10))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .opacity(symbol == nil ? 0 : 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    // The field starts from the pane's own name, not a title its shell set.
                    RenameField(title: row.title) { model.finishRenaming(row.id, to: $0) } cancel: {
                        model.cancelRenaming()
                    }
                    .font(.system(size: 12.5, weight: .semibold))
                } else {
                    Text(shown?.title ?? row.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                }
                if let shown {
                    PaneSubtitle(label: shown)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(row.summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 10 + CGFloat(row.depth) * 14)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }

    /// Groups have no icon.
    private var symbol: String? {
        switch row.kind {
        case .group: nil
        case .terminal: "terminal"
        case .page: "globe"
        case .settings: "gearshape"
        }
    }
}
