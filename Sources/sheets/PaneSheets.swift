import SheetsCore
import SwiftUI

/// A group's sheet, under the title bar the stack draws: its children, each a row that opens
/// the child over it. A right click on a row edits that pane, and a right click elsewhere adds a
/// pane to the group.
struct GroupSheet: View {
    let model: SheetsModel
    let pane: Pane
    let openedID: PaneID?
    let open: (PaneID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if pane.children.isEmpty {
                Text("Nothing in this group yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(pane.children) { child in
                            SheetRow(
                                id: child.id, title: child.title, summary: child.summary,
                                isOpen: child.id == openedID, open: { open(child.id) })
                            .contextMenu { PaneContextMenu(model: model, id: child.id) }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .contextMenu { NewPaneMenuItems(model: model, near: pane.id) }
    }
}

/// A page's sheet. There is no web view yet, so under its title bar it says what will be there.
struct PlaceholderSheet: View {
    let pane: Pane

    var body: some View {
        VStack(spacing: 6) {
            Text("No page view yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("The page will load here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
