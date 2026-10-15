import Foundation

/// Persistent, validated config store.
///
/// Mirrors `src/main/config-store.ts`. Reads/writes JSON at a configurable
/// `fileURL` (defaults to `~/Library/Application Support/VoiceType/config.json`).
/// Writes go through a `.tmp` sibling that is `fsync`'d and renamed over the
/// destination — atomic on the same filesystem.
///
/// `subscribe(_:)` notifies callbacks with a snapshot of the *current*
/// subscriber list (FU-004 mitigation): callbacks added during another
/// callback's invocation will not fire for the same save.
public actor ConfigStore {

    public enum StoreError: Error, Sendable, Equatable {
        case ioFailure(String)
    }

    public typealias Subscriber = @Sendable (AppConfig) -> Void

    // MARK: - Subscriber registry (lock-protected for sync cancel)

    private final class SubscriberRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [UUID: Subscriber] = [:]

        func register(_ callback: @escaping Subscriber) -> UUID {
            let id = UUID()
            lock.lock()
            entries[id] = callback
            lock.unlock()
            return id
        }

        func remove(_ id: UUID) {
            lock.lock()
            entries.removeValue(forKey: id)
            lock.unlock()
        }

        func snapshot() -> [Subscriber] {
            lock.lock()
            defer { lock.unlock() }
            return Array(entries.values)
        }

        func removeAll() {
            lock.lock()
            entries.removeAll()
            lock.unlock()
        }
    }

    // MARK: - Configuration

    /// Shared production instance. Retained for CoreDemo and Core tests; the
    /// app target injects via `AppDependencies` and should not reference this.
    @available(*, deprecated, message: "Inject via AppDependencies in the app target; this remains only for CoreDemo and tests.")
    public static let shared = ConfigStore()

    public static let defaultFileURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("VoiceType", isDirectory: true)
            .appendingPathComponent("config.json")
    }()

    private let fileURL: URL
    private let fileManager: FileManager

    // MARK: - State

    private var cached: AppConfig?
    private nonisolated let subscribers = SubscriberRegistry()

    // MARK: - Init

    public init(fileURL: URL = ConfigStore.defaultFileURL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Load the persisted config. On first call, materializes defaults if the
    /// file is missing. On corruption, deletes the bad file and returns defaults.
    public func load() throws -> AppConfig {
        if let cached { return cached }

        guard fileManager.fileExists(atPath: fileURL.path) else {
            let defaults = AppConfig()
            cached = defaults
            return defaults
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
            // Best-effort: if validation fails on load, treat as corruption.
            try decoded.validate()
            cached = decoded
            return decoded
        } catch {
            CoreLog.configStore.warning("config corrupted at \(self.fileURL.path, privacy: .public); resetting to defaults")
            try? fileManager.removeItem(at: fileURL)
            let defaults = AppConfig()
            cached = defaults
            return defaults
        }
    }

    /// Persist a new config. Validates first; throws `AppConfig.ValidationError`
    /// without mutating either the file or the in-memory cache when validation fails.
    public func save(_ next: AppConfig) throws {
        try next.validate()

        try ensureDirectoryExists()
        try atomicWrite(next)
        cached = next

        // Snapshot subscribers BEFORE iterating: a callback might call `subscribe`
        // (whose new listener must not fire on the current save) or even trigger
        // another `save` (which would recurse forever on the live array).
        let snapshot = subscribers.snapshot()
        for cb in snapshot {
            cb(next)
        }
    }

    /// Register a notification callback. The returned `Cancellable` removes the
    /// subscriber when `cancel()` is called; cancellation is idempotent.
    public nonisolated func subscribe(_ callback: @escaping Subscriber) -> Cancellable {
        let id = subscribers.register(callback)
        let registry = subscribers
        return Cancellable {
            registry.remove(id)
        }
    }

    /// Clears in-memory state. Test-only entry point; production callers should
    /// not invoke. Mirrors the gated `resetForTests` in the Electron build.
    public func resetForTests() {
        #if !DEBUG
        // No-op in release builds. The function stays callable so test code keeps
        // a single import path.
        return
        #else
        cached = nil
        subscribers.removeAll()
        #endif
    }

    // MARK: - Atomic write

    private func ensureDirectoryExists() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// First run only (no config file yet): seeds the refine shortcut by
    /// hardware — Fn on an Apple keyboard, Control+Alt otherwise. An existing
    /// file (default or custom) is never touched, so hot-plugging keyboards
    /// later can't change a shortcut already chosen. Returns true if seeded.
    @discardableResult
    public func seedFirstRunShortcut(hasAppleFnKey: Bool) throws -> Bool {
        guard !fileManager.fileExists(atPath: fileURL.path) else { return false }
        var cfg = try load()
        cfg.shortcuts.refine = hasAppleFnKey ? "Fn" : "Control+Alt"
        try save(cfg)
        return true
    }

    // MARK: - Test helpers

    #if DEBUG
    /// In-memory-style store backed by a unique temp file. Test-only.
    public static func inMemory() -> ConfigStore {
        ConfigStore(fileURL: URL(fileURLWithPath: "/tmp/voicetype-test-\(UUID().uuidString).json"))
    }
    #endif

    private func atomicWrite(_ cfg: AppConfig) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(cfg)

        let tmpURL = fileURL.appendingPathExtension("tmp")

        // 1) Write bytes to .tmp.
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: tmpURL)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
        // 2) fsync so bytes are durable before rename.
        try handle.synchronize()
        try handle.close()

        // 3) Atomic rename. POSIX rename(2) replaces the destination atomically on
        //    the same filesystem.
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: tmpURL)
        } else {
            try fileManager.moveItem(at: tmpURL, to: fileURL)
        }
    }
}
