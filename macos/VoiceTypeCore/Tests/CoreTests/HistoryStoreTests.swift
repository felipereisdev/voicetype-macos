import Testing
import Foundation
@testable import Core

@Suite("HistoryStore")
struct HistoryStoreTests {
    private func makeStore() -> (HistoryStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTypeTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let file = tmp.appendingPathComponent("history.json")
        return (HistoryStore(fileURL: file), file)
    }

    private func makeEntry(_ text: String, mode: HistoryMode = .refine) -> HistoryEntry {
        HistoryEntry(mode: mode, sourceApp: "com.apple.TextEdit", text: text)
    }

    @Test("list começa vazio")
    func emptyOnFirstUse() async throws {
        let (store, _) = makeStore()
        let entries = await store.list()
        #expect(entries.isEmpty)
    }

    @Test("add insere no topo")
    func addInsertsAtTop() async throws {
        let (store, _) = makeStore()
        await store.add(makeEntry("a"))
        await store.add(makeEntry("b"))
        let entries = await store.list()
        #expect(entries.count == 2)
        #expect(entries[0].text == "b")
        #expect(entries[1].text == "a")
    }

    @Test("cap 500 — eviction acontece on add (não lazy)")
    func capEnforcedOnAdd() async throws {
        let (store, file) = makeStore()
        for i in 0..<505 {
            await store.add(makeEntry("entry-\(i)"))
        }
        let entries = await store.list()
        #expect(entries.count == HistoryStore.defaultCap)
        #expect(entries.first?.text == "entry-504")
        #expect(entries.last?.text == "entry-5")

        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let onDisk = try decoder.decode([HistoryEntry].self, from: data)
        #expect(onDisk.count == HistoryStore.defaultCap)
    }

    @Test("delete por id")
    func deleteById() async throws {
        let (store, _) = makeStore()
        let target = makeEntry("delete-me")
        await store.add(makeEntry("a"))
        await store.add(target)
        await store.add(makeEntry("b"))
        await store.delete(id: target.id)
        let entries = await store.list()
        #expect(entries.count == 2)
        #expect(!entries.contains { $0.id == target.id })
    }

    @Test("clear remove tudo")
    func clearRemovesAll() async throws {
        let (store, _) = makeStore()
        await store.add(makeEntry("a"))
        await store.add(makeEntry("b"))
        await store.clear()
        let entries = await store.list()
        #expect(entries.isEmpty)
    }

    @Test("persistence round-trip via atomic write")
    func persistenceRoundTrip() async throws {
        let (store, file) = makeStore()
        await store.add(makeEntry("primeira", mode: .refine))
        await store.add(makeEntry("segunda", mode: .translate))

        let reopened = HistoryStore(fileURL: file)
        let entries = await reopened.list()
        #expect(entries.count == 2)
        #expect(entries[0].text == "segunda")
        #expect(entries[0].mode == .translate)
        #expect(entries[1].text == "primeira")
    }

    @Test("subscribe recebe snapshot inicial + atualização após add")
    func subscriberFires() async throws {
        let (store, _) = makeStore()
        await store.add(makeEntry("first"))

        actor Collector {
            var received: [[HistoryEntry]] = []
            func push(_ s: [HistoryEntry]) { received.append(s) }
            func snapshot() -> [[HistoryEntry]] { received }
        }
        let collector = Collector()

        let token = await store.subscribe { snapshot in
            Task { await collector.push(snapshot) }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        await store.add(makeEntry("second"))
        try await Task.sleep(nanoseconds: 50_000_000)

        let received = await collector.snapshot()
        #expect(received.count >= 2)
        #expect(received.last?.first?.text == "second")
        token.cancel()
    }

    @Test("subscribe — cancel para de notificar")
    func subscriberCancel() async throws {
        let (store, _) = makeStore()
        actor Counter {
            var n = 0
            func tick() { n += 1 }
            func value() -> Int { n }
        }
        let counter = Counter()

        let token = await store.subscribe { _ in
            Task { await counter.tick() }
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        token.cancel()
        try await Task.sleep(nanoseconds: 30_000_000)
        let before = await counter.value()
        await store.add(makeEntry("after-cancel"))
        try await Task.sleep(nanoseconds: 50_000_000)
        let after = await counter.value()
        #expect(after == before)
    }

    @Test func add_with_smaller_cap_evicts_extras() async {
        let url = URL(fileURLWithPath: "/tmp/voicetype-history-cap-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = HistoryStore(fileURL: url)
        for i in 0..<10 {
            await store.add(
                HistoryEntry(mode: .refine, sourceApp: "x", text: "entry-\(i)"),
                cap: 3
            )
        }
        let list = await store.list()
        #expect(list.count == 3)
        #expect(list.first?.text == "entry-9")
        #expect(list.last?.text == "entry-7")
    }

    @Test func add_default_cap_remains_500() async {
        let url = URL(fileURLWithPath: "/tmp/voicetype-history-default-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = HistoryStore(fileURL: url)
        for i in 0..<600 {
            await store.add(HistoryEntry(mode: .refine, sourceApp: "x", text: "e-\(i)"))
        }
        let list = await store.list()
        #expect(list.count == 500)
    }
}
