import XCTest
import ServiceManagement
@testable import VoiceType

final class LoginItemTests: XCTestCase {

    final class StubService: LoginItemStatusReporting, @unchecked Sendable {
        var statusRaw: SMAppService.Status = .notRegistered
        var registerCalls = 0
        var unregisterCalls = 0
        var registerError: Error?
        var unregisterError: Error?

        func register() throws {
            registerCalls += 1
            if let e = registerError { throw e }
        }

        func unregister() throws {
            unregisterCalls += 1
            if let e = unregisterError { throw e }
        }
    }

    struct StubError: Error, Equatable {}

    @MainActor
    func testRegisterCallsService() throws {
        let stub = StubService()
        let item = LoginItem(service: stub)
        try item.register()
        XCTAssertEqual(stub.registerCalls, 1)
    }

    @MainActor
    func testUnregisterCallsService() throws {
        let stub = StubService()
        let item = LoginItem(service: stub)
        try item.unregister()
        XCTAssertEqual(stub.unregisterCalls, 1)
    }

    @MainActor
    func testRegisterRethrowsError() {
        let stub = StubService()
        stub.registerError = StubError()
        let item = LoginItem(service: stub)
        XCTAssertThrowsError(try item.register()) { error in
            XCTAssertTrue(error is StubError)
        }
    }

    @MainActor
    func testUnregisterRethrowsError() {
        let stub = StubService()
        stub.unregisterError = StubError()
        let item = LoginItem(service: stub)
        XCTAssertThrowsError(try item.unregister()) { error in
            XCTAssertTrue(error is StubError)
        }
    }

    @MainActor
    func testStatusMapsAllCases() {
        let stub = StubService()
        let item = LoginItem(service: stub)

        stub.statusRaw = .enabled
        XCTAssertEqual(item.status, .enabled)
        stub.statusRaw = .notRegistered
        XCTAssertEqual(item.status, .notRegistered)
        stub.statusRaw = .requiresApproval
        XCTAssertEqual(item.status, .requiresApproval)
        stub.statusRaw = .notFound
        XCTAssertEqual(item.status, .notFound)
    }
}
