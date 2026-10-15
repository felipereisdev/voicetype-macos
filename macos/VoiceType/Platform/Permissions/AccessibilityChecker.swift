import ApplicationServices
import Foundation

public enum AccessibilityChecker {
    // True if the process is trusted to use Accessibility APIs.
    // `prompt: true` once at bootstrap to surface the system prompt; `false` for
    // live status polling (Settings UI in Phase 6).
    public static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
