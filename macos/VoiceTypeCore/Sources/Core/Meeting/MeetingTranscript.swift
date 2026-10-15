import Foundation

// Turns the per-track ASR output of a meeting into the merged
// "[mm:ss] Você: …" / "[mm:ss] Outros: …" transcript fed to the summarizer.
// Pure: no WhisperKit, no I/O beyond the JSON checkpoint helpers.

/// One ASR segment, already placed on the meeting clock.
public struct MeetingUtterance: Codable, Sendable, Equatable {
    public var track: MeetingTrack
    /// Seconds since `MeetingManifest.startedAt`.
    public var start: Double
    public var end: Double
    public var text: String
    public var compressionRatio: Double

    public init(track: MeetingTrack, start: Double, end: Double, text: String, compressionRatio: Double = 0) {
        self.track = track
        self.start = start
        self.end = end
        self.text = text
        self.compressionRatio = compressionRatio
    }
}

public enum MeetingTranscript {
    /// Lowercased words without punctuation — shared by the hallucination and echo checks.
    public static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Strips Whisper special tokens (`<|en|>`, `<|0.00|>`, ...) and trims.
    public static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|]*\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper's silence fillers (#74 spike 4): RMS can't separate them, these
    /// three text-level rules took ~200 mic segments down to ~10 real ones.
    public static func isHallucination(_ u: MeetingUtterance) -> Bool {
        let words = tokens(clean(u.text))
        if words.isEmpty { return true }
        if u.compressionRatio > 2.4 { return true }
        if words.count >= 6, Double(Set(words).count) / Double(words.count) < 0.3 { return true }
        // "E aí" / "Thank you" stretched over a whole window of silence.
        if u.end - u.start > 4, words.count <= 2 { return true }
        return false
    }

    /// Fraction of `mic`'s distinct words that also appear in `system`.
    /// Measured from the mic side (not Jaccard): an echo segment is often a
    /// slice of a longer system segment, and Jaccard would punish that.
    public static func echoScore(mic: String, system: String) -> Double {
        let m = Set(tokens(mic))
        guard !m.isEmpty else { return 0 }
        return Double(m.intersection(tokens(system)).count) / Double(m.count)
    }

    /// Drops mic segments that are just the speakers leaking into the mic
    /// (#74 spike 2: without AEC the mic transcript repeats the system one).
    /// ponytail: per-segment word containment; a genuine one-word reply that
    /// happens to be inside an overlapping system segment is dropped too.
    /// Upgrade path is real AEC (VPIO / WebRTC APM) on the mic track.
    public static func removeEcho(
        mic: [MeetingUtterance], system: [MeetingUtterance],
        window: Double = 2, threshold: Double = 0.6
    ) -> [MeetingUtterance] {
        mic.filter { m in
            // Union of every overlapping system segment: Whisper often splits a
            // sentence at a different point on each track ("…dias na" | "semana…").
            let nearby = system
                .filter { m.start <= $0.end + window && m.end >= $0.start - window }
                .map(\.text).joined(separator: " ")
            return echoScore(mic: m.text, system: nearby) < threshold
        }
    }

    /// Hallucination filter → echo dedupe → time-ordered, cleaned utterances.
    public static func process(_ utterances: [MeetingUtterance]) -> [MeetingUtterance] {
        let kept = utterances
            .filter { !isHallucination($0) }
            .map { u -> MeetingUtterance in var u = u; u.text = clean(u.text); return u }
        let system = kept.filter { $0.track == .system }
        let mic = removeEcho(mic: kept.filter { $0.track == .mic }, system: system)
        return (system + mic).sorted { ($0.start, $0.track == .mic ? 1 : 0) < ($1.start, $1.track == .mic ? 1 : 0) }
    }

    /// `[mm:ss] Você: …` lines, consecutive turns of the same speaker coalesced.
    /// Input must already be processed (clean + ordered).
    public static func render(_ utterances: [MeetingUtterance]) -> String {
        var lines: [String] = []
        var last: MeetingTrack?
        for u in utterances {
            if u.track == last, !lines.isEmpty {
                lines[lines.count - 1] += " " + u.text
            } else {
                let s = max(0, Int(u.start))
                let speaker = u.track == .mic ? "Você" : "Outros"
                lines.append(String(format: "[%02d:%02d] %@: %@", s / 60, s % 60, speaker, u.text))
            }
            last = u.track
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Checkpoints

/// Progress of the post-capture pipeline, persisted next to the manifest so a
/// crash / quit / sleep never forces re-transcribing (#74 spike 5).
public struct MeetingPipelineState: Codable, Sendable, Equatable {
    public static let transcriptFileName = "transcript.json"
    public static let stateFileName = "pipeline.json"

    /// Stable across retries so the note writer overwrites instead of duplicating.
    public var noteID: UUID
    public var notePath: String?
    public var transcriptPath: String?
    /// False when the note was written with "Resumo indisponível" — a reprocess
    /// should try the summary again.
    public var summarized: Bool

    public init(noteID: UUID = UUID(), notePath: String? = nil, transcriptPath: String? = nil, summarized: Bool = false) {
        self.noteID = noteID
        self.notePath = notePath
        self.transcriptPath = transcriptPath
        self.summarized = summarized
    }
}
