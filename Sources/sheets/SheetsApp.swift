import SheetsCore
import SwiftUI

/// The app's one scene: the main window. Started from `main.swift`.
///
/// There is no Settings window. Settings is a pane in the window's own tree, so Command-comma
/// opens it as a sheet over the sidebar.
struct SheetsApp: App {
    @State private var updater = AppUpdater()
    @State private var model = SheetsModel(tree: SamplePanes.tree)

    var body: some Scene {
        Window(AppName.display, id: "main") {
            MainWindowView(model: model, updater: updater)
                .frame(minWidth: 640, minHeight: 400)
                .standardTitleBar()
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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
