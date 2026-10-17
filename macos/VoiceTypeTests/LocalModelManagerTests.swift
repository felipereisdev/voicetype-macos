import XCTest
import Core
@testable import VoiceType

final class FakeBackend: LocalSpeechBackend, @unchecked Sendable {
    func transcribe(samples: [Float], lang: String, vocabulary: String?) async throws -> String { "" }
}

/// Logs `load:<id>`, `end:<id>` and `delete:<id>` in order. Each load stays
/// suspended until the test resolves it and, like a Core ML compile, ignores
/// cancellation until then.
@MainActor
final class FakeLoader: LocalModelLoading {
    var downloaded: Set<String> = []
    private(set) var log: [String] = []
    private var pending: [String: [CheckedContinuation<any LocalSpeechBackend, Error>]] = [:]

    func isDownloaded(_ model: LocalModel) -> Bool { downloaded.contains(model.id) }

    func load(
        _ model: LocalModel, progress: @escaping @Sendable (LocalModelLoadProgress) -> Void
    ) async throws -> any LocalSpeechBackend {
        log.append("load:\(model.id)")
        defer { log.append("end:\(model.id)") }
        return try await withCheckedThrowingContinuation { pending[model.id, default: []].append($0) }
    }

    func deleteFiles(_ model: LocalModel) {
        log.append("delete:\(model.id)")
    }

    @discardableResult
    func succeed(_ id: String) throws -> FakeBackend {
        let backend = FakeBackend()
        try next(id).resume(returning: backend)
        return backend
    }

    func fail(_ id: String, _ error: Error) throws {
        try next(id).resume(throwing: error)
    }

    func failAll() {
        for continuation in pending.values.flatMap({ $0 }) {
            continuation.resume(throwing: CancellationError())
        }
        pending = [:]
    }

    private func next(_ id: String) throws -> CheckedContinuation<any LocalSpeechBackend, Error> {
        let continuation = try XCTUnwrap(pending[id]?.first, "no load of \(id) in flight")
        pending[id]?.removeFirst()
        return continuation
    }
}

private struct FakeError: LocalizedError {
    var errorDescription: String? { "boom" }
}

@MainActor
final class LocalModelManagerTests: XCTestCase {
    private let smallID = "openai_whisper-small"
    private let turboID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private let parakeetID = "parakeet-ultra"

    private var loader: FakeLoader!
    private var persisted: [String] = []

    override func setUp() async throws {
        loader = FakeLoader()
        persisted = []
    }

    override func tearDown() async throws {
        loader.failAll()
        await settle()
    }

    private func makeManager() -> LocalModelManager {
        LocalModelManager(loader: loader, models: LocalModelCatalog.all, persist: { [weak self] id in
            self?.persisted.append(id)
        })
    }

    /// Lets the manager's main-actor tasks run until they suspend again.
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func readyWithSmall() async throws -> (LocalModelManager, FakeBackend) {
        loader.downloaded.insert(smallID)
        let manager = makeManager()
        manager.bootstrap(selectedID: smallID)
        await settle()
        let backend = try loader.succeed(smallID)
        await settle()
        XCTAssertEqual(manager.activeModel?.id, smallID)
        persisted = []
        return (manager, backend)
    }

    private func count(_ entry: String) -> Int {
        loader.log.filter { $0 == entry }.count
    }

    func test_bootstrap_loads_selected_and_becomes_ready() async throws {
        loader.downloaded.insert(smallID)
        let manager = makeManager()
        manager.bootstrap(selectedID: smallID)
        await settle()
        XCTAssertFalse(manager.isReady)
        XCTAssertEqual(loader.log, ["load:\(smallID)"])

        try loader.succeed(smallID)
        await settle()

        XCTAssertTrue(manager.isReady)
        XCTAssertEqual(manager.transcriptionTarget()?.model.id, smallID)
    }

    func test_target_stays_previous_while_pending() async throws {
        let (manager, small) = try await readyWithSmall()
        manager.select(turboID)
        await settle()

        XCTAssertEqual(manager.selection.pending, turboID)
        let target = try XCTUnwrap(manager.transcriptionTarget())
        XCTAssertEqual(target.model.id, smallID)
        XCTAssertTrue(target.backend === small)
        XCTAssertTrue(manager.isReady)
    }

    func test_failure_deletes_files_and_persists_previous() async throws {
        let (manager, small) = try await readyWithSmall()
        manager.select(turboID)
        await settle()
        try loader.fail(turboID, FakeError())
        await settle()

        XCTAssertEqual(count("delete:\(turboID)"), 1)
        XCTAssertEqual(persisted, [turboID, smallID])
        XCTAssertEqual(manager.selection.status(of: turboID), .failed("boom"))
        XCTAssertTrue(manager.transcriptionTarget()?.backend === small)
    }

    func test_cancelled_load_result_is_discarded() async throws {
        let (manager, small) = try await readyWithSmall()
        manager.select(turboID)
        await settle()
        manager.cancel()
        let turbo = try loader.succeed(turboID)
        await settle()

        XCTAssertEqual(manager.activeModel?.id, smallID)
        XCTAssertTrue(manager.transcriptionTarget()?.backend === small)
        XCTAssertFalse(manager.transcriptionTarget()?.backend === turbo)
    }

    func test_cancel_waits_for_load_to_end_before_deleting() async throws {
        let (manager, _) = try await readyWithSmall()
        manager.select(turboID)
        await settle()
        manager.cancel()
        await settle()
        XCTAssertEqual(count("delete:\(turboID)"), 0)

        try loader.fail(turboID, CancellationError())
        await settle()

        XCTAssertEqual(Array(loader.log.suffix(2)), ["end:\(turboID)", "delete:\(turboID)"])
    }

    func test_reselect_after_cancel_ignores_stale_success() async throws {
        let (manager, small) = try await readyWithSmall()
        manager.select(turboID)       // A
        await settle()
        manager.cancel()
        manager.select(turboID)       // B
        await settle()
        XCTAssertEqual(count("load:\(turboID)"), 1)

        let stale = try loader.succeed(turboID)
        await settle()

        XCTAssertEqual(manager.activeModel?.id, smallID)
        XCTAssertTrue(manager.transcriptionTarget()?.backend === small)
        XCTAssertFalse(manager.transcriptionTarget()?.backend === stale)
        XCTAssertEqual(
            Array(loader.log.suffix(4)),
            ["load:\(turboID)", "end:\(turboID)", "delete:\(turboID)", "load:\(turboID)"]
        )

        let fresh = try loader.succeed(turboID)
        await settle()

        let target = try XCTUnwrap(manager.transcriptionTarget())
        XCTAssertEqual(target.model.id, turboID)
        XCTAssertTrue(target.backend === fresh)
    }

    func test_reselect_after_cancel_ignores_stale_failure() async throws {
        let (manager, small) = try await readyWithSmall()
        manager.select(turboID)       // A
        await settle()
        manager.cancel()
        manager.select(turboID)       // B
        await settle()

        try loader.fail(turboID, FakeError())
        await settle()

        if case .failed = manager.selection.status(of: turboID) {
            XCTFail("a stale failure must not mark the pending model as failed")
        }
        XCTAssertEqual(persisted, [turboID, smallID, turboID])
        XCTAssertEqual(count("delete:\(turboID)"), 1)
        XCTAssertEqual(manager.selection.pending, turboID)
        XCTAssertEqual(loader.log.last, "load:\(turboID)")
        XCTAssertTrue(manager.transcriptionTarget()?.backend === small)
    }

    func test_boot_failure_with_default_deleted_loads_default() async throws {
        let manager = makeManager()
        manager.bootstrap(selectedID: turboID)
        await settle()
        try loader.fail(turboID, FakeError())
        await settle()

        XCTAssertEqual(count("load:\(smallID)"), 1)
        XCTAssertEqual(persisted, [smallID])
        XCTAssertEqual(manager.selection.pending, smallID)
    }

    func test_boot_cancel_with_default_deleted_loads_default() async throws {
        let manager = makeManager()
        manager.bootstrap(selectedID: turboID)
        await settle()
        manager.cancel()
        await settle()

        XCTAssertEqual(count("load:\(smallID)"), 1)
        XCTAssertEqual(persisted, [smallID])
        XCTAssertEqual(manager.selection.pending, smallID)

        try loader.fail(turboID, CancellationError())
        try loader.succeed(smallID)
        await settle()
        XCTAssertEqual(manager.activeModel?.id, smallID)
    }

    func test_delete_calls_loader_only_for_idle_downloaded_model() async throws {
        loader.downloaded = [turboID, parakeetID]
        let (manager, _) = try await readyWithSmall()

        manager.delete(smallID)       // active
        manager.select(parakeetID)
        manager.delete(parakeetID)    // pending
        await settle()
        XCTAssertFalse(loader.log.contains { $0.hasPrefix("delete:") })

        manager.delete(turboID)       // idle and downloaded
        manager.delete(turboID)       // no longer downloaded
        await settle()
        XCTAssertEqual(loader.log.filter { $0.hasPrefix("delete:") }, ["delete:\(turboID)"])
        XCTAssertEqual(manager.selection.status(of: turboID), .notDownloaded)
    }
}
