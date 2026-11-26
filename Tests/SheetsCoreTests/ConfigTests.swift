import Foundation
import Testing
@testable import SheetsCore

@Suite struct ConfigKeysTests {
    @Test func everyKeyIsUniqueLowercaseDottedKebab() {
        let keys = ConfigKeys.all.map(\.key)
        #expect(Set(keys).count == keys.count)
        for key in keys {
            #expect(key.wholeMatch(of: #/[a-z]+(\.[a-z]+(-[a-z]+)*)+/#) != nil, "\(key)")
            #expect(ConfigKeys.definition(for: key)?.key == key)
        }
        #expect(ConfigKeys.definition(for: "terminal.no-such-key") == nil)
    }

    @Test func everyDefaultIsAllowedForItsOwnKey() {
        for definition in ConfigKeys.all {
            let value = definition.defaultValue ?? definition.example
            #expect(value != nil, "\(definition.key) has neither a default nor an example")
            if let value {
                #expect((try? definition.check(value).get()) == value, "\(definition.key)")
            }
            if definition.defaultValue == nil { #expect(definition.unsetMeaning != nil, "\(definition.key)") }
            #expect(!definition.summary.isEmpty)
        }
    }

    @Test func theDefaultsAreTodaysTerminal() {
        #expect(Config.defaults.terminalAppearance == .standard)
        #expect(Config.defaults.terminalBehavior == .standard)
        #expect(TerminalBehavior.standard.scrollbackLines == 10_000)
        #expect(TerminalBehavior.standard.optionAsMeta == .off)
        #expect(TerminalBehavior.standard.bell == .sound)
        #expect(TerminalBehavior.standard.mouseReporting)
        #expect(!TerminalBehavior.standard.copyOnSelect)
        #expect(Config.defaults.shell == nil)
        #expect(Config.defaults.shellArguments == [])
        #expect(Config.defaults.startingFolder(home: "/home/someone") == "/home/someone")
        #expect(Config.defaults[ConfigKeys.fontFamily] == nil)
        #expect(Config.defaults[ConfigKeys.palette]?.arrayValue?.count == 16)
    }

    @Test func rangesAreChecked() {
        let size = ConfigKeys.fontSize
        #expect((try? size.check(.integer(13)).get()) == .integer(13))
        #expect((try? size.check(.float(12.5)).get()) == .float(12.5))
        #expect((try? size.check(.integer(5)).get()) == nil)
        #expect((try? size.check(.integer(73)).get()) == nil)
        #expect((try? size.check(.float(.nan)).get()) == nil)
        #expect((try? size.check(.string("13")).get()) == nil)
        let scrollback = ConfigKeys.scrollbackLines
        #expect((try? scrollback.check(.integer(0)).get()) == .integer(0))
        #expect((try? scrollback.check(.integer(-1)).get()) == nil)
        #expect((try? scrollback.check(.float(100)).get()) == nil)
    }

    @Test func choicesAreChecked() {
        for name in ["block", "underline", "bar"] {
            #expect((try? ConfigKeys.cursorStyle.check(.string(name)).get()) != nil)
        }
        #expect((try? ConfigKeys.cursorStyle.check(.string("beam")).get()) == nil)
        for name in ["off", "left", "right", "both"] {
            #expect((try? ConfigKeys.optionAsMeta.check(.string(name)).get()) != nil)
        }
        for name in ["none", "sound", "visual", "sound-and-visual"] {
            #expect((try? ConfigKeys.bell.check(.string(name)).get()) != nil)
        }
        #expect((try? ConfigKeys.bell.check(.string("Sound")).get()) == nil)
    }

    @Test func colorsAndThePaletteAreChecked() {
        #expect((try? ConfigKeys.foreground.check(.string("#a1B2c3")).get()) != nil)
        #expect((try? ConfigKeys.foreground.check(.string("a1b2c3")).get()) == nil)
        #expect((try? ConfigKeys.foreground.check(.string("#abc")).get()) == nil)
        #expect((try? ConfigKeys.foreground.check(.string("#GGGGGG")).get()) == nil)
        let sixteen = ConfigValue.strings(Array(repeating: "#000000", count: 16))
        #expect((try? ConfigKeys.palette.check(sixteen).get()) == sixteen)
        let fifteen = ConfigKeys.palette.check(.strings(Array(repeating: "#000000", count: 15)))
        #expect(fifteen == .failure(ConfigValueProblem("exactly 16 colors, not 15")))
        #expect((try? ConfigKeys.palette.check(.strings(Array(repeating: "red", count: 16))).get()) == nil)
    }

    @Test func colorsReadAndWriteAsHex() {
        #expect(TerminalColor(hexString: "#1D1E21") == TerminalColor(hex: 0x1D1E21))
        #expect(TerminalColor(hex: 0x1D1E21).hexString == "#1D1E21")
        #expect(TerminalColor(hexString: "#ffffff")?.hexString == "#FFFFFF")
        #expect(TerminalColor(hexString: "#12345") == nil)
        #expect(TerminalColor(hexString: "#+12345") == nil)
    }
}

@Suite struct ConfigLoadingTests {
    @Test func aMissingOrEmptyFileIsAllDefaults() {
        let loaded = Config.load("")
        #expect(loaded.config == .defaults)
        #expect(loaded.issues.isEmpty)
        #expect(Config.load("# only comments\n\n").config == .defaults)
    }

    @Test func goodLinesOverrideTheDefaults() {
        let text = """
            terminal.font-family = "Menlo"
            terminal.font-size = 14
            terminal.line-spacing = 1.2
            terminal.background = "#000000"
            terminal.cursor-style = "bar"   # thin
            terminal.cursor-blink = false
            terminal.option-as-meta = "left"
            terminal.copy-on-select = true
            terminal.mouse-reporting = false
            terminal.bell = "visual"
            terminal.scrollback-lines = 500
            terminal.shell = "/bin/bash"
            terminal.shell-arguments = ["-l"]
            terminal.starting-folder = "~/Projects"
            """
        let loaded = Config.load(text)
        #expect(loaded.issues.isEmpty)
        let appearance = loaded.config.terminalAppearance
        #expect(appearance.fontName == "Menlo")
        #expect(appearance.fontSize == 14)
        #expect(appearance.lineSpacing == 1.2)
        #expect(appearance.background == TerminalColor(hex: 0))
        #expect(appearance.foreground == TerminalAppearance.standard.foreground)
        #expect(appearance.cursorShape == .bar)
        #expect(!appearance.cursorBlinks)
        let behavior = loaded.config.terminalBehavior
        #expect(behavior == TerminalBehavior(
            scrollbackLines: 500, optionAsMeta: .left, copyOnSelect: true, mouseReporting: false, bell: .visual))
        #expect(loaded.config.shell == "/bin/bash")
        #expect(loaded.config.shellArguments == ["-l"])
        #expect(loaded.config.startingFolder(home: "/home/someone") == "/home/someone/Projects")
    }

    @Test func aBadLineIsAnErrorWithItsLineNumberAndTheKeyKeepsItsDefault() {
        let loaded = Config.load("# comment\nterminal.font-size = 200\nterminal.bell = sound\n")
        #expect(loaded.config == .defaults)
        #expect(loaded.issues.map(\.line) == [2, 3])
        #expect(loaded.issues.allSatisfy { $0.severity == .error })
        #expect(loaded.issues[0].key == "terminal.font-size")
        #expect(loaded.issues[0].message == "terminal.font-size must be a number from 6 to 72. It keeps its last good value.")
        #expect(loaded.issues[1].message.contains("\"sound\""))
        #expect(loaded.issues[0].description.hasPrefix("Line 2: "))
    }

    @Test func aBadLineKeepsTheLastGoodValueWhileRunning() {
        let first = Config.load("terminal.font-size = 15").config
        let second = Config.load("terminal.font-size = huge", previous: first)
        #expect(second.config.number(ConfigKeys.fontSize) == 15)
        #expect(second.issues.count == 1)
        // A key the file no longer mentions goes back to its default.
        #expect(Config.load("", previous: first).config == .defaults)
        // A bad line for one key leaves the others to the file.
        let third = Config.load("terminal.font-size = huge\nterminal.bell = \"none\"", previous: first)
        #expect(third.config.number(ConfigKeys.fontSize) == 15)
        #expect(third.config.terminalBehavior.bell == .none)
    }

    @Test func aWrongTypeIsAnError() {
        let loaded = Config.load("terminal.copy-on-select = \"yes\"\nterminal.palette = [\"#000000\"]")
        #expect(loaded.issues.map(\.line) == [1, 2])
        #expect(loaded.issues[0].message == "terminal.copy-on-select must be true or false. It keeps its last good value.")
        #expect(loaded.issues[1].message.contains("exactly 16 colors, not 1"))
        #expect(loaded.config == .defaults)
    }

    @Test func anUnknownKeyIsAWarningAndIgnored() {
        let loaded = Config.load("\nterminal.font-sise = 13\nfuture.thing = true")
        #expect(loaded.config == .defaults)
        #expect(loaded.issues.map(\.line) == [2, 3])
        #expect(loaded.issues.allSatisfy { $0.severity == .warning })
        #expect(loaded.issues[0].message == "terminal.font-sise is not a setting this version knows. The line is ignored.")
    }

    @Test func aDuplicateKeyUsesTheLastLineWithAWarning() {
        let loaded = Config.load("terminal.font-size = 13\nterminal.font-size = 16\n")
        #expect(loaded.config.number(ConfigKeys.fontSize) == 16)
        #expect(loaded.issues == [ConfigIssue(
            line: 2, severity: .warning, key: "terminal.font-size",
            message: "terminal.font-size is also set on line 1. The last one is used.")])
        // A bad line after a good one leaves the good one in place.
        let bad = Config.load("terminal.font-size = 13\nterminal.font-size = 0\n")
        #expect(bad.config.number(ConfigKeys.fontSize) == 13)
        #expect(bad.issues.map(\.severity) == [.error])
    }

    @Test func syntaxErrorsCarryTheirLineNumber() {
        let loaded = Config.load("a = 1\n[terminal]\nterminal.font-size = \"13\n")
        #expect(loaded.issues.map(\.line) == [1, 2, 3])
        #expect(loaded.issues[1].severity == .error)
        #expect(loaded.issues[1].message.contains("Tables are not used"))
        #expect(loaded.issues[2].key == "terminal.font-size")
        #expect(loaded.issues[2].message.contains("closing"))
    }

    @Test func tildeExpandsOnlyAtTheStart() {
        #expect(Config.expandingTilde("~", home: "/h") == "/h")
        #expect(Config.expandingTilde("~/a", home: "/h") == "/h/a")
        #expect(Config.expandingTilde("/a/~", home: "/h") == "/a/~")
        #expect(Config.expandingTilde("~other", home: "/h") == "~other")
    }
}

@Suite struct ConfigEditorTests {
    let sample = """
        # My settings
        terminal.font-size = 12   # small

        future.key = "kept as is"
        terminal.bell="none"
        # end

        """

    @Test func setReplacesOnlyTheValueOfThatLine() {
        let edited = ConfigEditor.setting("terminal.font-size", to: .integer(14), in: sample)
        #expect(edited == sample.replacingOccurrences(of: "= 12   # small", with: "= 14   # small"))
        let bell = ConfigEditor.setting("terminal.bell", to: .string("visual"), in: sample)
        #expect(bell == sample.replacingOccurrences(of: #"terminal.bell="none""#, with: #"terminal.bell="visual""#))
    }

    @Test func everyOtherByteStaysTheSame() {
        let crlf = "# a\r\n\r\nterminal.font-size = 12\r\nunknown = [1, 2]\r\n"
        let edited = ConfigEditor.setting("terminal.font-size", to: .float(12.5), in: crlf)
        #expect(edited == "# a\r\n\r\nterminal.font-size = 12.5\r\nunknown = [1, 2]\r\n")
        #expect(Data(edited.utf8).count == Data(crlf.utf8).count + 2)
    }

    @Test func aKeyNotThereIsAddedAtTheEnd() {
        #expect(ConfigEditor.setting("terminal.bell", to: .string("none"), in: "") == "terminal.bell = \"none\"\n")
        #expect(ConfigEditor.setting("terminal.bell", to: .string("none"), in: "# a\n") == "# a\nterminal.bell = \"none\"\n")
        #expect(ConfigEditor.setting("terminal.bell", to: .string("none"), in: "# a") == "# a\nterminal.bell = \"none\"\n")
        #expect(ConfigEditor.setting("terminal.bell", to: .string("none"), in: "# a\r\n") == "# a\r\nterminal.bell = \"none\"\r\n")
    }

    @Test func aBadLineForTheKeyIsReplacedWhole() {
        let edited = ConfigEditor.setting("terminal.font-size", to: .integer(13), in: "terminal.font-size = big # x\nb = 1\n")
        #expect(edited == "terminal.font-size = 13\nb = 1\n")
    }

    @Test func aKeySetTwiceEndsUpOnOneLine() {
        let text = "terminal.font-size = 12\n# between\nterminal.font-size = 16 # later\n"
        let edited = ConfigEditor.setting("terminal.font-size", to: .integer(18), in: text)
        #expect(edited == "# between\nterminal.font-size = 18 # later\n")
    }

    @Test func removeDeletesTheKeysLinesOnly() {
        let removed = ConfigEditor.removing("terminal.font-size", from: sample)
        #expect(removed == sample.replacingOccurrences(of: "terminal.font-size = 12   # small\n", with: ""))
        #expect(ConfigEditor.removing("terminal.shell", from: sample) == sample)
        #expect(ConfigEditor.removing("a", from: "a = 1\nb = 2\na = 3") == "b = 2\n")
        #expect(ConfigEditor.removing("b", from: "a = 1\nb = 2") == "a = 1\n")
    }

    @Test func setThenRemoveRoundTrips() {
        let added = ConfigEditor.setting("terminal.shell", to: .string("/bin/bash"), in: sample)
        #expect(Config.load(added).config.shell == "/bin/bash")
        #expect(ConfigEditor.removing("terminal.shell", from: added) == sample)
        // Editing keeps unknown keys and their warnings.
        #expect(Config.load(added).issues.map(\.key) == ["future.key"])
    }

    @Test func valuesWithQuotesAndArraysWriteValidLines() {
        var text = ConfigEditor.setting("terminal.font-family", to: .string(#"Odd "Name" \ Mono"#), in: "")
        text = ConfigEditor.setting("terminal.shell-arguments", to: .strings(["-c", "echo \"hi\""]), in: text)
        let loaded = Config.load(text)
        #expect(loaded.issues.isEmpty)
        #expect(loaded.config.string(ConfigKeys.fontFamily) == #"Odd "Name" \ Mono"#)
        #expect(loaded.config.shellArguments == ["-c", "echo \"hi\""])
    }
}

@Suite struct ConfigFileLocationTests {
    let home = "/home/someone"

    @Test func theDefaultIsInDotConfig() {
        #expect(ConfigFileLocation.path(environment: [:], home: home) == "/home/someone/.config/sheets/config")
    }

    @Test func xdgConfigHomeIsUsedWhenAbsolute() {
        #expect(ConfigFileLocation.path(environment: ["XDG_CONFIG_HOME": "/xdg"], home: home) == "/xdg/sheets/config")
        #expect(ConfigFileLocation.path(environment: ["XDG_CONFIG_HOME": "relative"], home: home) == "/home/someone/.config/sheets/config")
        #expect(ConfigFileLocation.path(environment: ["XDG_CONFIG_HOME": ""], home: home) == "/home/someone/.config/sheets/config")
    }

    @Test func theOverrideWinsAndExpandsTilde() {
        let environment = ["XDG_CONFIG_HOME": "/xdg", "SHEETS_CONFIG_PATH": "~/test/config"]
        #expect(ConfigFileLocation.path(environment: environment, home: home) == "/home/someone/test/config")
        #expect(ConfigFileLocation.path(environment: ["SHEETS_CONFIG_PATH": "/tmp/c"], home: home) == "/tmp/c")
        #expect(ConfigFileLocation.path(environment: ["SHEETS_CONFIG_PATH": ""], home: home) == "/home/someone/.config/sheets/config")
    }

    @Test func pathsShowTheHomeFolderAsTilde() {
        #expect(ConfigFileLocation.displayPath("/home/someone/.config/sheets/config", home: home) == "~/.config/sheets/config")
        #expect(ConfigFileLocation.displayPath("/home/someone", home: home) == "~")
        #expect(ConfigFileLocation.displayPath("/home/someoneelse/x", home: home) == "/home/someoneelse/x")
    }
}

@Suite struct ConfigReferenceTests {
    /// The repo's `docs/config.md`.
    static let docURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/config.md")

    @Test func theCommittedReferenceMatchesTheKeyTable() throws {
        let generated = ConfigReference.markdown()
        if ProcessInfo.processInfo.environment["SHEETS_WRITE_CONFIG_REFERENCE"] == "1" {
            try generated.write(to: Self.docURL, atomically: true, encoding: .utf8)
        }
        let committed = try String(contentsOf: Self.docURL, encoding: .utf8)
        #expect(committed == generated, """
            docs/config.md is out of date. Run: SHEETS_WRITE_CONFIG_REFERENCE=1 swift test --filter ConfigReferenceTests
            """)
    }

    @Test func theSampleNamesEveryKeyAndSetsNothing() {
        let sample = ConfigReference.sampleFile()
        for definition in ConfigKeys.all {
            #expect(sample.contains("# \(definition.key) = "), "\(definition.key)")
        }
        let loaded = Config.load(sample)
        #expect(loaded.config == .defaults)
        #expect(loaded.issues.isEmpty)
        #expect(sample.contains("# terminal.font-size = 12\n"))
    }

    @Test func uncommentingEverySampleLineGivesValidSettings() {
        let uncommented = ConfigReference.sampleFile()
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let text = String(line)
                let isSetting = ConfigKeys.all.contains { text.hasPrefix("# \($0.key) = ") }
                return isSetting ? String(text.dropFirst(2)) : text
            }
            .joined(separator: "\n")
        let loaded = Config.load(uncommented)
        #expect(loaded.issues.isEmpty)
        #expect(loaded.config.overrides.count == ConfigKeys.all.count)
        #expect(loaded.config.terminalAppearance.fontName == "Menlo")
        #expect(loaded.config.terminalBehavior == .standard)
    }
}
