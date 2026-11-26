import Testing
@testable import SheetsCore

@Suite struct PaneEditingTests {
    typealias ID = SamplePanes.ID
    let tree = SamplePanes.tree.addingSettings()
    let settings = SettingsSection.settingsID
    let general = SettingsSection.general.paneID
    let home = "/home/someone"

    func editor(_ stack: [PaneID] = []) -> PaneEditor {
        PaneEditor(tree: tree, stack: SheetStack(stack))
    }

    // MARK: Where a new pane goes

    @Test func aNewPaneGoesLastInASelectedGroup() {
        #expect(tree.placeForNewPane(near: ID.acmeWeb) == PanePlace(parent: ID.acmeWeb, index: 2))
        #expect(tree.placeForNewPane(near: ID.homelab) == PanePlace(parent: ID.homelab, index: 0))
    }

    @Test func aNewPaneGoesJustAfterASelectedTerminalOrPage() {
        #expect(tree.placeForNewPane(near: ID.devServer) == PanePlace(parent: ID.acmeWeb, index: 1))
        #expect(tree.placeForNewPane(near: ID.localhost) == PanePlace(parent: ID.devServer, index: 1))
        #expect(tree.placeForNewPane(near: ID.scratch) == PanePlace(parent: nil, index: 4))
    }

    @Test func withNothingSelectedANewPaneGoesLastAboveSettings() {
        let end = PanePlace(parent: nil, index: 4)
        #expect(tree.placeForNewPane(near: nil) == end)
        #expect(tree.placeForNewPane(near: settings) == end)
        #expect(tree.placeForNewPane(near: general) == end)
        #expect(tree.placeForNewPane(near: "missing") == end)
    }

    // MARK: Adding

    @Test func addingATerminalPutsItInPlaceAndOpensIt() {
        var editor = editor([ID.acmeWeb])
        let id = editor.add(.terminal, near: ID.acmeWeb, homeFolder: home, id: "new")
        #expect(id == "new")
        #expect(editor.tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.devServer, ID.claude, "new"])
        #expect(editor.stack == SheetStack([ID.acmeWeb, "new"]))
        #expect(editor.tree.pane("new")?.title == "~")
        #expect(editor.tree.pane("new")?.folder == home)
    }

    @Test func aNewChildOfTheOpenGroupSlidesInAndANewSiblingSwaps() {
        var child = editor([ID.acmeWeb])
        child.add(.terminal, near: ID.acmeWeb, homeFolder: home, id: "new")
        #expect(SheetStackChange(from: SheetStack([ID.acmeWeb]), to: child.stack, in: child.tree) == .open)

        var sibling = editor([ID.acmeWeb, ID.devServer])
        sibling.add(.terminal, near: ID.devServer, homeFolder: home, id: "new")
        #expect(sibling.stack == SheetStack([ID.acmeWeb, "new"]))
        #expect(sibling.tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.devServer, "new", ID.claude])
        #expect(
            SheetStackChange(from: SheetStack([ID.acmeWeb, ID.devServer]), to: sibling.stack, in: sibling.tree)
                == .swap(depth: 2, direction: .fromBelow))
    }

    @Test func addingAtTheTopLevelStaysAboveSettings() {
        var editor = editor([settings, general])
        editor.add(.group, near: settings, homeFolder: home, id: "new")
        #expect(editor.tree.roots.map(\.id) == [ID.acmeWeb, ID.acmeAPI, ID.homelab, ID.scratch, "new", settings])
        #expect(editor.stack == SheetStack(["new"]))
        #expect(editor.tree.pane("new")?.title == "New Group")
        #expect(editor.tree.pane("new")?.folder == nil)

        // An index past the end still lands above Settings.
        var tree = tree
        tree.insert(Pane(id: "late", kind: .page, title: "late"), at: PanePlace(parent: nil, index: 99))
        #expect(tree.roots.suffix(2).map(\.id) == ["late", settings])
    }

    @Test func addingAPageUnderAGivenPane() {
        var editor = editor()
        editor.add(.page, at: PanePlace(parent: ID.claude, index: 0), homeFolder: home, id: "docs")
        #expect(editor.tree.path(to: "docs") == [ID.acmeWeb, ID.claude, "docs"])
        #expect(editor.tree.pane("docs")?.title == "New Page")
        #expect(editor.tree.pane("docs")?.folder == nil)
        #expect(editor.stack == SheetStack([ID.acmeWeb, ID.claude, "docs"]))
    }

    @Test func nothingGoesUnderSettingsAndNoSettingsPaneIsAdded() {
        var editor = editor([settings])
        do {
            let result = editor.add(.terminal, at: PanePlace(parent: settings, index: 0), homeFolder: home) == nil
            #expect(result)
        }
        do {
            let result = editor.add(.terminal, at: PanePlace(parent: general, index: 0), homeFolder: home) == nil
            #expect(result)
        }
        do {
            let result = editor.add(.settings, near: nil, homeFolder: home) == nil
            #expect(result)
        }
        do {
            let result = editor.add(.terminal, at: PanePlace(parent: "missing", index: 0), homeFolder: home) == nil
            #expect(result)
        }
        #expect(editor.tree == tree)
        #expect(editor.stack == SheetStack([settings]))
    }

    @Test func aNewTerminalStartsInItsNearestGroupsFolder() {
        var tree = tree
        tree.update(ID.acmeWeb) { $0.folder = "/work/acme-web" }
        var editor = PaneEditor(tree: tree)
        editor.add(.terminal, at: PanePlace(parent: ID.devServer, index: 0), homeFolder: home, id: "deep")
        #expect(editor.tree.pane("deep")?.folder == "/work/acme-web")
        #expect(editor.tree.pane("deep")?.title == "acme-web")

        // A group without a folder falls back to the home folder.
        editor.add(.terminal, near: ID.acmeAPI, homeFolder: home, id: "api")
        #expect(editor.tree.pane("api")?.folder == home)

        // A nearer group's folder wins.
        editor.add(.group, at: PanePlace(parent: ID.acmeWeb, index: 0), homeFolder: home, id: "inner")
        editor.tree.update("inner") { $0.folder = "/work/acme-web/docs/" }
        editor.add(.terminal, near: "inner", homeFolder: home, id: "inner-terminal")
        #expect(editor.tree.pane("inner-terminal")?.folder == "/work/acme-web/docs/")
        #expect(editor.tree.pane("inner-terminal")?.title == "docs")
    }

    @Test func theStartingFolderReplacesOnlyTheHomeFolderFallback() {
        var tree = tree
        tree.update(ID.acmeWeb) { $0.folder = "/work/acme-web" }
        var editor = PaneEditor(tree: tree)
        let start = "/home/someone/Projects"
        // A group's folder still wins.
        editor.add(.terminal, at: PanePlace(parent: ID.devServer, index: 0), homeFolder: home, startingFolder: start, id: "deep")
        #expect(editor.tree.pane("deep")?.folder == "/work/acme-web")
        // With no group folder above it, the starting folder, named relative to home.
        editor.add(.terminal, near: ID.acmeAPI, homeFolder: home, startingFolder: start, id: "api")
        #expect(editor.tree.pane("api")?.folder == start)
        #expect(editor.tree.pane("api")?.title == "Projects")
        // The first launch's terminal starts there too, and home is still called ~.
        let first = PaneEditor.firstLaunch(homeFolder: home, startingFolder: start, id: "first")
        #expect(first.tree.pane("first")?.folder == start)
        #expect(PaneEditor.firstLaunch(homeFolder: home, startingFolder: home, id: "f").tree.pane("f")?.title == "~")
    }

    @Test func aTerminalIsNamedForItsFolder() {
        #expect(PaneTree.title(forFolder: home, home: home) == "~")
        #expect(PaneTree.title(forFolder: home + "/", home: home) == "~")
        #expect(PaneTree.title(forFolder: "/work/acme-web", home: home) == "acme-web")
        #expect(PaneTree.title(forFolder: "/", home: home) == "/")
    }

    @Test func newIDsAreUnique() {
        #expect(PaneID.unique() != PaneID.unique())
    }

    @Test func firstLaunchIsOneOpenTerminalInTheHomeFolder() {
        let editor = PaneEditor.firstLaunch(homeFolder: home, id: "first")
        #expect(editor.tree.roots == [Pane(id: "first", kind: .terminal, title: "~", folder: home)])
        #expect(editor.stack == SheetStack(["first"]))
    }

    // MARK: Closing

    @Test func closingAPaneClosesEverythingUnderIt() {
        var editor = editor()
        let closed = editor.close(ID.devServer)
        #expect(closed?.id == ID.devServer)
        #expect(!editor.tree.contains(ID.localhost))
        #expect(editor.tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.claude])
    }

    @Test func closingTheOpenPaneClosesItsSheet() {
        var editor = editor([ID.acmeWeb, ID.claude])
        editor.close(ID.claude)
        #expect(editor.stack == SheetStack([ID.acmeWeb]))
        #expect(SheetStackChange(from: SheetStack([ID.acmeWeb, ID.claude]), to: editor.stack, in: editor.tree) == .back)
    }

    @Test func closingAParentClosesEverySheetAboveIt() {
        var editor = editor([ID.acmeWeb, ID.devServer, ID.localhost])
        editor.close(ID.acmeWeb)
        #expect(editor.stack == SheetStack())

        var middle = self.editor([ID.acmeWeb, ID.devServer, ID.localhost])
        middle.close(ID.devServer)
        #expect(middle.stack == SheetStack([ID.acmeWeb]))
    }

    @Test func closingAPaneThatIsNotOpenLeavesTheStack() {
        var editor = editor([ID.acmeWeb, ID.devServer])
        editor.close(ID.claude)
        #expect(editor.stack == SheetStack([ID.acmeWeb, ID.devServer]))
    }

    @Test func settingsCannotBeClosed() {
        var editor = editor([settings, general])
        do {
            let result = editor.close(settings) == nil
            #expect(result)
        }
        do {
            let result = editor.close(general) == nil
            #expect(result)
        }
        do {
            let result = editor.close("missing") == nil
            #expect(result)
        }
        #expect(editor.tree == tree)
        #expect(editor.stack == SheetStack([settings, general]))
    }

    @Test func onlyClosingAPaneWithChildrenAsksFirst() {
        let editor = editor()
        #expect(editor.closingNeedsConfirmation(ID.acmeWeb))
        #expect(editor.closingNeedsConfirmation(ID.devServer))
        #expect(!editor.closingNeedsConfirmation(ID.claude))
        #expect(!editor.closingNeedsConfirmation(ID.homelab))
        #expect(!editor.closingNeedsConfirmation(settings))
    }

    // MARK: Renaming

    @Test func renamingTrimsAndRefusesBlankTitles() {
        var editor = editor([ID.acmeWeb])
        do {
            let result = editor.rename(ID.claude, to: "  assistant \n")
            #expect(result)
        }
        #expect(editor.tree.pane(ID.claude)?.title == "assistant")
        do {
            let result = !editor.rename(ID.claude, to: "   ")
            #expect(result)
        }
        #expect(editor.tree.pane(ID.claude)?.title == "assistant")
        do {
            let result = !editor.rename("missing", to: "x")
            #expect(result)
        }
        #expect(editor.stack == SheetStack([ID.acmeWeb]))
    }

    @Test func renamingMarksAPaneNamedByHand() {
        var editor = editor([ID.acmeWeb])
        #expect(editor.tree.pane(ID.claude)?.isNamedByHand == false)
        let renamed = editor.rename(ID.claude, to: "assistant")
        #expect(renamed)
        #expect(editor.tree.pane(ID.claude)?.isNamedByHand == true)
    }

    @Test func keepingTheSameNameChangesNothing() {
        // A rename that ends without an edit, such as by clicking away, does not mark the pane
        // named by hand, so its shell's title still shows.
        var editor = editor([ID.acmeWeb])
        let renamed = editor.rename(ID.claude, to: " claude ")
        #expect(!renamed)
        #expect(editor.tree.pane(ID.claude)?.isNamedByHand == false)
    }

    @Test func newPanesAreNotNamedByHand() {
        var editor = editor()
        let added = editor.add(.terminal, near: nil, homeFolder: "/home/someone", id: "new")
        #expect(added == "new")
        #expect(editor.tree.pane("new")?.isNamedByHand == false)
        #expect(PaneEditor.firstLaunch(homeFolder: "/home/someone", id: "first").tree.pane("first")?.isNamedByHand == false)
    }

    @Test func settingsCannotBeRenamed() {
        var editor = editor()
        do {
            let result = !editor.rename(settings, to: "Preferences")
            #expect(result)
        }
        do {
            let result = !editor.rename(general, to: "Main")
            #expect(result)
        }
        #expect(editor.tree == tree)
    }

    // MARK: Moving

    @Test func movingWithinTheSameListCountsPlacesBeforeTheMove() {
        var tree = tree
        // Just below `homelab`, which is index 3 before `acme-web` leaves index 0.
        do {
            let result = tree.move(ID.acmeWeb, to: PanePlace(parent: nil, index: 3))
            #expect(result)
        }
        #expect(tree.roots.map(\.id) == [ID.acmeAPI, ID.homelab, ID.acmeWeb, ID.scratch, settings])

        do {
            let result = tree.move(ID.scratch, to: PanePlace(parent: nil, index: 0))
            #expect(result)
        }
        #expect(tree.roots.map(\.id) == [ID.scratch, ID.acmeAPI, ID.homelab, ID.acmeWeb, settings])
    }

    @Test func movingToJustAboveOrBelowItselfChangesNothing() {
        var tree = tree
        do {
            let result = tree.move(ID.acmeAPI, to: PanePlace(parent: nil, index: 1))
            #expect(result)
        }
        do {
            let result = tree.move(ID.acmeAPI, to: PanePlace(parent: nil, index: 2))
            #expect(result)
        }
        #expect(tree == self.tree)
    }

    @Test func movingToAnotherParentTakesEverythingUnderIt() {
        var tree = tree
        do {
            let result = tree.move(ID.devServer, to: PanePlace(parent: ID.homelab, index: 0))
            #expect(result)
        }
        #expect(tree.path(to: ID.localhost) == [ID.homelab, ID.devServer, ID.localhost])
        #expect(tree.pane(ID.acmeWeb)?.children.map(\.id) == [ID.claude])
    }

    @Test func movingNeverGoesBelowSettings() {
        var tree = tree
        do {
            let result = tree.move(ID.acmeWeb, to: PanePlace(parent: nil, index: 99))
            #expect(result)
        }
        #expect(tree.roots.map(\.id) == [ID.acmeAPI, ID.homelab, ID.scratch, ID.acmeWeb, settings])
    }

    @Test func aPaneCannotMoveIntoItselfOrUnderItself() {
        var tree = tree
        do {
            let result = !tree.move(ID.acmeWeb, to: PanePlace(parent: ID.acmeWeb, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(ID.acmeWeb, to: PanePlace(parent: ID.devServer, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(ID.acmeWeb, to: PanePlace(parent: ID.localhost, index: 0))
            #expect(result)
        }
        #expect(tree == self.tree)
    }

    @Test func settingsCannotMoveAndNothingMovesUnderIt() {
        var tree = tree
        do {
            let result = !tree.move(settings, to: PanePlace(parent: nil, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(general, to: PanePlace(parent: nil, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(ID.scratch, to: PanePlace(parent: settings, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(ID.scratch, to: PanePlace(parent: general, index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move(ID.scratch, to: PanePlace(parent: "missing", index: 0))
            #expect(result)
        }
        do {
            let result = !tree.move("missing", to: PanePlace(parent: nil, index: 0))
            #expect(result)
        }
        #expect(tree == self.tree)
    }

    @Test func theStackFollowsAMovedPane() {
        var editor = editor([ID.acmeWeb, ID.devServer, ID.localhost])
        do {
            let result = editor.move(ID.devServer, to: PanePlace(parent: ID.homelab, index: 0))
            #expect(result)
        }
        #expect(editor.stack == SheetStack([ID.homelab, ID.devServer, ID.localhost]))

        // A pane moved out from under the open one leaves the stack as it was.
        var other = self.editor([ID.acmeWeb, ID.devServer])
        do {
            let result = other.move(ID.claude, to: PanePlace(parent: nil, index: 0))
            #expect(result)
        }
        #expect(other.stack == SheetStack([ID.acmeWeb, ID.devServer]))
    }

    // MARK: Dropping a row on a row

    @Test func dropZonesPickAPlace() {
        #expect(tree.place(forDropOn: ID.claude, zone: .before) == PanePlace(parent: ID.acmeWeb, index: 1))
        #expect(tree.place(forDropOn: ID.claude, zone: .after) == PanePlace(parent: ID.acmeWeb, index: 2))
        #expect(tree.place(forDropOn: ID.claude, zone: .into) == PanePlace(parent: ID.claude, index: 0))
        #expect(tree.place(forDropOn: ID.acmeWeb, zone: .into) == PanePlace(parent: ID.acmeWeb, index: 2))
        // Below a row whose children show under it is above its first child.
        #expect(tree.place(forDropOn: ID.acmeWeb, zone: .after) == PanePlace(parent: ID.acmeWeb, index: 0))
        #expect(tree.place(forDropOn: ID.acmeWeb, zone: .after, childrenShown: false) == PanePlace(parent: nil, index: 1))
        #expect(tree.place(forDropOn: settings, zone: .before) == nil)
        #expect(tree.place(forDropOn: "missing", zone: .before) == nil)
    }

    // MARK: The stack after a change

    @Test func aStackKeepsWhatIsStillAPath() {
        var tree = tree
        tree.remove(ID.devServer)
        #expect(SheetStack([ID.acmeWeb, ID.devServer, ID.localhost]).following(tree) == SheetStack([ID.acmeWeb]))
        #expect(SheetStack([ID.acmeWeb, ID.claude]).following(tree) == SheetStack([ID.acmeWeb, ID.claude]))
        #expect(SheetStack().following(tree) == SheetStack())
        #expect(SheetStack(["missing"]).following(tree) == SheetStack())
    }
}
