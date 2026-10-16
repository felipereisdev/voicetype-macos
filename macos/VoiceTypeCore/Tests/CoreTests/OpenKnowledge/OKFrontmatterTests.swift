import Foundation
import Testing
@testable import Core

@Suite("OKFrontmatter")
struct OKFrontmatterTests {

    @Test func readsTopLevelScalarsIncludingFoldedAndQuoted() {
        let md = "---\ntitle: 'TODO — título'\ndescription: \"Linha um\n  continua\"\ntype: decisao\ntemplate:\n  title: Decisão (ADR)\ntags:\n  - a\n---\n# Corpo\n"
        #expect(OKFrontmatter.scalar("title", in: md) == "TODO — título")
        #expect(OKFrontmatter.scalar("description", in: md) == "Linha um continua")
        #expect(OKFrontmatter.scalar("type", in: md) == "decisao")
        #expect(OKFrontmatter.scalar("missing", in: md) == nil)
        #expect(OKFrontmatter.split(md).body == "# Corpo\n")
    }

    @Test func blockValuesAndEscapes() {
        let md = "---\ntemplate:\n  title: T\ntags:\n  - a\nq: 'it''s'\nd: \"a \\\"b\\\" c\\\\d\"\n---\nb\n"
        #expect(OKFrontmatter.scalar("template", in: md) == nil)
        #expect(OKFrontmatter.scalar("tags", in: md) == nil)
        #expect(OKFrontmatter.scalar("title", in: md) == nil)
        #expect(OKFrontmatter.scalar("q", in: md) == "it's")
        #expect(OKFrontmatter.scalar("d", in: md) == "a \"b\" c\\d")
        // Round-trips what MeetingNoteRenderer.yamlString writes.
        let hostile = "Título \"x\" \\ y"
        #expect(OKFrontmatter.scalar("t", in: "---\nt: \(MeetingNoteRenderer.yamlString(hostile))\n---\n") == hostile)
    }

    @Test func splitWithoutOrEmptyFrontmatter() {
        #expect(OKFrontmatter.split("# só corpo\n").frontmatter == nil)
        #expect(OKFrontmatter.split("# só corpo\n").body == "# só corpo\n")
        #expect(OKFrontmatter.split("---\n---\nb\n").frontmatter == "")
        #expect(OKFrontmatter.split("---\n---\nb\n").body == "b\n")
        #expect(OKFrontmatter.split("---\ntitle: x\n---").body == "")
        #expect(OKFrontmatter.split("---\ntitle: x\n").frontmatter == nil)
        #expect(OKFrontmatter.scalar("title", in: "# t\ntitle: x\n") == nil)
    }

    @Test func settingReplacesKeyWithItsContinuationLinesOrAppends() {
        let md = "---\ntitle: x\ntags:\n  - a\n  - b\nproject: TODO\n---\nbody\n"
        let out = OKFrontmatter.setting("project", to: "p5", in: OKFrontmatter.setting("tags", to: "[decisao, p5]", in: md))
        #expect(out == "---\ntitle: x\ntags: [decisao, p5]\nproject: p5\n---\nbody\n")
        #expect(OKFrontmatter.setting("status", to: "aceita", in: "---\ntitle: x\n---\nb\n") == "---\ntitle: x\nstatus: aceita\n---\nb\n")
        #expect(OKFrontmatter.removing("template", in: "---\ntemplate:\n  title: T\ntitle: x\n---\nb\n") == "---\ntitle: x\n---\nb\n")
        #expect(OKFrontmatter.containsTODO("---\nproject: TODO\n---\nok\n") && !OKFrontmatter.containsTODO("---\nproject: p\n---\nTODO no corpo\n"))
    }

    @Test func settingCreatesFrontmatterAndRemovingIsNoOpWithoutKey() {
        #expect(OKFrontmatter.setting("title", to: "x", in: "# b\n") == "---\ntitle: x\n---\n# b\n")
        #expect(OKFrontmatter.setting("title", to: "x", in: "---\n---\nb\n") == "---\ntitle: x\n---\nb\n")
        #expect(OKFrontmatter.removing("missing", in: "---\ntitle: x\n---\nb\n") == "---\ntitle: x\n---\nb\n")
        #expect(OKFrontmatter.removing("title", in: "# b\n") == "# b\n")
        // An indented `title:` inside `template:` is not a top-level key.
        #expect(OKFrontmatter.setting("title", to: "y", in: "---\ntemplate:\n  title: T\n---\nb\n") == "---\ntemplate:\n  title: T\ntitle: y\n---\nb\n")
        #expect(!OKFrontmatter.containsTODO("# TODO\n"))
    }
}
