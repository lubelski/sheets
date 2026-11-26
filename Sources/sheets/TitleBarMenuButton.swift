import SheetsCore
import SwiftUI

/// The small button at the trailing end of the window's title bar, and the menu it opens. What
/// the menu holds comes from `TitleBarMenu` in SheetsCore. This view draws it and runs its
/// actions.
///
/// The glyph is faint until the pointer is over it, so the title bar stays quiet.
struct TitleBarMenuButton: View {
    let model: SheetsModel
    let updater: AppUpdater
    var buildInfo = BuildInfo.current()
    /// Draws the button as if the pointer were over it, for renders.
    var showsHover = false

    @State private var isHovered = false

    var body: some View {
        let menu = TitleBarMenu(
            updatesAvailable: updater.isAvailable, canCheckNow: updater.canCheck,
            appName: AppName.display, buildInfo: buildInfo)
        let lit = isHovered || showsHover
        Menu {
            ForEach(Array(menu.entries.enumerated()), id: \.offset) { _, entry in
                switch entry {
                case .divider:
                    Divider()
                case .item(let item):
                    Button(item.title) { perform(item.action) }
                        .disabled(!item.isEnabled)
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(lit ? .secondary : .tertiary)
                .frame(width: 24, height: 18)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(.primary.opacity(lit ? 0.08 : 0))
                }
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        // Clear of the window's trailing edge, about as far as the window buttons are from
        // the leading one.
        .padding(.horizontal, 8)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: lit)
        .help(TitleBarMenu.buttonHelp)
        .accessibilityLabel(TitleBarMenu.buttonLabel)
    }

    private func perform(_ action: TitleBarMenu.Action?) {
        switch action {
        case .checkForUpdates: updater.checkForUpdates()
        case .openSettings: model.openSettings()
        case nil: break
        }
    }
}
