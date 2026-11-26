import Darwin
import Foundation
import SheetsCore
import SwiftTerm
import Testing
@testable import SheetsSwiftTermEngine

// These start real programs in a pseudo-terminal, with no window, and wait for them to end.
// Each test ends what it started.

@MainActor
@Suite(.serialized) struct SwiftTermSessionTests {
    func launch(_ executable: String, _ arguments: [String], programName: String? = nil) -> TerminalLaunch {
        TerminalLaunch(
            executable: executable, arguments: arguments, programName: programName, folder: "/",
            environment: ["TERM": "xterm-256color", "PATH": "/usr/bin:/bin"])
    }

    /// Waits up to a few seconds for a condition.
    func wait(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<200 where !condition() {
            try await Task.sleep(for: .milliseconds(25))
        }
        return condition()
    }

    static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    @Test func aProgramThatExitsReportsItsStatus() async throws {
        let session = SwiftTermEngine().makeSession() as! SwiftTermSession
        var events: [TerminalEvent] = []
        session.events = { events.append($0) }
        session.apply(TerminalAppearance.standard)
        session.start(launch("/bin/sh", ["-c", "printf 'ready'; exit 3"]))
        #expect(try await wait { events.contains(.exited(status: 3)) })
        session.end()
    }

    @Test func theTitleAProgramSetsIsReported() async throws {
        let session = SwiftTermEngine().makeSession() as! SwiftTermSession
        var events: [TerminalEvent] = []
        session.events = { events.append($0) }
        session.start(launch("/bin/sh", ["-c", "printf '\\033]2;placeholder title\\007'; sleep 0.2"]))
        #expect(try await wait { events.contains(.titleChanged("placeholder title")) })
        session.end()
    }

    @Test func endingHangsUpOnAnInteractiveShell() async throws {
        let session = SwiftTermEngine().makeSession() as! SwiftTermSession
        // An interactive shell ignores SIGTERM, so this only ends if it is hung up on.
        session.start(launch("/bin/zsh", ["-f", "-i"], programName: "-zsh"))
        #expect(try await wait { session.shellProcessID != nil })
        let pid = try #require(session.shellProcessID)
        var events: [TerminalEvent] = []
        session.events = { events.append($0) }
        session.end()
        #expect(try await wait { Self.isGone(pid) })
        // Nothing is reported after the session ends.
        try await Task.sleep(for: .milliseconds(100))
        #expect(events.isEmpty)
    }

    @Test func aProgramThatCannotRunExitsWith127() async throws {
        let session = SwiftTermEngine().makeSession() as! SwiftTermSession
        var events: [TerminalEvent] = []
        session.events = { events.append($0) }
        session.start(launch("/nowhere/no-such-shell", []))
        #expect(try await wait {
            events.contains { event in
                switch event {
                case .exited(status: 127), .failedToStart: true
                default: false
                }
            }
        })
        session.end()
    }

    @Test func settingsReachTheTerminalView() throws {
        var appearance = TerminalAppearance.standard
        appearance.lineSpacing = 1.2
        appearance.cursorShape = .bar
        appearance.cursorBlinks = false
        let behavior = TerminalBehavior(
            scrollbackLines: 100, optionAsMeta: .left, copyOnSelect: true, mouseReporting: false, bell: .visual)
        let session = SwiftTermEngine().makeSession(appearance: appearance, behavior: behavior) as! SwiftTermSession
        session.apply(appearance)
        let view = try #require(session.terminalView as? TerminalView)
        #expect(view.optionAsMetaKey)
        #expect(view.optionAsMetaSide == .left)
        #expect(view.copyOnSelect == .clipboard)
        #expect(!view.allowMouseReporting)
        #expect(view.bellStyle == .visual)
        #expect(abs(view.lineSpacing - 1.2) < 0.0001)

        session.apply(TerminalBehavior.standard)
        #expect(!view.optionAsMetaKey)
        #expect(view.copyOnSelect == .off)
        #expect(view.allowMouseReporting)
        #expect(view.bellStyle == .sound)
        session.end()
    }

    @Test func aFontFamilyNameFindsItsRegularFace() {
        #expect(SwiftTermSession.font(named: "Menlo", size: 12)?.familyName == "Menlo")
        #expect(SwiftTermSession.font(named: "Menlo-Bold", size: 12)?.fontName == "Menlo-Bold")
        #expect(SwiftTermSession.font(named: "No Such Font Family", size: 12) == nil)
    }
}
