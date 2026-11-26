import Foundation

/// A value in the config file, as TOML writes it: a string, an integer, a float, a boolean, or
/// an array of values.
public enum ConfigValue: Hashable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case array([ConfigValue])

    /// A number, written as an integer when it has no fraction, so 13 is `13` rather than
    /// `13.0`.
    public static func number(_ value: Double) -> ConfigValue {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 { return .integer(Int(value)) }
        return .float(value)
    }

    /// An array of strings.
    public static func strings(_ values: [String]) -> ConfigValue {
        .array(values.map(ConfigValue.string))
    }

    /// The value as TOML text, as it goes after `key = `.
    public var tomlText: String {
        switch self {
        case .string(let string): Self.quoted(string)
        case .integer(let integer): String(integer)
        case .float(let float): Self.floatText(float)
        case .bool(let bool): bool ? "true" : "false"
        case .array(let values): "[" + values.map(\.tomlText).joined(separator: ", ") + "]"
        }
    }

    /// The name of the value's type, as an issue says it.
    public var typeName: String {
        switch self {
        case .string: "a string"
        case .integer: "an integer"
        case .float: "a float"
        case .bool: "a boolean"
        case .array: "an array"
        }
    }

    /// The number, for an integer or a float.
    public var numberValue: Double? {
        switch self {
        case .integer(let integer): Double(integer)
        case .float(let float): float
        default: nil
        }
    }

    public var stringValue: String? {
        if case .string(let string) = self { return string }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }

    public var arrayValue: [ConfigValue]? {
        if case .array(let values) = self { return values }
        return nil
    }

    /// A TOML basic string: in double quotes, with quotes, backslashes, and control characters
    /// escaped.
    static func quoted(_ string: String) -> String {
        var text = "\""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\t": text += "\\t"
            case "\r": text += "\\r"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                text += String(format: "\\u%04X", scalar.value)
            default: text.unicodeScalars.append(scalar)
            }
        }
        return text + "\""
    }

    /// A float that TOML reads back as a float: always with a fraction or an exponent.
    static func floatText(_ value: Double) -> String {
        if value.isNaN { return "nan" }
        if value.isInfinite { return value < 0 ? "-inf" : "inf" }
        let text = String(value)
        return text.contains(where: { $0 == "." || $0 == "e" || $0 == "E" }) ? text : text + ".0"
    }
}
