import XCTest
@testable import VoiceType
import Core

final class StartupSectionViewModelTests: XCTestCase {

    final class StubLoginItem: LoginItemControlling, @unchecked Sendable {
        var didRegister = false
        var didUnregister = false
        var registerThrows: Error?
        var unregisterThrows: Error?

        func register() throws {
            if let e = registerThrows { throw e }
            didRegister = true
        }
        func unregister() throws {
            if let e = unregisterThrows { throw e }
            didUnregister = true
        }
    }

    struct StubError: Error {}

    struct StubNotifier: NotifierEmitting {
        func error(title: String, body: String) async {}
        func info(title: String, body: String) async {}
    }

    @MainActor
    func testStartAtLoginTogglePersistsAndRegisters() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot(seed: AppConfig(startAtLogin: false))
        let stub = StubLoginItem()
        let vm = StartupSectionViewModel(snapshot: snapshot, loginItem: stub, notifier: StubNotifier())
        XCTAssertFalse(snapshot.config.startAtLogin)
        await vm.commitStartAtLogin(desired: true)
        XCTAssertTrue(stub.didRegister)
        XCTAssertTrue(snapshot.config.startAtLogin)
    }

    @MainActor
    func testStartAtLoginUnregisterPersistsFalse() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot(seed: AppConfig(startAtLogin: true))
        let stub = StubLoginItem()
        let vm = StartupSectionViewModel(snapshot: snapshot, loginItem: stub, notifier: StubNotifier())
        await vm.commitStartAtLogin(desired: false)
        XCTAssertTrue(stub.didUnregister)
        XCTAssertFalse(snapshot.config.startAtLogin)
    }

    @MainActor
    func testRollsBackOnLoginItemFailure() async throws {
        let snapshot = try await SettingsTestSupport.makeSnapshot(seed: AppConfig(startAtLogin: false))
        let stub = StubLoginItem()
        stub.registerThrows = StubError()
        let vm = StartupSectionViewModel(snapshot: snapshot, loginItem: stub, notifier: StubNotifier())
        await vm.commitStartAtLogin(desired: true)
        XCTAssertFalse(snapshot.config.startAtLogin, "UI must reflect the failure to register")
    }
}
