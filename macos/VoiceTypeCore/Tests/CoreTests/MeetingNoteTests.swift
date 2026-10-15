import Testing
import Foundation
@testable import Core

@Suite("MeetingSummary.validated")
struct MeetingSummaryTests {
    @Test func trimsAndDropsEmptyEntries() throws {
        let raw = MeetingSummary(
            title: "  Sprint review \n",
            summary: " ok ",
            decisions: ["  manter prazo ", "  "],
            actionItems: [
                .init(task: " revisar PR ", owner: "  ", dueDate: " 2026-10-16 "),
                .init(task: "   "),
            ]
        )
        let v = try raw.validated(orgs: [])
        #expect(v.title == "Sprint review")
        #expect(v.summary == "ok")
        #expect(v.decisions == ["manter prazo"])
        #expect(v.actionItems == [.init(task: "revisar PR", owner: nil, dueDate: "2026-10-16")])
    }

    @Test func dropsNonISOOrImpossibleDueDates() throws {
        let raw = MeetingSummary(title: "t", summary: "s", actionItems: [
            .init(task: "a", dueDate: "sexta"),
            .init(task: "b", dueDate: "16/10/2026"),
            .init(task: "c", dueDate: "2026-02-30"),
            .init(task: "d", dueDate: "2026-10-16T10:00"),
        ])
        #expect(try raw.validated(orgs: []).actionItems.allSatisfy { $0.dueDate == nil })
    }

    @Test func normalizesOrgClientAndMeetingType() throws {
        func v(_ org: String?, _ client: String?, _ type: String? = nil) throws -> MeetingSummary {
            try MeetingSummary(title: "t", summary: "s", org: org, client: client, meetingType: type)
                .validated(orgs: MeetingOrg.testCatalog)
        }
        let aliased = try v(" ini ", "umbrella corporation", " Sprint_Review ")
        #expect(aliased.org == "Initech")
        #expect(aliased.client == "Umbrella")
        #expect(aliased.meetingType == "sprint_review")
        // Unknown values never become new variants; unknown/null org → Pessoal.
        let unknown = try v("Acme", "Hooli", "brainstorm")
        #expect(unknown.org == "Pessoal" && unknown.client == nil && unknown.meetingType == nil)
        #expect(try v(nil, nil).org == "Pessoal")
        // No fallback org in the catalog → stays nil.
        let noFallback = try MeetingSummary(title: "t", summary: "s", org: nil)
            .validated(orgs: [MeetingOrg(name: "Acme")])
        #expect(noFallback.org == nil)
        // Client must belong to the chosen org.
        let foreign = try v("Pessoal", "Hooli")
        #expect(foreign.org == "Pessoal" && foreign.client == nil)
        #expect(try v("IT", "nope").client == nil)
    }

    @Test func rejectsBlankMandatoryFields() {
        #expect(throws: MeetingSummary.ValidationError.emptyTitle) {
            try MeetingSummary(title: " ", summary: "x").validated(orgs: [])
        }
        #expect(throws: MeetingSummary.ValidationError.emptySummary) {
            try MeetingSummary(title: "x", summary: "\n").validated(orgs: [])
        }
    }

    @Test func schemaEnumsComeFromCatalog() throws {
        let schema = MeetingSummary.jsonSchema(orgs: MeetingOrg.testCatalog)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(schema.utf8)) as? [String: Any])
        #expect(object["type"] as? String == "object")
        let props = try #require(object["properties"] as? [String: [String: Any]])
        let orgs = try #require(props["org"]?["enum"] as? [Any])
        #expect(orgs.compactMap { $0 as? String } == ["Initech", "Pessoal"])
        #expect(orgs.last is NSNull)
        let clients = try #require(props["client"]?["enum"] as? [Any]).compactMap { $0 as? String }
        #expect(clients.contains("Hooli") && clients.contains("Soylent") && !clients.contains("Pessoal"))
        let types = try #require(props["meetingType"]?["enum"] as? [Any]).compactMap { $0 as? String }
        #expect(types == MeetingSummary.meetingTypes)
        #expect((object["required"] as? [String])?.contains("org") == true)
    }
}

@Suite("MeetingNoteRenderer")
struct MeetingNoteRendererTests {
    static let tz = TimeZone(identifier: "America/Sao_Paulo")!
    // 2026-10-14 14:30:00 -03:00
    static let start = Date(timeIntervalSince1970: 1_791_999_000)

    static func note(title: String = "Sprint review", transcript: String? = nil) -> MeetingNote {
        MeetingNote(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            startedAt: start,
            duration: 47 * 60 + 10,
            platform: "teams",
            summary: MeetingSummary(
                title: title,
                summary: "Revisamos a sprint.",
                decisions: ["Manter o prazo"],
                actionItems: [.init(task: "Revisar PR #74", owner: "Mac", dueDate: "2026-10-15"), .init(task: "Atualizar doc")],
                org: "Initech", client: "Hooli", meetingType: "sprint_review"
            ),
            transcript: transcript
        )
    }

    @Test func baseNameIsDatedAndSanitized() {
        let stamp = Self.stampPrefix()
        #expect(MeetingNoteRenderer.baseName(for: Self.note(), timeZone: Self.tz) == "\(stamp) Sprint review")
        #expect(MeetingNoteRenderer.baseName(for: Self.note(title: "a/b: [c]#d|e?\nf"), timeZone: Self.tz) == "\(stamp) a b c d e f")
        #expect(MeetingNoteRenderer.baseName(for: Self.note(title: "...hidden"), timeZone: Self.tz) == "\(stamp) hidden")
        #expect(MeetingNoteRenderer.baseName(for: Self.note(title: "///"), timeZone: Self.tz) == stamp)
    }

    @Test func rendersFrontmatterAndSections() {
        let md = MeetingNoteRenderer.renderNote(Self.note(), transcriptLink: "X — transcrição", timeZone: Self.tz)
        #expect(md.hasPrefix("""
        ---
        id: 11111111-2222-3333-4444-555555555555
        type: meeting
        title: "Sprint review"
        date: 2026-10-14
        created: 2026-10-14T14:30:00-03:00
        duration_minutes: 47
        platform: "teams"
        org: "[[Initech]]"
        client: "Hooli"
        meeting_type: sprint_review
        transcript: "[[X — transcrição]]"
        tags: [meeting]
        ---

        # Sprint review

        ## Resumo

        Revisamos a sprint.

        """))
        #expect(md.contains("## Decisões\n\n- Manter o prazo\n"))
        #expect(md.contains("- [ ] Revisar PR #74 [owner:: Mac] [due:: 2026-10-15]\n- [ ] Atualizar doc\n"))
        #expect(md.contains("## Transcrição\n\n[[X — transcrição]]\n"))
    }

    @Test func omitsEmptySectionsAndUnclassifiedFields() {
        var n = Self.note()
        n.summary.decisions = []
        n.summary.actionItems = []
        n.summary.org = nil
        n.summary.client = nil
        n.summary.meetingType = nil
        n.platform = nil
        let md = MeetingNoteRenderer.renderNote(n, timeZone: Self.tz)
        #expect(!md.contains("## Decisões"))
        #expect(!md.contains("## Action items"))
        #expect(!md.contains("## Transcrição"))
        for key in ["org:", "client:", "meeting_type:", "transcript:", "platform:"] {
            #expect(!md.contains("\n\(key)"), "unexpected \(key)")
        }
    }

    @Test func taskLineOnlyCarriesPresentFields() {
        #expect(MeetingNoteRenderer.taskLine(.init(task: "a\nb")) == "- [ ] a b")
        #expect(MeetingNoteRenderer.taskLine(.init(task: "a", owner: "Ana")) == "- [ ] a [owner:: Ana]")
        #expect(MeetingNoteRenderer.taskLine(.init(task: "a", dueDate: "2026-10-16")) == "- [ ] a [due:: 2026-10-16]")
    }

    @Test func rendersTranscriptLinkingBackToNote() {
        let md = MeetingNoteRenderer.renderTranscript(Self.note(), transcript: "Você: oi", noteLink: "N", timeZone: Self.tz)
        #expect(md.hasPrefix("""
        ---
        id: 11111111-2222-3333-4444-555555555555
        type: transcript
        meeting: "[[N]]"
        date: 2026-10-14
        tags: [transcript]
        ---

        """))
        #expect(md.hasSuffix("Você: oi\n"))
    }

    @Test func orgIndexQueriesMeetingsLinkingToIt() {
        let md = MeetingNoteRenderer.renderOrgIndex(org: "Initech")
        #expect(md.contains("# Initech\n"))
        #expect(md.contains("```dataview\nTABLE rows.file.link AS \"Reunião\", rows.date AS \"Data\", rows.meeting_type AS \"Tipo\"\nFROM \"Meetings\"\nWHERE org = this.file.link\nSORT date DESC\nGROUP BY client\n```"))
        #expect(md.contains("```dataview\nTASK\nFROM \"Meetings\"\nWHERE !completed AND org = this.file.link\n```"))
    }

    @Test func modelOutputCannotBreakFrontmatter() {
        let md = MeetingNoteRenderer.renderNote(Self.note(title: "x\"\n---\nevil: true \\"), timeZone: Self.tz)
        #expect(md.contains("title: \"x\\\" --- evil: true \\\\\"\n"))
        var n = Self.note()
        n.summary.client = "a\"\nb: c"
        #expect(MeetingNoteRenderer.renderNote(n, timeZone: Self.tz).contains("\nclient: \"a\\\" b: c\"\n"))
        #expect(!md.contains("\nevil: true"))
        #expect(md.contains("# x\" --- evil: true \\\n"))
    }

    static func stampPrefix() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f.string(from: start)
    }
}

@Suite("MeetingNoteWriter")
struct MeetingNoteWriterTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-writer-\(UUID().uuidString)")
    let tz = MeetingNoteRendererTests.tz
    var notesDir: URL { dir.appendingPathComponent("Meetings/2026") }

    @Test func writesNoteAndTranscriptIntoYearFoldersLinkedBothWays() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let written = try MeetingNoteWriter.write(MeetingNoteRendererTests.note(transcript: "Você: oi\nOutros: olá"), to: dir, timeZone: tz)
        let base = MeetingNoteRenderer.baseName(for: MeetingNoteRendererTests.note(), timeZone: tz)
        #expect(written.note == notesDir.appendingPathComponent("\(base).md"))
        #expect(written.transcript == dir.appendingPathComponent("Transcripts/2026/\(base) — transcrição.md"))
        let md = try String(contentsOf: written.note, encoding: .utf8)
        #expect(md.contains("transcript: \"[[\(base) — transcrição]]\""))
        let transcript = try String(contentsOf: written.transcript!, encoding: .utf8)
        #expect(transcript.contains("meeting: \"[[\(base)]]\""))
        #expect(transcript.contains("Você: oi\nOutros: olá"))
    }

    @Test func createsOrgIndexOnceAndNeverOverwrites() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try MeetingNoteWriter.write(MeetingNoteRendererTests.note(), to: dir, timeZone: tz)
        let index = dir.appendingPathComponent("Initech.md")
        #expect(first.orgIndex == index)
        #expect(try String(contentsOf: index, encoding: .utf8) == MeetingNoteRenderer.renderOrgIndex(org: "Initech"))

        try "minha versão".write(to: index, atomically: true, encoding: .utf8)
        let second = try MeetingNoteWriter.write(MeetingNoteRendererTests.note(), to: dir, timeZone: tz)
        #expect(second.orgIndex == nil)
        #expect(try String(contentsOf: index, encoding: .utf8) == "minha versão")

        var unclassified = MeetingNoteRendererTests.note()
        unclassified.id = UUID()
        unclassified.summary.org = nil
        #expect(try MeetingNoteWriter.write(unclassified, to: dir, timeZone: tz).orgIndex == nil)
    }

    @Test func rewriteOfSameMeetingIsIdempotent() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        var note = MeetingNoteRendererTests.note()
        let first = try MeetingNoteWriter.write(note, to: dir, timeZone: tz)
        note.summary.summary = "Versão corrigida."
        let second = try MeetingNoteWriter.write(note, to: dir, timeZone: tz)
        #expect(first.note == second.note)
        #expect(try String(contentsOf: second.note, encoding: .utf8).contains("Versão corrigida."))
        #expect(try FileManager.default.contentsOfDirectory(atPath: notesDir.path).count == 1)
    }

    @Test func differentMeetingWithSameNameGetsSuffix() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try MeetingNoteWriter.write(MeetingNoteRendererTests.note(transcript: "a"), to: dir, timeZone: tz)
        var other = MeetingNoteRendererTests.note(transcript: "b")
        other.id = UUID()
        let second = try MeetingNoteWriter.write(other, to: dir, timeZone: tz)
        #expect(first.note != second.note)
        #expect(second.note.lastPathComponent.hasSuffix(" (2).md"))
        // Each side links to the other's actual (suffixed) name.
        let link = second.note.deletingPathExtension().lastPathComponent
        #expect(try String(contentsOf: second.transcript!, encoding: .utf8).contains("meeting: \"[[\(link)]]\""))
    }

    @Test func doesNotClobberUnrelatedUserFile() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let base = MeetingNoteRenderer.baseName(for: MeetingNoteRendererTests.note(), timeZone: tz)
        let userFile = notesDir.appendingPathComponent("\(base).md")
        try "minhas notas".write(to: userFile, atomically: true, encoding: .utf8)
        let written = try MeetingNoteWriter.write(MeetingNoteRendererTests.note(), to: dir, timeZone: tz)
        #expect(written.note != userFile)
        #expect(try String(contentsOf: userFile, encoding: .utf8) == "minhas notas")
    }
}
