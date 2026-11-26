import Foundation

/// Something wrong, or worth knowing, about a line of the config file.
public struct ConfigIssue: Hashable, Sendable, Identifiable {
    public enum Severity: Hashable, Sendable {
        /// The line is not used. Its key keeps its last good value.
        case error
        /// The line is used, or harmlessly ignored, but is probably a mistake.
        case warning
    }

    /// The line's number, from 1.
    public let line: Int
    public let severity: Severity
    /// The key the line is about, when it has one.
    public let key: String?
    public let message: String

    public var id: String { "\(line):\(message)" }

    public init(line: Int, severity: Severity, key: String?, message: String) {
        self.line = line
        self.severity = severity
        self.key = key
        self.message = message
    }

    /// `Line 3: …`, as the issue reads on its own.
    public var description: String { "Line \(line): \(message)" }
}

/// The settings in effect: the built-in defaults, with the config file's good lines over them.
///
/// It keeps only the keys the file sets. A key it does not have reads as its default.
public struct Config: Hashable, Sendable {
    /// The values the file sets, by key. Every one has been checked against its key.
    public private(set) var overrides: [String: ConfigValue]

    public init(overrides: [String: ConfigValue] = [:]) {
        self.overrides = overrides
    }

    /// Every key at its default.
    public static let defaults = Config()

    /// The result of reading a config file.
    public struct Loaded: Hashable, Sendable {
        public let config: Config
        public let issues: [ConfigIssue]
    }

    /// Reads the text of a config file.
    ///
    /// - A good line sets its key. When a key is set twice, the last good line wins, with a
    ///   warning on each line that sets it again.
    /// - A bad line, with a syntax error or a value its key does not take, is left out with an
    ///   error. When a key has no good line, it keeps the value it had in `previous`, which is
    ///   its last good value while the app runs, or its default at launch.
    /// - A key the app does not know is left out with a warning, and the line stays as it is.
    public static func load(_ text: String, previous: Config = .defaults) -> Loaded {
        var overrides: [String: ConfigValue] = [:]
        var badKeys: Set<String> = []
        var seen: [String: Int] = [:]
        var issues: [ConfigIssue] = []
        for line in ConfigParser.lines(of: text) {
            switch line.content {
            case .blank, .comment:
                continue
            case .invalid(let key, let message):
                let definition = key.flatMap(ConfigKeys.definition(for:))
                if let definition { badKeys.insert(definition.key) }
                let text: String
                if let definition, let word = line.unreadableWord {
                    text = definition.unreadableValueMessage(word)
                } else if let key {
                    text = "\(key): \(message)"
                } else {
                    text = message
                }
                issues.append(ConfigIssue(line: line.number, severity: .error, key: key, message: text))
            case .setting(let key, let value):
                guard let definition = ConfigKeys.definition(for: key) else {
                    issues.append(ConfigIssue(
                        line: line.number, severity: .warning, key: key,
                        message: "\(key) is not a setting this version knows. The line is ignored."))
                    continue
                }
                switch definition.check(value) {
                case .success(let good):
                    if let earlier = seen[key] {
                        issues.append(ConfigIssue(
                            line: line.number, severity: .warning, key: key,
                            message: "\(key) is also set on line \(earlier). The last one is used."))
                    }
                    seen[key] = line.number
                    overrides[key] = good
                case .failure(let problem):
                    badKeys.insert(key)
                    issues.append(ConfigIssue(
                        line: line.number, severity: .error, key: key,
                        message: "\(key) must be \(problem.expected). It keeps its last good value."))
                }
            }
        }
        for key in badKeys where overrides[key] == nil {
            overrides[key] = previous.overrides[key]
        }
        return Loaded(config: Config(overrides: overrides), issues: issues)
    }

    // MARK: Reading values

    /// The key's value: the file's when it sets one, or else the default. Nil for a key with
    /// no default that the file does not set.
    public subscript(_ definition: ConfigKeyDefinition) -> ConfigValue? {
        overrides[definition.key] ?? definition.defaultValue
    }

    /// True when the file sets the key.
    public func isSet(_ definition: ConfigKeyDefinition) -> Bool {
        overrides[definition.key] != nil
    }

    public func string(_ definition: ConfigKeyDefinition) -> String? {
        self[definition]?.stringValue
    }

    public func number(_ definition: ConfigKeyDefinition) -> Double {
        self[definition]?.numberValue ?? definition.defaultValue?.numberValue ?? 0
    }

    public func integer(_ definition: ConfigKeyDefinition) -> Int {
        if case .integer(let value) = self[definition] { return value }
        if case .integer(let value) = definition.defaultValue { return value }
        return 0
    }

    public func bool(_ definition: ConfigKeyDefinition) -> Bool {
        self[definition]?.boolValue ?? definition.defaultValue?.boolValue ?? false
    }

    public func strings(_ definition: ConfigKeyDefinition) -> [String] {
        (self[definition]?.arrayValue ?? []).compactMap(\.stringValue)
    }

    public func color(_ definition: ConfigKeyDefinition) -> TerminalColor {
        string(definition).flatMap(TerminalColor.init(hexString:))
            ?? definition.defaultValue?.stringValue.flatMap(TerminalColor.init(hexString:))
            ?? TerminalColor(hex: 0)
    }

    public func colors(_ definition: ConfigKeyDefinition) -> [TerminalColor] {
        strings(definition).compactMap(TerminalColor.init(hexString:))
    }

    /// The value of a choice key as one of an enum's cases, or the default's case.
    public func choice<Choice: RawRepresentable<String>>(_ definition: ConfigKeyDefinition, as type: Choice.Type) -> Choice? {
        string(definition).flatMap(Choice.init(rawValue:))
            ?? definition.defaultValue?.stringValue.flatMap(Choice.init(rawValue:))
    }

    // MARK: Changing values

    /// The config with a key set, without checking the value.
    public func setting(_ definition: ConfigKeyDefinition, to value: ConfigValue?) -> Config {
        var config = self
        config.overrides[definition.key] = value
        return config
    }
}

// MARK: Terminals

extension Config {
    /// How terminals look under these settings.
    public var terminalAppearance: TerminalAppearance {
        let palette = colors(ConfigKeys.palette)
        return TerminalAppearance(
            fontName: string(ConfigKeys.fontFamily).flatMap { $0.isEmpty ? nil : $0 },
            fontSize: number(ConfigKeys.fontSize),
            lineSpacing: number(ConfigKeys.lineSpacing),
            foreground: color(ConfigKeys.foreground),
            background: color(ConfigKeys.background),
            cursor: color(ConfigKeys.cursorColor),
            selection: color(ConfigKeys.selectionColor),
            palette: palette.count == 16 ? palette : TerminalAppearance.standard.palette,
            cursorShape: choice(ConfigKeys.cursorStyle, as: TerminalCursorShape.self) ?? .block,
            cursorBlinks: bool(ConfigKeys.cursorBlink))
    }

    /// How terminals behave under these settings.
    public var terminalBehavior: TerminalBehavior {
        TerminalBehavior(
            scrollbackLines: integer(ConfigKeys.scrollbackLines),
            optionAsMeta: choice(ConfigKeys.optionAsMeta, as: TerminalOptionAsMeta.self) ?? .off,
            copyOnSelect: bool(ConfigKeys.copyOnSelect),
            mouseReporting: bool(ConfigKeys.mouseReporting),
            bell: choice(ConfigKeys.bell, as: TerminalBell.self) ?? .sound)
    }

    /// The shell a new terminal runs, when the file names one.
    public var shell: String? {
        string(ConfigKeys.shell).flatMap { $0.isEmpty ? nil : Self.expandingTilde($0, home: NSHomeDirectory()) }
    }

    /// The arguments a new terminal's shell starts with.
    public var shellArguments: [String] {
        strings(ConfigKeys.shellArguments)
    }

    /// The folder a new terminal starts in when no group above it has one, with `~` expanded.
    public func startingFolder(home: String) -> String {
        let folder = string(ConfigKeys.startingFolder) ?? "~"
        return folder.isEmpty ? home : Self.expandingTilde(folder, home: home)
    }

    /// A path with a leading `~` or `~/` turned into the home folder.
    public static func expandingTilde(_ path: String, home: String) -> String {
        if path == "~" { return home }
        if path.hasPrefix("~/") { return (home as NSString).appendingPathComponent(String(path.dropFirst(2))) }
        return path
    }
}
