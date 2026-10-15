import SwiftUI
import AVFoundation
import Core
import Observation

@MainActor
@Observable
final class AudioSectionViewModel {
    var devices: [AudioInputDevice] = []
    var isTesting: Bool = false

    let preview: AudioDevicePreview

    @ObservationIgnored private let snapshot: ConfigStoreSnapshot
    @ObservationIgnored private let probe: AudioDeviceProbing
    // Observer tokens are plain objects with no MainActor invariants; mark them
    // `nonisolated(unsafe)` so `deinit` (which runs without MainActor isolation)
    // can call `removeObserver` on them.
    @ObservationIgnored private nonisolated(unsafe) var connectObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var disconnectObserver: NSObjectProtocol?
    @ObservationIgnored private var testTask: Task<Void, Never>?

    init(
        snapshot: ConfigStoreSnapshot,
        probe: AudioDeviceProbing = LiveAudioDeviceProbe(),
        preview: AudioDevicePreview? = nil
    ) {
        self.snapshot = snapshot
        self.probe = probe
        self.preview = preview ?? AudioDevicePreview()
        self.devices = probe.discover()
        installObservers()
        healSavedDevice()
    }

    deinit {
        if let o = connectObserver { NotificationCenter.default.removeObserver(o) }
        if let o = disconnectObserver { NotificationCenter.default.removeObserver(o) }
    }

    func refresh() {
        devices = probe.discover()
        healSavedDevice()
    }

    // Saved USB UID went stale (mic moved to another port) → re-point the
    // config at the same-named device so the list shows it selected (G-031).
    private func healSavedDevice() {
        let rec = snapshot.config.recording
        guard !rec.inputDeviceID.isEmpty,
              let healed = AudioInputResolver.healedUID(
                  saved: rec.inputDeviceID, label: rec.inputDeviceLabel, devices: devices
              ) else { return }
        Task { await commitSelection(id: healed) }
    }

    func commitSelection(id: String) async {
        let label = devices.first(where: { $0.uniqueID == id })?.localizedName ?? ""
        await snapshot.update {
            $0.recording.inputDeviceID = id
            $0.recording.inputDeviceLabel = label
        }
        // Restart preview so it follows the new selection without forcing the
        // user to re-toggle the test button.
        if preview.isActive {
            preview.start(deviceUID: id)
        }
    }

    func startPreview() {
        preview.start(deviceUID: snapshot.config.recording.inputDeviceID)
    }

    func stopPreview() {
        testTask?.cancel()
        testTask = nil
        isTesting = false
        preview.stop()
    }

    func startTimedTest() {
        testTask?.cancel()
        isTesting = true
        preview.start(deviceUID: snapshot.config.recording.inputDeviceID)
        testTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.isTesting = false
            self.preview.stop()
            self.testTask = nil
        }
    }

    private func installObservers() {
        connectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        disconnectObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
}

struct AudioSection: View {
    let snapshot: ConfigStoreSnapshot
    @State private var vm: AudioSectionViewModel
    @Bindable private var permissions: PermissionsChecker

    init(snapshot: ConfigStoreSnapshot, permissions: PermissionsChecker) {
        self.snapshot = snapshot
        _vm = State(initialValue: AudioSectionViewModel(snapshot: snapshot))
        _permissions = Bindable(wrappedValue: permissions)
    }

    var body: some View {
        Form {
            Section(SettingsStrings.micDeviceLabel) {
                if permissions.microphone != .granted && vm.devices.allSatisfy({ $0.localizedName.isEmpty }) {
                    Text(SettingsStrings.micDevicePermissionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(SettingsStrings.micDevicePermissionButton) {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .audio)
                            await permissions.refresh()
                            vm.refresh()
                        }
                    }
                } else {
                    deviceList
                }
            }

            if permissions.microphone == .granted {
                Section(SettingsStrings.micDevicePreviewSectionLabel) {
                    HStack(spacing: 12) {
                        Text(SettingsStrings.micDevicePreviewLevelLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 60, alignment: .leading)
                        LevelBar(level: vm.preview.level)
                            .frame(height: 8)
                    }
                    HStack {
                        Button(SettingsStrings.micDeviceTestButton) {
                            vm.startTimedTest()
                        }
                        .disabled(vm.isTesting)
                        if vm.isTesting {
                            Text(SettingsStrings.micDeviceTestingHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(SettingsStrings.continuitySectionLabel) {
                Toggle(
                    SettingsStrings.continuityToggleLabel,
                    isOn: Binding(
                        get: { snapshot.config.continuityFallbackEnabled },
                        set: { newValue in
                            Task { await snapshot.update { $0.continuityFallbackEnabled = newValue } }
                        }
                    )
                )
                .accessibilityIdentifier("settings.audio.continuityToggle")
                Text(SettingsStrings.continuityToggleHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarAudio)
        .task { await permissions.refresh() }
        .onAppear {
            if permissions.microphone == .granted {
                vm.startPreview()
            }
        }
        .onDisappear {
            vm.stopPreview()
        }
    }

    @ViewBuilder
    private var deviceList: some View {
        DeviceRow(
            label: SettingsStrings.micDeviceDefault,
            secondary: nil,
            icon: nil,
            isSelected: snapshot.config.recording.inputDeviceID.isEmpty
        ) {
            Task { await vm.commitSelection(id: "") }
        }
        ForEach(vm.devices) { device in
            DeviceRow(
                label: device.localizedName.isEmpty ? device.uniqueID : device.localizedName,
                secondary: device.isContinuity ? SettingsStrings.micDeviceContinuityTag : nil,
                icon: device.isContinuity ? "iphone" : nil,
                isSelected: snapshot.config.recording.inputDeviceID == device.uniqueID
            ) {
                Task { await vm.commitSelection(id: device.uniqueID) }
            }
        }
    }
}

private struct DeviceRow: View {
    let label: String
    let secondary: String?
    let icon: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let icon {
                            Image(systemName: icon)
                                .foregroundStyle(.secondary)
                        }
                        Text(label)
                            .foregroundStyle(.primary)
                    }
                    if let secondary {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, level))))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
    }
}
