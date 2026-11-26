import Foundation

/// A color as red, green, and blue from 0 to 1, in sRGB.
public struct TerminalColor: Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// A color from a hex number such as `0x1E1F22`.
    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// A color from `#RRGGBB`, in either case. Nil for anything else.
    public init?(hexString: String) {
        guard hexString.count == 7, hexString.first == "#",
              hexString.dropFirst().allSatisfy(\.isHexDigit),
              let hex = UInt32(hexString.dropFirst(), radix: 16)
        else { return nil }
        self.init(hex: hex)
    }

    /// The color as `#RRGGBB`, upper case, each channel rounded to the nearest of 256 steps.
    public var hexString: String {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}

/// The shape of a terminal's cursor.
public enum TerminalCursorShape: String, CaseIterable, Hashable, Sendable, Codable {
    case block
    case underline
    case bar
}

/// How a terminal looks: its font, colors, and cursor, as plain values any engine can use.
public struct TerminalAppearance: Hashable, Sendable, Codable {
    /// A font family such as `Menlo`, or a font's PostScript name, or nil for the system's
    /// monospaced font, SF Mono.
    public var fontName: String?
    /// The font size in points.
    public var fontSize: Double
    /// The height of a line as a multiple of the font's own line height.
    public var lineSpacing: Double
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var cursor: TerminalColor
    public var selection: TerminalColor
    /// The 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan, white, then the
    /// bright version of each.
    public var palette: [TerminalColor]
    public var cursorShape: TerminalCursorShape
    public var cursorBlinks: Bool

    public init(
        fontName: String?, fontSize: Double, lineSpacing: Double = 1, foreground: TerminalColor,
        background: TerminalColor, cursor: TerminalColor, selection: TerminalColor, palette: [TerminalColor],
        cursorShape: TerminalCursorShape = .block, cursorBlinks: Bool = true
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.palette = palette
        self.cursorShape = cursorShape
        self.cursorBlinks = cursorBlinks
    }

    /// The built-in look, which the config file's settings change: SF Mono at 12 pt on a dark gray close to the
    /// window's own dark gray, so a terminal sits with the sheets in dark mode and reads as a
    /// dark panel on a light sheet in light mode. The palette is muted, so colored output does
    /// not shout over the quiet chrome around it. The cursor is a blinking block.
    public static let standard = TerminalAppearance(
        fontName: nil,
        fontSize: 12,
        foreground: TerminalColor(hex: 0xDCDDE1),
        background: TerminalColor(hex: 0x1D1E21),
        cursor: TerminalColor(hex: 0xC9CBD1),
        selection: TerminalColor(hex: 0x3A4658),
        palette: [
            0x2B2D31, 0xE0736F, 0x8FC17E, 0xDDBA6B, 0x6FA3E0, 0xC390D4, 0x6BC3C4, 0xC5C7CC,
            0x5D6067, 0xF08F8B, 0xA8D896, 0xEED08A, 0x8DB9EE, 0xD5A9E3, 0x8AD7D8, 0xF0F1F3,
        ].map(TerminalColor.init(hex:)))
}

/// Which Option keys act as Meta, sending Escape before the key, rather than typing the
/// characters the keyboard layout puts on them.
public enum TerminalOptionAsMeta: String, CaseIterable, Hashable, Sendable, Codable {
    /// Neither: Option types characters such as é, as everywhere else on a Mac.
    case off
    case left
    case right
    case both
}

/// What a terminal does when a program rings the bell.
public enum TerminalBell: String, CaseIterable, Hashable, Sendable, Codable {
    case none
    case sound
    case visual
    case soundAndVisual = "sound-and-visual"
}

/// How a terminal behaves, as plain values any engine can use: its scrollback, keyboard, mouse,
/// and bell.
public struct TerminalBehavior: Hashable, Sendable, Codable {
    /// How many lines a terminal keeps above the screen. An engine may read this only when a
    /// session starts.
    public var scrollbackLines: Int
    public var optionAsMeta: TerminalOptionAsMeta
    /// Whether finishing a selection copies it to the clipboard.
    public var copyOnSelect: Bool
    /// Whether programs that ask for mouse events get them.
    public var mouseReporting: Bool
    public var bell: TerminalBell

    public init(
        scrollbackLines: Int = 10_000, optionAsMeta: TerminalOptionAsMeta = .off, copyOnSelect: Bool = false,
        mouseReporting: Bool = true, bell: TerminalBell = .sound
    ) {
        self.scrollbackLines = scrollbackLines
        self.optionAsMeta = optionAsMeta
        self.copyOnSelect = copyOnSelect
        self.mouseReporting = mouseReporting
        self.bell = bell
    }

    /// The built-in behavior: 10,000 lines of scrollback, Option typing characters, no copy on
    /// select, mouse reporting on, and the bell's sound.
    public static let standard = TerminalBehavior()
}
