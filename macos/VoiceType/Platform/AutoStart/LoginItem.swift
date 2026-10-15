import Foundation
@preconcurrency import ServiceManagement
import os.log

/// Test seam: subset of `SMAppService` we depend on. Phase 6 introduced this
/// alongside a thin `LiveLoginItem`; Phase 8 promotes it to a full facade with
/// status reporting + Notifier-friendly error surfacing.
protocol LoginItemControlling: Sendable {
    func register() throws
    func unregister() throws
}

/// Extended protocol exposing `status` for callers that need to render the
/// current SMAppService state (Settings UI). Production `LiveLoginItem`
/// returns the live value; tests stub it. Kept separate from
/// `LoginItemControlling` so existing Phase 6 stubs in
/// `StartupSectionViewModelTests` keep working.
protocol LoginItemStatusReporting: LoginItemControlling {
    var statusRaw: SMAppService.Status { get }
}

struct LiveLoginItem: LoginItemStatusReporting {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var statusRaw: SMAppService.Status { service.status }
    func register() throws { try service.register() }
    func unregister() throws { try service.unregister() }
}

/// Façade over `LoginItemStatusReporting` exposing a friendlier `Status` enum
/// and logging. Used by Settings UI and tests.
@MainActor
final class LoginItem {
    enum Status: Equatable {
        case enabled
        case notRegistered
        case requiresApproval
        case notFound
    }

    static let shared = LoginItem(service: LiveLoginItem())

    private let service: LoginItemStatusReporting
    private let log = Logger(subsystem: "com.voicetype.app", category: "loginitem")

    init(service: LoginItemStatusReporting) {
        self.service = service
    }

    var status: Status {
        Self.map(service.statusRaw)
    }

    func register() throws {
        do {
            try service.register()
            log.info("login item registered")
        } catch {
            log.error("register failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func unregister() throws {
        do {
            try service.unregister()
            log.info("login item unregistered")
        } catch {
            log.error("unregister failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func map(_ raw: SMAppService.Status) -> Status {
        switch raw {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }
}
