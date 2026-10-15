import AppKit
import SwiftUI
import Core

// Tone per app: per-app override > category style > global style (General tab).
struct RefineStyleSection: View {
    let snapshot: ConfigStoreSnapshot

    var body: some View {
        Form {
            Section {
                Toggle(SettingsStrings.cursorContextLabel, isOn: Binding(
                    get: { snapshot.config.cursorContextEnabled },
                    set: { v in Task { await snapshot.update { $0.cursorContextEnabled = v } } }
                ))
                .accessibilityIdentifier("settings.refineStyle.cursorContextToggle")

                Text(SettingsStrings.cursorContextHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(SettingsStrings.categoryStylesHeader) {
                ForEach(AppCategory.allCases.filter { $0 != .other }, id: \.self) { category in
                    Picker(SettingsStrings.categoryLabel(category), selection: Binding(
                        get: { snapshot.config.categoryStyles[category.rawValue] ?? "" },
                        set: { v in
                            Task { await snapshot.update { $0.categoryStyles[category.rawValue] = v.isEmpty ? nil : v } }
                        }
                    )) {
                        Text(SettingsStrings.styleUseGlobal).tag("")
                        styleOptions
                    }
                }
                Text(SettingsStrings.categoryStylesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(SettingsStrings.appOverridesHeader) {
                ForEach(snapshot.config.appStyleOverrides.keys.sorted(), id: \.self) { bundleID in
                    HStack {
                        Picker(Self.appName(bundleID), selection: Binding(
                            get: { snapshot.config.appStyleOverrides[bundleID] ?? "" },
                            set: { v in Task { await snapshot.update { $0.appStyleOverrides[bundleID] = v } } }
                        )) {
                            styleOptions
                        }
                        Button {
                            Task { await snapshot.update { $0.appStyleOverrides[bundleID] = nil } }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(SettingsStrings.removeAppOverride)
                    }
                }

                Picker(SettingsStrings.addAppOverride, selection: Binding(
                    get: { "" },
                    set: { id in
                        guard !id.isEmpty else { return }
                        Task {
                            await snapshot.update { $0.appStyleOverrides[id] = $0.recording.refineStyle }
                        }
                    }
                )) {
                    Text(SettingsStrings.addAppOverridePlaceholder).tag("")
                    ForEach(Self.runningApps(excluding: snapshot.config.appStyleOverrides), id: \.id) { app in
                        Text(app.name).tag(app.id)
                    }
                }

                Text(SettingsStrings.appOverridesHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarRefineStyle)
    }

    @ViewBuilder private var styleOptions: some View {
        ForEach(SettingsStrings.refineStyleOptions, id: \.id) { opt in
            Text(opt.label).tag(opt.id)
        }
    }

    private static func appName(_ bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func runningApps(excluding: [String: String]) -> [(id: String, name: String)] {
        var seen = Set(excluding.keys)
        seen.insert(Bundle.main.bundleIdentifier ?? "")
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
