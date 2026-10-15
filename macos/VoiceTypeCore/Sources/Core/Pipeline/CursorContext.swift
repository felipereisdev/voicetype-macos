import Foundation

// Text around the caret in the focused field, captured via AX at hotkey-down
// (App target) so the refiner can match capitalization/punctuation of the
// surrounding text (#54). Each side is capped at `maxChars` and cut on a word
// boundary at its FAR end — `before` keeps its tail (nearest the caret),
// `after`/`selected` keep their head. Counts are Characters, so an emoji or an
// accented letter is never split.
public struct CursorContext: Sendable, Equatable {
    public static let maxChars = 500

    public let before: String
    public let selected: String
    public let after: String

    public init(before: String, selected: String, after: String) {
        self.before = Self.tail(before)
        self.selected = Self.head(selected)
        self.after = Self.head(after)
    }

    public var isEmpty: Bool { before.isEmpty && selected.isEmpty && after.isEmpty }

    /// Splits an AX value around an AX selected range (UTF-16 offsets).
    /// Invalid range or empty field → nil.
    public static func from(value: String, selectedRange: NSRange) -> CursorContext? {
        let ns = value as NSString
        guard ns.length > 0,
              selectedRange.location != NSNotFound,
              selectedRange.location >= 0, selectedRange.length >= 0,
              NSMaxRange(selectedRange) <= ns.length
        else { return nil }
        return CursorContext(
            before: ns.substring(to: selectedRange.location),
            selected: ns.substring(with: selectedRange),
            after: ns.substring(from: NSMaxRange(selectedRange))
        )
    }

    // Keep the first `maxChars`; if that cut a word, drop the partial word.
    static func head(_ s: String) -> String {
        guard s.count > maxChars else { return s }
        let cut = s.prefix(maxChars)
        if s[cut.endIndex].isWhitespace { return String(cut) }
        guard let space = cut.lastIndex(where: \.isWhitespace) else { return "" }
        return String(cut[..<space])
    }

    // Keep the last `maxChars`; if that cut a word, drop the partial word.
    static func tail(_ s: String) -> String {
        guard s.count > maxChars else { return s }
        let cut = s.suffix(maxChars)
        if s[s.index(before: cut.startIndex)].isWhitespace { return String(cut) }
        guard let space = cut.firstIndex(where: \.isWhitespace) else { return "" }
        return String(cut[cut.index(after: space)...])
    }
}
