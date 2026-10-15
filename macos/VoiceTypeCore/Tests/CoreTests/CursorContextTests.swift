import Testing
import Foundation
@testable import Core

@Suite("CursorContext")
struct CursorContextTests {

    @Test func splitsValueAroundSelection() throws {
        let ctx = try #require(CursorContext.from(value: "Olá mundo bonito", selectedRange: NSRange(location: 4, length: 5)))
        #expect(ctx.before == "Olá ")
        #expect(ctx.selected == "mundo")
        #expect(ctx.after == " bonito")
    }

    @Test func caretWithoutSelection() throws {
        let ctx = try #require(CursorContext.from(value: "abc def", selectedRange: NSRange(location: 3, length: 0)))
        #expect(ctx.before == "abc")
        #expect(ctx.selected == "")
        #expect(ctx.after == " def")
    }

    @Test func outOfBoundsRangeIsNil() {
        #expect(CursorContext.from(value: "abc", selectedRange: NSRange(location: 10, length: 0)) == nil)
        #expect(CursorContext.from(value: "abc", selectedRange: NSRange(location: 2, length: 5)) == nil)
        #expect(CursorContext.from(value: "abc", selectedRange: NSRange(location: NSNotFound, length: 0)) == nil)
    }

    @Test func utf16OffsetsHandleEmojiAndAccents() throws {
        // "👍🏽" is 4 UTF-16 units; "é" is 1. AX ranges are UTF-16.
        let value = "oi 👍🏽 é"
        let ctx = try #require(CursorContext.from(value: value, selectedRange: NSRange(location: 3, length: 4)))
        #expect(ctx.before == "oi ")
        #expect(ctx.selected == "👍🏽")
        #expect(ctx.after == " é")
    }

    @Test func emptyFieldIsNil() {
        #expect(CursorContext.from(value: "", selectedRange: NSRange(location: 0, length: 0)) == nil)
    }

    // MARK: - Truncation at word boundaries

    @Test func beforeIsCutAtTheFarEndOnAWordBoundary() {
        let before = String(repeating: "palavra ", count: 100) + "fim"   // 803 chars
        let ctx = CursorContext(before: before, selected: "", after: "")
        #expect(ctx.before.count <= CursorContext.maxChars)
        #expect(ctx.before.hasSuffix("fim"))
        #expect(ctx.before.hasPrefix("palavra"))   // no half word at the far end
    }

    @Test func afterIsCutAtTheFarEndOnAWordBoundary() {
        let after = "início " + String(repeating: "ação ", count: 200)
        let ctx = CursorContext(before: "", selected: "", after: after)
        #expect(ctx.after.count <= CursorContext.maxChars)
        #expect(ctx.after.hasPrefix("início"))
        #expect(ctx.after.hasSuffix("ação"))
    }

    @Test func emojiNeverSplit() {
        let after = String(repeating: "👍🏽 ", count: 400)
        let ctx = CursorContext(before: after, selected: after, after: after)
        for side in [ctx.before, ctx.selected, ctx.after] {
            #expect(side.count <= CursorContext.maxChars)
            #expect(side.allSatisfy { $0 == "👍🏽" || $0 == " " })
            #expect(!side.isEmpty)
        }
    }

    @Test func shortTextIsUntouched() {
        let ctx = CursorContext(before: "Olá, ", selected: "você", after: " aí")
        #expect(ctx == CursorContext(before: "Olá, ", selected: "você", after: " aí"))
        #expect(ctx.before == "Olá, ")
    }

    @Test func singleHugeWordDropsToEmpty() {
        let ctx = CursorContext(before: String(repeating: "a", count: 900), selected: "", after: "")
        #expect(ctx.before == "")
    }

    @Test func isEmptyWhenAllSidesEmpty() {
        #expect(CursorContext(before: "", selected: "", after: "").isEmpty)
        #expect(!CursorContext(before: "x", selected: "", after: "").isEmpty)
    }
}
