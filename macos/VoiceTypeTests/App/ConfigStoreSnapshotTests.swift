import XCTest
import Core
@testable import VoiceType

@MainActor
final class ConfigStoreSnapshotTests: XCTestCase {

    func test_initial_value_loads_from_store() async throws {
        let store = ConfigStore.inMemory()
        var seeded = AppConfig()
        seeded.groq.apiKey = "gsk_x"
        try await store.save(seeded)

        let snapshot = ConfigStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(snapshot.config.groq.apiKey, "gsk_x")
    }

    func test_save_via_store_updates_snapshot() async throws {
        let store = ConfigStore.inMemory()
        let snapshot = ConfigStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 100_000_000)

        var next = AppConfig()
        next.groq.apiKey = "gsk_new"
        try await store.save(next)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(snapshot.config.groq.apiKey, "gsk_new")
    }

    func test_update_via_snapshot_persists_to_store() async throws {
        let store = ConfigStore.inMemory()
        let snapshot = ConfigStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 100_000_000)

        await snapshot.update { cfg in
            cfg.groq.apiKey = "gsk_via_snapshot"
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let stored = try await store.load()
        XCTAssertEqual(stored.groq.apiKey, "gsk_via_snapshot")
        XCTAssertEqual(snapshot.config.groq.apiKey, "gsk_via_snapshot")
    }
}
