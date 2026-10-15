import AppKit
import SwiftUI

/// Per-screen notch metrics. `update(for:)` reads `safeAreaInsets.top` and the
/// auxiliary top areas exposed by `NSScreen` on notched MacBooks. Screens
/// without a notch leave `hasNotch == false`; callers should fall back to the
/// pill HUD in that case.
@Observable
@MainActor
final class NotchGeometry {
    var notchWidth: CGFloat = 185
    var safeAreaTop: CGFloat = 0
    var hasNotch = false

    func update(for screen: NSScreen) {
        hasNotch = screen.safeAreaInsets.top > 0
        safeAreaTop = screen.safeAreaInsets.top
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea?.width,
           let right = screen.auxiliaryTopRightArea?.width {
            notchWidth = screen.frame.width - left - right + 4
        } else {
            notchWidth = 200
        }
    }
}
