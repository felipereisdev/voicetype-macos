import Testing
import Foundation
@testable import Core

@Suite("RefineBypass")
struct RefineBypassTests {

    @Test func knownTerminalsBypass() {
        for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
                   "net.kovidgoyal.kitty", "com.github.wez.wezterm", "dev.warp.Warp-Stable"] {
            #expect(RefineBypass.shouldBypass(bundleID: id, disabledFor: []), "\(id)")
        }
    }

    @Test func bundleIDMatchIsCaseInsensitive() {
        #expect(RefineBypass.isTerminal("COM.APPLE.TERMINAL"))
    }

    @Test func unknownAppKeepsRefine() {
        #expect(!RefineBypass.shouldBypass(bundleID: "com.apple.TextEdit", disabledFor: []))
        #expect(!RefineBypass.shouldBypass(bundleID: "", disabledFor: []))
    }

    @Test func perAppOptOutKeepsRefine() {
        #expect(!RefineBypass.shouldBypass(bundleID: "com.googlecode.iterm2",
                                           disabledFor: ["com.googlecode.iterm2"]))
        #expect(RefineBypass.shouldBypass(bundleID: "com.apple.Terminal",
                                          disabledFor: ["com.googlecode.iterm2"]))
    }
}
