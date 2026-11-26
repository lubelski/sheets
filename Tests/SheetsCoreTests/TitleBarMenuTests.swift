import SheetsCore
import Testing

@Suite struct TitleBarMenuTests {
    let build = BuildInfo(version: "0.4.0", build: "40", commit: "1a2b3c4", signing: "Signed ad hoc")

    private func menu(updatesAvailable: Bool = true, canCheckNow: Bool = true) -> TitleBarMenu {
        TitleBarMenu(updatesAvailable: updatesAvailable, canCheckNow: canCheckNow, appName: "Sheets", buildInfo: build)
    }

    private func item(_ action: TitleBarMenu.Action, in menu: TitleBarMenu) -> TitleBarMenu.Item? {
        for case .item(let item) in menu.entries where item.action == action { return item }
        return nil
    }

    @Test func holdsUpdatesThenSettingsThenTheVersion() {
        #expect(menu().entries == [
            .item(.init(title: "Check for Updates…", action: .checkForUpdates, isEnabled: true)),
            .divider,
            .item(.init(title: "Settings…", action: .openSettings, isEnabled: true)),
            .divider,
            .item(.init(title: "Sheets 0.4.0", action: nil, isEnabled: false)),
        ])
    }

    @Test func aBuildWithoutAnUpdaterShowsCheckForUpdatesDimmed() {
        let menu = menu(updatesAvailable: false, canCheckNow: false)
        #expect(item(.checkForUpdates, in: menu)?.isEnabled == false)
        // The rest of the menu is the same.
        #expect(menu.entries.count == 5)
        #expect(item(.openSettings, in: menu)?.isEnabled == true)
    }

    @Test func checkForUpdatesIsDimmedWhileACheckIsRunning() {
        #expect(item(.checkForUpdates, in: menu(canCheckNow: false))?.isEnabled == false)
    }

    @Test func anUpdaterThatCannotBeUsedIsNeverEnabledByCanCheckAlone() {
        #expect(item(.checkForUpdates, in: menu(updatesAvailable: false, canCheckNow: true))?.isEnabled == false)
    }

    @Test func theVersionLineIsTheNameAndVersionAndCannotBeChosen() {
        guard case .item(let line) = menu().entries.last else {
            Issue.record("The menu should end with the version line")
            return
        }
        #expect(line.title == "Sheets 0.4.0")
        #expect(line.action == nil)
        #expect(!line.isEnabled)
    }

    @Test func settingsCanAlwaysBeChosen() {
        for available in [true, false] {
            for canCheck in [true, false] {
                #expect(item(.openSettings, in: menu(updatesAvailable: available, canCheckNow: canCheck))?.isEnabled == true)
            }
        }
    }
}
