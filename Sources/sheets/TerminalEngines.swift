import AppKit
import SheetsCore
import SheetsSwiftTermEngine

// The terminal engines the app has. This is the one file in the app that names an engine: a
// second engine is one more entry in `registry()` and one more `TerminalViewHosting`
// conformance here.

enum TerminalEngines {
    /// Every engine, with the standard one as the fallback.
    @MainActor
    static func registry() -> TerminalEngineRegistry {
        TerminalEngineRegistry([SwiftTermEngine()], fallback: .standard)
    }
}

/// The view half of an engine's session: the view its terminal draws in. The session owns the
/// view and keeps it while the pane lives. A sheet that shows the pane borrows it, so the view
/// moves between sheets and the shell keeps running with none.
@MainActor
protocol TerminalViewHosting: AnyObject {
    var terminalView: NSView { get }
}

extension SwiftTermSession: TerminalViewHosting {}
