import Foundation

/// Stand-in panes for previews, renders, and tests. Placeholder names only.
public enum SamplePanes {
    /// Ids of the sample panes, so previews and tests can name them.
    public enum ID {
        public static let acmeWeb: PaneID = "acme-web"
        public static let devServer: PaneID = "acme-web/dev-server"
        public static let localhost: PaneID = "acme-web/dev-server/localhost-5173"
        public static let claude: PaneID = "acme-web/claude"
        public static let acmeAPI: PaneID = "acme-api"
        public static let homelab: PaneID = "homelab"
        public static let scratch: PaneID = "scratch"
    }

    /// A group `acme-web` holding the terminals `dev server` and `claude`, with a page
    /// `localhost:5173` opened from `dev server`. Then two empty groups, `acme-api` and
    /// `homelab`, and a loose terminal, `scratch`, at the top level.
    public static let tree = PaneTree(roots: [
        Pane(id: ID.acmeWeb, kind: .group, title: "acme-web", children: [
            Pane(id: ID.devServer, kind: .terminal, title: "dev server", children: [
                Pane(id: ID.localhost, kind: .page, title: "localhost:5173"),
            ]),
            Pane(id: ID.claude, kind: .terminal, title: "claude"),
        ]),
        Pane(id: ID.acmeAPI, kind: .group, title: "acme-api"),
        Pane(id: ID.homelab, kind: .group, title: "homelab"),
        Pane(id: ID.scratch, kind: .terminal, title: "scratch"),
    ])
}
