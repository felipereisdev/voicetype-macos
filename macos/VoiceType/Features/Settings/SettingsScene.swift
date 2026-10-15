import SwiftUI
import Core

struct SettingsScene: View {
    @Environment(AppDependencies.self) private var deps
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.label, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle(SettingsStrings.header)
            .frame(minWidth: 180)
        } detail: {
            detail
                .frame(minWidth: 460, minHeight: 360)
                .task { await deps.permissionsChecker.refresh() }
        }
        .frame(minWidth: 680, minHeight: 420)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .general:
            GeneralSection(snapshot: deps.configSnapshot)
        case .shortcuts:
            ShortcutsSection(snapshot: deps.configSnapshot)
        case .audio:
            AudioSection(snapshot: deps.configSnapshot, permissions: deps.permissionsChecker)
        case .localTranscription:
            LocalTranscriptionSection(snapshot: deps.configSnapshot, models: deps.whisperModels)
        case .localRefinement:
            LocalRefinementSection(snapshot: deps.configSnapshot)
        case .refineStyle:
            RefineStyleSection(snapshot: deps.configSnapshot)
        case .vocabulary:
            VocabularySection(snapshot: deps.configSnapshot, suggestions: deps.suggestionStore)
        case .appearance:
            AppearanceSection(snapshot: deps.configSnapshot)
        case .history:
            HistorySection(snapshot: deps.configSnapshot)
        case .meetings:
            MeetingSection(snapshot: deps.configSnapshot)
        case .startup:
            StartupSection(
                snapshot: deps.configSnapshot,
                permissions: deps.permissionsChecker,
                notifier: deps.notifier
            )
        case .about:
            AboutSection()
        }
    }
}
