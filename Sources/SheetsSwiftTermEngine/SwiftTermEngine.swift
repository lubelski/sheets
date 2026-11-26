import AppKit
import Darwin
import SheetsCore
import SwiftTerm

// The SwiftTerm engine. SwiftTerm keeps a terminal's screen and scrollback in its AppKit view,
// so a session owns its view and outlives every place that shows it: the app moves the view
// into whichever sheet shows the pane, and the shell keeps running while it is in none.
//
// SwiftTerm parses the shell's output on its own thread, whether or not the view is in a
// window, so a terminal that is off screen keeps up and shows its latest output when it comes
// back.
//
// Nothing outside this target names a SwiftTerm type.

/// Makes SwiftTerm sessions.
@MainActor
public struct SwiftTermEngine: TerminalEngine {
    public let id = TerminalEngineID.swiftTerm
    public let name = "SwiftTerm"

    public init() {}

    public func makeSession(appearance: TerminalAppearance, behavior: TerminalBehavior) -> any TerminalSession {
        SwiftTermSession(appearance: appearance, behavior: behavior)
    }
}

/// One shell in a SwiftTerm view.
@MainActor
public final class SwiftTermSession: TerminalSession {
    public var events: ((TerminalEvent) -> Void)?
    /// The view the terminal draws in. The app puts it in a sheet and moves it between sheets.
    public var terminalView: NSView { view }
    /// The process id of the shell while it runs, or nil.
    public var shellProcessID: pid_t? {
        guard let process = view.process, process.running, process.shellPid > 0 else { return nil }
        return process.shellPid
    }

    private let view: SessionTerminalView
    private let reporter = Reporter()
    /// The last link request SwiftTerm made, so the link can be opened later with SwiftTerm's
    /// own checks.
    private var linkRequest: TerminalLinkRequest?
    private var hasEnded = false
    /// The cursor style last applied, so applying the same look again leaves a style a
    /// program set alone.
    private var lastCursorStyle: CursorStyle?

    /// Scrollback, and the cursor a program gets back when it resets the cursor, are set here
    /// for the life of the session. The rest is applied again by `apply`.
    init(appearance: TerminalAppearance, behavior: TerminalBehavior) {
        view = SessionTerminalView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 400), font: nil,
            options: TerminalOptions(
                cursorStyle: appearance.swiftTermCursorStyle, scrollback: max(behavior.scrollbackLines, 0)))
        apply(behavior)
        reporter.session = self
        view.processDelegate = reporter
        view.linkClicked = { [weak self] request in
            guard let self else { return }
            self.linkRequest = request
            self.events?(.linkClicked(TerminalLink(target: request.link)))
        }
    }

    public func start(_ launch: TerminalLaunch) {
        guard !hasEnded else { return }
        view.startProcess(
            executable: launch.executable, args: launch.arguments, environment: launch.environmentList,
            execName: launch.programName, currentDirectory: launch.folder)
    }

    public func resize(columns: Int, rows: Int) {
        guard columns > 0, rows > 0 else { return }
        view.resize(cols: columns, rows: rows)
    }

    public func send(_ text: String) {
        view.send(data: Array(text.utf8)[...])
    }

    public func apply(_ appearance: TerminalAppearance) {
        let size = CGFloat(appearance.fontSize)
        let font = appearance.fontName.flatMap { Self.font(named: $0, size: size) }
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if view.font != font { view.font = font }
        let spacing = CGFloat(appearance.lineSpacing)
        if view.lineSpacing != spacing { view.lineSpacing = spacing }
        let cursorStyle = appearance.swiftTermCursorStyle
        if cursorStyle != lastCursorStyle {
            // Changing the cursor's style from here sends nothing to the shell. A program can
            // still set its own style afterward.
            lastCursorStyle = cursorStyle
            view.setCursorStyle(cursorStyle)
        }
        view.nativeForegroundColor = appearance.foreground.nsColor
        view.nativeBackgroundColor = appearance.background.nsColor
        view.caretColor = appearance.cursor.nsColor
        view.selectedTextBackgroundColor = appearance.selection.nsColor
        if appearance.palette.count == 16 {
            view.installColors(appearance.palette.map(\.swiftTermColor))
        }
    }

    public func apply(_ behavior: TerminalBehavior) {
        switch behavior.optionAsMeta {
        case .off:
            // Option types characters such as é and #, as everywhere else on a Mac.
            view.optionAsMetaKey = false
        case .left:
            view.optionAsMetaKey = true
            view.optionAsMetaSide = .left
        case .right:
            view.optionAsMetaKey = true
            view.optionAsMetaSide = .right
        case .both:
            view.optionAsMetaKey = true
            view.optionAsMetaSide = .both
        }
        view.copyOnSelect = behavior.copyOnSelect ? .clipboard : .off
        if view.allowMouseReporting != behavior.mouseReporting { view.allowMouseReporting = behavior.mouseReporting }
        let bell: BellStyle = switch behavior.bell {
        case .none: .none
        case .sound: .sound
        case .visual: .visual
        case .soundAndVisual: .soundAndVisual
        }
        if view.bellStyle != bell { view.bellStyle = bell }
    }

    /// A font from a family name such as `Menlo`, in its regular face, or from a PostScript
    /// name such as `Menlo-Bold`.
    static func font(named name: String, size: CGFloat) -> NSFont? {
        NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
            ?? NSFont(name: name, size: size)
    }

    public func openWithDefaultHandler(_ link: TerminalLink) {
        guard let request = linkRequest, request.link == link.target else { return }
        request.openDefault()
    }

    /// Hangs up on the shell, as closing a terminal window does: the shell gets SIGHUP and
    /// passes it to its jobs. Then SwiftTerm's own `terminate()`, which sends SIGTERM, and
    /// shutting the view down. An interactive shell may ignore SIGTERM, so the hang-up comes
    /// first.
    public func end() {
        guard !hasEnded else { return }
        hasEnded = true
        events = nil
        if let pid = shellProcessID { kill(pid, SIGHUP) }
        view.terminate()
        view.removeFromSuperview()
        view.updateUiClosed()
    }

    fileprivate func report(_ event: TerminalEvent) {
        guard !hasEnded else { return }
        events?(event)
    }
}

/// SwiftTerm's process view, with clicked links reported instead of opened.
private final class SessionTerminalView: LocalProcessTerminalView {
    var linkClicked: ((TerminalLinkRequest) -> Void)?

    override func requestOpenLink(source: TerminalView, request: TerminalLinkRequest) {
        if let linkClicked {
            linkClicked(request)
        } else {
            super.requestOpenLink(source: source, request: request)
        }
    }
}

/// Turns SwiftTerm's process callbacks into `TerminalEvent`s.
@MainActor
private final class Reporter: LocalProcessTerminalViewDelegate {
    weak var session: SwiftTermSession?

    /// This Mac's host name, with and without its domain, and with `.local`, the forms a
    /// shell puts in its report. Read with `gethostname`, which never waits on the network.
    private static let localHostNames: Set<String> = {
        var buffer = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&buffer, buffer.count) == 0 else { return [] }
        let name = String(cString: buffer)
        let short = name.split(separator: ".").first.map(String.init) ?? name
        return [name, short, short + ".local"]
    }()

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        session?.report(.titleChanged(title))
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        let folder = directory.flatMap { TerminalEvent.folder(fromReport: $0, localHostNames: Self.localHostNames) }
        session?.report(.folderChanged(folder))
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        session?.report(.exited(status: exitCode))
    }

    func processFailedToStart(source: TerminalView, error: LocalProcessError) {
        session?.report(.failedToStart(String(describing: error)))
    }
}

extension TerminalAppearance {
    var swiftTermCursorStyle: CursorStyle {
        switch (cursorShape, cursorBlinks) {
        case (.block, true): .blinkBlock
        case (.block, false): .steadyBlock
        case (.underline, true): .blinkUnderline
        case (.underline, false): .steadyUnderline
        case (.bar, true): .blinkBar
        case (.bar, false): .steadyBar
        }
    }
}

extension TerminalColor {
    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    var swiftTermColor: SwiftTerm.Color {
        func channel(_ value: Double) -> UInt16 { UInt16((min(max(value, 0), 1) * 65535).rounded()) }
        return SwiftTerm.Color(red: channel(red), green: channel(green), blue: channel(blue))
    }
}
