import XCTest
import AVFoundation
@testable import VoiceType
import Core

final class AudioSectionViewModelTests: XCTestCase {

    final class StubDeviceProbe: AudioDeviceProbing, @unchecked Sendable {
        var devices: [AudioInputDevice]
        init(devices: [AudioInputDevice]) { self.devices = devices }
        func discover() -> [AudioInputDevice] { devices }
    }

    @MainActor
    func testEnumeratesAudioInputDevices() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot()
        let probe = StubDeviceProbe(devices: [
            AudioInputDevice(uniqueID: "builtin", localizedName: "MacBook Pro Microphone", isContinuity: false),
            AudioInputDevice(uniqueID: "airpods", localizedName: "AirPods Pro", isContinuity: false),
        ])
        let vm = AudioSectionViewModel(snapshot: snapshot, probe: probe)
        XCTAssertEqual(vm.devices.map(\.uniqueID), ["builtin", "airpods"])
    }

    @MainActor
    func testSelectDevicePersistsIDAndLabel() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot()
        let probe = StubDeviceProbe(devices: [
            AudioInputDevice(uniqueID: "airpods", localizedName: "AirPods Pro", isContinuity: false),
        ])
        let vm = AudioSectionViewModel(snapshot: snapshot, probe: probe)
        await vm.commitSelection(id: "airpods")
        XCTAssertEqual(snapshot.config.recording.inputDeviceID, "airpods")
        XCTAssertEqual(snapshot.config.recording.inputDeviceLabel, "AirPods Pro")
    }

    @MainActor
    func testDeviceConnectNotificationRefreshes() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot()
        let probe = StubDeviceProbe(devices: [])
        let vm = AudioSectionViewModel(snapshot: snapshot, probe: probe)
        XCTAssertEqual(vm.devices.count, 0)
        probe.devices = [AudioInputDevice(uniqueID: "usb", localizedName: "USB Mic", isContinuity: false)]
        NotificationCenter.default.post(name: AVCaptureDevice.wasConnectedNotification, object: nil)
        // Let the .main queue + MainActor task settle.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(vm.devices.count, 1)
    }

    @MainActor
    func testProbeMarksContinuityDevices() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot()
        let probe = StubDeviceProbe(devices: [
            AudioInputDevice(uniqueID: "builtin", localizedName: "MacBook Pro Microphone", isContinuity: false),
            AudioInputDevice(uniqueID: "iphone", localizedName: "Mac's iPhone", isContinuity: true),
        ])
        let vm = AudioSectionViewModel(snapshot: snapshot, probe: probe)
        XCTAssertEqual(vm.devices.first(where: { $0.uniqueID == "iphone" })?.isContinuity, true)
        XCTAssertEqual(vm.devices.first(where: { $0.uniqueID == "builtin" })?.isContinuity, false)
    }

    @MainActor
    func testPreviewStopIsIdempotent() async {
        let preview = AudioDevicePreview()
        preview.stop()
        preview.stop()
        XCTAssertEqual(preview.level, 0)
        XCTAssertFalse(preview.isActive)
    }
}
