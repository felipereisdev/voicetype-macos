import SwiftUI
import Core
import Observation

enum TestState: Equatable, Sendable {
    case idle
    case testing
    case ok
    case invalid(Int)
    case noResponse
}

@MainActor
@Observable
final class GeneralSectionViewModel {
    var testState: TestState = .idle

    private let groq: GroqKeyTesting

    init(groq: GroqKeyTesting) {
        self.groq = groq
    }

    func testKey(_ apiKey: String) async {
        testState = .testing
        let result = await groq.testKey(apiKey)
        if result.ok {
            testState = .ok
        } else if let status = result.status {
            testState = .invalid(status)
        } else {
            testState = .noResponse
        }
    }
}

struct GeneralSection: View {
    let snapshot: ConfigStoreSnapshot
    @State private var vm: GeneralSectionViewModel

    init(snapshot: ConfigStoreSnapshot, groq: GroqKeyTesting? = nil) {
        self.snapshot = snapshot
        let tester = groq ?? GeneralSection.defaultTester()
        _vm = State(initialValue: GeneralSectionViewModel(groq: tester))
    }

    static func defaultTester() -> GroqKeyTesting {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-test-stub-groq-ok") {
            return StubKeyTester(result: TestKeyResult(ok: true, status: nil))
        }
        if args.contains("--ui-test-stub-groq-401") {
            return StubKeyTester(result: TestKeyResult(ok: false, status: 401))
        }
        #endif
        return LiveGroqKeyTester()
    }

    var body: some View {
        Form {
            Section(SettingsStrings.apiKeyLabel) {
                SecureField(SettingsStrings.apiKeyPlaceholder, text: Binding(
                    get: { snapshot.config.groq.apiKey },
                    set: { newValue in
                        if vm.testState != .idle { vm.testState = .idle }
                        Task { await snapshot.update { $0.groq.apiKey = newValue } }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("settings.general.apiKeyField")

                HStack(spacing: 12) {
                    Button(testButtonLabel) {
                        Task { await vm.testKey(snapshot.config.groq.apiKey) }
                    }
                    .disabled(vm.testState == .testing || snapshot.config.groq.apiKey.isEmpty)
                    .accessibilityIdentifier("settings.general.testButton")

                    statusRow
                        .accessibilityIdentifier("settings.general.testStatus")
                }

                Text(SettingsStrings.apiKeyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(SettingsStrings.languageLabel, selection: Binding(
                    get: { snapshot.config.recording.language },
                    set: { newValue in
                        Task { await snapshot.update { $0.recording.language = newValue } }
                    }
                )) {
                    ForEach(SettingsStrings.languageOptions, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }

                Picker(SettingsStrings.refineStyleLabel, selection: Binding(
                    get: { snapshot.config.recording.refineStyle },
                    set: { newValue in
                        Task { await snapshot.update { $0.recording.refineStyle = newValue } }
                    }
                )) {
                    ForEach(SettingsStrings.refineStyleOptions, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
            }

            Section(SettingsStrings.terminalBypassSectionLabel) {
                ForEach(RefineBypass.terminalApps, id: \.bundleID) { app in
                    Toggle(app.name, isOn: Binding(
                        get: { !snapshot.config.refineBypassDisabledApps.contains(app.bundleID) },
                        set: { bypass in
                            Task {
                                await snapshot.update { cfg in
                                    cfg.refineBypassDisabledApps.removeAll { $0 == app.bundleID }
                                    if !bypass { cfg.refineBypassDisabledApps.append(app.bundleID) }
                                }
                            }
                        }
                    ))
                }

                Text(SettingsStrings.terminalBypassHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(SettingsStrings.feedbackSectionLabel) {
                Toggle(SettingsStrings.soundFeedbackLabel, isOn: Binding(
                    get: { snapshot.config.soundFeedbackEnabled },
                    set: { newValue in
                        Task { await snapshot.update { $0.soundFeedbackEnabled = newValue } }
                    }
                ))
                .accessibilityIdentifier("settings.general.soundFeedbackToggle")

                Text(SettingsStrings.soundFeedbackHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(SettingsStrings.autoEnterLabel, isOn: Binding(
                    get: { snapshot.config.autoEnterEnabled },
                    set: { newValue in
                        Task { await snapshot.update { $0.autoEnterEnabled = newValue } }
                    }
                ))
                .accessibilityIdentifier("settings.general.autoEnterToggle")

                Text(SettingsStrings.autoEnterHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarGeneral)
    }

    private var testButtonLabel: String {
        vm.testState == .testing ? SettingsStrings.testButtonLoading : SettingsStrings.testButton
    }

    @ViewBuilder
    private var statusRow: some View {
        switch vm.testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .ok:
            Label(SettingsStrings.testOk, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .invalid(let status):
            Label(SettingsStrings.testInvalid(status), systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .noResponse:
            Label(SettingsStrings.testNoResponse, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

#if DEBUG
struct StubKeyTester: GroqKeyTesting {
    let result: TestKeyResult
    func testKey(_ apiKey: String) async -> TestKeyResult { result }
}
#endif
