import XCTest
import Core
@testable import VoiceType

@MainActor
final class HistoryStoreSnapshotTests: XCTestCase {

    private func makeStore() -> HistoryStore {
        let url = URL(fileURLWithPath: "/tmp/voicetype-history-snap-\(UUID()).json")
        return HistoryStore(fileURL: url)
    }

    func test_initial_load_populates_entries() async throws {
        let store = makeStore()
        let seeded = HistoryEntry(mode: .refine, sourceApp: "x", text: "t1")
        await store.add(seeded)

        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(snapshot.entries.first?.text, "t1")
    }

    func test_add_updates_snapshot() async throws {
        let store = makeStore()
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)

        await store.add(HistoryEntry(mode: .refine, sourceApp: "x", text: "added"))
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(snapshot.entries.first?.text, "added")
    }

    func test_clear_empties_snapshot() async throws {
        let store = makeStore()
        await store.add(HistoryEntry(mode: .refine, sourceApp: "x", text: "to-clear"))

        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(snapshot.entries.count, 1)

        await store.clear()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(snapshot.entries.isEmpty)
    }
}
