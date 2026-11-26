import SheetsCore
import SwiftUI

/// A group's sheet: its children, each a row that opens the child over it.
struct GroupSheet: View {
    let pane: Pane
    let openedID: PaneID?
    let open: (PaneID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: pane.title)
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
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// A terminal's or a page's sheet. There is no terminal engine or web view yet, so under its
/// title bar it says what will be there.
struct PlaceholderSheet: View {
    let pane: Pane

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: pane.title)
            VStack(spacing: 6) {
                Text(pane.kind == .page ? "No page view yet" : "No terminal yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(pane.kind == .page ? "The page will load here." : "A shell will run here.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
