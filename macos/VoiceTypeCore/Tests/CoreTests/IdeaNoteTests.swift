import Testing
import Foundation
@testable import Core

@Suite("IdeaNote")
struct IdeaNoteTests {
    let utc = TimeZone(identifier: "UTC")!
    // 2026-10-14 14:32:00 UTC
    let date = Date(timeIntervalSince1970: 1_791_988_320)
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000079")!

    @Test func sanitizesTags() {
        #expect(IdeaNote.sanitizeTags(["Negócios B2B", " idea ", "2026", "negocios-b2b", "IA/ML", "x", "y"])
            == ["negocios-b2b", "ia-ml", "x"])
        #expect(IdeaNote.sanitizeTags(["--", ""]) == [])
    }

    @Test func validatesAndCapsTitle() throws {
        let p = IdeaNote.Polished(title: "um dois\ntrês quatro cinco seis sete oito nove", text: "  texto \n", tags: ["A B"])
        let idea = try IdeaNote.validated(p, original: "orig", at: date, id: id)
        #expect(idea.title == "um dois três quatro cinco seis sete oito")
        #expect(idea.text == "texto")
        #expect(idea.tags == ["a-b"])
        #expect(throws: IdeaNote.ValidationError.emptyText) {
            try IdeaNote.validated(.init(title: "t", text: " \n", tags: []), original: "", at: date)
        }
        #expect(throws: IdeaNote.ValidationError.emptyTitle) {
            try IdeaNote.validated(.init(title: "[[ ]]", text: "x", tags: []), original: "", at: date)
        }
    }

    @Test func rendersNote() {
        let idea = IdeaNote(id: id, createdAt: date, title: #"Venda "B2B" por encomenda"#,
                            text: "Tive uma ideia: vender B2B por encomenda.", tags: ["vendas", "b2b"],
                            original: "tem uma ideia vender btubi em comenda\n")
        #expect(idea.baseName(timeZone: utc) == "2026-10-14 1432 Venda B2B por encomenda")
        #expect(idea.render(timeZone: utc) == """
        ---
        id: 00000000-0000-0000-0000-000000000079
        type: idea
        title: "Venda \\"B2B\\" por encomenda"
        date: 2026-10-14
        created: 2026-10-14T14:32:00+00:00
        tags: [idea, vendas, b2b]
        ---

        Tive uma ideia: vender B2B por encomenda.

        ## Transcrição original

        tem uma ideia vender btubi em comenda

        """)
    }

    @Test func writesUnderIdeasYearAndHandlesCollisions() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vault) }
        let idea = IdeaNote(id: id, createdAt: date, title: "Ideia", text: "a", original: "a")

        let url = try idea.write(to: vault, timeZone: utc)
        #expect(url.path.hasSuffix("/Ideas/2026/2026-10-14 1432 Ideia.md"))
        #expect(try idea.write(to: vault, timeZone: utc) == url) // same id: idempotent
        let other = IdeaNote(createdAt: date, title: "Ideia", text: "b", original: "b")
        #expect(try other.write(to: vault, timeZone: utc).lastPathComponent == "2026-10-14 1432 Ideia (2).md")
    }
}
