import SheetsCore
import SwiftUI

/// The app's one scene: the main window. Started from `main.swift`.
struct SheetsApp: App {
    @State private var updater = AppUpdater()

    var body: some Scene {
        Window(AppName.display, id: "main") {
            MainWindowView(tree: SamplePanes.tree)
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
        }
    }
}
