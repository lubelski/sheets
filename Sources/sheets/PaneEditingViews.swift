import SheetsCore
import SwiftUI
import UniformTypeIdentifiers

// The parts of the window that edit the pane tree: context menus, the rename field, the
// confirmation before closing a pane with children, and dragging sidebar rows.

/// New Terminal, New Group, and New Page, placed near a row, or at the top level for nil.
struct NewPaneMenuItems: View {
    let model: SheetsModel
    let near: PaneID?

    var body: some View {
        Button("New Terminal") { model.add(.terminal, near: near) }
        Button("New Group") { model.add(.group, near: near) }
        Button("New Page") { model.add(.page, near: near) }
    }
}

/// The context menu on a row for a pane: new panes near it, and Rename and Close. Settings and
/// its sections have none, since nothing about them can change.
struct PaneContextMenu: View {
    let model: SheetsModel
    let id: PaneID

    var body: some View {
        if model.tree.canEdit(id) {
            NewPaneMenuItems(model: model, near: id)
            Divider()
            Button("Rename…") { model.startRenaming(id) }
            Button(PaneEditor(tree: model.tree).closingNeedsConfirmation(id) ? "Close…" : "Close") {
                model.requestClose(id)
            }
        }
    }
}

/// A title being edited in place. Return keeps the new title, Escape keeps the old one, and
/// clicking away keeps the new one, as in the Finder.
struct RenameField: View {
    let commit: (String) -> Void
    let cancel: () -> Void
    @State private var text: String
    @State private var isDone = false
    @FocusState private var isFocused: Bool

    init(title: String, commit: @escaping (String) -> Void, cancel: @escaping () -> Void) {
        self.commit = commit
        self.cancel = cancel
        _text = State(initialValue: title)
    }

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused($isFocused)
            // A field's own background and an accent outline, drawn outside the text so the
            // title stays where it was.
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .strokeBorder(Color.accentColor, lineWidth: 1)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
            }
            .onSubmit { finish { commit(text) } }
            .onExitCommand { finish(cancel) }
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused { finish { commit(text) } }
            }
    }

    private func finish(_ action: () -> Void) {
        guard !isDone else { return }
        isDone = true
        action()
    }
}

/// Asks before closing a pane that has panes under it, since they all close with it.
struct CloseConfirmation: ViewModifier {
    @Bindable var model: SheetsModel

    func body(content: Content) -> some View {
        let pane = model.pendingClose.flatMap(model.tree.pane)
        content.confirmationDialog(
            pane.map { "Close “\($0.title)” and everything in it?" } ?? "",
            isPresented: Binding(get: { pane != nil }, set: { if !$0 { model.pendingClose = nil } }),
            presenting: pane
        ) { pane in
            Button("Close", role: .destructive) { model.close(pane.id) }
            Button("Cancel", role: .cancel) { model.pendingClose = nil }
        } message: { pane in
            Text("\(Self.count(in: pane)) under it will close too.")
        }
    }

    /// "1 pane", "3 panes": everything under a pane, at any depth.
    static func count(in pane: Pane) -> String {
        func count(_ panes: [Pane]) -> Int { panes.reduce(0) { $0 + 1 + count($1.children) } }
        let n = count(pane.children)
        return "\(n) \(n == 1 ? "pane" : "panes")"
    }
}

// MARK: - Dragging sidebar rows

/// Where a dragged sidebar row would land: on which row, and in which part of it.
struct SidebarDropTarget: Equatable {
    let row: PaneID
    let zone: PaneDropZone
}

/// Makes a sidebar row draggable and a place to drop other rows, while the drag experiment is
/// on. The top quarter of a row puts the dropped pane above it, the bottom quarter below it,
/// and the middle inside it. A line or an outline shows where it would go.
struct SidebarRowDragging: ViewModifier {
    let model: SheetsModel
    let row: PaneTree.Row
    let isOn: Bool
    @Binding var dragged: PaneID?
    @Binding var target: SidebarDropTarget?
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        if isOn && model.tree.canEdit(row.id) {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .onDrag {
                    dragged = row.id
                    return NSItemProvider(object: row.id.rawValue as NSString)
                }
                .onDrop(of: [.plainText], delegate: SidebarRowDrop(
                    model: model, row: row, height: height, dragged: $dragged, target: $target))
                .overlay(alignment: indicatorAlignment) { indicator }
        } else {
            content
        }
    }

    private var zone: PaneDropZone? {
        target?.row == row.id ? target?.zone : nil
    }

    private var indicatorAlignment: Alignment {
        zone == .after ? .bottom : .top
    }

    @ViewBuilder
    private var indicator: some View {
        switch zone {
        case .before, .after:
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, 10 + CGFloat(row.depth + (zone == .after && row.hasChildren ? 1 : 0)) * 14)
                .allowsHitTesting(false)
        case .into:
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(.horizontal, 4)
                .allowsHitTesting(false)
        case nil:
            EmptyView()
        }
    }
}

/// Drops on one sidebar row. The dragged pane is the one this window noted when the drag
/// began, so the drop moves it without reading the dragged text back.
struct SidebarRowDrop: DropDelegate {
    let model: SheetsModel
    let row: PaneTree.Row
    let height: CGFloat
    @Binding var dragged: PaneID?
    @Binding var target: SidebarDropTarget?

    private func zone(_ info: DropInfo) -> PaneDropZone {
        let y = info.location.y
        if y < height * 0.25 { return .before }
        if y > height * 0.75 { return .after }
        return .into
    }

    /// Where the dragged pane would go, or nil when it cannot go there, such as into itself.
    private func place(_ info: DropInfo) -> PanePlace? {
        guard let dragged,
              let place = model.tree.place(forDropOn: row.id, zone: zone(info), childrenShown: !row.isFolded)
        else { return nil }
        var tree = model.tree
        return tree.move(dragged, to: place) ? place : nil
    }

    func validateDrop(info: DropInfo) -> Bool {
        place(info) != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard place(info) != nil else {
            if target?.row == row.id { target = nil }
            return DropProposal(operation: .forbidden)
        }
        target = SidebarDropTarget(row: row.id, zone: zone(info))
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if target?.row == row.id { target = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragged = nil
            target = nil
        }
        guard let dragged, let place = place(info) else { return false }
        model.move(dragged, to: place)
        return true
    }
}
