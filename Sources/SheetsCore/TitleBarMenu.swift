import Foundation

/// What the small menu at the trailing end of the window's title bar holds: a few app-wide
/// commands, apart from the panes, and a line saying which version is running.
///
/// The view draws these entries in order and does nothing else, so what the menu holds and when
/// each item can be chosen are decided here and tested.
public struct TitleBarMenu: Equatable, Sendable {
    /// Something an item does when chosen.
    public enum Action: Equatable, Sendable {
        /// The same as Check for Updates in the app menu.
        case checkForUpdates
        /// Opens Settings as a sheet, as Command-comma does.
        case openSettings
    }

    /// One item: its title, what it does, and whether it can be chosen. An item with no action
    /// is a line of information, shown dimmed.
    public struct Item: Equatable, Sendable {
        public var title: String
        public var action: Action?
        public var isEnabled: Bool

        public init(title: String, action: Action?, isEnabled: Bool) {
            self.title = title
            self.action = action
            self.isEnabled = isEnabled
        }
    }

    public enum Entry: Equatable, Sendable {
        case item(Item)
        case divider
    }

    /// The accessibility label of the button that opens the menu.
    public static let buttonLabel = "More"
    /// The tooltip of the button that opens the menu.
    public static let buttonHelp = "Updates, Settings, and version"

    public var entries: [Entry]

    /// - Parameters:
    ///   - updatesAvailable: Whether this build can update itself. A build without a feed, such
    ///     as a development build, still lists Check for Updates, dimmed, so the menu keeps its
    ///     shape and says that updates exist.
    ///   - canCheckNow: Whether the updater can start a check now. False while one is running.
    ///   - appName: The app's name as people see it.
    ///   - buildInfo: Which version is running.
    public init(updatesAvailable: Bool, canCheckNow: Bool, appName: String, buildInfo: BuildInfo) {
        entries = [
            .item(Item(
                title: "Check for Updates…", action: .checkForUpdates,
                isEnabled: updatesAvailable && canCheckNow)),
            .divider,
            .item(Item(title: "Settings…", action: .openSettings, isEnabled: true)),
            .divider,
            .item(Item(title: Self.versionLine(appName: appName, buildInfo: buildInfo), action: nil, isEnabled: false)),
        ]
    }

    /// The app's name and version, such as "Sheets 0.4.0".
    public static func versionLine(appName: String, buildInfo: BuildInfo) -> String {
        "\(appName) \(buildInfo.version)"
    }
}
