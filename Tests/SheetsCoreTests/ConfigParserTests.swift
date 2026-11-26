import Foundation
import Testing
@testable import SheetsCore

@Suite struct ConfigParserTests {
    func content(_ line: String) -> ConfigLine.Content {
        ConfigParser.parseLine(line).content
    }

    func value(_ text: String) -> ConfigValue? {
        if case .setting(_, let value) = content("key = \(text)") { return value }
        return nil
    }

    func message(_ line: String) -> String? {
        if case .invalid(_, let message) = content(line) { return message }
        return nil
    }

    @Test func blankLinesAndCommentsSetNothing() {
        #expect(content("") == .blank)
        #expect(content("   \t ") == .blank)
        #expect(content("# a comment") == .comment)
        #expect(content("   # indented comment = 3") == .comment)
    }

    @Test func keysAreBareAndDotted() {
        #expect(content("terminal.font-size = 13") == .setting(key: "terminal.font-size", value: .integer(13)))
        #expect(content("  a . b_c . d-e=1") == .setting(key: "a.b_c.d-e", value: .integer(1)))
        #expect(message("\"quoted\" = 1")?.contains("Quoted keys") == true)
        #expect(message("a. = 1")?.contains("after the dot") == true)
        #expect(message("= 1") != nil)
        #expect(message("terminal.font-size 13")?.contains("Expected =") == true)
    }

    @Test func stringsTakeBasicEscapes() {
        #expect(value(#""plain""#) == .string("plain"))
        #expect(value(#""a \"quote\" and \\ backslash""#) == .string(#"a "quote" and \ backslash"#))
        #expect(value(#""tab\there\nnew\rline\b\f""#) == .string("tab\there\nnew\rline\u{08}\u{0C}"))
        #expect(value(#""\u00E9\U0001F600""#) == .string("é😀"))
        #expect(value(##""# not a comment""##) == .string("# not a comment"))
        #expect(value("\"\"") == .string(""))
        #expect(value("'C:\\no\\escapes'") == .string("C:\\no\\escapes"))
    }

    @Test func badStringsSayWhy() {
        #expect(message(#"key = "open"#)?.contains("closing") == true)
        #expect(message(#"key = "\q""#)?.contains("escape") == true)
        #expect(message(#"key = "\u12""#)?.contains("hex digits") == true)
        #expect(message(#"key = """multi""""#)?.contains("Multi-line") == true)
        #expect(message("key = \"a\u{01}b\"")?.contains("control character") == true)
    }

    @Test func numbersAreIntegersOrFloats() {
        #expect(value("13") == .integer(13))
        #expect(value("-4") == .integer(-4))
        #expect(value("+4") == .integer(4))
        #expect(value("10_000") == .integer(10_000))
        #expect(value("0") == .integer(0))
        #expect(value("1.25") == .float(1.25))
        #expect(value("-0.5") == .float(-0.5))
        #expect(value("1e3") == .float(1000))
        #expect(value("2.5E-1") == .float(0.25))
        #expect(value("inf") == .float(.infinity))
        #expect(message("key = 012") != nil)
        #expect(message("key = 1.") != nil)
        #expect(message("key = .5") != nil)
        #expect(message("key = 1__0") != nil)
        #expect(message("key = 0x1F")?.contains("decimal") == true)
        #expect(message("key = 99999999999999999999")?.contains("too large") == true)
    }

    @Test func booleansAreLowercase() {
        #expect(value("true") == .bool(true))
        #expect(value("false") == .bool(false))
        #expect(message("key = True")?.contains("quotes") == true)
        #expect(message("key = yes")?.contains("not a value TOML knows") == true)
        #expect(ConfigParser.parseLine("key = yes").unreadableWord == "yes")
        #expect(ConfigParser.parseLine("key = \"yes").unreadableWord == nil)
    }

    @Test func arraysStayOnOneLine() {
        #expect(value("[]") == .array([]))
        #expect(value(#"["-l", "-i"]"#) == .strings(["-l", "-i"]))
        #expect(value(#"[ "a" , "b", ]"#) == .strings(["a", "b"]))
        #expect(value("[1, [2, 3], \"x\"]") == .array([.integer(1), .array([.integer(2), .integer(3)]), .string("x")]))
        #expect(message("key = [\"a\", \"b\"")?.contains("closing ]") == true)
        #expect(message("key = [\"a\" # comment")?.contains("closing ]") == true)
        #expect(message("key = [\"a\" \"b\"]")?.contains("Expected , or ]") == true)
    }

    @Test func aTrailingCommentFollowsTheValue() {
        #expect(content("a = 1 # one") == .setting(key: "a", value: .integer(1)))
        #expect(content("a = \"x\"# tight") == .setting(key: "a", value: .string("x")))
        #expect(content("a = [1, 2]   # two") == .setting(key: "a", value: .array([.integer(1), .integer(2)])))
        #expect(message("a = 1 2")?.contains("Unexpected text") == true)
        #expect(message("a = \"x\" y")?.contains("Unexpected text") == true)
    }

    @Test func tablesAndOtherTOMLAreNotUsed() {
        #expect(message("[terminal]")?.contains("Tables are not used") == true)
        #expect(message("a = { b = 1 }")?.contains("Inline tables") == true)
        #expect(message("a =")?.contains("Expected a value") == true)
        #expect(message("a = 1979-05-27") != nil)
    }

    @Test func theValueRangeCoversOnlyTheValue() {
        let line = ConfigParser.parseLine("  terminal.font-size   =  13   # big")
        let scalars = Array(line.text.unicodeScalars)
        let range = try! #require(line.valueRange)
        #expect(String(String.UnicodeScalarView(scalars[range])) == "13")
    }

    @Test func linesAreNumberedFromOneAndKeepTheirBreaks() {
        let lines = ConfigParser.lines(of: "# top\r\n\na = 1\nb = oops")
        #expect(lines.map(\.number) == [1, 2, 3, 4])
        #expect(lines.map(\.terminator) == ["\r\n", "\n", "\n", ""])
        #expect(lines[2].key == "a")
        #expect(lines[3].key == "b")
        if case .invalid = lines[3].content {} else { Issue.record("line 4 should be invalid") }
        #expect(ConfigParser.lines(of: "").isEmpty)
        #expect(ConfigParser.lines(of: "a = 1\n").count == 1)
    }

    @Test func valuesWriteBackAsTheSameTOML() {
        let values: [ConfigValue] = [
            .string("plain"), .string("quote \" backslash \\ tab \t newline \n bell \u{07}"), .integer(-3),
            .float(1.2), .float(1), .float(1e-5), .bool(true), .array([]),
            .strings(["#2B2D31", "-l"]), .array([.integer(1), .array([.bool(false)])]),
        ]
        for original in values {
            let line = ConfigParser.parseLine("key = \(original.tomlText)")
            #expect(line.content == .setting(key: "key", value: original), "\(original.tomlText)")
        }
        #expect(ConfigValue.number(13) == .integer(13))
        #expect(ConfigValue.number(1.5) == .float(1.5))
        #expect(ConfigValue.float(1).tomlText == "1.0")
    }
}

@Suite struct ShellWordsTests {
    @Test func wordsSplitOnSpacesOutsideQuotes() {
        #expect(ShellWords.split("") == [])
        #expect(ShellWords.split("  -l   -i ") == ["-l", "-i"])
        #expect(ShellWords.split(#"-c "echo hi there""#) == ["-c", "echo hi there"])
        #expect(ShellWords.split("'single quoted' x") == ["single quoted", "x"])
        #expect(ShellWords.split(#"a\ b "" c"#) == ["a b", "", "c"])
        #expect(ShellWords.split(#""say \"hi\"""#) == [#"say "hi""#])
    }

    @Test func joiningAndSplittingRoundTrips() {
        let cases: [[String]] = [[], ["-l"], ["-c", "echo hi"], [""], [#"a "quoted" \ word"#, "it's"]]
        for words in cases {
            #expect(ShellWords.split(ShellWords.join(words)) == words, "\(words)")
        }
        #expect(ShellWords.join(["-l", "-i"]) == "-l -i")
    }
}
