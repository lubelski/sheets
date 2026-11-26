import SheetsCore
import SwiftUI

// Settings is a pane, not a window. Its sheet opens over the sidebar and lists the sections,
// and each section opens as a sheet over it.

/// The Settings sheet: a row per section.
struct SettingsSheet: View {
    let openedID: PaneID?
    let open: (PaneID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: SettingsSection.pane.title)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(SettingsSection.allCases) { section in
                        SheetRow(
                            id: section.paneID, title: section.title, summary: section.summary,
                            isOpen: section.paneID == openedID, open: { open(section.paneID) })
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

/// One section's sheet, under a title bar with its name.
struct SettingsSectionSheet: View {
    let section: SettingsSection
    let updater: AppUpdater
    let buildInfo: BuildInfo
    let config: ConfigStore

    var body: some View {
        VStack(spacing: 0) {
            SheetTitleBar(title: section.title)
            switch section {
            case .general: GeneralSettings(updater: updater, buildInfo: buildInfo)
            case .terminal: TerminalSettings(config: config)
            case .experiments: ExperimentsSettings(config: config)
            case .debugging: DebuggingSettings(buildInfo: buildInfo)
            }
        }
    }
}

/// Updates, when this build has an updater, and the version.
struct GeneralSettings: View {
    let updater: AppUpdater
    let buildInfo: BuildInfo
    /// A copy of the updater's setting, which is not observable, so the switch redraws.
    @State private var updatesAutomatically = false

    var body: some View {
        Form {
            Section {
                if updater.isAvailable {
                    Toggle("Update automatically", isOn: Binding(
                        get: { updatesAutomatically },
                        set: {
                            updater.updatesAutomatically = $0
                            updatesAutomatically = $0
                        }))
                    LabeledContent("Check for updates now") {
                        Button("Check for Updates") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
                LabeledContent("Version") {
                    Text("\(buildInfo.version) (\(buildInfo.build))").textSelection(.enabled)
                }
            } header: {
                Text("Updates")
            } footer: {
                Text(updater.isAvailable
                     ? "Checks about once a day, downloads a newer release, and installs it when the app quits."
                     : "This build does not update itself. Only a release build does.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onAppear { updatesAutomatically = updater.updatesAutomatically }
    }
}

/// Features being tried: a switch for each, off until turned on, or a note that there are none.
struct ExperimentsSettings: View {
    let config: ConfigStore

    var body: some View {
        if Experiment.allCases.isEmpty {
            VStack(spacing: 6) {
                Text("No experiments right now")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Features being tried show up here as switches, off until turned on.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Form {
                Section {
                    ForEach(Experiment.allCases) { ExperimentToggle(experiment: $0, config: config) }
                } footer: {
                    Text("Features being tried. Each is off until turned on, and is an experiments key in the config file.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One experiment's switch, kept in the config file under the experiment's key.
struct ExperimentToggle: View {
    let experiment: Experiment
    let config: ConfigStore

    var body: some View {
        Toggle(isOn: Binding(
            get: { experiment.isOn(in: config.config) },
            // Off is the default, so turning a switch off removes its line.
            set: { on in
                if on {
                    try? config.set(experiment.definition, to: .bool(true))
                } else {
                    try? config.remove(experiment.definition)
                }
            })) {
            Text(experiment.title)
            Text(experiment.summary)
        }
        .help(experiment.key)
    }
}

/// What this copy of the app is: version, build, commit, and signing.
struct DebuggingSettings: View {
    let buildInfo: BuildInfo

    var body: some View {
        Form {
            Section("Build") {
                LabeledContent("Version") { Text(buildInfo.version).textSelection(.enabled) }
                LabeledContent("Build") { Text(buildInfo.build).textSelection(.enabled) }
                LabeledContent("Commit") {
                    Text(buildInfo.commit).font(.body.monospaced()).textSelection(.enabled)
                }
                LabeledContent("Signing") { Text(buildInfo.signing).textSelection(.enabled) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
