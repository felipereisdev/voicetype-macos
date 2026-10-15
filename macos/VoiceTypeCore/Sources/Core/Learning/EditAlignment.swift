import Foundation

/// One word-level correction the user made to pasted text (#50).
public struct EditSubstitution: Equatable, Sendable {
    public let original: String
    public let corrected: String

    public init(original: String, corrected: String) {
        self.original = original
        self.corrected = corrected
    }
}

/// Word-level diff between what VoiceType pasted and what the field holds a few
/// seconds later. Pure; the App target supplies both strings (pasted range only).
///
/// Only edits that look like ASR misses survive: 1–3 words replaced by 1–3 words
/// that are spelled similarly ("Kodex" → "Codex", "mac silva" → "Macsilva").
/// Case/punctuation-only changes, insertions, deletions and dissimilar rewrites
/// ("bom" → "ótimo") are style edits and are ignored. A heavy rewrite — or a
/// misaligned read-back — yields nothing at all.
public enum EditAlignment {
    public static let maxSubstitutions = 4
    static let maxBlockWords = 3
    static let minSimilarity = 0.5

    public static func substitutions(pasted: String, edited: String) -> [EditSubstitution] {
        let a = words(pasted), b = words(edited)
        guard !a.isEmpty, !b.isEmpty else { return [] }
        let ka = a.map(key), kb = b.map(key)
        let matches = lcs(ka, kb)
        // Most of the dictation must survive untouched, else it's a rewrite.
        guard matches.count * 2 >= ka.count else { return [] }

        var result: [EditSubstitution] = []
        var i = 0, j = 0
        for (mi, mj) in matches + [(a.count, b.count)] {
            let gapA = Array(a[i..<mi]), gapB = Array(b[j..<mj])
            if let sub = substitution(gapA, gapB) { result.append(sub) }
            i = mi + 1
            j = mj + 1
        }
        // ponytail: >4 corrections reads as a rewrite, not ASR misses — drop all.
        return result.count > maxSubstitutions ? [] : result
    }

    private static func substitution(_ a: [String], _ b: [String]) -> EditSubstitution? {
        guard (1...maxBlockWords).contains(a.count), (1...maxBlockWords).contains(b.count) else { return nil }
        let original = a.map(trimPunctuation).joined(separator: " ")
        let corrected = b.map(trimPunctuation).joined(separator: " ")
        let ja = letters(original), jb = letters(corrected)
        // Case/punctuation-only edits never get here: the LCS key already matched them.
        guard !ja.isEmpty, !jb.isEmpty, similarity(ja, jb) >= minSimilarity else { return nil }
        return EditSubstitution(original: original, corrected: corrected)
    }

    static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Comparison key: case- and punctuation-insensitive, diacritics kept.
    private static func key(_ w: String) -> String { letters(w) }

    private static func letters(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    private static func trimPunctuation(_ w: String) -> String {
        w.trimmingCharacters(in: .punctuationCharacters.union(.symbols))
    }

    /// 1 − normalized Levenshtein distance.
    static func similarity(_ x: String, _ y: String) -> Double {
        let a = Array(x), b = Array(y)
        guard !a.isEmpty, !b.isEmpty else { return a.count == b.count ? 1 : 0 }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return 1 - Double(prev[b.count]) / Double(max(a.count, b.count))
    }

    /// Index pairs of a longest common subsequence, in order.
    private static func lcs(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        var t = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                t[i][j] = a[i] == b[j] ? t[i + 1][j + 1] + 1 : max(t[i + 1][j], t[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0, j = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { pairs.append((i, j)); i += 1; j += 1 }
            else if t[i + 1][j] >= t[i][j + 1] { i += 1 }
            else { j += 1 }
        }
        return pairs
    }
}
