import Foundation

// The config file's syntax: one setting per line, each line valid TOML.
//
//     # A comment
//     terminal.font-size = 13   # a trailing comment
//     terminal.palette = ["#2B2D31", "#E0736F"]
//
// Keys are bare dotted keys. Values are strings (basic in double quotes, or literal in single
// quotes), integers, floats, booleans, and arrays on one line. Tables, inline tables,
// multi-line strings, and dates are not used, and say so when they show up.

/// One line of the config file, read but not yet checked against the keys.
public struct ConfigLine: Hashable, Sendable {
    public enum Content: Hashable, Sendable {
        /// Nothing but white space.
        case blank
        /// A comment, `#` to the end of the line, with only white space before it.
        case comment
        /// A setting: a key and a value.
        case setting(key: String, value: ConfigValue)
        /// A line that is not valid. The key is there when the line got far enough to have one.
        case invalid(key: String?, message: String)
    }

    /// The line's number, from 1.
    public let number: Int
    /// The line's text, without its line break.
    public let text: String
    /// The line break after it: `\n`, `\r\n`, or nothing for a last line without one.
    public let terminator: String
    public let content: Content
    /// Where the value is in `text`, counted in Unicode scalars, for a setting. Editing a value
    /// replaces just this part, so the key's spelling and a trailing comment stay.
    public let valueRange: Range<Int>?

    /// The key the line sets, valid or not.
    public var key: String? {
        switch content {
        case .setting(let key, _): key
        case .invalid(let key, _): key
        case .blank, .comment: nil
        }
    }
}

public enum ConfigParser {
    /// Splits text into lines and reads each one.
    public static func lines(of text: String) -> [ConfigLine] {
        split(text).enumerated().map { index, part in
            parseLine(part.text, number: index + 1, terminator: part.terminator)
        }
    }

    /// The text's lines with their line breaks. A final line break does not start another line.
    static func split(_ text: String) -> [(text: String, terminator: String)] {
        var lines: [(String, String)] = []
        var current = ""
        for character in text {
            if character == "\n" || character == "\r\n" {
                lines.append((current, String(character)))
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { lines.append((current, "")) }
        return lines
    }

    /// Reads one line.
    public static func parseLine(_ text: String, number: Int = 1, terminator: String = "") -> ConfigLine {
        var scanner = Scanner(Array(text.unicodeScalars))
        func line(_ content: ConfigLine.Content, value: Range<Int>? = nil) -> ConfigLine {
            ConfigLine(number: number, text: text, terminator: terminator, content: content, valueRange: value)
        }
        scanner.skipSpace()
        guard let first = scanner.peek() else { return line(.blank) }
        if first == "#" { return line(.comment) }
        if first == "[" {
            return line(.invalid(key: nil, message: "Tables are not used. Write each setting on its own line with a dotted key, such as terminal.font-size = 13."))
        }

        let key: String
        do {
            key = try scanner.key()
        } catch {
            return line(.invalid(key: nil, message: error.message))
        }
        scanner.skipSpace()
        guard scanner.peek() == "=" else {
            return line(.invalid(key: key, message: "Expected = after the key \(key)."))
        }
        scanner.advance()
        scanner.skipSpace()
        let start = scanner.position
        let value: ConfigValue
        do {
            value = try scanner.value()
        } catch {
            return line(.invalid(key: key, message: error.message))
        }
        let end = scanner.position
        scanner.skipSpace()
        if let next = scanner.peek(), next != "#" {
            return line(.invalid(key: key, message: "Unexpected text after the value. A comment starts with #."))
        }
        return line(.setting(key: key, value: value), value: start..<end)
    }
}

/// What went wrong reading a line.
struct ConfigSyntaxError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Reads TOML from a line's Unicode scalars.
private struct Scanner {
    let scalars: [Unicode.Scalar]
    var position = 0

    init(_ scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    func peek(_ offset: Int = 0) -> Unicode.Scalar? {
        position + offset < scalars.count ? scalars[position + offset] : nil
    }

    mutating func advance(_ count: Int = 1) {
        position += count
    }

    mutating func skipSpace() {
        while let scalar = peek(), scalar == " " || scalar == "\t" { advance() }
    }

    static func isBareKey(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar {
        case "A"..."Z", "a"..."z", "0"..."9", "_", "-": true
        default: false
        }
    }

    /// A bare key, or bare keys joined with dots.
    mutating func key() throws(ConfigSyntaxError) -> String {
        var parts: [String] = []
        while true {
            skipSpace()
            if peek() == "\"" || peek() == "'" {
                throw ConfigSyntaxError("Quoted keys are not used. Write the key bare, such as terminal.font-size.")
            }
            var part = ""
            while let scalar = peek(), Self.isBareKey(scalar) {
                part.unicodeScalars.append(scalar)
                advance()
            }
            if part.isEmpty {
                throw ConfigSyntaxError(parts.isEmpty
                    ? "Expected a setting such as terminal.font-size = 13, or a comment starting with #."
                    : "Expected a name after the dot in \(parts.joined(separator: ".")).")
            }
            parts.append(part)
            skipSpace()
            guard peek() == "." else { break }
            advance()
        }
        return parts.joined(separator: ".")
    }

    mutating func value() throws(ConfigSyntaxError) -> ConfigValue {
        guard let first = peek() else {
            throw ConfigSyntaxError("Expected a value after =.")
        }
        switch first {
        case "\"": return .string(try basicString())
        case "'": return .string(try literalString())
        case "[": return try array()
        case "{": throw ConfigSyntaxError("Inline tables are not used.")
        default: return try bareValue()
        }
    }

    mutating func basicString() throws(ConfigSyntaxError) -> String {
        if peek(1) == "\"" && peek(2) == "\"" {
            throw ConfigSyntaxError("Multi-line strings are not used. Keep a string on one line, with \\n for a line break.")
        }
        advance()
        var string = ""
        while let scalar = peek() {
            advance()
            switch scalar {
            case "\"":
                return string
            case "\\":
                string.unicodeScalars.append(try escape())
            case _ where (scalar.value < 0x20 && scalar != "\t") || scalar.value == 0x7F:
                throw ConfigSyntaxError("A control character must be escaped in a string.")
            default:
                string.unicodeScalars.append(scalar)
            }
        }
        throw ConfigSyntaxError("A string is missing its closing \".")
    }

    mutating func escape() throws(ConfigSyntaxError) -> Unicode.Scalar {
        guard let scalar = peek() else { throw ConfigSyntaxError("A string is missing its closing \".") }
        advance()
        switch scalar {
        case "b": return "\u{08}"
        case "t": return "\t"
        case "n": return "\n"
        case "f": return "\u{0C}"
        case "r": return "\r"
        case "e": return "\u{1B}"
        case "\"": return "\""
        case "\\": return "\\"
        case "u": return try hexScalar(digits: 4)
        case "U": return try hexScalar(digits: 8)
        default: throw ConfigSyntaxError("\\\(scalar) is not an escape TOML knows.")
        }
    }

    mutating func hexScalar(digits: Int) throws(ConfigSyntaxError) -> Unicode.Scalar {
        var hex = ""
        for _ in 0..<digits {
            guard let scalar = peek(), scalar.properties.isASCIIHexDigit else {
                throw ConfigSyntaxError("\\\(digits == 4 ? "u" : "U") needs \(digits) hex digits.")
            }
            hex.unicodeScalars.append(scalar)
            advance()
        }
        guard let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) else {
            throw ConfigSyntaxError("\\\(digits == 4 ? "u" : "U")\(hex) is not a Unicode character.")
        }
        return scalar
    }

    mutating func literalString() throws(ConfigSyntaxError) -> String {
        if peek(1) == "'" && peek(2) == "'" {
            throw ConfigSyntaxError("Multi-line strings are not used. Keep a string on one line.")
        }
        advance()
        var string = ""
        while let scalar = peek() {
            advance()
            if scalar == "'" { return string }
            if (scalar.value < 0x20 && scalar != "\t") || scalar.value == 0x7F {
                throw ConfigSyntaxError("A literal string cannot hold a control character.")
            }
            string.unicodeScalars.append(scalar)
        }
        throw ConfigSyntaxError("A string is missing its closing '.")
    }

    mutating func array() throws(ConfigSyntaxError) -> ConfigValue {
        advance()
        var values: [ConfigValue] = []
        while true {
            skipSpace()
            guard let scalar = peek() else {
                throw ConfigSyntaxError("An array is missing its closing ]. Keep an array on one line.")
            }
            if scalar == "]" {
                advance()
                return .array(values)
            }
            if scalar == "#" {
                throw ConfigSyntaxError("An array is missing its closing ]. Keep an array on one line.")
            }
            values.append(try value())
            skipSpace()
            switch peek() {
            case ",": advance()
            case "]": continue
            case nil, "#": throw ConfigSyntaxError("An array is missing its closing ]. Keep an array on one line.")
            default: throw ConfigSyntaxError("Expected , or ] after a value in an array.")
            }
        }
    }

    /// `true`, `false`, or a number.
    mutating func bareValue() throws(ConfigSyntaxError) -> ConfigValue {
        var word = ""
        while let scalar = peek(), Self.isBareKey(scalar) || scalar == "+" || scalar == "." || scalar == ":" {
            word.unicodeScalars.append(scalar)
            advance()
        }
        if word.isEmpty {
            throw ConfigSyntaxError("Expected a value: a string in double quotes, a number, true or false, or an array in brackets.")
        }
        switch word {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "inf", "+inf": return .float(.infinity)
        case "-inf": return .float(-.infinity)
        case "nan", "+nan", "-nan": return .float(.nan)
        default: break
        }
        if word.wholeMatch(of: #/[+-]?(0|[1-9](_?[0-9])*)/#) != nil {
            guard let integer = Int(word.replacing("_", with: "")) else {
                throw ConfigSyntaxError("\(word) is too large.")
            }
            return .integer(integer)
        }
        if word.wholeMatch(of: #/[+-]?(0|[1-9](_?[0-9])*)(\.[0-9](_?[0-9])*)?([eE][+-]?[0-9](_?[0-9])*)?/#) != nil,
           let float = Double(word.replacing("_", with: ""))
        {
            return .float(float)
        }
        if word.wholeMatch(of: #/[+-]?0[xob][0-9A-Fa-f_]+/#) != nil {
            throw ConfigSyntaxError("Write \(word) as a decimal number.")
        }
        if word.first?.isLetter ?? false {
            throw ConfigSyntaxError("\(word) needs quotes to be a string: \"\(word)\".")
        }
        throw ConfigSyntaxError("\(word) is not a value TOML knows: use a string in double quotes, a number, true or false, or an array in brackets.")
    }
}
