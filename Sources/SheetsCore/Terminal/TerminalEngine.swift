import Foundation

// The seam between the app and whatever draws a terminal and runs its shell.
//
// An engine makes sessions. A session runs one shell in a pseudo-terminal, keeps its screen and
// scrollback, and reports what happens to it as `TerminalEvent`s. Nothing here names an engine's
// own types, so a second engine is one more conformance and one more line where the app lists
// its engines. Each engine also has a view half, which lives in the app, since this module has
// no UI.

/// Names a terminal engine. Saved with a terminal pane, so it is a plain string.
public struct TerminalEngineID: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public var description: String { rawValue }

    /// SwiftTerm, an emulator and AppKit view written in Swift.
    public static let swiftTerm: TerminalEngineID = "swiftterm"

    /// The engine a terminal uses when it names none.
    public static let standard: TerminalEngineID = .swiftTerm
}

/// A link the person clicked in a terminal. The target is terminal output, so it is untrusted.
public struct TerminalLink: Hashable, Sendable {
    /// The link as the terminal found it: a URL, or a path it detected.
    public let target: String

    public init(target: String) {
        self.target = target
    }
}

/// Something that happened in a session.
public enum TerminalEvent: Hashable, Sendable {
    /// The shell or a program in it set the title.
    case titleChanged(String)
    /// The shell reported its working folder, as a path. Nil when it reported one that is not a
    /// folder on this Mac.
    case folderChanged(String?)
    /// The shell exited by itself. The status is from 0 to 255, or nil when a signal ended it.
    case exited(status: Int32?)
    /// The shell could not be started.
    case failedToStart(String)
    /// The person clicked a link.
    case linkClicked(TerminalLink)
}

/// One shell in one terminal, with its screen and scrollback.
///
/// A session lives as long as its pane, not as long as a view showing it. It is ended with
/// `end()`, never by going off screen.
@MainActor
public protocol TerminalSession: AnyObject {
    /// Called with each event, on the main actor.
    var events: ((TerminalEvent) -> Void)? { get set }

    /// Starts the shell. Called once per session.
    func start(_ launch: TerminalLaunch)

    /// Sets the size of the terminal in character cells. An engine whose view follows its own
    /// frame may do this by itself, and treats this as a request.
    func resize(columns: Int, rows: Int)

    /// Sends text to the shell as if it were typed.
    func send(_ text: String)

    /// Sets the font, colors, and cursor.
    func apply(_ appearance: TerminalAppearance)

    /// Sets the keyboard, mouse, and bell behavior. Scrollback is read when the session is
    /// made, so a change to it reaches only new sessions.
    func apply(_ behavior: TerminalBehavior)

    /// Opens a link the way the engine would by itself, after its own safety checks.
    func openWithDefaultHandler(_ link: TerminalLink)

    /// Ends the shell and everything it started, and lets go of the screen. No events follow.
    func end()
}

/// Makes sessions of one kind.
@MainActor
public protocol TerminalEngine {
    var id: TerminalEngineID { get }
    /// The engine's name, as a person would read it.
    var name: String { get }
    /// A session that starts with this look and behavior. Some of them, such as scrollback,
    /// can only be set here.
    func makeSession(appearance: TerminalAppearance, behavior: TerminalBehavior) -> any TerminalSession
}

extension TerminalEngine {
    /// A session with the built-in look and behavior.
    public func makeSession() -> any TerminalSession {
        makeSession(appearance: .standard, behavior: .standard)
    }
}

/// The engines the app has, by id.
@MainActor
public struct TerminalEngineRegistry {
    /// The engines, in the order they were given.
    public let engines: [any TerminalEngine]
    /// The engine used when a pane names none, or names one that is not here.
    public let fallback: TerminalEngineID

    public init(_ engines: [any TerminalEngine], fallback: TerminalEngineID = .standard) {
        self.engines = engines
        self.fallback = fallback
    }

    /// The ids of the engines, in order.
    public var ids: [TerminalEngineID] { engines.map(\.id) }

    /// The engine with an id. With no id, or one that is not here, the fallback engine, or the
    /// first engine when the fallback is not here either. Nil only when there are no engines.
    public func engine(for id: TerminalEngineID?) -> (any TerminalEngine)? {
        if let id, let engine = engines.first(where: { $0.id == id }) { return engine }
        return engines.first { $0.id == fallback } ?? engines.first
    }
}

extension TerminalEvent {
    /// The folder in a shell's report of its working folder (OSC 7), as a path. A report is a
    /// `file://` URL naming a host, or a plain path. Nil when it names another host, since
    /// then the folder is not on this Mac, or when it is not a path at all.
    ///
    /// - Parameter localHostNames: Names this Mac goes by, besides `localhost` and none.
    public static func folder(fromReport report: String, localHostNames: Set<String>) -> String? {
        if report.hasPrefix("/") { return report }
        guard let url = URL(string: report), url.scheme?.lowercased() == "file" else { return nil }
        let host = url.host(percentEncoded: false)?.lowercased() ?? ""
        let local = Set(localHostNames.map { $0.lowercased() })
        guard host.isEmpty || host == "localhost" || local.contains(host) else { return nil }
        let path = url.path(percentEncoded: false)
        return path.hasPrefix("/") ? path : nil
    }
}
