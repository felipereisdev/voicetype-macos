import XCTest
import AppKit
@testable import VoiceType

final class AppDelegateSmokeTests: XCTestCase {
    @MainActor
    func test_applicationDidFinishLaunching_setsAccessoryActivationPolicy() {
        let deps = AppDependencies()
        AppDelegate.injectedDeps = deps
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    func test_applicationShouldTerminateAfterLastWindowClosed_returnsFalse() {
        let delegate = AppDelegate()
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }
}
