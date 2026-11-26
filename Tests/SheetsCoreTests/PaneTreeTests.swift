import Testing
@testable import SheetsCore

@Suite struct PaneTreeTests {
    typealias ID = SamplePanes.ID
    let tree = SamplePanes.tree

    @Test func findsPanesAtAnyDepth() {
        #expect(tree.pane(ID.acmeWeb)?.kind == .group)
        #expect(tree.pane(ID.devServer)?.title == "dev server")
        #expect(tree.pane(ID.localhost)?.kind == .page)
        #expect(tree.pane("missing") == nil)
        #expect(tree.contains(ID.scratch))
    }

    @Test func pathRunsFromTheTopLevelDownToThePane() {
        #expect(tree.path(to: ID.localhost) == [ID.acmeWeb, ID.devServer, ID.localhost])
        #expect(tree.path(to: ID.scratch) == [ID.scratch])
        #expect(tree.path(to: "missing") == nil)
    }

    @Test func parentIsTheStepAbove() {
        #expect(tree.parent(of: ID.localhost) == ID.devServer)
        #expect(tree.parent(of: ID.acmeWeb) == nil)
        #expect(tree.parent(of: "missing") == nil)
    }

    @Test func addsUnderAParentOrAtTheTopLevel() {
        var tree = tree
        let addedDocs = tree.add(Pane(id: "docs", kind: .page, title: "docs"), under: ID.claude)
        #expect(addedDocs)
        #expect(tree.path(to: "docs") == [ID.acmeWeb, ID.claude, "docs"])

        let addedNotes = tree.add(Pane(id: "notes", kind: .terminal, title: "notes"), under: nil)
        #expect(addedNotes)
        #expect(tree.roots.last?.id == "notes")

        // New children go last.
        let addedLogs = tree.add(Pane(id: "logs", kind: .terminal, title: "logs"), under: ID.acmeWeb)
        #expect(addedLogs)
        #expect(tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.devServer, ID.claude, "logs"])
    }

    @Test func refusesAMissingParentOrARepeatedID() {
        var tree = tree
        let underMissing = tree.add(Pane(id: "docs", kind: .page, title: "docs"), under: "missing")
        #expect(!underMissing)
        let repeated = tree.add(Pane(id: ID.claude, kind: .terminal, title: "again"), under: nil)
        #expect(!repeated)
        // An id repeated deeper inside the new pane counts too.
        let nested = Pane(id: "new", kind: .group, title: "new", children: [
            Pane(id: ID.scratch, kind: .terminal, title: "scratch"),
        ])
        let repeatedInside = tree.add(nested, under: nil)
        #expect(!repeatedInside)
        #expect(tree == SamplePanes.tree)
    }

    @Test func removesAPaneWithEverythingUnderIt() {
        var tree = tree
        let removed = tree.remove(ID.devServer)
        #expect(removed?.id == ID.devServer)
        #expect(!tree.contains(ID.devServer))
        #expect(!tree.contains(ID.localhost))
        #expect(tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.claude])

        let removedScratch = tree.remove(ID.scratch)
        #expect(removedScratch?.id == ID.scratch)
        #expect(tree.roots.map(\.id) == [ID.acmeWeb, ID.acmeAPI, ID.homelab])

        let removedMissing = tree.remove("missing")
        #expect(removedMissing == nil)
    }

    @Test func updatesAPaneInPlace() {
        var tree = tree
        let renamed = tree.update(ID.claude) { $0.title = "assistant" }
        #expect(renamed)
        #expect(tree.pane(ID.claude)?.title == "assistant")
        let renamedMissing = tree.update("missing") { $0.title = "x" }
        #expect(!renamedMissing)
    }

    @Test func sidebarRowsAreDepthFirstWithTheirDepth() {
        let rows = tree.sidebarRows()
        #expect(rows.map(\.title) == [
            "acme-web", "dev server", "localhost:5173", "claude", "acme-api", "homelab", "scratch",
        ])
        #expect(rows.map(\.depth) == [0, 1, 2, 1, 0, 0, 0])
        #expect(rows.map(\.hasChildren) == [true, true, false, false, false, false, false])
        #expect(rows.allSatisfy { !$0.isFolded })
    }

    @Test func foldingHidesEverythingUnderAPane() {
        let foldedGroup = tree.sidebarRows(folded: [ID.acmeWeb])
        #expect(foldedGroup.map(\.id) == [ID.acmeWeb, ID.acmeAPI, ID.homelab, ID.scratch])
        #expect(foldedGroup.first?.isFolded == true)

        let foldedTerminal = tree.sidebarRows(folded: [ID.devServer])
        #expect(foldedTerminal.map(\.id) == [
            ID.acmeWeb, ID.devServer, ID.claude, ID.acmeAPI, ID.homelab, ID.scratch,
        ])
    }

    @Test func foldingAPaneWithoutChildrenChangesNothing() {
        let rows = tree.sidebarRows(folded: [ID.scratch, ID.localhost])
        #expect(rows.map(\.id) == tree.sidebarRows().map(\.id))
        #expect(rows.allSatisfy { !$0.isFolded })
    }
}
