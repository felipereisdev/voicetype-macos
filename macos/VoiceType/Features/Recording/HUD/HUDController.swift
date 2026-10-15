import AppKit
import SwiftUI

@MainActor
final class HUDController {

    // Test seam — production callers should treat this as opaque.
    var panelForTesting: NSPanel? { panel }

    var preset: WaveformColorPreset = .aurora
    var style: HUDIndicatorStyle = .auto

    init() {}

    func show(state: HUDState) {
        currentState = state
        if shouldUseNotch() {
            notchPanel.show(state: state, preset: preset)
            hidePill()
        } else {
            notchPanel.hide()
            showPill(state: state)
        }
    }

    func hide() {
        notchPanel.hide()
        hidePill()
        currentState = .hidden
    }

    func update(level: Float) {
        guard case .recording(_, let elapsed, let locked) = currentState else { return }
        let next = HUDState.recording(level: level, elapsed: elapsed, locked: locked)
        currentState = next
        pushUpdate(next)
    }

    func update(elapsed: TimeInterval) {
        guard case .recording(let level, _, let locked) = currentState else { return }
        let next = HUDState.recording(level: level, elapsed: elapsed, locked: locked)
        currentState = next
        pushUpdate(next)
    }

    // Hands-free locked: same recording HUD plus a lock glyph.
    func markLocked() {
        guard case .recording(let level, let elapsed, _) = currentState else { return }
        let next = HUDState.recording(level: level, elapsed: elapsed, locked: true)
        currentState = next
        pushUpdate(next)
    }

    private var panel: NSPanel?
    private var host: NSHostingView<AnyView>?
    private let notchPanel = NotchIndicatorPanel()
    private var currentState: HUDState = .hidden

    private static let panelSize = NSSize(width: 296, height: 96)
    private static let bottomInset: CGFloat = 120

    // MARK: - Style routing

    private func shouldUseNotch() -> Bool {
        switch style {
        case .pill:
            return false
        case .notch, .auto:
            return (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
        }
    }

    private func pushUpdate(_ next: HUDState) {
        if shouldUseNotch() {
            notchPanel.update(state: next)
        } else {
            host?.rootView = AnyView(
                HUDView(state: next, onOpenMicSettings: Self.openMicSettings, preset: preset)
            )
        }
    }

    // MARK: - Pill (existing behavior)

    private func showPill(state: HUDState) {
        if panel == nil { buildPanel() }
        positionPanel()
        host?.rootView = AnyView(
            HUDView(state: state, onOpenMicSettings: Self.openMicSettings, preset: preset)
        )
        panel?.orderFrontRegardless()
    }

    private func hidePill() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        host = nil
    }

    private func buildPanel() {
        let rect = NSRect(origin: .zero, size: Self.panelSize)
        let panel = NonActivatingPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        // Set level last — setting `isFloatingPanel` flips it to .floating (3).
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(
            rootView: AnyView(
                HUDView(state: currentState, onOpenMicSettings: Self.openMicSettings, preset: preset)
            )
        )
        host.frame = rect
        panel.contentView = host

        self.panel = panel
        self.host = host
    }

    private func positionPanel() {
        guard let panel,
              let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = Self.panelSize
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + Self.bottomInset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    private static func openMicSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
