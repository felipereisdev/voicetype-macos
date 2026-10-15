import SwiftUI
import Core

struct HistorySection: View {
    let snapshot: ConfigStoreSnapshot
    @Environment(MainWindowRouter.self) private var router

    init(snapshot: ConfigStoreSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsStrings.keepHistoryLabel, isOn: Binding(
                    get: { snapshot.config.history.enabled },
                    set: { newValue in
                        Task { await snapshot.update { $0.history.enabled = newValue } }
                    }
                ))

                if snapshot.config.history.enabled {
                    Stepper(value: Binding(
                        get: { snapshot.config.history.retentionCount },
                        set: { newValue in
                            let clamped = min(max(newValue, 1), 500)
                            Task { await snapshot.update { $0.history.retentionCount = clamped } }
                        }
                    ), in: 1...500, step: 10) {
                        LabeledContent(SettingsStrings.historyRetentionLabel) {
                            Text("\(snapshot.config.history.retentionCount)")
                                .monospacedDigit()
                        }
                    }
                }
            }

            Section {
                // Old entries stay viewable/deletable even with capture off.
                Button(SettingsStrings.openHistoryButton) {
                    router.selection = .history
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarHistory)
    }
}
