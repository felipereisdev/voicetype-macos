import Foundation

public final class HistoryCancellable: @unchecked Sendable {
    private let onCancel: @Sendable () -> Void
    init(onCancel: @escaping @Sendable () -> Void) { self.onCancel = onCancel }
    deinit { onCancel() }
    public func cancel() { onCancel() }
}

public actor HistoryStore {
    public static let defaultCap = 500

    /// Shared production instance. Retained for CoreDemo and Core tests; the
    /// app target injects via `AppDependencies` and should not reference this.
    @available(*, deprecated, message: "Inject via AppDependencies in the app target; this remains only for CoreDemo and tests.")
    public static let shared = HistoryStore()

    private let fileURL: URL
    private var entries: [HistoryEntry] = []
    private var subscribers: [UUID: @Sendable ([HistoryEntry]) -> Void] = [:]
    private var loaded = false

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("VoiceType", isDirectory: true)
            self.fileURL = base.appendingPathComponent("history.json", isDirectory: false)
        }
    }

    public func add(_ entry: HistoryEntry, cap: Int = HistoryStore.defaultCap) async {
        await ensureLoaded()
        entries.insert(entry, at: 0)
        let effectiveCap = max(1, cap)
        if entries.count > effectiveCap {
            entries.removeLast(entries.count - effectiveCap)
        }
        await persist()
        notify()
    }

    public func list() async -> [HistoryEntry] {
        await ensureLoaded()
        return entries
    }

    public func delete(id: UUID) async {
        await ensureLoaded()
        let before = entries.count
        entries.removeAll { $0.id == id }
        if entries.count != before {
            await persist()
            notify()
        }
    }

    public func clear() async {
        await ensureLoaded()
        guard !entries.isEmpty else { return }
        entries.removeAll()
        await persist()
        notify()
    }

    @discardableResult
    public func subscribe(_ handler: @escaping @Sendable ([HistoryEntry]) -> Void) -> HistoryCancellable {
        let token = UUID()
        subscribers[token] = handler
        let snapshot = entries
        Task { handler(snapshot) }
        return HistoryCancellable(onCancel: { [weak self] in
            Task { await self?.removeSubscriber(token: token) }
        })
    }

    public func resetForTests() async {
        entries.removeAll()
        subscribers.removeAll()
        loaded = true
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func removeSubscriber(token: UUID) {
        subscribers.removeValue(forKey: token)
    }

    private func notify() {
        let snapshot = entries
        for handler in subscribers.values {
            handler(snapshot)
        }
    }

    private func ensureLoaded() async {
        guard !loaded else { return }
        loaded = true
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([HistoryEntry].self, from: data)
            if entries.count > Self.defaultCap {
                entries.removeLast(entries.count - Self.defaultCap)
                await persist()
            }
        } catch {
            entries = []
        }
    }

    private func persist() async {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)

            // Atomic write: write to tmp, fsync, rename.
            let tmpURL = fileURL.appendingPathExtension("tmp")
            if FileManager.default.fileExists(atPath: tmpURL.path) {
                try FileManager.default.removeItem(at: tmpURL)
            }
            FileManager.default.createFile(atPath: tmpURL.path, contents: nil, attributes: nil)
            let handle = try FileHandle(forWritingTo: tmpURL)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()

            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: fileURL)
            }
        } catch {
            print("[HistoryStore] persist failed: \(error)")
        }
    }
}
