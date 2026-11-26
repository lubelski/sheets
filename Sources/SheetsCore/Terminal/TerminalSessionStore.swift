import Foundation
import Observation

/// Where a session's shell is.
public enum TerminalSessionStatus: Hashable, Sendable {
    case running
    /// The shell exited by itself, with a status from 0 to 255, or nil when a signal ended it.
    case exited(status: Int32?)
    /// The shell never started, with what went wrong.
    case failedToStart(String)

    public var isRunning: Bool { self == .running }
}

/// One terminal pane's live session, and what its shell has reported.
@MainActor
@Observable
public final class TerminalSessionRecord {
    public let paneID: PaneID
    public let engine: TerminalEngineID
    public let session: any TerminalSession
    public let launch: TerminalLaunch
    public fileprivate(set) var status: TerminalSessionStatus = .running
    /// The title the shell or a program in it set, if any. It is shown beside the pane's own
    /// title and never renames the pane.
    public fileprivate(set) var title: String?
    /// The working folder the shell last reported, if any.
    public fileprivate(set) var folder: String?

    init(paneID: PaneID, engine: TerminalEngineID, session: any TerminalSession, launch: TerminalLaunch) {
        self.paneID = paneID
        self.engine = engine
        self.session = session
        self.launch = launch
    }
}

/// The live sessions, one per terminal pane.
///
/// The rules:
///
/// - A terminal's session starts the first time its sheet is shown, covered or on top.
/// - It is kept while the pane is in the tree, whether its sheet shows or not. Going to a
///   sibling and coming back shows the same shell with its scrollback.
/// - It ends when the pane leaves the tree, which includes closing a pane above it, and when
///   the app quits (`endAll`).
/// - A shell that exits by itself leaves its session in place, marked exited, so its last
///   output stays readable. `restart` starts a new one.
///
/// `sync(tree:stack:)` applies the first three rules after any change to the tree or the stack.
@MainActor
@Observable
public final class TerminalSessionStore {
    public private(set) var records: [PaneID: TerminalSessionRecord] = [:]
    @ObservationIgnored public let engines: TerminalEngineRegistry
    @ObservationIgnored private let makeLaunch: (Pane) -> TerminalLaunch
    /// The look of every session, now and later.
    @ObservationIgnored public var appearance: TerminalAppearance {
        didSet {
            guard appearance != oldValue else { return }
            for record in records.values { record.session.apply(appearance) }
        }
    }
    /// The behavior of every session, now and later. Scrollback reaches only new sessions.
    @ObservationIgnored public var behavior: TerminalBehavior {
        didSet {
            guard behavior != oldValue else { return }
            for record in records.values { record.session.apply(behavior) }
        }
    }
    /// Called when the person clicks a link in a terminal, with the terminal's pane. This is
    /// where a page sheet will open from a link.
    @ObservationIgnored public var linkClicked: ((PaneID, TerminalLink, any TerminalSession) -> Void)?

    /// - Parameter launch: What a pane's session starts, such as
    ///   `TerminalLaunch.loginShell(in: pane.folder, programVersion:)`.
    public init(
        engines: TerminalEngineRegistry, appearance: TerminalAppearance = .standard,
        behavior: TerminalBehavior = .standard, launch: @escaping (Pane) -> TerminalLaunch
    ) {
        self.engines = engines
        self.appearance = appearance
        self.behavior = behavior
        self.makeLaunch = launch
    }

    /// The session for a pane, if it has one.
    public func record(for id: PaneID) -> TerminalSessionRecord? {
        records[id]
    }

    /// Brings the sessions in line with the tree and the stack: ends the sessions of panes that
    /// are no longer terminals in the tree, and starts one for each terminal shown in the stack
    /// that has none.
    public func sync(tree: PaneTree, stack: SheetStack) {
        endSessions(notIn: tree)
        for id in stack.entries {
            if let pane = tree.pane(id), pane.kind == .terminal { start(pane) }
        }
    }

    /// Ends the sessions of panes that are no longer terminals in the tree.
    public func endSessions(notIn tree: PaneTree) {
        for id in Array(records.keys) where tree.pane(id)?.kind != .terminal {
            end(id)
        }
    }

    /// The pane's session, started now if it has none. Nil for a pane that is not a terminal,
    /// or when there is no engine.
    @discardableResult
    public func start(_ pane: Pane) -> TerminalSessionRecord? {
        guard pane.kind == .terminal else { return nil }
        if let existing = records[pane.id] { return existing }
        guard let engine = engines.engine(for: pane.engine) else { return nil }
        let session = engine.makeSession(appearance: appearance, behavior: behavior)
        let record = TerminalSessionRecord(
            paneID: pane.id, engine: engine.id, session: session, launch: makeLaunch(pane))
        records[pane.id] = record
        session.apply(appearance)
        session.apply(behavior)
        session.events = { [weak self, weak record] event in
            guard let self, let record else { return }
            self.handle(event, from: record)
        }
        session.start(record.launch)
        return record
    }

    /// Ends the pane's session, if any, and starts a new one.
    @discardableResult
    public func restart(_ pane: Pane) -> TerminalSessionRecord? {
        end(pane.id)
        return start(pane)
    }

    /// Ends the pane's session, if it has one.
    public func end(_ id: PaneID) {
        guard let record = records.removeValue(forKey: id) else { return }
        record.session.events = nil
        record.session.end()
    }

    /// Ends every session, as when the app quits.
    public func endAll() {
        for id in Array(records.keys) { end(id) }
    }

    /// True when Escape belongs to the terminal on top rather than to the stack: the top
    /// sheet's pane has a session whose shell is running. Shells and programs such as `vim`
    /// need Escape. Once the shell has exited, Escape closes the sheet again.
    public func escapeGoesToTerminal(top: PaneID?) -> Bool {
        top.flatMap { records[$0] }?.status.isRunning ?? false
    }

    private func handle(_ event: TerminalEvent, from record: TerminalSessionRecord) {
        // A session that was ended or replaced has nothing more to say.
        guard records[record.paneID] === record else { return }
        switch event {
        case .titleChanged(let title):
            record.title = title.isEmpty ? nil : title
        case .folderChanged(let folder):
            record.folder = folder
        case .exited(let status):
            record.status = .exited(status: status)
        case .failedToStart(let reason):
            record.status = .failedToStart(reason)
        case .linkClicked(let link):
            linkClicked?(record.paneID, link, record.session)
        }
    }
}
