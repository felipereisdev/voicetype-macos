import Testing
import Foundation
@testable import Core

@Suite("DailyNote")
struct DailyNoteTests {
    let utc = TimeZone(identifier: "UTC")!
    // 2026-10-14 14:32:00 UTC
    let date = Date(timeIntervalSince1970: 1_791_988_320)

    @Test func createsNoteWhenMissing() {
        let out = DailyNote.inserting("Ideia nova", at: date, into: nil, timeZone: utc)
        #expect(out == """
        ---
        type: daily
        date: 2026-10-14
        tags: [daily]
        ---

        ## Ideias

        - 14:32 Ideia nova

        """)
    }

    @Test func appendsSectionWhenAbsent() {
        let existing = "# 2026-10-14\n\nTexto meu.\n\n\n"
        let out = DailyNote.inserting("x", at: date, into: existing, timeZone: utc)
        #expect(out == "# 2026-10-14\n\nTexto meu.\n\n## Ideias\n\n- 14:32 x\n")
    }

    @Test func appendsAtEndOfSectionInTheMiddle() {
        let existing = """
        # Dia

        ## Ideias

        - 09:00 primeira
          ### sub
          continuação

        ## Tarefas

        - [ ] algo

        """
        let out = DailyNote.inserting("segunda", at: date, into: existing, timeZone: utc)
        #expect(out == """
        # Dia

        ## Ideias

        - 09:00 primeira
          ### sub
          continuação
        - 14:32 segunda

        ## Tarefas

        - [ ] algo

        """)
    }

    @Test func fillsEmptySectionAndKeepsNextHeading() {
        let existing = "## Ideias\n\n## Tarefas\n"
        let out = DailyNote.inserting("a", at: date, into: existing, timeZone: utc)
        #expect(out == "## Ideias\n\n- 14:32 a\n\n## Tarefas\n")
    }

    @Test func appendsAtEndOfFileSectionWithoutTrailingNewline() {
        let out = DailyNote.inserting("b", at: date, into: "## Ideias\n\n- 10:00 a", timeZone: utc)
        #expect(out == "## Ideias\n\n- 10:00 a\n- 14:32 b\n")
    }

    @Test func multiLineIndentsContinuationAndDropsBlankLines() {
        let out = DailyNote.inserting("linha um\n\n  linha dois\n## não é seção", at: date, into: "## Ideias\n", timeZone: utc)
        #expect(out == "## Ideias\n\n- 14:32 linha um\n  linha dois\n  ## não é seção\n")
        // The indented "## " line must not count as a section break on the next append.
        let again = DailyNote.inserting("três", at: date, into: out, timeZone: utc)
        #expect(again.hasSuffix("  ## não é seção\n- 14:32 três\n"))
    }

    @Test func keepsSpecialCharactersVerbatim() {
        let text = #"Ação "aspas" & <tag> #ideia [[Link]] \ $x: --- *ênfase*"#
        let out = DailyNote.inserting(text, at: date, into: "## Ideias\n", timeZone: utc)
        #expect(out == "## Ideias\n\n- 14:32 \(text)\n")
    }

    @Test func emptyTextLeavesFileUntouched() {
        #expect(DailyNote.inserting("  \n ", at: date, into: "conteúdo", timeZone: utc) == "conteúdo")
    }

    @Test func linkUsesFileNameAndSafeAlias() {
        let url = URL(fileURLWithPath: "/v/Ideas/2026/2026-10-14 1432 Venda B2B.md")
        #expect(DailyNote.link(to: url, title: "Venda | B2B]]") == "[[2026-10-14 1432 Venda B2B|Venda B2B]]")
        let out = DailyNote.inserting(DailyNote.link(to: url, title: "Venda B2B"), at: date, into: "## Ideias\n", timeZone: utc)
        #expect(out == "## Ideias\n\n- 14:32 [[2026-10-14 1432 Venda B2B|Venda B2B]]\n")
    }

    @Test func appendWritesUnderDailyYearFolder() throws {
        let vault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vault) }

        let url = try DailyNote.append("um", at: date, to: vault, timeZone: utc)
        #expect(url.path.hasSuffix("/Daily/2026/2026-10-14.md"))
        try DailyNote.append("dois", at: date.addingTimeInterval(60), to: vault, timeZone: utc)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasSuffix("## Ideias\n\n- 14:32 um\n- 14:33 dois\n"))
    }
}
