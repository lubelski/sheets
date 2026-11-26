import SheetsCore
import SwiftUI

/// The app's one scene: the main window. Started from `main.swift`.
///
/// There is no Settings window. Settings is a pane in the window's own tree, so Command-comma
/// opens it as a sheet over the sidebar.
struct SheetsApp: App {
    @State private var updater = AppUpdater()
    @State private var model = SheetsModel.firstLaunch()

    var body: some Scene {
        Window(AppName.display, id: "main") {
            MainWindowView(model: model, updater: updater)
                .frame(minWidth: 640, minHeight: 400)
                .standardTitleBar { TitleBarMenuButton(model: model, updater: updater) }
        }
        .defaultSize(width: 1000, height: 640)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isAvailable {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheck)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Terminal") { model.add(.terminal) }
                    .keyboardShortcut("t", modifiers: .command)
                Button("New Group") { model.add(.group) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Page") { model.add(.page) }
            }
            // Close takes the place of the window's Close item. With sheets open it closes the
            // top one's pane, and with only the sidebar showing it closes the window.
            CommandGroup(replacing: .saveItem) {
                Button(model.stack.isAtSidebar ? "Close Window" : "Close") { model.closeTop() }
                    .keyboardShortcut("w", modifiers: .command)
                Button("Rename…") { model.selection.map(model.startRenaming) }
                    .disabled(!(model.selection.map(model.tree.canEdit) ?? false))
            }
            // Back closes the top sheet, as Escape does. It works while a terminal has the
            // keyboard, where Escape goes to the shell.
            CommandMenu("Go") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.stack.isAtSidebar)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
