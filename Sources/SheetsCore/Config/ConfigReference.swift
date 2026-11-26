import Foundation

/// The reference for the config file, made from the key table, so it never falls behind.
///
/// `docs/config.md` is `markdown()`. A test checks the two match.
public enum ConfigReference {
    /// Every key as a commented-out line at its default, under a comment saying what it does.
    /// Uncommenting a line gives a valid setting.
    public static func sampleFile() -> String {
        var text = """
            # sheets config file. Each line is one setting, `key = value`, in TOML.
            # Lines starting with # are comments. A missing key uses its default, shown here.

            """
        for definition in ConfigKeys.all {
            text += "\n"
            for line in descriptionLines(definition) { text += "# \(line)\n" }
            text += "# \(definition.key) = \(sampleValue(definition).tomlText)\n"
        }
        return text
    }

    /// What the reference says about a key: its summary, then what unset means and when a
    /// change takes effect, when those need saying.
    static func descriptionLines(_ definition: ConfigKeyDefinition) -> [String] {
        var lines = [definition.summary]
        if definition.defaultValue == nil, let unset = definition.unsetMeaning {
            lines.append("Unset by default, which means \(unset).")
        }
        if definition.timing == .newTerminals {
            lines.append("Applies to terminals started after the change.")
        }
        return lines
    }

    /// The value the sample shows: the default, or an example for a key with none.
    static func sampleValue(_ definition: ConfigKeyDefinition) -> ConfigValue {
        definition.defaultValue ?? definition.example ?? .string("")
    }

    /// The whole of `docs/config.md`.
    public static func markdown() -> String {
        var text = """
            # The config file

            <!-- Made by ConfigReference.markdown() from the key table in Sources/SheetsCore/Config/ConfigKeys.swift. -->
            <!-- After changing a key, run: SHEETS_WRITE_CONFIG_REFERENCE=1 swift test --filter ConfigReferenceTests -->

            sheets reads its settings from a plain text file, so a person or a tool can change them
            with any editor. Settings, Terminal shows the same settings and writes to the same file.

            ## Where it is

            `~/.config/sheets/config`, or `$XDG_CONFIG_HOME/sheets/config` when `XDG_CONFIG_HOME`
            is set. `SHEETS_CONFIG_PATH` names another file, for tests.

            The file does not need to exist. The app makes it the first time a setting is changed
            in Settings.

            ## How it reads

            - One setting per line: `key = value`. Keys are lowercase and dotted, such as
              `terminal.font-size`.
            - Every line is valid TOML: strings in double quotes, numbers, `true` and `false`, and
              arrays on one line, such as `["-l"]`. Colors are strings such as `"#1D1E21"`.
              There are no `[tables]`.
            - `#` starts a comment, on its own line or after a value.
            - The file holds only what differs from the defaults. Remove a line to go back to the
              default.
            - The app watches the file and applies a change while it runs. Some settings reach
              only terminals started after the change, as each one says.

            ## When a line is wrong

            The app always starts. A line it cannot use is listed in Settings, Terminal, with its
            line number:

            - A line with a syntax error, or a value its key does not take, is skipped, and its key
              keeps its last good value, or its default at launch.
            - A key the app does not know is skipped with a warning. The line stays in the file.
            - A key set twice uses the last line, with a warning.

            Changing a setting in Settings rewrites only that setting's line. Comments, blank
            lines, the order of lines, and keys the app does not know stay as they are.

            ## Every setting

            The file below sets nothing: every line is a comment showing a key at its default.

            ```toml

            """
        text += sampleFile()
        text += "```\n"
        return text
    }
}
