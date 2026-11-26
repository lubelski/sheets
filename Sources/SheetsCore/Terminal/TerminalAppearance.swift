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
}

/// How a terminal looks: its font and colors, as plain values any engine can use.
public struct TerminalAppearance: Hashable, Sendable, Codable {
    /// A font's PostScript name, or nil for the system's monospaced font, SF Mono.
    public var fontName: String?
    /// The font size in points.
    public var fontSize: Double
    public var foreground: TerminalColor
    public var background: TerminalColor
    public var cursor: TerminalColor
    public var selection: TerminalColor
    /// The 16 ANSI colors: black, red, green, yellow, blue, magenta, cyan, white, then the
    /// bright version of each.
    public var palette: [TerminalColor]

    public init(
        fontName: String?, fontSize: Double, foreground: TerminalColor, background: TerminalColor,
        cursor: TerminalColor, selection: TerminalColor, palette: [TerminalColor]
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.foreground = foreground
        self.background = background
        self.cursor = cursor
        self.selection = selection
        self.palette = palette
    }

    /// The look every terminal has for now: SF Mono at 12 pt on a dark gray close to the
    /// window's own dark gray, so a terminal sits with the sheets in dark mode and reads as a
    /// dark panel on a light sheet in light mode. The palette is muted, so colored output does
    /// not shout over the quiet chrome around it.
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
