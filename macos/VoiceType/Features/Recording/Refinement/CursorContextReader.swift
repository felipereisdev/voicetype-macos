import ApplicationServices
import Core
import Foundation

// Reads the text around the caret of the focused field at hotkey-down (#41).
// Read-only, short AX messaging timeout, never touches secure fields. Any
// failure — no AX permission, unsupported role, Electron app without AX — is
// nil, never an error. Splitting/truncation lives in Core (`CursorContext`).
enum CursorContextReader {
    // Per-call AX timeout: a hung target app must not stall the recording start.
    private static let timeout: Float = 0.05
    // Fields with more text than this are read in windows via AXStringForRange
    // instead of copying the whole value.
    private static let maxFullValueLength = 20_000
    private static let window = CursorContext.maxChars * 4

    private static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    private static let secureMarker = "AXSecureTextField"

    static func read() -> CursorContext? {
        guard let element = focusedTextElement(), let range = selectedRange(of: element) else { return nil }

        let length: Int? = attribute(kAXNumberOfCharactersAttribute, of: element)
        if length.map({ $0 <= maxFullValueLength }) ?? true, let value: String = attribute(kAXValueAttribute, of: element) {
            return nonEmpty(CursorContext.from(value: value, selectedRange: range))
        }
        // Large (or value-less) field: read only the windows around the caret.
        guard let length, range.location >= 0, NSMaxRange(range) <= length else { return nil }
        let beforeStart = max(0, range.location - window)
        let afterEnd = min(length, NSMaxRange(range) + window)
        return nonEmpty(CursorContext(
            before: string(in: NSRange(location: beforeStart, length: range.location - beforeStart), of: element) ?? "",
            selected: string(in: NSRange(location: range.location, length: min(range.length, window)), of: element) ?? "",
            after: string(in: NSRange(location: NSMaxRange(range), length: max(0, afterEnd - NSMaxRange(range))), of: element) ?? ""
        ))
    }

    /// Focused element if it's a plain text role. Secure check comes FIRST,
    /// before any value read. Shared with `EditObserver` (#50).
    static func focusedTextElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        guard let element: AXUIElement = attribute(kAXFocusedUIElementAttribute, of: systemWide) else { return nil }
        AXUIElementSetMessagingTimeout(element, timeout)
        let role: String? = attribute(kAXRoleAttribute, of: element)
        let subrole: String? = attribute(kAXSubroleAttribute, of: element)
        guard let role, role != secureMarker, subrole != secureMarker, textRoles.contains(role) else { return nil }
        return element
    }

    private static func nonEmpty(_ ctx: CursorContext?) -> CursorContext? {
        guard let ctx, !ctx.isEmpty else { return nil }
        return ctx
    }

    static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func selectedRange(of element: AXUIElement) -> NSRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    static func string(in range: NSRange, of element: AXUIElement) -> String? {
        guard range.length > 0 else { return "" }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let param = AXValueCreate(.cfRange, &cfRange) else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXStringForRangeParameterizedAttribute as CFString, param, &value
        ) == .success else { return nil }
        return value as? String
    }
}
