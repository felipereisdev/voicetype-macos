import XCTest
import UserNotifications
@testable import VoiceType

final class NotifierTests: XCTestCase {

    final class StubCenter: UserNotificationCenter, @unchecked Sendable {
        var authShouldGrant = true
        var authError: Error?
        var addedRequests: [UNNotificationRequest] = []
        var addThrowsOnce: Error?

        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            if let authError { throw authError }
            return authShouldGrant
        }

        func add(_ request: UNNotificationRequest) async throws {
            if let err = addThrowsOnce {
                addThrowsOnce = nil
                throw err
            }
            addedRequests.append(request)
        }
    }

    @MainActor
    func testErrorBuildsRequestWithBangAndDash() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        await notifier.error(title: "Falha", body: "Detalhe")

        XCTAssertEqual(stub.addedRequests.count, 1)
        let content = stub.addedRequests[0].content
        XCTAssertEqual(content.title, "VoiceType")
        XCTAssertEqual(content.body, "❌ Falha — Detalhe")
    }

    @MainActor
    func testInfoUsesPlainBody() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        await notifier.info(title: "OK", body: "Tudo certo")

        XCTAssertEqual(stub.addedRequests[0].content.body, "OK — Tudo certo")
    }

    @MainActor
    func testSuccessUsesCheckEmoji() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        await notifier.success(title: "Pronto", body: "Colado")

        XCTAssertEqual(stub.addedRequests[0].content.body, "✓ Pronto — Colado")
    }

    @MainActor
    func testSilentFallbackWhenAuthDenied() async {
        let stub = StubCenter()
        stub.authShouldGrant = false
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        await notifier.error(title: "Falha", body: "x")
        XCTAssertTrue(stub.addedRequests.isEmpty)
    }

    @MainActor
    func testSwallowsAddErrors() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        stub.addThrowsOnce = NSError(domain: "test", code: 1)
        await notifier.error(title: "Falha", body: "x")
        // Should not have thrown.
    }

    @MainActor
    func testDedupesIdenticalWithin5Seconds() async {
        let stub = StubCenter()
        var clock = Date(timeIntervalSince1970: 1_000)
        let notifier = Notifier(center: stub, now: { clock })
        await notifier.bootstrap()

        await notifier.error(title: "Falha", body: "x")
        clock = clock.addingTimeInterval(2)
        await notifier.error(title: "Falha", body: "x")
        clock = clock.addingTimeInterval(2)
        await notifier.error(title: "Falha", body: "x")

        XCTAssertEqual(stub.addedRequests.count, 1)
    }

    @MainActor
    func testAllowsRepeatAfter5Seconds() async {
        let stub = StubCenter()
        var clock = Date(timeIntervalSince1970: 1_000)
        let notifier = Notifier(center: stub, now: { clock })
        await notifier.bootstrap()

        await notifier.error(title: "Falha", body: "x")
        clock = clock.addingTimeInterval(5.1)
        await notifier.error(title: "Falha", body: "x")

        XCTAssertEqual(stub.addedRequests.count, 2)
    }

    @MainActor
    func testDedupeKeyDistinguishesBodies() async {
        let stub = StubCenter()
        let clock = Date(timeIntervalSince1970: 1_000)
        let notifier = Notifier(center: stub, now: { clock })
        await notifier.bootstrap()

        await notifier.error(title: "A", body: "x")
        await notifier.error(title: "A", body: "y")
        await notifier.error(title: "B", body: "x")

        XCTAssertEqual(stub.addedRequests.count, 3)
    }

    @MainActor
    func testDedupeKeyDistinguishesLevels() async {
        let stub = StubCenter()
        let clock = Date(timeIntervalSince1970: 1_000)
        let notifier = Notifier(center: stub, now: { clock })
        await notifier.bootstrap()

        await notifier.info(title: "A", body: "x")
        await notifier.error(title: "A", body: "x")

        XCTAssertEqual(stub.addedRequests.count, 2)
    }

    @MainActor
    func testBootstrapIdempotent() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        await notifier.bootstrap()
        stub.authShouldGrant = false   // flip; should not retake effect
        await notifier.bootstrap()
        XCTAssertTrue(notifier.authorized)
    }

    @MainActor
    func testOnAuthChangedFiresAfterBootstrap() async {
        let stub = StubCenter()
        let notifier = Notifier(center: stub, now: { Date(timeIntervalSince1970: 0) })
        var received: Bool?
        notifier.onAuthChanged = { received = $0 }
        await notifier.bootstrap()
        XCTAssertEqual(received, true)
    }
}
