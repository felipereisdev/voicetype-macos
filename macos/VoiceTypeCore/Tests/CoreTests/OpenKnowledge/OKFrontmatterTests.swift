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

    @Test func duplicatedKeysAreAmbiguousAndSettingCollapsesThem() {
        // Model output with `project`, `type` and `status` repeated (one with a block continuation).
        let md = "---\ntitle: A\nproject: outro\ntype: decisao\ndescription: B\nproject: outro\nstatus: proposta\ntype:\n  - gotcha\nstatus: aceita\nproject: terceiro\n---\nCorpo\n"
        #expect(OKFrontmatter.duplicateKeys(md) == ["project", "type", "status"])
        #expect(OKFrontmatter.scalar("project", in: md) == nil)
        #expect(OKFrontmatter.scalar("type", in: md) == nil)
        #expect(OKFrontmatter.scalar("status", in: md) == nil)
        #expect(OKFrontmatter.scalar("title", in: md) == "A")

        var out = md
        for (key, value) in [("type", "decisao"), ("project", "p5"), ("status", "aceita")] {
            out = OKFrontmatter.setting(key, to: value, in: out)
        }
        #expect(out == "---\ntitle: A\nproject: p5\ntype: decisao\ndescription: B\nstatus: aceita\n---\nCorpo\n")
        #expect(OKFrontmatter.duplicateKeys(out) == [])
        #expect(OKFrontmatter.scalar("project", in: out) == "p5")
        #expect(OKFrontmatter.scalar("type", in: out) == "decisao")
        #expect(OKFrontmatter.scalar("status", in: out) == "aceita")
    }

    @Test func removingDropsEveryOccurrenceAndDuplicatesIgnoreNestedKeys() {
        #expect(OKFrontmatter.removing("template", in: "---\ntemplate:\n  title: T\ntitle: x\ntemplate: y\n---\nb\n") == "---\ntitle: x\n---\nb\n")
        // Nested keys, list items, comments and the body don't count as duplicates.
        let md = "---\ntemplate:\n  title: T\ntitle: x\ntags:\n  - a\n  - a\n# title: c\n---\ntitle: corpo\n"
        #expect(OKFrontmatter.duplicateKeys(md) == [])
        #expect(OKFrontmatter.duplicateKeys("---\ntags: [a]\ntags: [b]\n---\n") == ["tags"])
        #expect(OKFrontmatter.duplicateKeys("sem frontmatter\n") == [])
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
