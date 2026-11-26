@testable import SheetsCore

/// An engine that runs nothing. Its sessions record what was asked of them, and a test plays
/// the shell's part with `emit`.
@MainActor
final class FakeTerminalEngine: TerminalEngine {
    let id: TerminalEngineID
    let name = "Fake"
    private(set) var made: [FakeTerminalSession] = []

    init(id: TerminalEngineID = .standard) {
        self.id = id
    }

    func makeSession(appearance: TerminalAppearance, behavior: TerminalBehavior) -> any TerminalSession {
        let session = FakeTerminalSession(engine: id, startingBehavior: behavior)
        made.append(session)
        return session
    }
}

@MainActor
final class FakeTerminalSession: TerminalSession {
    let engine: TerminalEngineID
    var events: ((TerminalEvent) -> Void)?
    private(set) var launches: [TerminalLaunch] = []
    private(set) var sizes: [(columns: Int, rows: Int)] = []
    private(set) var sent: [String] = []
    private(set) var appearances: [TerminalAppearance] = []
    private(set) var behaviors: [TerminalBehavior] = []
    /// The behavior the engine made the session with, which is where scrollback comes from.
    let startingBehavior: TerminalBehavior
    private(set) var opened: [TerminalLink] = []
    private(set) var endCount = 0

    init(engine: TerminalEngineID, startingBehavior: TerminalBehavior = .standard) {
        self.engine = engine
        self.startingBehavior = startingBehavior
    }

    var isRunning: Bool { !launches.isEmpty && endCount == 0 }

    func start(_ launch: TerminalLaunch) { launches.append(launch) }
    func resize(columns: Int, rows: Int) { sizes.append((columns, rows)) }
    func send(_ text: String) { sent.append(text) }
    func apply(_ appearance: TerminalAppearance) { appearances.append(appearance) }
    func apply(_ behavior: TerminalBehavior) { behaviors.append(behavior) }
    func openWithDefaultHandler(_ link: TerminalLink) { opened.append(link) }
    func end() { endCount += 1 }

    /// Plays the shell's part.
    func emit(_ event: TerminalEvent) { events?(event) }
}
