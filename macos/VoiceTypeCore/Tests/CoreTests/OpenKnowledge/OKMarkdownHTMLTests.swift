import Foundation
import Testing
@testable import Core

@Suite("OKMarkdownHTML")
struct OKMarkdownHTMLTests {

    @Test func escapesHTMLAndDropsUnsafeLinks() {
        let html = OKMarkdownHTML.body("<script>alert(1)</script> [x](javascript:alert(1)) [y](../decisoes/y.md)")
        #expect(!html.contains("<script") && html.contains("&lt;script&gt;"))
        #expect(!html.contains("javascript:") || !html.contains("href=\"javascript"))
        #expect(html.contains("href=\"../decisoes/y.md\""))
    }

    @Test func escapesQuotesAndRefusesOtherSchemes() {
        let html = OKMarkdownHTML.body("Tom & \"Jerry\" 'x' [a](https://ex.com/?a=1&b=\"2\") [b](data:text/html,x) [c](file:///etc/passwd) [d](//evil.com) [e](JavaScript:x)")
        #expect(html.contains("Tom &amp; &quot;Jerry&quot; &#39;x&#39;"))
        #expect(html.contains("href=\"https://ex.com/?a=1&amp;b=&quot;2&quot;\""))
        #expect(!html.contains("href=\"data:") && !html.contains("href=\"file:"))
        #expect(!html.contains("href=\"//evil") && !html.lowercased().contains("href=\"javascript"))
    }

    @Test func rendersTableCalloutTasksAndHeadings() {
        let html = OKMarkdownHTML.body("## Fontes\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n> [!info] Status: **aceita**\n> Linha\n\n- [ ] fazer\n- [x] feito\n")
        #expect(html.contains("<h2>Fontes</h2>") && html.contains("<table>") && html.contains("<td>2</td>"))
        #expect(html.contains("callout-info") && html.contains("<strong>aceita</strong>"))
        #expect(html.contains("☐ fazer") && html.contains("☑ feito"))
    }

    @Test func frontmatterBecomesKeyValueTable() {
        let html = OKMarkdownHTML.body("---\ntitle: X\ntags:\n  - a\n---\n# H")
        #expect(html.contains("<th>title</th><td>X</td>"))
        #expect(html.contains("<th>tags</th>") && html.contains("- a"))
        #expect(html.contains("<h1>H</h1>"))
        #expect(!html.contains("<hr"))
    }

    @Test func hostileFrontmatterIsEscaped() {
        let html = OKMarkdownHTML.body("---\ntitle: \"<img src=x onerror=alert(1)>\"\n---\n")
        #expect(!html.contains("<img") && html.contains("&lt;img"))
    }

    @Test func listsNestOneLevelAndOrderedListsRender() {
        let html = OKMarkdownHTML.body("- a\n  - a1\n* b\n\n1. um\n2. dois\n")
        #expect(html.contains("<ul><li>a<ul><li>a1</li></ul></li><li>b</li></ul>"))
        #expect(html.contains("<ol><li>um</li><li>dois</li></ol>"))
    }

    @Test func codeFencesKeepContentLiteral() {
        let html = OKMarkdownHTML.body("```mermaid\ngraph TD; A-->B **x**\n```\n\nTexto `<b>` e *it* e _it2_\n")
        #expect(html.contains("<pre><code class=\"language-mermaid\">graph TD; A--&gt;B **x**</code></pre>"))
        #expect(html.contains("<code>&lt;b&gt;</code>") && html.contains("<em>it</em>") && html.contains("<em>it2</em>"))
    }

    @Test func blockquoteWithoutCalloutAndParagraphs() {
        let html = OKMarkdownHTML.body("> citação\n\nlinha um\nlinha dois\n\n### T\n")
        #expect(html.contains("<blockquote>") && html.contains("citação"))
        #expect(html.contains("<p>linha um\nlinha dois</p>") && html.contains("<h3>T</h3>"))
    }

    @Test func calloutTypeIsSanitizedIntoClassName() {
        let html = OKMarkdownHTML.body("> [!warn\" onclick=\"x] Título\n")
        #expect(!html.contains("onclick=\""))
        #expect(html.contains("class=\"callout callout-"))
    }

    @Test func documentIsSelfContainedWithDarkMode() {
        let doc = OKMarkdownHTML.document("# H\n")
        #expect(doc.hasPrefix("<!doctype html>") && doc.contains("prefers-color-scheme: dark"))
        #expect(!doc.contains("<script") && !doc.contains("http://") && !doc.contains("https://"))
        #expect(!doc.contains("O que muda"))
    }

    @Test func documentWithPreviousShowsChangesFirst() {
        let old = "# Doc\n\nlinha velha\n"
        let new = "# Doc\n\nlinha nova\n"
        let doc = OKMarkdownHTML.document(new, previous: old)
        let changes = doc.range(of: "O que muda")
        let heading = doc.range(of: "<h1>Doc</h1>")
        #expect(changes != nil && heading != nil)
        if let changes, let heading { #expect(changes.lowerBound < heading.lowerBound) }
        #expect(doc.contains("class=\"diff-added\">linha nova") && doc.contains("class=\"diff-removed\">linha velha"))
    }

    @Test func diffCollapsesLongUnchangedRuns() {
        let common = (1...20).map { "l\($0)" }
        let old = (common + ["fim"]).joined(separator: "\n")
        let new = (common + ["FIM"]).joined(separator: "\n")
        let doc = OKMarkdownHTML.document(new, previous: old)
        let block = String(doc[..<(doc.range(of: "</section>")?.lowerBound ?? doc.endIndex)])
        #expect(block.contains("…"))
        #expect(!block.contains(">l1<") && block.contains(">l19<") && block.contains(">l20<"))
    }
}

@Suite("OKLineDiff")
struct OKLineDiffTests {

    @Test func lineDiffMarksAddedAndRemoved() {
        #expect(OKLineDiff.diff(old: "a\nb\nc", new: "a\nB\nc") == [.same("a"), .removed("b"), .added("B"), .same("c")])
    }

    @Test func emptyAndIdentical() {
        #expect(OKLineDiff.diff(old: "", new: "x") == [.added("x")])
        #expect(OKLineDiff.diff(old: "a\n", new: "a") == [.same("a")])
        #expect(OKLineDiff.diff(old: "a\nb", new: "a\nb") == [.same("a"), .same("b")])
        #expect(OKLineDiff.diff(old: "a", new: "a\nb\nc") == [.same("a"), .added("b"), .added("c")])
    }
}
