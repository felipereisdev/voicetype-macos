import SwiftUI
import Core

struct VocabularySection: View {
    let snapshot: ConfigStoreSnapshot
    let suggestions: SuggestionStore
    @State private var pending: [LearnedSuggestion] = []

    init(snapshot: ConfigStoreSnapshot, suggestions: SuggestionStore) {
        self.snapshot = snapshot
        self.suggestions = suggestions
    }

    var body: some View {
        Form {
            Section(SettingsStrings.vocabularyHeader) {
                TextEditor(text: Binding(
                    get: { snapshot.config.vocabularyKeywords },
                    set: { newValue in
                        Task { await snapshot.update { $0.vocabularyKeywords = newValue } }
                    }
                ))
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(alignment: .topLeading) {
                    if snapshot.config.vocabularyKeywords.isEmpty {
                        Text(SettingsStrings.vocabularyPlaceholder)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityIdentifier("settings.vocabulary.editor")

                Text(SettingsStrings.vocabularyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(SettingsStrings.vocabularyCount(
                    used: snapshot.config.vocabularyKeywords.count,
                    max: SettingsStrings.vocabularyMaxChars
                ))
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    snapshot.config.vocabularyKeywords.count > SettingsStrings.vocabularyMaxChars
                        ? Color.red
                        : Color.secondary
                )
                .accessibilityIdentifier("settings.vocabulary.count")
            }

            Section(SettingsStrings.learnHeader) {
                Toggle(SettingsStrings.learnLabel, isOn: Binding(
                    get: { snapshot.config.learnFromEditsEnabled },
                    set: { v in Task { await snapshot.update { $0.learnFromEditsEnabled = v } } }
                ))
                .accessibilityIdentifier("settings.vocabulary.learnToggle")

                Text(SettingsStrings.learnHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if pending.isEmpty {
                    Text(SettingsStrings.learnEmpty)
                        .foregroundStyle(.secondary)
                }
                ForEach(pending) { s in
                    HStack {
                        Text("\(s.original) → \(s.corrected)")
                            .font(.body.monospaced())
                        Spacer()
                        Button(SettingsStrings.learnApprove) { act { await approve(s) } }
                        Button(SettingsStrings.learnReject) { act { await suggestions.reject(id: s.id) } }
                        Button(SettingsStrings.learnDelete, role: .destructive) { act { await suggestions.remove(id: s.id) } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { pending = await suggestions.pending() }
        .navigationTitle(SettingsStrings.sidebarVocabulary)
    }

    private func act(_ op: @escaping () async -> Void) {
        Task {
            await op()
            pending = await suggestions.pending()
        }
    }

    private func approve(_ s: LearnedSuggestion) async {
        await snapshot.update { $0.vocabularyKeywords = LearnedSuggestion.vocabulary($0.vocabularyKeywords, adding: s.corrected) }
        await suggestions.remove(id: s.id)
    }
}
