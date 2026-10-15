import AppKit

/// Shared counter that keeps `NSApp.activationPolicy` flipped to `.regular`
/// while any tracked window is open. Without this, two windows that each call
/// `.regular`/.accessory in `.onAppear`/`.onDisappear` would race: closing
/// History demotes the app to `.accessory` even while Settings is still open,
/// which kills the Dock icon mid-session.
///
/// Caller contract: every `.onAppear` of a tracked Window scene must call
/// `enter()`; every `.onDisappear` must call `leave()`. Policy only flips back
/// to `.accessory` when the count returns to zero.
@MainActor
enum ActivationPolicyTracker {
    private static var openCount = 0

    static func enter() {
        openCount += 1
        if openCount == 1 {
            NSApp.setActivationPolicy(.regular)
        }
    }

    static func leave() {
        guard openCount > 0 else { return }
        openCount -= 1
        if openCount == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
