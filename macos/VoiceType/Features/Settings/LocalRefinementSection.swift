import SwiftUI
import Core

struct LocalRefinementSection: View {
    let snapshot: ConfigStoreSnapshot

    var body: some View {
        Form {
            Section(SettingsStrings.localRefinementHeader) {
                Picker(SettingsStrings.localRefinementEngineLabel, selection: Binding(
                    get: { snapshot.config.refineEngine },
                    set: { v in Task { await snapshot.update { $0.refineEngine = v } } }
                )) {
                    Text(SettingsStrings.engineAuto).tag("auto")
                    Text(SettingsStrings.engineLocal).tag("local")
                    Text(SettingsStrings.engineGroq).tag("groq")
                }
                Picker(SettingsStrings.localTranslateEngineLabel, selection: Binding(
                    get: { snapshot.config.translateEngine },
                    set: { v in Task { await snapshot.update { $0.translateEngine = v } } }
                )) {
                    Text(SettingsStrings.engineAuto).tag("auto")
                    Text(SettingsStrings.engineLocal).tag("local")
                    Text(SettingsStrings.engineGroq).tag("groq")
                }
                Text(aiStatusText).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(SettingsStrings.localRefinementIndependenceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.localRefinementHeader)
    }

    @MainActor
    private var aiStatusText: String {
        if #available(macOS 26, *) {
            return AIAvailability().unavailableReason ?? SettingsStrings.localRefinementStatusAvailable
        } else {
            return SettingsStrings.localRefinementStatusRequires26
        }
    }
}
