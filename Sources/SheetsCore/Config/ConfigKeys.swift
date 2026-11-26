import Foundation

/// The kind of value a key takes, with what is allowed.
public enum ConfigValueKind: Hashable, Sendable {
    /// Any string.
    case string
    /// A path to a file or folder. `~` at the start means the home folder.
    case path
    /// An array of strings.
    case strings
    /// A whole number in a range.
    case integer(ClosedRange<Int>)
    /// A number in a range, whole or not.
    case number(ClosedRange<Double>)
    case bool
    /// One of a few names.
    case choice([String])
    /// A color as `"#RRGGBB"`.
    case color
    /// An array of exactly this many colors.
    case colors(count: Int)

    /// What a value of this kind looks like, as an issue says it.
    public var expectation: String {
        switch self {
        case .string: "a string in double quotes"
        case .path: "a path in double quotes"
        case .strings: "an array of strings, such as [\"-l\"]"
        case .integer(let range): "a whole number from \(range.lowerBound) to \(range.upperBound)"
        case .number(let range):
            "a number from \(ConfigValue.number(range.lowerBound).tomlText) to \(ConfigValue.number(range.upperBound).tomlText)"
        case .bool: "true or false"
        case .choice(let names): "one of " + names.map { "\"\($0)\"" }.joined(separator: ", ")
        case .color: "a color such as \"#1D1E21\""
        case .colors(let count): "an array of exactly \(count) colors such as \"#1D1E21\""
        }
    }

    /// The value when it is allowed, or what is wrong with it.
    public func check(_ value: ConfigValue) -> Result<ConfigValue, ConfigValueProblem> {
        let problem = Result<ConfigValue, ConfigValueProblem>.failure(ConfigValueProblem(expectation))
        switch self {
        case .string, .path:
            return value.stringValue == nil ? problem : .success(value)
        case .strings:
            guard let values = value.arrayValue, values.allSatisfy({ $0.stringValue != nil }) else { return problem }
            return .success(value)
        case .integer(let range):
            guard case .integer(let integer) = value, range.contains(integer) else { return problem }
            return .success(value)
        case .number(let range):
            guard let number = value.numberValue, number.isFinite, range.contains(number) else { return problem }
            return .success(value)
        case .bool:
            return value.boolValue == nil ? problem : .success(value)
        case .choice(let names):
            guard let name = value.stringValue, names.contains(name) else { return problem }
            return .success(value)
        case .color:
            guard let string = value.stringValue, TerminalColor(hexString: string) != nil else { return problem }
            return .success(value)
        case .colors(let count):
            guard let values = value.arrayValue,
                  values.allSatisfy({ $0.stringValue.flatMap(TerminalColor.init(hexString:)) != nil })
            else { return problem }
            guard values.count == count else {
                return .failure(ConfigValueProblem("exactly \(count) colors, not \(values.count)"))
            }
            return .success(value)
        }
    }
}

/// What a value needs to be, when it is not.
public struct ConfigValueProblem: Error, Hashable, Sendable {
    /// What the value should be, such as "a whole number from 0 to 100000".
    public let expected: String

    public init(_ expected: String) {
        self.expected = expected
    }
}

/// When a change to a key reaches the terminals.
public enum ConfigTiming: Hashable, Sendable {
    /// Running terminals change straight away.
    case live
    /// Only terminals started after the change have it. A terminal started again with Start
    /// Again counts as new.
    case newTerminals
    /// Not about terminals: the app changes straight away.
    case app
}

/// One key of the config file: its name, what it takes, its default, and what it does.
///
/// The parser, the checks, the reference, and the Settings UI all read these.
public struct ConfigKeyDefinition: Hashable, Sendable, Identifiable {
    /// The dotted key, such as `terminal.font-size`.
    public let key: String
    public let kind: ConfigValueKind
    /// The built-in value, or nil when the key has none and its absence means something,
    /// such as the system's monospaced font.
    public let defaultValue: ConfigValue?
    /// What an unset key means, for a key with no default value.
    public let unsetMeaning: String?
    /// A value to show in the reference for a key with no default value.
    public let example: ConfigValue?
    /// One line saying what the key does.
    public let summary: String
    public let timing: ConfigTiming

    public var id: String { key }

    init(
        _ key: String, _ kind: ConfigValueKind, default defaultValue: ConfigValue?, unset: String? = nil,
        example: ConfigValue? = nil, timing: ConfigTiming = .live, _ summary: String
    ) {
        self.key = key
        self.kind = kind
        self.defaultValue = defaultValue
        self.unsetMeaning = unset
        self.example = example
        self.summary = summary
        self.timing = timing
    }

    /// The value when it is allowed for this key, or an issue's message saying what it must be.
    public func check(_ value: ConfigValue) -> Result<ConfigValue, ConfigValueProblem> {
        kind.check(value)
    }
}

/// Every key the config file knows, in the order the reference lists them.
public enum ConfigKeys {
    private static let standard = TerminalAppearance.standard
    private static let standardBehavior = TerminalBehavior.standard

    // MARK: Font

    public static let fontFamily = ConfigKeyDefinition(
        "terminal.font-family", .string, default: nil, unset: "the system's monospaced font, SF Mono",
        example: .string("Menlo"),
        "The font family, such as \"Menlo\".")
    public static let fontSize = ConfigKeyDefinition(
        "terminal.font-size", .number(6...72), default: .number(standard.fontSize),
        "The font size in points.")
    public static let lineSpacing = ConfigKeyDefinition(
        "terminal.line-spacing", .number(0.8...2), default: .number(standard.lineSpacing),
        "The height of a line, as a multiple of the font's own. 1.2 adds a fifth.")

    // MARK: Colors

    public static let foreground = ConfigKeyDefinition(
        "terminal.foreground", .color, default: .string(standard.foreground.hexString),
        "The color of text.")
    public static let background = ConfigKeyDefinition(
        "terminal.background", .color, default: .string(standard.background.hexString),
        "The color behind the text.")
    public static let cursorColor = ConfigKeyDefinition(
        "terminal.cursor-color", .color, default: .string(standard.cursor.hexString),
        "The color of the cursor.")
    public static let selectionColor = ConfigKeyDefinition(
        "terminal.selection-color", .color, default: .string(standard.selection.hexString),
        "The color behind selected text.")
    public static let palette = ConfigKeyDefinition(
        "terminal.palette", .colors(count: 16), default: .strings(standard.palette.map(\.hexString)),
        "The 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan, white, then the bright version of each.")

    // MARK: Cursor

    public static let cursorStyle = ConfigKeyDefinition(
        "terminal.cursor-style", .choice(TerminalCursorShape.allCases.map(\.rawValue)),
        default: .string(standard.cursorShape.rawValue),
        "The cursor's shape: \"block\", \"underline\", or \"bar\". A program can change it while it runs.")
    public static let cursorBlink = ConfigKeyDefinition(
        "terminal.cursor-blink", .bool, default: .bool(standard.cursorBlinks),
        "Whether the cursor blinks.")

    // MARK: Keyboard and mouse

    public static let optionAsMeta = ConfigKeyDefinition(
        "terminal.option-as-meta", .choice(TerminalOptionAsMeta.allCases.map(\.rawValue)),
        default: .string(standardBehavior.optionAsMeta.rawValue),
        "Which Option keys act as Meta: \"off\", \"left\", \"right\", or \"both\". Off types characters such as é.")
    public static let copyOnSelect = ConfigKeyDefinition(
        "terminal.copy-on-select", .bool, default: .bool(standardBehavior.copyOnSelect),
        "Whether selecting text copies it to the clipboard.")
    public static let mouseReporting = ConfigKeyDefinition(
        "terminal.mouse-reporting", .bool, default: .bool(standardBehavior.mouseReporting),
        "Whether programs that ask for the mouse, such as vim and tmux, get clicks and scrolling.")
    public static let bell = ConfigKeyDefinition(
        "terminal.bell", .choice(TerminalBell.allCases.map(\.rawValue)),
        default: .string(standardBehavior.bell.rawValue),
        "What the bell does: \"none\", \"sound\", \"visual\", or \"sound-and-visual\".")
    public static let scrollbackLines = ConfigKeyDefinition(
        "terminal.scrollback-lines", .integer(0...1_000_000), default: .integer(standardBehavior.scrollbackLines),
        timing: .newTerminals,
        "How many lines a terminal keeps above the screen.")

    // MARK: Shell

    public static let shell = ConfigKeyDefinition(
        "terminal.shell", .path, default: nil, unset: "the login shell from your user record, or else /bin/zsh",
        example: .string("/bin/zsh"), timing: .newTerminals,
        "The shell's path. It starts as a login shell.")
    public static let shellArguments = ConfigKeyDefinition(
        "terminal.shell-arguments", .strings, default: .strings([]), timing: .newTerminals,
        "Arguments the shell starts with.")
    public static let startingFolder = ConfigKeyDefinition(
        "terminal.starting-folder", .path, default: .string("~"), timing: .newTerminals,
        "The folder a new terminal starts in when no group above it has a folder. ~ is the home folder.")

    // MARK: Experiments

    public static let dragToMove = ConfigKeyDefinition(
        "experiments.drag-to-move", .bool, default: .bool(false), timing: .app,
        "Drag sidebar rows to move panes.")

    /// Every key, in the reference's order.
    public static let all: [ConfigKeyDefinition] = [
        fontFamily, fontSize, lineSpacing,
        foreground, background, cursorColor, selectionColor, palette,
        cursorStyle, cursorBlink,
        optionAsMeta, copyOnSelect, mouseReporting, bell, scrollbackLines,
        shell, shellArguments, startingFolder,
        dragToMove,
    ]

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    /// The key with a name, or nil when the file does not know it.
    public static func definition(for key: String) -> ConfigKeyDefinition? {
        byKey[key]
    }
}
