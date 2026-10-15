import SwiftUI
import Core

struct ShortcutsSection: View {
    let snapshot: ConfigStoreSnapshot

    init(snapshot: ConfigStoreSnapshot) {
        self.snapshot = snapshot
    }

    private var translateConflict: Bool {
        snapshot.config.translate.enabled
            && !snapshot.config.shortcuts.refine.isEmpty
            && snapshot.config.shortcuts.refine == snapshot.config.shortcuts.translate
    }

    var body: some View {
        Form {
            Section(SettingsStrings.shortcutLabel) {
                ShortcutRecorderField(accelerator: Binding(
                    get: { snapshot.config.shortcuts.refine },
                    set: { newValue in
                        Task { await snapshot.update { $0.shortcuts.refine = newValue } }
                    }
                ))
                Text(SettingsStrings.shortcutHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(SettingsStrings.handsFreeLabel, isOn: Binding(
                    get: { snapshot.config.handsFreeEnabled },
                    set: { newValue in
                        Task { await snapshot.update { $0.handsFreeEnabled = newValue } }
                    }
                ))
                Text(SettingsStrings.handsFreeHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(SettingsStrings.translateEnabledLabel, isOn: Binding(
                    get: { snapshot.config.translate.enabled },
                    set: { newValue in
                        Task { await snapshot.update { $0.translate.enabled = newValue } }
                    }
                ))

                if snapshot.config.translate.enabled {
                    LabeledContent(SettingsStrings.translateShortcutLabel) {
                        ShortcutRecorderField(accelerator: Binding(
                            get: { snapshot.config.shortcuts.translate },
                            set: { newValue in
                                Task { await snapshot.update { $0.shortcuts.translate = newValue } }
                            }
                        ))
                    }

                    Picker(SettingsStrings.translateTargetLabel, selection: Binding(
                        get: { snapshot.config.translate.target },
                        set: { newValue in
                            Task { await snapshot.update { $0.translate.target = newValue } }
                        }
                    )) {
                        ForEach(SettingsStrings.translateTargetOptions, id: \.id) { opt in
                            Text(opt.label).tag(opt.id)
                        }
                    }

                    if translateConflict {
                        Label(SettingsStrings.translateShortcutConflict, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    Text(SettingsStrings.translateHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarShortcuts)
    }
}
