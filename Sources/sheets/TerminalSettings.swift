import AppKit
import SheetsCore
import SwiftUI
import UniformTypeIdentifiers

/// Settings, Terminal: the terminals' font, colors, cursor, keyboard and mouse, and shell, and
/// the config file they live in.
///
/// Every control reads the loaded config and writes through `ConfigStore`, which changes only
/// that key's line in the file. An edit to the file from anywhere else shows here as soon as
/// it is saved. A control for a key the file sets has a reset button, which removes the line.
struct TerminalSettings: View {
    let config: ConfigStore

    var body: some View {
        Form {
            ConfigFileSection(config: config)
            Section("Font") {
                FontFamilyRow(config: config)
                SettingRow("Size", ConfigKeys.fontSize, config) {
                    NumberStepper(
                        config: config, definition: ConfigKeys.fontSize, step: 1, range: 6...72,
                        format: { "\(Int($0)) pt" })
                }
                SettingRow("Line spacing", ConfigKeys.lineSpacing, config) {
                    NumberStepper(
                        config: config, definition: ConfigKeys.lineSpacing, step: 0.1, range: 0.8...2,
                        format: { String(format: "%.1f×", $0) })
                }
            }
            Section("Colors") {
                ColorRow("Text", ConfigKeys.foreground, config)
                ColorRow("Background", ConfigKeys.background, config)
                ColorRow("Cursor", ConfigKeys.cursorColor, config)
                ColorRow("Selection", ConfigKeys.selectionColor, config)
                PaletteRow(config: config)
            }
            Section("Cursor") {
                SettingRow("Shape", ConfigKeys.cursorStyle, config) {
                    ChoicePicker(config: config, definition: ConfigKeys.cursorStyle, choices: [
                        ("block", "Block"), ("underline", "Underline"), ("bar", "Bar"),
                    ])
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                SettingRow("Blink", ConfigKeys.cursorBlink, config) {
                    BoolSwitch(config: config, definition: ConfigKeys.cursorBlink)
                }
            }
            Section("Keyboard and mouse") {
                SettingRow("Option as Meta", ConfigKeys.optionAsMeta, config,
                           note: "Off types characters such as é. Meta sends Escape before the key.") {
                    ChoicePicker(config: config, definition: ConfigKeys.optionAsMeta, choices: [
                        ("off", "Off"), ("left", "Left Option"), ("right", "Right Option"), ("both", "Both Option keys"),
                    ])
                    .fixedSize()
                }
                SettingRow("Copy on select", ConfigKeys.copyOnSelect, config) {
                    BoolSwitch(config: config, definition: ConfigKeys.copyOnSelect)
                }
                SettingRow("Mouse reporting", ConfigKeys.mouseReporting, config,
                           note: "Programs such as vim and tmux get clicks and scrolling.") {
                    BoolSwitch(config: config, definition: ConfigKeys.mouseReporting)
                }
                SettingRow("Bell", ConfigKeys.bell, config) {
                    ChoicePicker(config: config, definition: ConfigKeys.bell, choices: [
                        ("none", "None"), ("sound", "Sound"), ("visual", "Flash"), ("sound-and-visual", "Sound and flash"),
                    ])
                    .fixedSize()
                }
            }
            Section {
                SettingRow("Shell", ConfigKeys.shell, config) {
                    ConfigTextField(
                        config: config, definition: ConfigKeys.shell, prompt: Self.loginShell,
                        text: { $0?.stringValue ?? "" },
                        value: { $0.isEmpty ? nil : .string($0) })
                }
                SettingRow("Arguments", ConfigKeys.shellArguments, config) {
                    ConfigTextField(
                        config: config, definition: ConfigKeys.shellArguments, prompt: "None",
                        text: { ShellWords.join(($0?.arrayValue ?? []).compactMap(\.stringValue)) },
                        value: { .strings(ShellWords.split($0)) })
                }
                SettingRow("Starting folder", ConfigKeys.startingFolder, config,
                           note: "When no group above a new terminal has a folder.") {
                    StartingFolderField(config: config)
                }
                SettingRow("Scrollback", ConfigKeys.scrollbackLines, config) {
                    ConfigTextField(
                        config: config, definition: ConfigKeys.scrollbackLines, prompt: "10000", width: 90,
                        text: { $0.map { $0.tomlText } ?? "" },
                        value: { text in
                            let digits = text.filter { !$0.isWhitespace && $0 != "," && $0 != "_" }
                            return digits.isEmpty ? nil : Int(digits).map(ConfigValue.integer) ?? .string(text)
                        })
                    Text("lines").foregroundStyle(.secondary)
                }
            } header: {
                Text("Shell")
            } footer: {
                Text("These apply to terminals started after the change, and to Start Again.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// The shell a terminal runs when the config file names none.
    static let loginShell: String = {
        let shell = TerminalUser.current().shell ?? TerminalLaunch.fallbackShell
        return shell.hasPrefix("/") ? shell : TerminalLaunch.fallbackShell
    }()
}

// MARK: The config file

/// Where the file is, buttons to show and open it, and what is wrong in it.
struct ConfigFileSection: View {
    let config: ConfigStore

    var body: some View {
        Section {
            LabeledContent("File") {
                Text(config.displayPath)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            HStack {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder", action: reveal)
                Button("Open", action: openInEditor)
            }
            if let error = config.fileError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            ForEach(config.issues) { issue in
                ConfigIssueRow(issue: issue)
            }
        } header: {
            Text("Config file")
        } footer: {
            Text("Settings here are written to this file, which any editor can change too. A change to the file shows here once it is saved.")
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        guard config.fileExists else { return "Not made yet. Every setting is at its default." }
        let errors = config.issues.filter { $0.severity == .error }.count
        let warnings = config.issues.count - errors
        switch (errors, warnings) {
        case (0, 0): return "No issues."
        case (_, 0): return errors == 1 ? "1 line could not be used." : "\(errors) lines could not be used."
        case (0, _): return warnings == 1 ? "1 warning." : "\(warnings) warnings."
        default:
            return "\(errors) \(errors == 1 ? "line" : "lines") could not be used, \(warnings) \(warnings == 1 ? "warning" : "warnings")."
        }
    }

    /// Shows the file in Finder, or the nearest folder that exists when the file does not.
    private func reveal() {
        let url = URL(filePath: config.path)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        var folder = url.deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: folder.path), folder.path != "/" {
            folder = folder.deletingLastPathComponent()
        }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
    }

    /// Opens the file in the default text editor. A file that does not exist yet is made first,
    /// with every key commented out at its default.
    private func openInEditor() {
        try? config.createIfMissing()
        let url = URL(filePath: config.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        // The file has no extension, so name the app rather than leave it to the file's type.
        if let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) {
            NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

/// One issue: its line number and what is wrong.
struct ConfigIssueRow: View {
    let issue: ConfigIssue

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(issue.severity == .error ? Color.red : Color.yellow)
            Text("Line \(issue.line)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)
            Text(issue.message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .textSelection(.enabled)
    }
}

// MARK: Rows

/// A setting's row: its label, a reset button while the file sets the key, and the control.
/// The reset button's place is kept when it is hidden, so the control does not move.
struct SettingRow<Control: View>: View {
    let title: String
    let definition: ConfigKeyDefinition
    let config: ConfigStore
    let note: String?
    @ViewBuilder let control: () -> Control

    init(
        _ title: String, _ definition: ConfigKeyDefinition, _ config: ConfigStore, note: String? = nil,
        @ViewBuilder control: @escaping () -> Control
    ) {
        self.title = title
        self.definition = definition
        self.config = config
        self.note = note
        self.control = control
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                ResetButton(config: config, definition: definition)
                control()
            }
        } label: {
            Text(title)
            if let note { Text(note) }
        }
        .help(definition.key)
    }
}

/// Removes a key's line from the file. Shown only while the file sets the key.
struct ResetButton: View {
    let config: ConfigStore
    let definition: ConfigKeyDefinition

    var body: some View {
        let isSet = config.config.isSet(definition)
        Button {
            try? config.remove(definition)
        } label: {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("Reset to the default")
        .accessibilityLabel("Reset \(definition.key) to the default")
        .opacity(isSet ? 1 : 0)
        .disabled(!isSet)
    }
}

/// An on and off switch for a boolean key.
struct BoolSwitch: View {
    let config: ConfigStore
    let definition: ConfigKeyDefinition

    var body: some View {
        Toggle(definition.key, isOn: Binding(
            get: { config.config.bool(definition) },
            set: { try? config.set(definition, to: .bool($0)) }))
            .labelsHidden()
            .toggleStyle(.switch)
    }
}

/// A picker for a key that takes one of a few names.
struct ChoicePicker: View {
    let config: ConfigStore
    let definition: ConfigKeyDefinition
    /// Each name with its label.
    let choices: [(String, String)]

    var body: some View {
        Picker(definition.key, selection: Binding(
            get: { config.config.string(definition) ?? "" },
            set: { try? config.set(definition, to: .string($0)) })) {
            ForEach(choices, id: \.0) { name, label in Text(label).tag(name) }
        }
        .labelsHidden()
    }
}

/// A number with a stepper beside it.
struct NumberStepper: View {
    let config: ConfigStore
    let definition: ConfigKeyDefinition
    let step: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        let value = config.config.number(definition)
        HStack(spacing: 4) {
            Text(format(value))
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
            Stepper(definition.key, value: Binding(
                get: { value },
                set: { new in
                    // Round to the step, so 1.2 is written as 1.2 and not 1.2000000000000002.
                    let rounded = ((new / step).rounded() * step * 1000).rounded() / 1000
                    try? config.set(definition, to: .number(min(max(rounded, range.lowerBound), range.upperBound)))
                }), in: range, step: step)
                .labelsHidden()
        }
    }
}

/// A color well for a color key.
struct ColorRow: View {
    let title: String
    let definition: ConfigKeyDefinition
    let config: ConfigStore

    init(_ title: String, _ definition: ConfigKeyDefinition, _ config: ConfigStore) {
        self.title = title
        self.definition = definition
        self.config = config
    }

    var body: some View {
        SettingRow(title, definition, config) {
            Text(config.config.color(definition).hexString)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            ColorPicker(definition.key, selection: Binding(
                get: { Color(config.config.color(definition)) },
                set: { color in
                    guard let new = TerminalColor(color), new != config.config.color(definition) else { return }
                    try? config.set(definition, to: .string(new.hexString))
                }), supportsOpacity: false)
                .labelsHidden()
        }
    }
}

/// The 16 ANSI colors: two rows of eight small wells, the normal colors over the bright ones.
struct PaletteRow: View {
    let config: ConfigStore

    static let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]

    var body: some View {
        let palette = currentPalette
        SettingRow("ANSI colors", ConfigKeys.palette, config, note: "Normal, then bright.") {
            VStack(alignment: .trailing, spacing: 4) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<8, id: \.self) { column in
                            let index = row * 8 + column
                            ColorPicker(
                                (row == 1 ? "Bright " : "") + Self.names[column],
                                selection: Binding(
                                    get: { Color(palette[index]) },
                                    set: { color in set(index, to: color) }),
                                supportsOpacity: false)
                                .labelsHidden()
                                .controlSize(.small)
                                .help((row == 1 ? "Bright " : "") + Self.names[column].lowercased())
                        }
                    }
                }
            }
        }
    }

    private var currentPalette: [TerminalColor] {
        let colors = config.config.colors(ConfigKeys.palette)
        return colors.count == 16 ? colors : TerminalAppearance.standard.palette
    }

    private func set(_ index: Int, to color: Color) {
        var palette = currentPalette
        guard let new = TerminalColor(color), palette[index] != new else { return }
        palette[index] = new
        try? config.set(ConfigKeys.palette, to: .strings(palette.map(\.hexString)))
    }
}

/// The font family: the system's monospaced font, or any fixed-width family on this Mac.
struct FontFamilyRow: View {
    let config: ConfigStore

    /// The fixed-width font families, by name.
    static let families: [String] = {
        let manager = NSFontManager.shared
        let names = manager.availableFontNames(with: .fixedPitchFontMask) ?? []
        let families = Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })
        return families.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }()

    var body: some View {
        let current = config.config.string(ConfigKeys.fontFamily) ?? ""
        SettingRow("Family", ConfigKeys.fontFamily, config) {
            Picker(ConfigKeys.fontFamily.key, selection: Binding(
                get: { current },
                set: { family in
                    if family.isEmpty {
                        try? config.remove(ConfigKeys.fontFamily)
                    } else {
                        try? config.set(ConfigKeys.fontFamily, to: .string(family))
                    }
                })) {
                Text("System Monospaced").tag("")
                Divider()
                // A family the file names that this Mac does not have stays choosable.
                if !current.isEmpty, !Self.families.contains(current) {
                    Text("\(current) (not installed)").tag(current)
                }
                ForEach(Self.families, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}

/// A text field for a key, written when Return is pressed or the field loses focus. An empty
/// field removes the key. A value the key does not take is not written, and the field says
/// why.
struct ConfigTextField: View {
    let config: ConfigStore
    let definition: ConfigKeyDefinition
    let prompt: String
    var width: CGFloat = 220
    /// The field's text for a value.
    let text: (ConfigValue?) -> String
    /// The value for the field's text, or nil to remove the key.
    let value: (String) -> ConfigValue?

    @State private var editing = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        let saved = text(config.config.isSet(definition) ? config.config[definition] : nil)
        VStack(alignment: .trailing, spacing: 2) {
            TextField(definition.key, text: $editing, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .focused($isFocused)
                .onSubmit(commit)
                .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear { editing = saved }
        .onChange(of: saved) { _, new in if !isFocused { editing = new } }
    }

    private func commit() {
        let trimmed = editing.trimmingCharacters(in: .whitespaces)
        do {
            if let new = value(trimmed) {
                try config.set(definition, to: new)
            } else {
                try config.remove(definition)
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// The starting folder: a path to type, and a button to choose one.
struct StartingFolderField: View {
    let config: ConfigStore

    var body: some View {
        ConfigTextField(
            config: config, definition: ConfigKeys.startingFolder, prompt: "~", width: 160,
            text: { $0?.stringValue ?? "" },
            value: { $0.isEmpty ? nil : .string($0) })
        Button("Choose…", action: choose)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = ConfigFileLocation.displayPath(url.path, home: NSHomeDirectory())
        try? config.set(ConfigKeys.startingFolder, to: .string(path))
    }
}

extension TerminalColor {
    /// A SwiftUI color in sRGB, or nil when it cannot be put in sRGB.
    init?(_ color: Color) {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
        // Snap to the 256 steps the file keeps, so a color read back compares equal.
        guard let snapped = TerminalColor(hexString: hexString) else { return nil }
        self = snapped
    }
}
