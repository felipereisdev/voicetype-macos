import Foundation
@testable import VoiceType
import Core

/// Shared helpers for Phase 6 Settings VM tests. Each test seeds an in-memory
/// `ConfigStore` and injects fakes for any external collaborator (Groq client,
/// device probe, login item, …).
enum SettingsTestSupport {

    @discardableResult
    static func makeInMemoryStore(seed: AppConfig = AppConfig()) async throws -> ConfigStore {
        let store = ConfigStore.inMemory()
        // Save returns after persisting + notifying subscribers; we don't need
        // to keep the file around since each test gets a unique tmp path.
        try await store.save(seed)
        return store
    }

    @MainActor
    static func makeSnapshot(seed: AppConfig = AppConfig()) async throws -> ConfigStoreSnapshot {
        let store = try await makeInMemoryStore(seed: seed)
        let snapshot = ConfigStoreSnapshot(store: store)
        // Let initial load Task settle.
        try await Task.sleep(nanoseconds: 100_000_000)
        return snapshot
    }
}

final class FakeKeyTester: GroqKeyTesting, @unchecked Sendable {
    var result: TestKeyResult = .init(ok: false, status: 401)
    func testKey(_ apiKey: String) async -> TestKeyResult { result }
}
