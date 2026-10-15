import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Minimal SwiftUI shortcut recorder. Click → capture next keystroke (modifiers + key)
/// → format as the `CommandOrControl+Shift+V` accelerator string the rest of the
/// app already parses. Phase 4 decided against pulling in the
/// KeyboardShortcuts SwiftPM dep, so this is a hand-rolled recorder that
/// reuses the same token vocabulary as `HoldDetectorCore`.
struct ShortcutRecorderField: View {
    @Binding var accelerator: String
    @State private var isCapturing: Bool = false
    @State private var monitor: Any?
    // Largest modifier set seen during capture; recorded as a modifier-only
    // shortcut when everything is released without a main key.
    @State private var peakModifiers: [String] = []

    var body: some View {
        HStack(spacing: 8) {
            Text(displayString)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .foregroundStyle(isCapturing ? Color.secondary : Color.primary)
            Spacer()
            Button(isCapturing ? SettingsStrings.shortcutRecorderCancel : SettingsStrings.shortcutRecorderRecord) {
                toggleCapture()
            }
            .controlSize(.small)
        }
        .onDisappear { stopCapture() }
    }

    private var displayString: String {
        if isCapturing { return SettingsStrings.shortcutRecorderCapturing }
        return Self.prettyPrint(accelerator)
    }

    private func toggleCapture() {
        if isCapturing { stopCapture() } else { startCapture() }
    }

    private func startCapture() {
        isCapturing = true
        let mon = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                handleFlags(event)
            } else {
                handle(event)
            }
            return nil // swallow the keystroke while capturing
        }
        monitor = mon
    }

    private func stopCapture() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        isCapturing = false
        peakModifiers = []
    }

    private func handleFlags(_ event: NSEvent) {
        var held: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { held.append("CommandOrControl") }
        if flags.contains(.control) { held.append("Control") }
        if flags.contains(.option) { held.append("Alt") }
        if flags.contains(.shift) { held.append("Shift") }
        if flags.contains(.function) { held.append("Fn") }
        if held.count > peakModifiers.count { peakModifiers = held }
        guard held.isEmpty, !peakModifiers.isEmpty else { return }
        let peak = peakModifiers
        peakModifiers = []
        // A lone Cmd/Ctrl/Alt/Shift would start recording on every ordinary
        // chord; only Fn stands alone.
        guard peak == ["Fn"] || peak.count >= 2 else { return }
        accelerator = peak.joined(separator: "+")
        stopCapture()
    }

    private func handle(_ event: NSEvent) {
        // Escape cancels capture without changing the value.
        if event.keyCode == UInt16(kVK_Escape) {
            stopCapture()
            return
        }
        guard let token = Self.keycodeTokens[Int(event.keyCode)] else {
            // Unrecognized keycode — keep capturing.
            return
        }
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { parts.append("CommandOrControl") }
        if flags.contains(.control), !flags.contains(.command) { parts.append("Control") }
        if flags.contains(.option) { parts.append("Alt") }
        if flags.contains(.shift) { parts.append("Shift") }
        // Reject pure-key without modifiers — the parser in `HoldDetectorCore`
        // requires at least one modifier for a global accelerator.
        guard !parts.isEmpty else { return }
        parts.append(token)
        accelerator = parts.joined(separator: "+")
        stopCapture()
    }

    /// Map of Carbon kVK_* codes → accelerator token. Mirrors the inverse of
    /// the `tokenToKeycode` table in `HoldDetectorCore`.
    static let keycodeTokens: [Int: String] = {
        var m: [Int: String] = [
            kVK_Space: "Space",
            kVK_Tab: "Tab",
            kVK_Delete: "Backspace",
            kVK_ForwardDelete: "Delete",
            kVK_Return: "Return",
        ]
        let letters: [(Int, String)] = [
            (kVK_ANSI_A, "A"), (kVK_ANSI_B, "B"), (kVK_ANSI_C, "C"), (kVK_ANSI_D, "D"),
            (kVK_ANSI_E, "E"), (kVK_ANSI_F, "F"), (kVK_ANSI_G, "G"), (kVK_ANSI_H, "H"),
            (kVK_ANSI_I, "I"), (kVK_ANSI_J, "J"), (kVK_ANSI_K, "K"), (kVK_ANSI_L, "L"),
            (kVK_ANSI_M, "M"), (kVK_ANSI_N, "N"), (kVK_ANSI_O, "O"), (kVK_ANSI_P, "P"),
            (kVK_ANSI_Q, "Q"), (kVK_ANSI_R, "R"), (kVK_ANSI_S, "S"), (kVK_ANSI_T, "T"),
            (kVK_ANSI_U, "U"), (kVK_ANSI_V, "V"), (kVK_ANSI_W, "W"), (kVK_ANSI_X, "X"),
            (kVK_ANSI_Y, "Y"), (kVK_ANSI_Z, "Z"),
        ]
        for (k, v) in letters { m[k] = v }
        let digits: [(Int, String)] = [
            (kVK_ANSI_0, "0"), (kVK_ANSI_1, "1"), (kVK_ANSI_2, "2"), (kVK_ANSI_3, "3"),
            (kVK_ANSI_4, "4"), (kVK_ANSI_5, "5"), (kVK_ANSI_6, "6"), (kVK_ANSI_7, "7"),
            (kVK_ANSI_8, "8"), (kVK_ANSI_9, "9"),
        ]
        for (k, v) in digits { m[k] = v }
        let fns: [(Int, String)] = [
            (kVK_F1, "F1"), (kVK_F2, "F2"), (kVK_F3, "F3"), (kVK_F4, "F4"),
            (kVK_F5, "F5"), (kVK_F6, "F6"), (kVK_F7, "F7"), (kVK_F8, "F8"),
            (kVK_F9, "F9"), (kVK_F10, "F10"), (kVK_F11, "F11"), (kVK_F12, "F12"),
        ]
        for (k, v) in fns { m[k] = v }
        return m
    }()

    /// Render `"CommandOrControl+Shift+V"` as `"⌃⌘⇧V"` for display.
    static func prettyPrint(_ accelerator: String) -> String {
        guard !accelerator.isEmpty else { return "—" }
        let tokens = accelerator.split(separator: "+").map(String.init)
        var pretty = ""
        for t in tokens {
            switch t {
            case "Command", "Cmd", "CommandOrControl", "CmdOrCtrl":
                pretty += "⌘"
            case "Control", "Ctrl":
                pretty += "⌃"
            case "Alt", "Option":
                pretty += "⌥"
            case "Shift":
                pretty += "⇧"
            case "Fn", "Globe":
                pretty += "fn"
            case "Space":
                pretty += "Space"
            case "Tab":
                pretty += "⇥"
            case "Backspace":
                pretty += "⌫"
            case "Delete":
                pretty += "⌦"
            case "Return", "Enter":
                pretty += "⏎"
            case "Escape", "Esc":
                pretty += "⎋"
            default:
                pretty += t
            }
        }
        return pretty
    }
}
