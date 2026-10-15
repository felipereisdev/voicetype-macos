import SwiftUI
import Core

struct ShortcutsSection: View {
    let snapshot: ConfigStoreSnapshot

    init(snapshot: ConfigStoreSnapshot) {
        self.snapshot = snapshot
    }

    private var translateConflict: Bool {
        snapshot.config.translate.enabled
            && Self.overlaps(snapshot.config.shortcuts.refine, snapshot.config.shortcuts.translate)
    }

    private var voiceNoteConflict: Bool {
        let note = snapshot.config.voiceNoteShortcut
        return Self.overlaps(note, snapshot.config.shortcuts.refine)
            || (snapshot.config.translate.enabled && Self.overlaps(note, snapshot.config.shortcuts.translate))
    }

    /// Same keys, or one shortcut's keys inside the other's (⌃⇧ in ⌃⇧N, ⌘L in
    /// ⌘⇧L): holding the bigger one also fires the smaller.
    static func overlaps(_ a: String, _ b: String) -> Bool {
        guard let ka = HoldDetectorCore.parseAccelerator(a).keycodes,
              let kb = HoldDetectorCore.parseAccelerator(b).keycodes else { return false }
        return ka.isSubset(of: kb) || kb.isSubset(of: ka)
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

            Section(SettingsStrings.voiceNoteShortcutLabel) {
                ShortcutRecorderField(accelerator: Binding(
                    get: { snapshot.config.voiceNoteShortcut },
                    set: { newValue in
                        Task { await snapshot.update { $0.voiceNoteShortcut = newValue } }
                    }
                ))
                if voiceNoteConflict {
                    Label(SettingsStrings.voiceNoteShortcutConflict, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Text(SettingsStrings.voiceNoteShortcutHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarShortcuts)
    }
}
