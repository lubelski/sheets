import Foundation

/// A list of arguments as one line of text, the way a shell writes them: separated by spaces,
/// with double quotes around an argument that has spaces or quotes in it. Settings edits the
/// shell's arguments this way.
public enum ShellWords {
    /// The arguments as one line. An empty argument is `""`.
    public static func join(_ words: [String]) -> String {
        words.map { word in
            let needsQuotes = word.isEmpty || word.contains { $0 == " " || $0 == "\t" || $0 == "\"" || $0 == "'" || $0 == "\\" }
            guard needsQuotes else { return word }
            let escaped = word.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
            return "\"\(escaped)\""
        }.joined(separator: " ")
    }

    /// A line split into arguments. Spaces separate arguments, except inside double or single
    /// quotes. A backslash outside single quotes keeps the next character as it is. An
    /// unclosed quote runs to the end of the line.
    public static func split(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        for character in line {
            if escaping {
                current.append(character)
                escaping = false
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\" && open == "\"" {
                    escaping = true
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case " ", "\t":
                if inWord {
                    words.append(current)
                    current = ""
                    inWord = false
                }
            case "\"", "'":
                quote = character
                inWord = true
            case "\\":
                escaping = true
                inWord = true
            default:
                current.append(character)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
