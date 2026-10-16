import Foundation

// Structured meeting summary produced by an LLM (Claude CLI, FoundationModels,
// ...) from a finished transcript. The JSON shape is the contract with the
// provider: `jsonSchema` is passed to it verbatim, and `validated()` re-checks
// the decoded value app-side because providers do not always honor the schema.
public struct MeetingSummary: Codable, Sendable, Equatable {
    public struct ActionItem: Codable, Sendable, Equatable {
        public var task: String
        public var owner: String?
        /// ISO `YYYY-MM-DD`, resolved by the model from the meeting date;
        /// anything else is dropped by `validated`.
        public var dueDate: String?

        public init(task: String, owner: String? = nil, dueDate: String? = nil) {
            self.task = task
            self.owner = owner
            self.dueDate = dueDate
        }
    }

    /// "Outro 2 is probably Ana Silva": a guess from what was said, only
    /// ever a calendar invitee. Optional so older/fallback JSON still decodes.
    public struct SpeakerGuess: Codable, Sendable, Equatable {
        public var label: String
        public var name: String

        public init(label: String, name: String) {
            self.label = label
            self.name = name
        }
    }

    public var title: String
    public var summary: String
    public var decisions: [String]
    public var actionItems: [ActionItem]
    /// Canonical `MeetingOrg.name`, or nil.
    public var org: String?
    /// Canonical `MeetingClient.name` of `org`, or nil.
    public var client: String?
    /// One of `meetingTypes`, or nil.
    public var meetingType: String?
    /// Nil or empty = no guesses.
    public var speakers: [SpeakerGuess]?

    public static let meetingTypes = [
        "standup", "sprint_review", "planning", "refinement", "alignment",
        "one_on_one", "client_meeting", "interview", "other",
    ]

    public init(
        title: String, summary: String, decisions: [String] = [], actionItems: [ActionItem] = [],
        org: String? = nil, client: String? = nil, meetingType: String? = nil,
        speakers: [SpeakerGuess]? = nil
    ) {
        self.title = title
        self.summary = summary
        self.decisions = decisions
        self.actionItems = actionItems
        self.org = org
        self.client = client
        self.meetingType = meetingType
        self.speakers = speakers
    }

    public enum ValidationError: Error, Sendable, Equatable {
        case emptyTitle
        case emptySummary
    }

    /// Trims every field, drops empty list entries and blank optionals,
    /// normalizes org/client against `orgs`, drops unknown meeting types and
    /// non-ISO due dates, and speaker guesses that aren't an "Outro N" label
    /// matched to one of `invitees` (first guess per label/name wins).
    /// Throws when the two mandatory fields are blank.
    public func validated(orgs: [MeetingOrg], invitees: [String] = []) throws -> MeetingSummary {
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        func cleanOptional(_ s: String?) -> String? {
            guard let s else { return nil }
            let c = clean(s)
            return c.isEmpty ? nil : c
        }

        let title = clean(title)
        let summary = clean(summary)
        guard !title.isEmpty else { throw ValidationError.emptyTitle }
        guard !summary.isEmpty else { throw ValidationError.emptySummary }

        let resolved = MeetingOrg.resolve(org: org, client: client, in: orgs)
        let type = cleanOptional(meetingType)?.lowercased()
        var labels = Set<String>(), names = Set<String>()
        let guesses = (speakers ?? []).compactMap { g -> SpeakerGuess? in
            let label = clean(g.label), name = clean(g.name)
            guard label.wholeMatch(of: #/Outro [1-9][0-9]*/#) != nil, invitees.contains(name),
                  !labels.contains(label), !names.contains(name) else { return nil }
            labels.insert(label)
            names.insert(name)
            return SpeakerGuess(label: label, name: name)
        }
        return MeetingSummary(
            title: title,
            summary: summary,
            decisions: decisions.map(clean).filter { !$0.isEmpty },
            actionItems: actionItems.compactMap { item in
                let task = clean(item.task)
                guard !task.isEmpty else { return nil }
                return ActionItem(task: task, owner: cleanOptional(item.owner), dueDate: cleanOptional(item.dueDate).flatMap(Self.isoDay))
            },
            org: resolved.org,
            client: resolved.client,
            meetingType: type.flatMap { Self.meetingTypes.contains($0) ? $0 : nil },
            speakers: guesses.isEmpty ? nil : guesses
        )
    }

    /// `value` if it is a real calendar day in `YYYY-MM-DD` (rejects 2026-02-30).
    static func isoDay(_ value: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        guard value.count == 10, let date = f.date(from: value), f.string(from: date) == value else { return nil }
        return value
    }

    /// JSON Schema handed to the provider (e.g. `claude -p --json-schema`).
    /// org/client are enums of the catalog's canonical names (or null);
    /// speaker names are an enum of `invitees` (no invitees = no guesses).
    public static func jsonSchema(orgs: [MeetingOrg], invitees: [String] = []) -> String {
        func nullableEnum(_ values: [String]) -> [String: Any] {
            ["type": ["string", "null"], "enum": values.map { $0 as Any } + [NSNull()]]
        }
        let actionItem: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["task"],
            "properties": [
                "task": ["type": "string"],
                "owner": ["type": ["string", "null"]],
                "dueDate": ["type": ["string", "null"], "pattern": "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"],
            ],
        ]
        let speaker: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["label", "name"],
            "properties": [
                "label": ["type": "string", "pattern": "^Outro [1-9][0-9]*$"],
                "name": ["type": "string", "enum": invitees],
            ],
        ]
        let speakers: [String: Any] = invitees.isEmpty
            ? ["type": "array", "maxItems": 0]
            : ["type": "array", "items": speaker]
        let schema: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["title", "summary", "decisions", "actionItems", "org", "client", "meetingType", "speakers"],
            "properties": [
                "title": ["type": "string"],
                "summary": ["type": "string"],
                "decisions": ["type": "array", "items": ["type": "string"]],
                "actionItems": ["type": "array", "items": actionItem],
                "org": nullableEnum(orgs.map(\.name)),
                "client": nullableEnum(orgs.flatMap { $0.clients.map(\.name) }),
                "meetingType": nullableEnum(meetingTypes),
                "speakers": speakers,
            ],
        ]
        // Only literals above: serialization cannot fail.
        let data = try! JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
}
