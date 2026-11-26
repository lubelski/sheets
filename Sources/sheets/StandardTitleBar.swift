import AppKit
import SwiftUI

/// The app's name as shown to people.
enum AppName {
    static let display = "Sheets"
}

/// Gives the window it sits in a plain title bar with the app's name centered in it, so every
/// window says which app it belongs to. The content starts below the bar instead of running
/// under it, and there is no toolbar, which is what lets the title sit in the middle.
///
/// A view can sit at the trailing end of the bar, in a title bar accessory. The accessory is
/// part of the window's frame, not its content, so nothing in the content, such as a sheet
/// sliding over, can cover it or take its clicks. The name stays centered on the whole bar.
private struct StandardTitleBar: NSViewRepresentable {
    let trailing: AnyView

    func makeNSView(context: Context) -> NSView { TitleBarView(trailing: trailing) }

    func updateNSView(_ view: NSView, context: Context) {
        guard let view = view as? TitleBarView else { return }
        view.trailing = trailing
        view.apply()
    }

    final class TitleBarView: NSView {
        var trailing: AnyView

        init(trailing: AnyView) {
            self.trailing = trailing
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not used") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        /// Marks the label this view adds to the title bar, so it is added once per window.
        private static let labelID = NSUserInterfaceItemIdentifier("StandardTitleBarLabel")
        /// Marks the accessory this view adds to the title bar, so it is added once per window.
        private static let trailingID = NSUserInterfaceItemIdentifier("StandardTitleBarTrailing")

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
            setTrailing(in: window)
        }

        /// Puts the trailing view in an accessory at the end of the bar, or updates the one
        /// already there.
        private func setTrailing(in window: NSWindow) {
            if let existing = window.titlebarAccessoryViewControllers.first(where: { $0.identifier == Self.trailingID }),
               let hosting = existing.view as? NSHostingView<AnyView> {
                hosting.rootView = trailing
                return
            }
            let hosting = NSHostingView(rootView: trailing)
            hosting.sizingOptions = [.intrinsicContentSize]
            // The accessory takes the width its view has when it is added.
            hosting.frame.size = hosting.fittingSize
            let accessory = NSTitlebarAccessoryViewController()
            accessory.identifier = Self.trailingID
            accessory.layoutAttribute = .trailing
            accessory.view = hosting
            window.addTitlebarAccessoryViewController(accessory)
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
    /// A plain title bar that says the app's name, the same on every window, with `trailing`
    /// at its trailing end.
    func standardTitleBar(@ViewBuilder trailing: () -> some View = { EmptyView() }) -> some View {
        navigationTitle(AppName.display).background(StandardTitleBar(trailing: AnyView(trailing())))
    }
}
