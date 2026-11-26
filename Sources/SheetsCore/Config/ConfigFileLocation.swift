import Foundation

/// Where the config file is.
public enum ConfigFileLocation {
    /// The environment variable that names another config file, for tests and renders.
    public static let overrideVariable = "SHEETS_CONFIG_PATH"

    /// The config file's path:
    ///
    /// 1. `$SHEETS_CONFIG_PATH`, when it is set and not empty. A leading `~` is the home folder.
    /// 2. `$XDG_CONFIG_HOME/sheets/config`, when that variable is an absolute path.
    /// 3. `~/.config/sheets/config`.
    public static func path(environment: [String: String], home: String) -> String {
        if let path = environment[overrideVariable], !path.isEmpty {
            return Config.expandingTilde(path, home: home)
        }
        if let base = environment["XDG_CONFIG_HOME"], base.hasPrefix("/") {
            return ((base as NSString).appendingPathComponent("sheets") as NSString).appendingPathComponent("config")
        }
        return (home as NSString).appendingPathComponent(".config/sheets/config")
    }

    /// The path for this process's environment and home folder.
    public static func current() -> String {
        path(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
    }

    /// A path as a person reads it, with the home folder as `~`.
    public static func displayPath(_ path: String, home: String) -> String {
        let home = (home as NSString).standardizingPath
        let standard = (path as NSString).standardizingPath
        if standard == home { return "~" }
        if standard.hasPrefix(home + "/") { return "~" + standard.dropFirst(home.count) }
        return standard
    }
}
