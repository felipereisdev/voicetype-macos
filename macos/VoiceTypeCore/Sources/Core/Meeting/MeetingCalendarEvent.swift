import Foundation

/// The calendar invite a recording happened during: its title and who was
/// invited (names only; the user is left out — they're "Você"). Read from the
/// Mac's Calendar (EventKit) app-side; this is the plain, testable shape.
///
/// Untrusted: an external invite's title/names are third-party text, so they
/// reach the summarizer only as data on stdin, never in the instruction.
public struct MeetingCalendarEvent: Codable, Sendable, Equatable {
    public var title: String
    public var start: Date
    public var end: Date
    public var organizer: String?
    /// Every named invitee except the user, organizer included.
    public var participants: [String]

    public init(title: String, start: Date, end: Date, organizer: String? = nil, participants: [String] = []) {
        self.title = title
        self.start = start
        self.end = end
        self.organizer = organizer
        self.participants = participants
    }

    /// The event the recording `[start, end]` belongs to: the one it overlaps
    /// the most. Nil when nothing overlaps or two events overlap it about as
    /// much (within a minute) — better no invite than the wrong one.
    /// Callers drop all-day, cancelled and declined events beforehand.
    public static func match(_ events: [MeetingCalendarEvent], start: Date, end: Date) -> MeetingCalendarEvent? {
        func overlap(_ e: MeetingCalendarEvent) -> TimeInterval {
            min(end, e.end).timeIntervalSince(max(start, e.start))
        }
        let ranked = events.map { ($0, overlap($0)) }.filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }
        guard let best = ranked.first else { return nil }
        if ranked.count > 1, best.1 - ranked[1].1 < 60 { return nil }
        return best.0
    }

    /// Stdin block for the summarizer, sent before the transcript.
    /// `<`/`>` are dropped so an invite can't close the tag early.
    public var promptData: String {
        func clean(_ s: String) -> String { MeetingNoteRenderer.singleLine(s.filter { $0 != "<" && $0 != ">" }) }
        var lines = ["título: \(clean(title))"]
        if let organizer { lines.append("organizador: \(clean(organizer))") }
        if !participants.isEmpty { lines.append("convidados: \(participants.map(clean).joined(separator: "; "))") }
        return "<convite>\n" + lines.joined(separator: "\n") + "\n</convite>\n"
    }
}
