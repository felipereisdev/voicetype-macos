import SwiftUI
import Core

struct AppearanceSection: View {
    let snapshot: ConfigStoreSnapshot

    var body: some View {
        Form {
            Section(SettingsStrings.appearanceWaveformSectionLabel) {
                Picker(SettingsStrings.appearanceWaveformPresetLabel, selection: Binding(
                    get: {
                        WaveformColorPreset(rawValue: snapshot.config.waveformPreset) ?? .aurora
                    },
                    set: { newValue in
                        Task {
                            await snapshot.update { $0.waveformPreset = newValue.rawValue }
                        }
                    }
                )) {
                    ForEach(WaveformColorPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .accessibilityIdentifier("settings.appearance.waveformPresetPicker")

                Text(SettingsStrings.appearanceWaveformPresetHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(SettingsStrings.appearanceIndicatorStyleSectionLabel) {
                Picker(SettingsStrings.appearanceIndicatorStyleLabel, selection: Binding(
                    get: {
                        HUDIndicatorStyle(rawValue: snapshot.config.indicatorStyle) ?? .auto
                    },
                    set: { newValue in
                        Task {
                            await snapshot.update { $0.indicatorStyle = newValue.rawValue }
                        }
                    }
                )) {
                    ForEach(HUDIndicatorStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .accessibilityIdentifier("settings.appearance.indicatorStylePicker")

                Text(SettingsStrings.appearanceIndicatorStyleHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarAppearance)
    }
}
