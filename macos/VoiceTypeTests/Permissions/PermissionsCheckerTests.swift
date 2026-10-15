import XCTest
@testable import VoiceType

final class PermissionsCheckerTests: XCTestCase {

    final class StubMic: MicrophoneAccessProbing, @unchecked Sendable {
        var value: PermissionStatus = .undetermined
        func currentStatus() -> PermissionStatus { value }
    }

    final class StubAX: AccessibilityProbing, @unchecked Sendable {
        var value: PermissionStatus = .undetermined
        func currentStatus() -> PermissionStatus { value }
    }

    final class StubNotif: NotificationAuthProbing, @unchecked Sendable {
        var value: PermissionStatus = .undetermined
        func currentStatus() async -> PermissionStatus { value }
    }

    @MainActor
    func testInitialStatesAreUndetermined() {
        let checker = PermissionsChecker(
            mic: StubMic(),
            accessibility: StubAX(),
            notifications: StubNotif()
        )
        XCTAssertEqual(checker.microphone, .undetermined)
        XCTAssertEqual(checker.accessibility, .undetermined)
        XCTAssertEqual(checker.notifications, .undetermined)
    }

    @MainActor
    func testRefreshUpdatesObservableState() async {
        let mic = StubMic(); let ax = StubAX(); let notif = StubNotif()
        let checker = PermissionsChecker(mic: mic, accessibility: ax, notifications: notif)
        mic.value = .granted
        ax.value = .denied
        notif.value = .granted
        await checker.refresh()
        XCTAssertEqual(checker.microphone, .granted)
        XCTAssertEqual(checker.accessibility, .denied)
        XCTAssertEqual(checker.notifications, .granted)
    }

    @MainActor
    func testSetNotificationsAuthorizedFlipsState() {
        let checker = PermissionsChecker(
            mic: StubMic(),
            accessibility: StubAX(),
            notifications: StubNotif()
        )
        checker.setNotificationsAuthorized(true)
        XCTAssertEqual(checker.notifications, .granted)
        checker.setNotificationsAuthorized(false)
        XCTAssertEqual(checker.notifications, .denied)
    }
}
