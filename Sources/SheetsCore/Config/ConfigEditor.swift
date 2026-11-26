import Foundation

/// Changes to a config file's text that touch only the lines of one key.
///
/// Every other byte stays as it was: comments, blank lines, the order of lines, keys the app
/// does not know, and line breaks. These are pure functions over the text, so the Settings UI
/// and any other tool that edits the file make the same changes.
public enum ConfigEditor {
    /// The text with a key set to a value.
    ///
    /// - When the key has a line, its value is replaced in place. The key as written, the
    ///   spaces around `=`, and a trailing comment stay. A line for the key that could not be
    ///   read is replaced whole.
    /// - When the key has more than one line, the last is replaced and the others are removed,
    ///   so the file says one thing.
    /// - When the key has no line, `key = value` is added at the end.
    public static func setting(_ key: String, to value: ConfigValue, in text: String) -> String {
        let lines = ConfigParser.lines(of: text)
        let matching = lines.indices.filter { lines[$0].key == key }
        guard let last = matching.last else {
            var result = text
            if let end = result.last, end != "\n", end != "\r\n" { result += newline(of: lines) }
            return result + "\(key) = \(value.tomlText)" + newline(of: lines)
        }
        var result = ""
        for index in lines.indices {
            let line = lines[index]
            if index == last {
                result += replacingValue(of: line, key: key, with: value) + line.terminator
            } else if !matching.contains(index) {
                result += line.text + line.terminator
            }
        }
        return result
    }

    /// The text without the key's lines, so the key goes back to its default. Text without
    /// the key comes back as it was.
    public static func removing(_ key: String, from text: String) -> String {
        let lines = ConfigParser.lines(of: text)
        guard lines.contains(where: { $0.key == key }) else { return text }
        return lines.filter { $0.key != key }.map { $0.text + $0.terminator }.joined()
    }

    /// One line with its value replaced.
    static func replacingValue(of line: ConfigLine, key: String, with value: ConfigValue) -> String {
        guard case .setting = line.content, let range = line.valueRange else {
            return "\(key) = \(value.tomlText)"
        }
        let scalars = Array(line.text.unicodeScalars)
        var text = String(String.UnicodeScalarView(scalars[..<range.lowerBound]))
        text += value.tomlText
        text += String(String.UnicodeScalarView(scalars[range.upperBound...]))
        return text
    }

    /// The line break the file uses: `\r\n` when its first line ends with one, or else `\n`.
    static func newline(of lines: [ConfigLine]) -> String {
        lines.first(where: { !$0.terminator.isEmpty })?.terminator ?? "\n"
    }
}
