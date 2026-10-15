import AppKit

/// `NSPanel` subclass that refuses key + main status even when system idle
/// traversal would otherwise grant it. Combined with `.nonactivatingPanel`
/// style mask this guarantees the foreign app the user was typing in never
/// loses frontmost status — same contract the Electron HUD used
/// `focusable: false + showInactive()` to maintain.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
