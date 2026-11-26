import Foundation

/// The sections of Settings, in the order its sheet lists them.
///
/// Settings is not a window of its own. It is a pane in the tree, pinned at the bottom of the
/// sidebar, and it opens as a sheet over the sidebar like any other pane. Its sheet lists these
/// sections, and each one opens as a child sheet over it.
///
/// A new section goes above Experiments. Experiments is second to last, and Debugging is
/// always last.
public enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    case general
    case experiments
    case debugging

    public var id: String { rawValue }

    /// The id of the Settings pane itself.
    public static let settingsID: PaneID = "settings"

    /// The id of this section's pane, a child of Settings.
    public var paneID: PaneID { PaneID("\(Self.settingsID.rawValue)/\(rawValue)") }

    /// The section a pane shows, or nil when the pane is not a section of Settings.
    public init?(paneID: PaneID) {
        guard let section = Self.allCases.first(where: { $0.paneID == paneID }) else { return nil }
        self = section
    }

    public var title: String {
        switch self {
        case .general: "General"
        case .experiments: "Experiments"
        case .debugging: "Debugging"
        }
    }

    /// The line under the title in the Settings sheet.
    public var summary: String {
        switch self {
        case .general: "Updates and version"
        case .experiments: "Features being tried"
        case .debugging: "Build, commit, and signing"
        }
    }

    /// The Settings pane, with a child pane for each section.
    public static var pane: Pane {
        Pane(
            id: settingsID, kind: .settings, title: "Settings",
            children: allCases.map { Pane(id: $0.paneID, kind: .settings, title: $0.title) })
    }
}

extension PaneTree {
    /// The tree with Settings at the end of the top level, if it is not there already. The
    /// sidebar pins it at the bottom, apart from the other panes.
    public func addingSettings() -> PaneTree {
        guard !contains(SettingsSection.settingsID) else { return self }
        var tree = self
        tree.add(SettingsSection.pane, under: nil)
        return tree
    }
}

/// Remembers which section of Settings was open, so Settings opens to it next time.
///
/// It notes every change to the stack. While Settings is the bottom open sheet, the section
/// over it is remembered, or no section when only the Settings sheet is open. A stack that does
/// not start at Settings changes nothing, so leaving Settings keeps the last section.
public struct SettingsSectionMemory {
    /// The `UserDefaults` key that holds the open section's raw value.
    public static let key = "SettingsOpenSection"

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The section that was open last, or nil when none was.
    public var section: SettingsSection? {
        defaults.string(forKey: Self.key).flatMap(SettingsSection.init(rawValue:))
    }

    /// Notes what the stack shows. Call it after every change.
    public func note(_ stack: SheetStack) {
        guard stack.entry(at: 1) == SettingsSection.settingsID else { return }
        if let id = stack.entry(at: 2), let section = SettingsSection(paneID: id) {
            defaults.set(section.rawValue, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    /// The stack that opening Settings leads to from the current one. When Settings is already
    /// open, nothing changes. Otherwise Settings opens over the sidebar, with the remembered
    /// section over it.
    public func stack(openingSettingsFrom current: SheetStack) -> SheetStack {
        if current.entry(at: 1) == SettingsSection.settingsID { return current }
        return SheetStack([SettingsSection.settingsID] + (section.map { [$0.paneID] } ?? []))
    }
}

/// Features being tried. Each is a switch in Settings, off by default, and with the switch
/// off the app is as it was. There are none yet.
public enum Experiment: CaseIterable, Sendable, Identifiable {
    public var id: String { key }

    /// The `UserDefaults` key for the switch.
    public var key: String {
        switch self {}
    }

    /// The switch's label in Settings.
    public var title: String {
        switch self {}
    }

    /// Whether the switch is on. Every experiment is off until it is turned on.
    public func isOn(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: key)
    }
}
