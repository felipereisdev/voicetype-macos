import SwiftUI
import Core
import Observation
import ServiceManagement

@MainActor
@Observable
final class StartupSectionViewModel {
    /// Latest known SMAppService raw status, exposed for the View to react to
    /// `.requiresApproval` (offer to open Login Items system pane).
    var loginStatus: SMAppService.Status?

    @ObservationIgnored private let snapshot: ConfigStoreSnapshot
    @ObservationIgnored private let loginItem: LoginItemControlling
    @ObservationIgnored private let notifier: NotifierEmitting

    init(
        snapshot: ConfigStoreSnapshot,
        loginItem: LoginItemControlling = LiveLoginItem(),
        notifier: NotifierEmitting
    ) {
        self.snapshot = snapshot
        self.loginItem = loginItem
        self.notifier = notifier
        self.loginStatus = (loginItem as? LoginItemStatusReporting)?.statusRaw
    }

    func commitStartAtLogin(desired: Bool) async {
        do {
            if desired {
                try loginItem.register()
            } else {
                try loginItem.unregister()
            }
            loginStatus = (loginItem as? LoginItemStatusReporting)?.statusRaw
            await snapshot.update { $0.startAtLogin = desired }
            if loginStatus == .requiresApproval {
                await notifier.info(
                    title: NotificationCopy.autoStartRequiresApprovalTitle,
                    body: NotificationCopy.autoStartRequiresApprovalBody
                )
            }
        } catch {
            loginStatus = (loginItem as? LoginItemStatusReporting)?.statusRaw
            await notifier.error(
                title: NotificationCopy.autoStartFailedTitle,
                body: NotificationCopy.autoStartFailedBody(error.localizedDescription)
            )
            // Rollback: snapshot was never updated, so UI naturally reflects snapshot.config.startAtLogin.
        }
    }
}

/// Test seam over `Notifier` so VM tests don't touch the real
/// `UNUserNotificationCenter`.
protocol NotifierEmitting: Sendable {
    func error(title: String, body: String) async
    func info(title: String, body: String) async
}

/// Forwards `NotifierEmitting` calls to a concrete `Notifier` supplied by
/// `AppDependencies`. The Notifier is `@MainActor` (and therefore Sendable
/// by isolation), so we can store it directly in a Sendable struct and hop
/// when invoking its `@MainActor` methods.
struct LiveNotifier: NotifierEmitting {
    private let notifier: Notifier

    init(_ notifier: Notifier) {
        self.notifier = notifier
    }

    func error(title: String, body: String) async {
        await notifier.error(title: title, body: body)
    }

    func info(title: String, body: String) async {
        await notifier.info(title: title, body: body)
    }
}

struct StartupSection: View {
    let snapshot: ConfigStoreSnapshot
    @State private var vm: StartupSectionViewModel
    @Bindable private var permissions: PermissionsChecker

    init(snapshot: ConfigStoreSnapshot, permissions: PermissionsChecker, notifier: Notifier) {
        self.snapshot = snapshot
        _vm = State(initialValue: StartupSectionViewModel(
            snapshot: snapshot,
            notifier: LiveNotifier(notifier)
        ))
        _permissions = Bindable(wrappedValue: permissions)
    }

    var body: some View {
        Form {
            Section {
                Toggle(SettingsStrings.startAtLoginLabel, isOn: Binding(
                    get: { snapshot.config.startAtLogin },
                    set: { newValue in
                        Task { await vm.commitStartAtLogin(desired: newValue) }
                    }
                ))
                if vm.loginStatus == .requiresApproval {
                    HStack(spacing: 8) {
                        Text(SettingsStrings.loginItemRequiresApproval)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Spacer()
                        Button(SettingsStrings.openSystemSettings) {
                            SystemSettingsLink.loginItems.open()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section(SettingsStrings.permissionsHeader) {
                PermissionRow(
                    title: SettingsStrings.permissionMic,
                    status: permissions.microphone,
                    onOpenSettings: { SystemSettingsLink.microphone.open() }
                )
                PermissionRow(
                    title: SettingsStrings.permissionAccessibility,
                    status: permissions.accessibility,
                    onOpenSettings: { SystemSettingsLink.accessibility.open() }
                )
                PermissionRow(
                    title: SettingsStrings.permissionNotifications,
                    status: permissions.notifications,
                    onOpenSettings: { SystemSettingsLink.notifications.open() }
                )
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SettingsStrings.sidebarStartup)
        .task { await permissions.refresh() }
    }
}
