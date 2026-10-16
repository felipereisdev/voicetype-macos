import Foundation

/// Line-based reads and edits of top-level frontmatter keys. Not a YAML
/// parser: enough for the vault's templates and docs (plain or quoted
/// scalars, flow lists, indented blocks), and every edit keeps the other
/// lines byte for byte.
public enum OKFrontmatter {
    /// The text between the `---` fences (without them) and what follows the
    /// closing fence. No opening `---` line, or no closing one, → `nil` and
    /// the whole input as body.
    public static func split(_ md: String) -> (frontmatter: String?, body: String) {
        guard let parts = fences(md) else { return (nil, md) }
        return (parts.lines.joined(separator: "\n"), parts.body)
    }

    /// A top-level scalar, unquoted (`''` → `'` in single quotes, `\"` and
    /// `\\` in double quotes). Indented lines after it that don't start with
    /// `- ` are folded in with one space. An empty value followed by an
    /// indented block (a map or a list) → `nil`, and so does a key that
    /// appears more than once (ambiguous; see `duplicateKeys`).
    public static func scalar(_ key: String, in md: String) -> String? {
        guard let lines = fences(md)?.lines else { return nil }
        let ranges = keyRanges(key, in: lines)
        guard ranges.count == 1, let range = ranges.first else { return nil }
        var value = String(lines[range.lowerBound].dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces)
        for line in lines[(range.lowerBound + 1)..<range.upperBound] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") || trimmed == "-" {
                if value.isEmpty { return nil }
                break
            }
            if value.isEmpty, !trimmed.isEmpty, trimmed.contains(":") { return nil }
            if !trimmed.isEmpty { value += value.isEmpty ? trimmed : " " + trimmed }
        }
        return unquoted(value)
    }

    /// Replaces `key` (with its indented continuation lines) by `key: yamlValue`
    /// where it first appears and drops any repeated occurrence, so the result
    /// holds the key exactly once. A missing key goes right before the closing
    /// fence, and a document without frontmatter gets one. `yamlValue` is
    /// written as is.
    public static func setting(_ key: String, to yamlValue: String, in md: String) -> String {
        let entry = "\(key): \(yamlValue)"
        guard var parts = fences(md) else { return "---\n\(entry)\n---\n" + md }
        let ranges = keyRanges(key, in: parts.lines)
        if let first = ranges.first {
            for range in ranges.dropFirst().reversed() { parts.lines.removeSubrange(range) }
            parts.lines.replaceSubrange(first, with: [entry])
        } else {
            parts.lines.append(entry)
        }
        return join(parts.lines, parts.closing, parts.body)
    }

    /// Drops every occurrence of `key` with its indented continuation lines;
    /// no key → `md` unchanged.
    public static func removing(_ key: String, in md: String) -> String {
        guard var parts = fences(md) else { return md }
        let ranges = keyRanges(key, in: parts.lines)
        guard !ranges.isEmpty else { return md }
        for range in ranges.reversed() { parts.lines.removeSubrange(range) }
        return join(parts.lines, parts.closing, parts.body)
    }

    /// Top-level keys that appear more than once, in order of first
    /// appearance. A strict YAML parser rejects such a frontmatter, so
    /// untrusted Markdown with any duplicate left after `setting` is refused.
    public static func duplicateKeys(_ md: String) -> [String] {
        guard let lines = fences(md)?.lines else { return [] }
        var seen: Set<String> = []
        var duplicates: [String] = []
        for line in lines {
            guard let key = topLevelKey(line) else { continue }
            if !seen.insert(key).inserted, !duplicates.contains(key) { duplicates.append(key) }
        }
        return duplicates
    }

    /// True when the frontmatter (never the body) still holds a template `TODO`.
    public static func containsTODO(_ md: String) -> Bool {
        fences(md)?.lines.contains { $0.contains("TODO") } ?? false
    }

    // MARK: - Helpers

    private struct Parts {
        var lines: [String]
        /// `"---\n"`, or `"---"` when the file ends right at the fence.
        var closing: String
        var body: String
    }

    private static func fences(_ md: String) -> Parts? {
        guard md.hasPrefix("---\n") else { return nil }
        var lines: [String] = []
        var rest = md.dropFirst(4)
        while !rest.isEmpty {
            let end = rest.firstIndex(of: "\n")
            let line = String(rest[..<(end ?? rest.endIndex)])
            let next = end.map { rest.index(after: $0) } ?? rest.endIndex
            if line == "---" {
                return Parts(lines: lines, closing: end == nil ? "---" : "---\n", body: String(rest[next...]))
            }
            lines.append(line)
            rest = rest[next...]
        }
        return nil
    }

    private static func join(_ lines: [String], _ closing: String, _ body: String) -> String {
        "---\n" + lines.map { $0 + "\n" }.joined() + closing + body
    }

    /// Each occurrence of the key line plus the indented (or `- ` list) lines
    /// that belong to it, in ascending order.
    private static func keyRanges(_ key: String, in lines: [String]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while start < lines.count {
            guard lines[start].hasPrefix(key + ":") else { start += 1; continue }
            var end = start + 1
            while end < lines.count, belongsToPrevious(lines[end]) { end += 1 }
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    /// `key` of a top-level `key: …` line; indented, list, comment and blank
    /// lines have none.
    private static func topLevelKey(_ line: String) -> String? {
        guard let first = line.first, !first.isWhitespace, first != "-", first != "#",
              let colon = line.firstIndex(of: ":") else { return nil }
        return String(line[..<colon])
    }

    private static func belongsToPrevious(_ line: String) -> Bool {
        line.hasPrefix(" ") || line.hasPrefix("\t") || line.hasPrefix("- ") || line == "-"
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            var out = ""
            var escaping = false
            for ch in value.dropFirst().dropLast() {
                if escaping {
                    if ch != "\"" && ch != "\\" { out.append("\\") }
                    out.append(ch)
                    escaping = false
                } else if ch == "\\" {
                    escaping = true
                } else {
                    out.append(ch)
                }
            }
            if escaping { out.append("\\") }
            return out
        }
        return value
    }
}
