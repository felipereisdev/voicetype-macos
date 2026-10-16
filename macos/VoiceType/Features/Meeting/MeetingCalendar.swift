import Core
import EventKit
import Foundation
import os

/// The calendar invite a meeting happened during, read from the Mac's
/// Calendar (every account added there: Exchange/Outlook, Google, iCloud…).
/// Only reads; never starts or stops a recording.
///
/// Best effort: no access or no clear match returns nil. A match is
/// checkpointed in `calendar.json`; a miss isn't, so a reprocess retries
/// (e.g. after granting access or adding an account).
enum MeetingCalendar {
    static let fileName = "calendar.json"
    private static let log = Logger(subsystem: "VoiceType", category: "meeting-calendar")

    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static func event(for dir: URL, start: Date, end: Date) -> MeetingCalendarEvent? {
        let cacheURL = dir.appendingPathComponent(fileName)
        if let cached = try? JSONDecoder().decode(MeetingCalendarEvent.self, from: Data(contentsOf: cacheURL)) {
            return cached
        }
        guard isAuthorized else { return nil }
        let store = EKEventStore()
        let candidates = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            .filter { !$0.isAllDay && $0.status != .canceled && myStatus($0) != .declined }
            .map(plain)
        guard let event = MeetingCalendarEvent.match(candidates, start: start, end: end) else {
            log.info("no calendar match for \(dir.lastPathComponent, privacy: .public) (\(candidates.count) candidates)")
            return nil
        }
        try? JSONEncoder().encode(event).write(to: cacheURL, options: .atomic)
        log.info("calendar match for \(dir.lastPathComponent, privacy: .public): \(event.participants.count) participants")
        return event
    }

    private static func myStatus(_ event: EKEvent) -> EKParticipantStatus? {
        event.attendees?.first(where: \.isCurrentUser)?.participantStatus
    }

    private static func plain(_ event: EKEvent) -> MeetingCalendarEvent {
        // Rooms/resources aren't people; a nameless invitee shows up as its
        // e-mail, which makes a poor [[link]].
        func name(_ p: EKParticipant?) -> String? {
            guard let p, !p.isCurrentUser, p.participantType == .person || p.participantType == .unknown,
                  let n = p.name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !n.isEmpty, !n.contains("@") else { return nil }
            return n
        }
        let organizer = name(event.organizer)
        var participants: [String] = organizer.map { [$0] } ?? []
        for n in (event.attendees ?? []).compactMap(name) where !participants.contains(n) {
            participants.append(n)
        }
        return MeetingCalendarEvent(
            title: event.title ?? "", start: event.startDate, end: event.endDate,
            organizer: organizer, participants: participants
        )
    }
}
