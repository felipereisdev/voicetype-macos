import Foundation
import Observation

/// Live snapshot of OS-level permissions VoiceType cares about.
///
/// `refresh()` is non-prompting — it only queries cached status. The actual
/// prompts surface either via the AccessibilityChecker bootstrap call or via
/// `AVCaptureDevice.requestAccess(for: .audio)` triggered from the Audio
/// Settings section.
@MainActor
@Observable
public final class PermissionsChecker {
    public private(set) var microphone: PermissionStatus = .undetermined
    public private(set) var accessibility: PermissionStatus = .undetermined
    public private(set) var notifications: PermissionStatus = .undetermined

    private let micProbe: MicrophoneAccessProbing
    private let axProbe: AccessibilityProbing
    private let notifProbe: NotificationAuthProbing

    public init(
        mic: MicrophoneAccessProbing = LiveMicrophoneAccessProbe(),
        accessibility: AccessibilityProbing = LiveAccessibilityProbe(),
        notifications: NotificationAuthProbing = LiveNotificationAuthProbe()
    ) {
        self.micProbe = mic
        self.axProbe = accessibility
        self.notifProbe = notifications
    }

    public func refresh() async {
        microphone = micProbe.currentStatus()
        accessibility = axProbe.currentStatus()
        notifications = await notifProbe.currentStatus()
    }

    /// Fast-path setter used by `Notifier.bootstrap()` to push the freshly
    /// observed notification auth result without re-querying
    /// `UNUserNotificationCenter.notificationSettings()`. Triggers a SwiftUI
    /// re-render through `@Observable` mutation tracking.
    public func setNotificationsAuthorized(_ authorized: Bool) {
        notifications = authorized ? .granted : .denied
    }
}
