import AppKit
import SwiftUI

/// The app's name as shown to people.
enum AppName {
    static let display = "Sheets"
}

/// Gives the window it sits in a plain title bar with the app's name centered in it, so every
/// window says which app it belongs to. The content starts below the bar instead of running
/// under it, and there is no toolbar, which is what lets the title sit in the middle.
private struct StandardTitleBar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleBarView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? TitleBarView)?.apply()
    }

    final class TitleBarView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// Marks the label this view adds to the title bar, so it is added once per window.
        private static let labelID = NSUserInterfaceItemIdentifier("StandardTitleBarLabel")

        func apply() {
            guard let window else { return }
            if window.toolbar != nil { window.toolbar = nil }
            if window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.remove(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = false
            window.titlebarSeparatorStyle = .line
            // The window keeps its title for Mission Control and the Window menu, but the bar
            // does not draw it: the system puts it beside the window buttons, and this app
            // wants it in the middle. The label below draws it there instead.
            if window.title != AppName.display { window.title = AppName.display }
            window.titleVisibility = .hidden
            addCenteredLabel(to: window)
        }

        private func addCenteredLabel(to window: NSWindow) {
            guard let bar = window.standardWindowButton(.closeButton)?.superview,
                  !bar.subviews.contains(where: { $0.identifier == Self.labelID })
            else { return }
            let label = NSTextField(labelWithString: AppName.display)
            label.identifier = Self.labelID
            label.font = .titleBarFont(ofSize: NSFont.systemFontSize)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            ])
        }
    }
}

extension View {
    /// A plain title bar that says the app's name, the same on every window.
    func standardTitleBar() -> some View {
        navigationTitle(AppName.display).background(StandardTitleBar())
    }
}
