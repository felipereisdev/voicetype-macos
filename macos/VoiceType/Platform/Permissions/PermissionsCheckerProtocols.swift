import AVFoundation
import ApplicationServices
import UserNotifications

public protocol MicrophoneAccessProbing: Sendable {
    func currentStatus() -> PermissionStatus
}

public protocol AccessibilityProbing: Sendable {
    func currentStatus() -> PermissionStatus
}

public protocol NotificationAuthProbing: Sendable {
    func currentStatus() async -> PermissionStatus
}

public struct LiveMicrophoneAccessProbe: MicrophoneAccessProbing {
    public init() {}
    public func currentStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
}

public struct LiveAccessibilityProbe: AccessibilityProbing {
    public init() {}
    public func currentStatus() -> PermissionStatus {
        // Non-prompting query — passing no options dictionary.
        AXIsProcessTrusted() ? .granted : .denied
    }
}

public struct LiveNotificationAuthProbe: NotificationAuthProbing {
    public init() {}
    public func currentStatus() async -> PermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .undetermined
        @unknown default: return .undetermined
        }
    }
}
