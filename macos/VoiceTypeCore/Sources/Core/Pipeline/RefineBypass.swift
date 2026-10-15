import Foundation

// Terminals get the raw transcription: an LLM pass "fixing" a shell command
// (capitalizing it, adding a period, turning flags into prose) breaks it. The
// personal dictionary still applies — it biases the ASR, not the refiner.
// Per-app opt-out lives in `AppConfig.refineBypassDisabledApps`.
public enum RefineBypass {
    public static let terminalApps: [(bundleID: String, name: String)] = [
        ("com.apple.Terminal", "Terminal"),
        ("com.googlecode.iterm2", "iTerm2"),
        ("com.mitchellh.ghostty", "Ghostty"),
        ("net.kovidgoyal.kitty", "kitty"),
        ("com.github.wez.wezterm", "WezTerm"),
        ("dev.warp.Warp-Stable", "Warp"),
    ]

    public static func isTerminal(_ bundleID: String) -> Bool {
        terminalApps.contains { $0.bundleID.caseInsensitiveCompare(bundleID) == .orderedSame }
    }

    /// True when the refine pass should be skipped for `bundleID`.
    public static func shouldBypass(bundleID: String, disabledFor: [String]) -> Bool {
        isTerminal(bundleID)
            && !disabledFor.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}
