import AppKit
import SheetsCore
import SwiftUI

/// `--render-previews <folder>`: draws the main window's key states offscreen with the sample
/// panes, writes a PNG of each in light and dark, and exits. It never puts a window on screen,
/// never takes focus, and never reads or writes the app's real preferences.
@MainActor
enum PreviewRenderer {
    static let argument = "--render-previews"
    static let size = CGSize(width: 1000, height: 640)

    static func render(to folder: URL) {
        // No Dock icon, no menu bar, and no activation.
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            print("Could not create \(folder.path): \(error.localizedDescription)")
            exit(1)
        }

        // A throwaway defaults suite, emptied before and after.
        let suite = "dev.lubelski.sheets.preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Stand-in build details, so a render says the same thing on any Mac.
        let buildInfo = BuildInfo(version: "0.1", build: "12", commit: "1a2b3c4", signing: "Signed ad hoc")
        let updater = AppUpdater.unavailable()
        typealias ID = SamplePanes.ID
        let settings = SettingsSection.settingsID
        // A placeholder home folder, so the first-launch render names no real one.
        let home = "/home/someone"
        func sample(_ stack: SheetStack, renaming: PaneID? = nil) -> () -> SheetsModel {
            {
                let model = SheetsModel(
                    tree: SamplePanes.tree, defaults: defaults, stack: stack, animates: false, homeFolder: home)
                model.renaming = renaming
                return model
            }
        }
        let states: [(String, () -> SheetsModel)] = [
            ("sidebar", sample(SheetStack())),
            ("group-open", sample(SheetStack([ID.acmeWeb]))),
            ("terminal-over-group", sample(SheetStack([ID.acmeWeb, ID.devServer]))),
            ("page-over-terminal", sample(SheetStack([ID.acmeWeb, ID.devServer, ID.localhost]))),
            ("settings-open", sample(SheetStack([settings]))),
            ("settings-general-open", sample(SheetStack([settings, SettingsSection.general.paneID]))),
            ("settings-experiments-open", sample(SheetStack([settings, SettingsSection.experiments.paneID]))),
            ("renaming-in-sidebar", sample(SheetStack([ID.acmeWeb, ID.claude]), renaming: ID.claude)),
            ("first-launch", {
                let start = PaneEditor.firstLaunch(homeFolder: home, id: "first")
                return SheetsModel(
                    tree: start.tree, defaults: defaults, stack: start.stack, animates: false, homeFolder: home)
            }),
        ]
        let looks: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

        var written: [URL] = []
        for (name, makeModel) in states {
            for (look, appearance) in looks {
                let model = makeModel()
                let view = MainWindowView(model: model, updater: updater, buildInfo: buildInfo)
                    .defaultAppStorage(defaults)
                let url = folder.appending(path: "\(name)-\(look).png")
                guard let rep = draw(view, appearance: appearance),
                      let data = rep.representation(using: .png, properties: [:])
                else {
                    print("Could not render \(name)-\(look)")
                    continue
                }
                do {
                    try data.write(to: url)
                    written.append(url)
                } catch {
                    print("Could not write \(url.path): \(error.localizedDescription)")
                }
            }
        }
        for url in written { print(url.path) }
    }

    /// Draws a view in a borderless window that is never put on screen.
    private static func draw(_ view: some View, appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let root = view
            .frame(width: size.width, height: size.height)
            // A real window draws its background behind the content. This one is never on
            // screen, so draw it here, or areas without one come out transparent.
            .background(Color(nsColor: .windowBackgroundColor))
        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        // Give SwiftUI a moment to lay out. The window stays off screen.
        for _ in 0..<5 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        window.contentView = nil
        return rep
    }
}
