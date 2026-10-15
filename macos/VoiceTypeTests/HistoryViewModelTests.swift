import XCTest
@testable import VoiceType
@testable import Core

@MainActor
final class HistoryViewModelTests: XCTestCase {
    private func makeStore() -> HistoryStore {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VTHistoryVM-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return HistoryStore(fileURL: tmp.appendingPathComponent("history.json"))
    }

    private func seed(_ store: HistoryStore, _ items: [(String, HistoryMode)]) async {
        for (text, mode) in items {
            await store.add(HistoryEntry(mode: mode, sourceApp: "com.apple.TextEdit", text: text))
        }
    }

    func test_load_reflectsStore() async throws {
        let store = makeStore()
        await seed(store, [("oi", .refine), ("hello", .translate)])
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let vm = HistoryViewModel(snapshot: snapshot, store: store, paster: NoopPaster())
        XCTAssertEqual(vm.filteredEntries.count, 2)
    }

    func test_search_filtersByText() async throws {
        let store = makeStore()
        await seed(store, [("comprar pão", .refine), ("buy bread", .translate), ("café", .raw)])
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let vm = HistoryViewModel(snapshot: snapshot, store: store, paster: NoopPaster())

        vm.query = "pão"
        XCTAssertEqual(vm.filteredEntries.map(\.text), ["comprar pão"])

        vm.query = "BREAD"
        XCTAssertEqual(vm.filteredEntries.map(\.text), ["buy bread"])

        vm.query = ""
        XCTAssertEqual(vm.filteredEntries.count, 3)
    }

    func test_delete_removesEntry() async throws {
        let store = makeStore()
        await seed(store, [("a", .refine), ("b", .refine)])
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let vm = HistoryViewModel(snapshot: snapshot, store: store, paster: NoopPaster())

        let toDelete = vm.filteredEntries.first { $0.text == "a" }!
        await vm.delete(id: toDelete.id)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(vm.filteredEntries.contains { $0.id == toDelete.id })
    }

    func test_clear_empties() async throws {
        let store = makeStore()
        await seed(store, [("a", .refine), ("b", .refine)])
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let vm = HistoryViewModel(snapshot: snapshot, store: store, paster: NoopPaster())

        await vm.clearAll()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(vm.filteredEntries.isEmpty)
    }

    func test_replay_callsPasterWithText() async throws {
        let store = makeStore()
        await seed(store, [("repaste-me", .refine)])
        let paster = MockPaster()
        let snapshot = HistoryStoreSnapshot(store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let vm = HistoryViewModel(snapshot: snapshot, store: store, paster: paster)

        let entry = vm.filteredEntries.first!
        await vm.repaste(entry)
        XCTAssertEqual(paster.pastedTexts, ["repaste-me"])
    }
}

final class NoopPaster: PasterProtocol, @unchecked Sendable {
    func paste(_ text: String) async {}
}

final class MockPaster: PasterProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "mock-paster")
    private var _pastedTexts: [String] = []
    var pastedTexts: [String] {
        queue.sync { _pastedTexts }
    }
    func paste(_ text: String) async {
        queue.sync { _pastedTexts.append(text) }
    }
}
