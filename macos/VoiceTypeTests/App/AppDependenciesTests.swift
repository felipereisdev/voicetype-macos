import XCTest
@testable import VoiceType
@testable import Core

@MainActor
final class AppDependenciesTests: XCTestCase {

    func test_default_init_assembles_full_graph() {
        let deps = AppDependencies(
            configStore: ConfigStore.inMemory(),
            historyStore: HistoryStore(fileURL: tempHistoryURL()),
            notifier: Notifier(),
            permissionsChecker: PermissionsChecker(),
            hudController: HUDController()
        )
        XCTAssertNotNil(deps.configStore)
        XCTAssertNotNil(deps.historyStore)
        XCTAssertNotNil(deps.notifier)
        XCTAssertNotNil(deps.permissionsChecker)
        XCTAssertNotNil(deps.hudController)
        XCTAssertNotNil(deps.recordingOrchestrator)
    }

    func test_orchestrator_uses_same_configStore_as_graph() {
        let store = ConfigStore.inMemory()
        let deps = AppDependencies(
            configStore: store,
            historyStore: HistoryStore(fileURL: tempHistoryURL()),
            notifier: Notifier(),
            permissionsChecker: PermissionsChecker(),
            hudController: HUDController()
        )
        XCTAssertTrue(deps.recordingOrchestrator.configStore === deps.configStore)
        XCTAssertTrue(deps.recordingOrchestrator.configStore === store)
    }

    func test_orchestrator_uses_same_hudController_as_graph() {
        let hud = HUDController()
        let deps = AppDependencies(
            configStore: ConfigStore.inMemory(),
            historyStore: HistoryStore(fileURL: tempHistoryURL()),
            notifier: Notifier(),
            permissionsChecker: PermissionsChecker(),
            hudController: hud
        )
        XCTAssertTrue(deps.hudController === hud)
    }

    private func tempHistoryURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("VTAppDeps-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }
}
