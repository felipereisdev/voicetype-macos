import XCTest
@testable import VoiceType

final class SystemSettingsLinkTests: XCTestCase {
    func testMicURL() {
        XCTAssertEqual(
            SystemSettingsLink.microphone.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    func testAccessibilityURL() {
        XCTAssertEqual(
            SystemSettingsLink.accessibility.url.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testNotificationsURL() {
        XCTAssertEqual(
            SystemSettingsLink.notifications.url.absoluteString,
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
    }

    func testLoginItemsURL() {
        XCTAssertEqual(
            SystemSettingsLink.loginItems.url.absoluteString,
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
        )
    }
}
