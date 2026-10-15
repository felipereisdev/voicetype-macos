import SwiftUI

struct PermissionRow: View {
    let title: String
    let status: PermissionStatus
    let onOpenSettings: () -> Void

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            badge
            Button(SettingsStrings.openSystemSettings, action: onOpenSettings)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var icon: String {
        switch status {
        case .granted:      return "checkmark.circle.fill"
        case .denied:       return "xmark.octagon.fill"
        case .undetermined: return "questionmark.circle"
        }
    }

    @ViewBuilder
    private var badge: some View {
        switch status {
        case .granted:
            Text(SettingsStrings.permissionGranted)
                .foregroundStyle(.green)
                .font(.caption)
        case .denied:
            Text(SettingsStrings.permissionDenied)
                .foregroundStyle(.red)
                .font(.caption)
        case .undetermined:
            Text(SettingsStrings.permissionUndetermined)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
