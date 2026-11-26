import SheetsCore
import SwiftUI

/// The main window for now: the pane tree on the left and a stand-in for the pane area.
/// This is a shell to hang later work on, not the design.
struct MainWindowView: View {
    let tree: PaneTree
    @State private var stack = SheetStack()

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(rows: tree.sidebarRows(), selected: stack.top) { id in
                if let shown = SheetStack(showing: id, in: tree) { stack = shown }
            }
            .frame(width: 220)
            Divider()
            PanePlaceholderView(titles: stack.entries.compactMap { tree.pane($0)?.title })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// The sidebar: one row per pane, indented by its depth in the tree.
struct SidebarView: View {
    let rows: [PaneTree.Row]
    let selected: PaneID?
    let select: (PaneID) -> Void

    var body: some View {
        List(rows) { row in
            Button { select(row.id) } label: {
                Text(row.title)
                    .fontWeight(row.id == selected ? .semibold : .regular)
                    .padding(.leading, CGFloat(row.depth) * 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.sidebar)
    }
}

/// Where the sheets will go. For now it names the path that is open.
struct PanePlaceholderView: View {
    /// The titles of the open panes, bottom sheet first.
    let titles: [String]

    var body: some View {
        if titles.isEmpty {
            Text("No pane open")
                .foregroundStyle(.secondary)
        } else {
            Text(titles.joined(separator: " › "))
                .font(.title3)
        }
    }
}
