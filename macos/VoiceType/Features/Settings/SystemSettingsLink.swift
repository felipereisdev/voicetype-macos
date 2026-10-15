import AppKit

enum SystemSettingsLink {
    case microphone
    case accessibility
    case notifications
    case loginItems

    var url: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .notifications:
            return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        case .loginItems:
            return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        }
    }

    func open() {
        NSWorkspace.shared.open(url)
    }
}
