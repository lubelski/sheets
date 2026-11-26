import AppKit
import SheetsCore
import SwiftUI

/// A terminal's sheet: its title bar, then the terminal, dark in light and dark mode alike.
///
/// The terminal itself belongs to the pane's session, not to this sheet, so the sheet only
/// borrows its view. When the shell exits by itself, a quiet line at the foot of the terminal
/// says so, with a way to start it again. The pane stays.
struct TerminalSheet: View {
    let model: SheetsModel
    let pane: Pane
    /// True when this sheet is on top, so its terminal has the keyboard.
    let isTop: Bool

    var body: some View {
        let record = model.terminals?.record(for: pane.id)
        let appearance = model.terminalAppearance
        VStack(spacing: 0) {
            SheetTitleBar(title: pane.title, detail: record?.title)
            ZStack(alignment: .bottom) {
                Color(appearance.background)
                Group {
                    if let host = record?.session as? TerminalViewHosting {
                        TerminalHostView(host: host, wantsFocus: isTop && model.renaming == nil)
                    } else {
                        TerminalStandIn(appearance: appearance)
                    }
                }
                // Room between the text and the sheet's edges.
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 6)
                if let record, !record.status.isRunning {
                    TerminalEndedLine(status: record.status, isTop: isTop, background: appearance.background) {
                        model.restartTerminal(pane.id)
                    }
                }
            }
            .environment(\.colorScheme, .dark)
        }
    }
}

/// The line at the foot of a terminal whose shell ended: what happened, and Start Again. On the
/// top sheet, Return starts it again.
struct TerminalEndedLine: View {
    let status: TerminalSessionStatus
    let isTop: Bool
    let background: TerminalColor
    let restart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Button(action: restart) {
                    HStack(spacing: 5) {
                        Text("Start Again")
                        if isTop {
                            Text("↩").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .modifier(DefaultActionWhen(isOn: isTop))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(background).opacity(0.92))
    }

    private var message: String {
        switch status {
        case .running: ""
        case .exited(status: 0): "The shell exited."
        case .exited(status: let code?): "The shell exited with status \(code)."
        case .exited(status: nil): "The shell was stopped."
        case .failedToStart(let reason): "The shell could not start: \(reason)"
        }
    }
}

/// Return presses the button, but only on the top sheet, so a covered terminal never takes it.
private struct DefaultActionWhen: ViewModifier {
    let isOn: Bool

    func body(content: Content) -> some View {
        if isOn {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
        }
    }
}

/// Puts a session's terminal view in this sheet, and gives it the keyboard while the sheet is
/// on top.
struct TerminalHostView: NSViewRepresentable {
    let host: any TerminalViewHosting
    let wantsFocus: Bool

    func makeNSView(context: Context) -> TerminalContainerView {
        TerminalContainerView()
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        container.show(host.terminalView, wantsFocus: wantsFocus)
    }

    static func dismantleNSView(_ container: TerminalContainerView, coordinator: ()) {
        container.letGo()
    }
}

/// Holds a terminal view it borrowed. A sheet that is leaving and the sheet replacing it can
/// both show the same pane for a moment. The newer one takes the view, and the older one does
/// not take it back.
final class TerminalContainerView: NSView {
    private weak var terminal: NSView?
    private var wantsFocus = false

    func show(_ view: NSView, wantsFocus: Bool) {
        if terminal !== view {
            if let terminal, terminal.superview === self { terminal.removeFromSuperview() }
            view.removeFromSuperview()
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            terminal = view
        }
        let gained = wantsFocus && !self.wantsFocus
        self.wantsFocus = wantsFocus
        if gained {
            focusSoon()
        } else if !wantsFocus, let window, window.firstResponder === view {
            window.makeFirstResponder(nil)
        }
    }

    func letGo() {
        if let terminal, terminal.superview === self { terminal.removeFromSuperview() }
        terminal = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus { focusSoon() }
    }

    /// On the next turn of the run loop, once SwiftUI has put this view in its window.
    private func focusSoon() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsFocus, let window = self.window, let terminal = self.terminal,
                  terminal.superview === self, window.firstResponder !== terminal
            else { return }
            window.makeFirstResponder(terminal)
        }
    }
}

/// What a render draws where the terminal goes: a few lines of a shell, drawn in the
/// terminal's font and colors. A live terminal does not draw into an offscreen render, and a
/// render should not start a shell.
struct TerminalStandIn: View {
    let appearance: TerminalAppearance

    var body: some View {
        let font = appearance.fontName.map { Font.custom($0, size: appearance.fontSize) }
            ?? Font.system(size: appearance.fontSize, design: .monospaced)
        let prompt = Text("someone@mac ~ % ").foregroundStyle(Color(appearance.palette[2]))
        VStack(alignment: .leading, spacing: 2 + appearance.fontSize * (appearance.lineSpacing - 1)) {
            Text("\(prompt)ls")
            Text("Package.swift  README.md  Sources  Tests")
                .foregroundStyle(Color(appearance.palette[4]))
            Text("\(prompt)git status --short")
            Text(" M README.md").foregroundStyle(Color(appearance.palette[1]))
            HStack(spacing: 0) {
                prompt
                cursor
            }
        }
        .font(font)
        .foregroundStyle(Color(appearance.foreground))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    /// The cursor in its shape: a block, a bar, or an underline.
    private var cursor: some View {
        let height = appearance.fontSize + 2
        let width = appearance.fontSize * 0.6
        return Rectangle()
            .fill(Color(appearance.cursor))
            .frame(
                width: appearance.cursorShape == .bar ? 2 : width,
                height: appearance.cursorShape == .underline ? 2 : height)
            .frame(width: width, height: height, alignment: appearance.cursorShape == .underline ? .bottom : .leading)
    }
}

extension Color {
    init(_ color: TerminalColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue)
    }
}
