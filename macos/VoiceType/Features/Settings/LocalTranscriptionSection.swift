import SwiftUI
import Core

struct LocalTranscriptionSection: View {
    let snapshot: ConfigStoreSnapshot
    let models: LocalModelManager

    var body: some View {
        Form {
            Section(SettingsStrings.localTranscriptionHeader) {
                Picker(SettingsStrings.localTranscriptionEngineLabel, selection: Binding(
                    get: { snapshot.config.transcriptionEngine },
                    set: { v in Task { await snapshot.update { $0.transcriptionEngine = v } } }
                )) {
                    Text(SettingsStrings.engineAuto).tag("auto")
                    Text(SettingsStrings.engineLocal).tag("local")
                    Text(SettingsStrings.engineGroq).tag("groq")
                }
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Text(SettingsStrings.localTranscriptionRefineNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.localTranscriptionHeader)
    }

    private var statusText: String {
        switch models.selection.status(of: models.selection.selected) {
        case .downloading(let p): return SettingsStrings.modelStatusDownloading(Int(p * 100))
        case .ready: return SettingsStrings.modelStatusReady
        case .failed(let m): return SettingsStrings.modelStatusFailed(m)
        case .notDownloaded, .downloaded, .preparing: return SettingsStrings.modelStatusNotReady
        }
    }
}
