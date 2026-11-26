import AppKit
import SheetsCore
import SwiftUI
@testable import sheets

/// An engine whose sessions run nothing but have a view, as the real engine's do, so a test can
/// tell whether a terminal's sheet put its session's view on screen.
@MainActor
final class HostableFakeEngine: TerminalEngine {
    let id = TerminalEngineID.standard
    let name = "Hostable fake"
    private(set) var made: [HostableFakeSession] = []

    func makeSession(appearance: TerminalAppearance, behavior: TerminalBehavior) -> any TerminalSession {
        let session = HostableFakeSession()
        made.append(session)
        return session
    }
}

@MainActor
final class HostableFakeSession: TerminalSession, TerminalViewHosting {
    let terminalView = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
    var events: ((TerminalEvent) -> Void)?
    private(set) var launches: [TerminalLaunch] = []
    private(set) var endCount = 0

    var isRunning: Bool { !launches.isEmpty && endCount == 0 }

    func start(_ launch: TerminalLaunch) { launches.append(launch) }
    func resize(columns: Int, rows: Int) {}
    func send(_ text: String) {}
    func apply(_ appearance: TerminalAppearance) {}
    func apply(_ behavior: TerminalBehavior) {}
    func openWithDefaultHandler(_ link: TerminalLink) {}
    func end() { endCount += 1 }
}

/// The app's main window, drawn in a window that is never put on screen, with a model that
/// animates its changes as the app's does. Nothing takes focus or shows in the Dock.
@MainActor
final class WindowHarness {
    static let home = "/home/someone"

    let engine: HostableFakeEngine
    let model: SheetsModel
    private let window: NSWindow
    private let hosting: NSView

    init(
        tree: PaneTree, stack: SheetStack, engines: [any TerminalEngine]? = nil, animates: Bool = true
    ) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let engine = HostableFakeEngine()
        self.engine = engine
        let store = TerminalSessionStore(engines: TerminalEngineRegistry(engines ?? [engine])) { pane in
            TerminalLaunch(executable: "/bin/zsh", folder: pane.folder ?? Self.home, environment: [:])
        }
        let defaults = UserDefaults(suiteName: "sheets-tests-\(UUID().uuidString)")!
        model = SheetsModel(
            tree: tree, defaults: defaults, stack: stack, animates: animates, homeFolder: Self.home,
            terminals: store, config: Self.emptyConfig())
        let size = CGSize(width: 1000, height: 640)
        let view = NSHostingView(rootView: MainWindowView(model: model, updater: AppUpdater.unavailable())
            .frame(width: size.width, height: size.height)
            .defaultAppStorage(defaults))
        view.frame = CGRect(origin: .zero, size: size)
        hosting = view
        window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: size), styleMask: [.titled],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        settle()
    }

    /// A config file that does not exist and is never written, so every setting is at its
    /// default.
    static func emptyConfig() -> ConfigStore {
        let path = FileManager.default.temporaryDirectory.appending(path: "sheets-tests-\(UUID().uuidString)/config").path
        return ConfigStore(path: path, watches: false)
    }

    /// The first time the app starts: one terminal in the home folder, open.
    static func firstLaunch() -> WindowHarness {
        let start = PaneEditor.firstLaunch(homeFolder: home)
        return WindowHarness(tree: start.tree, stack: start.stack)
    }

    /// Lets SwiftUI draw and any animation finish.
    func settle() {
        for _ in 0..<8 {
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
    }

    func session(_ id: PaneID) -> HostableFakeSession? {
        model.terminals?.record(for: id)?.session as? HostableFakeSession
    }

    /// True when the pane's terminal has a running session whose view is in the window.
    func showsShell(_ id: PaneID) -> Bool {
        guard let session = session(id) else { return false }
        return session.isRunning && session.terminalView.window === window
    }

    /// The panes that have a session.
    var sessionIDs: Set<PaneID> {
        Set(model.terminals.map { Array($0.records.keys) } ?? [])
    }

    /// The terminal panes in the tree.
    var terminalIDs: [PaneID] {
        func visit(_ panes: [Pane]) -> [PaneID] {
            panes.flatMap { ($0.kind == .terminal ? [$0.id] : []) + visit($0.children) }
        }
        return visit(model.tree.roots)
    }

    func close() {
        window.contentView = nil
    }
}
