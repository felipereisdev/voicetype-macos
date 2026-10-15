import Foundation

/// A dictionary term learned from a user edit (#50), awaiting review.
/// Nothing reaches `vocabularyKeywords` until the user approves it.
public struct LearnedSuggestion: Codable, Equatable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        /// Kept (hidden) only so the same pair is never suggested again.
        case rejected
    }

    public let id: UUID
    public let original: String
    public let corrected: String
    public let createdAt: Date
    public var status: Status

    public init(id: UUID = UUID(), original: String, corrected: String, createdAt: Date = Date(), status: Status = .pending) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.createdAt = createdAt
        self.status = status
    }

    func samePair(_ s: EditSubstitution) -> Bool {
        original.caseInsensitiveCompare(s.original) == .orderedSame
            && corrected.caseInsensitiveCompare(s.corrected) == .orderedSame
    }

    /// `vocabulary` with `term` appended on its own line, unless already listed.
    public static func vocabulary(_ vocabulary: String, adding term: String) -> String {
        let exists = Transcriber.terms(from: vocabulary).contains { $0.caseInsensitiveCompare(term) == .orderedSame }
        if exists { return vocabulary }
        let trimmed = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? term : trimmed + "\n" + term
    }
}

/// Persists learned suggestions (pending + rejected) at
/// `~/Library/Application Support/VoiceType/suggestions.json`, atomic write.
public actor SuggestionStore {
    public static let cap = 200

    private let fileURL: URL
    private var items: [LearnedSuggestion] = []
    private var loaded = false

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("VoiceType", isDirectory: true)
            .appendingPathComponent("suggestions.json", isDirectory: false)
    }

    /// Adds new pairs as pending; pairs already pending or rejected are skipped.
    public func add(_ subs: [EditSubstitution]) {
        ensureLoaded()
        let fresh = subs.filter { s in !items.contains { $0.samePair(s) } }
        guard !fresh.isEmpty else { return }
        items.insert(contentsOf: fresh.map { LearnedSuggestion(original: $0.original, corrected: $0.corrected) }, at: 0)
        if items.count > Self.cap { items.removeLast(items.count - Self.cap) }
        persist()
    }

    public func pending() -> [LearnedSuggestion] {
        ensureLoaded()
        return items.filter { $0.status == .pending }
    }

    public func reject(id: UUID) {
        ensureLoaded()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        items[i].status = .rejected
        persist()
    }

    /// Removes the entry outright (approved, or deleted by the user).
    public func remove(id: UUID) {
        ensureLoaded()
        let before = items.count
        items.removeAll { $0.id == id }
        if items.count != before { persist() }
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? Data(contentsOf: fileURL)).flatMap { try? decoder.decode([LearnedSuggestion].self, from: $0) } ?? []
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(items).write(to: fileURL, options: .atomic)
        } catch {
            print("[SuggestionStore] persist failed: \(error)")
        }
    }
}
