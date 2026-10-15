import SwiftUI
import Core

struct HistorySection: View {
    let snapshot: ConfigStoreSnapshot
    @Environment(\.openWindow) private var openWindow

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
                Button(SettingsStrings.openHistoryButton) {
                    openWindow(id: HistoryWindow.identifier)
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .disabled(!snapshot.config.history.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarHistory)
    }
}
