import Foundation
import Testing
@testable import Core

@Suite("OKInbox")
struct OKInboxTests {
    private let utc = TimeZone(identifier: "UTC")!
    // 2026-10-14 14:32:00 UTC
    private let date = Date(timeIntervalSince1970: 1_791_988_320)
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000079")!

    private func makeVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: vault.appendingPathComponent(".ok"), withIntermediateDirectories: true)
        return vault
    }

    private func idea(title: String = "Venda B2B por encomenda", id: UUID? = nil) -> IdeaNote {
        IdeaNote(id: id ?? self.id, createdAt: date, title: title,
                 text: "Tive uma ideia: vender B2B por encomenda.\nSegunda linha.", tags: ["vendas", "ideia"],
                 original: "tem uma ideia vender btubi em comenda\n")
    }

    @Test func ideaRendersOKFrontmatterAndLandsInInbox() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = try OKInbox.writeIdea(idea(), to: vault, timeZone: utc)
        #expect(url.path.hasSuffix("_inbox/ideias/2026-10-14-venda-b2b-por-encomenda.md"))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(OKFrontmatter.scalar("type", in: text) == "ideia")
        #expect(OKFrontmatter.scalar("description", in: text) == "Tive uma ideia: vender B2B por encomenda.")
        #expect(FileManager.default.fileExists(atPath: vault.appendingPathComponent("_inbox/.ok/frontmatter.yml").path))
    }

    @Test func rendersIdea() {
        #expect(OKInbox.renderIdea(idea(title: #"Venda "B2B""#), timeZone: utc) == """
        ---
        id: 00000000-0000-0000-0000-000000000079
        title: "Venda \\"B2B\\""
        description: "Tive uma ideia: vender B2B por encomenda."
        type: ideia
        date: 2026-10-14
        created: 2026-10-14T14:32:00+00:00
        tags: [ideia, vendas]
        ---

        Tive uma ideia: vender B2B por encomenda.
        Segunda linha.

        ## Transcrição original

        tem uma ideia vender btubi em comenda

        """)
    }

    @Test func descriptionIsCappedAndQuoted() {
        var long = idea()
        long.text = "  \n" + String(repeating: "é\"", count: 100) + "\nfim"
        let text = OKInbox.renderIdea(long, timeZone: utc)
        #expect(OKFrontmatter.isWellFormed(text))
        #expect(OKFrontmatter.scalar("description", in: text) == String(String(repeating: "é\"", count: 100).prefix(160)))
    }

    @Test func ideaFileNameFallsBackAndNeverOverwritesAnotherIdea() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let first = try OKInbox.writeIdea(idea(title: "✨✨"), to: vault, timeZone: utc)
        #expect(first.lastPathComponent == "2026-10-14-ideia.md")
        #expect(try OKInbox.writeIdea(idea(title: "✨✨"), to: vault, timeZone: utc) == first) // same id: idempotent
        let other = try OKInbox.writeIdea(idea(title: "!!!", id: UUID()), to: vault, timeZone: utc)
        #expect(other.lastPathComponent == "2026-10-14-ideia-2.md")
    }

    @Test func dailyGetsOKHeaderAndRelativeLink() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let ideaURL = try OKInbox.writeIdea(idea(), to: vault, timeZone: utc)
        let daily = try OKInbox.appendToDaily(OKInbox.link(toIdea: ideaURL, title: "Venda [B2B]", vault: vault),
                                              at: date, to: vault, timeZone: utc)
        #expect(daily == OKInbox.dailyURL(in: vault, for: date, timeZone: utc))
        #expect(daily.path.hasSuffix("_inbox/diario/2026-10-14.md"))
        let text = try String(contentsOf: daily, encoding: .utf8)
        #expect(text == """
        ---
        title: "Diário 2026-10-14"
        description: "Notas de voz de 2026-10-14."
        type: diario
        date: 2026-10-14
        tags: [diario]
        ---

        ## Ideias

        - 14:32 [Venda B2B](../ideias/2026-10-14-venda-b2b-por-encomenda.md)

        """)
        #expect(!text.contains("[["))
    }

    @Test func linkStripsBracketsAndParentheses() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let url = vault.appendingPathComponent("_inbox/ideias/2026-10-14-x.md")
        #expect(OKInbox.link(toIdea: url, title: "a (b) [c]\nd", vault: vault) == "[a b c d](../ideias/2026-10-14-x.md)")
        #expect(OKInbox.link(toIdea: url, title: "[]()", vault: vault) == "[ideia](../ideias/2026-10-14-x.md)")
    }

    @Test func dailyAppendsToExistingNoteWithoutTouchingIt() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try OKInbox.appendToDaily("primeira", at: date, to: vault, timeZone: utc)
        let daily = try OKInbox.appendToDaily("segunda\nlinha", at: date.addingTimeInterval(60), to: vault, timeZone: utc)
        let text = try String(contentsOf: daily, encoding: .utf8)
        #expect(text.hasSuffix("## Ideias\n\n- 14:32 primeira\n- 14:33 segunda\n  linha\n"))
        #expect(text.components(separatedBy: "type: diario").count == 2)
    }

    @Test func inboxMetadataIsCreatedOnce() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try OKInbox.appendToDaily("x", at: date, to: vault, timeZone: utc)
        let meta = vault.appendingPathComponent("_inbox/.ok/frontmatter.yml")
        #expect(try String(contentsOf: meta, encoding: .utf8)
            == "title: Inbox\ndescription: Notas de voz do VoiceType (diário e ideias), fora dos projetos.\ntags:\n  - inbox\n")
        let staging = vault.appendingPathComponent(".ok/local/voicetype-staging")
        #expect((try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? [] == [])
    }

    @Test func inboxMetadataIsNeverOverwritten() throws {
        let vault = try makeVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let meta = vault.appendingPathComponent("_inbox/.ok/frontmatter.yml")
        try FileManager.default.createDirectory(at: meta.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("title: Meu\n".utf8).write(to: meta)
        try OKInbox.writeIdea(idea(), to: vault, timeZone: utc)
        try OKInbox.appendToDaily("x", at: date, to: vault, timeZone: utc)
        #expect(try String(contentsOf: meta, encoding: .utf8) == "title: Meu\n")
    }

    @Test func obsidianDailyHeaderUnchanged() {
        #expect(DailyNote.inserting("Ideia nova", at: date, into: nil, timeZone: utc) == """
        ---
        type: daily
        date: 2026-10-14
        tags: [daily]
        ---

        ## Ideias

        - 14:32 Ideia nova

        """)
        #expect(DailyNote.inserting("Ideia nova", at: date, into: nil, timeZone: utc, newFileHeader: "# H\n\n")
            == "# H\n\n## Ideias\n\n- 14:32 Ideia nova\n")
        #expect(DailyNote.inserting("x", at: date, into: "# Meu\n", timeZone: utc, newFileHeader: "# H\n\n")
            == "# Meu\n\n## Ideias\n\n- 14:32 x\n")
    }
}
