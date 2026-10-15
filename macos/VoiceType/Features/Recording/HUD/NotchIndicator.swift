import AppKit
import SwiftUI

// MARK: - View

/// Notch-expanding indicator view. Sits flush against the top edge of the
/// screen, expands into a Dynamic-Island-style pill when state is recording
/// or processing, and collapses otherwise. The view is intentionally kept
/// small — animation is driven by SwiftUI state diffing via `.animation`.
private struct NotchIndicatorView: View {
    let state: HUDState
    let geometry: NotchGeometry
    let preset: WaveformColorPreset

    @State private var expanded = false

    private var shouldShow: Bool {
        switch state {
        case .recording, .processing: true
        default: false
        }
    }

    private var isWorking: Bool {
        if case .processing = state { return true }
        return false
    }

    private let expandedHeight: CGFloat = 50
    private let collapsedDeltaHeight: CGFloat = -4
    private let collapsedDeltaWidth: CGFloat = -8
    private let expandedDeltaWidth: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(cornerRadius: expanded ? 18 : 10)
                    .fill(.black)
                    .frame(
                        width: geometry.notchWidth + (expanded ? expandedDeltaWidth : collapsedDeltaWidth),
                        height: geometry.safeAreaTop + (expanded ? expandedHeight : collapsedDeltaHeight)
                    )

                if expanded {
                    waveformOrProgress
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: expanded)
        .onAppear {
            // Defer one tick so the spring animates from the collapsed shape.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                expanded = shouldShow
            }
        }
        .onChange(of: shouldShow) { _, show in
            expanded = show
        }
    }

    @ViewBuilder
    private var waveformOrProgress: some View {
        switch state {
        case .recording(let level, _, let locked):
            AuroraWaveform(level: normalizedLevel(level), preset: preset)
                .frame(
                    width: geometry.notchWidth - 10,
                    height: expandedHeight - 14
                )
                .overlay(alignment: .leading) {
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, geometry.safeAreaTop + 4)
                .transition(.opacity)
        case .processing:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(.white)
                .colorScheme(.dark)
                .padding(.top, geometry.safeAreaTop + 12)
        case .hidden, .permissionDenied:
            EmptyView()
        }
    }

    private func normalizedLevel(_ dB: Float) -> Float {
        max(0, min(1, (dB + 60) / 60))
    }
}

// MARK: - Panel controller

/// Owns the notch-indicator `NSPanel`. Layout is full-width across the active
/// screen so the dark notch shape can sit centered over the hardware notch.
/// The panel is non-activating, ignores mouse, and stays on every space —
/// same contract the pill HUD uses.
@MainActor
final class NotchIndicatorPanel {

    private var panel: NSPanel?
    private var host: NSHostingView<NotchIndicatorView>?
    private let geometry = NotchGeometry()
    private var currentPreset: WaveformColorPreset = .aurora
    private var currentState: HUDState = .hidden

    private static let panelHeight: CGFloat = 500

    var hasPanelForTesting: Bool { panel != nil }
    var geometryForTesting: NotchGeometry { geometry }

    func show(state: HUDState, preset: WaveformColorPreset) {
        guard let screen = NSScreen.main else { return }
        geometry.update(for: screen)
        guard geometry.hasNotch else { return }

        currentPreset = preset
        currentState = state

        if panel == nil {
            buildPanel(on: screen)
        }
        positionPanel(on: screen)
        setRootView(state: state)
        panel?.orderFrontRegardless()
    }

    func update(state: HUDState) {
        guard panel != nil else { return }
        currentState = state
        setRootView(state: state)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        host = nil
        currentState = .hidden
    }

    // MARK: - Private

    private func buildPanel(on screen: NSScreen) {
        let width = screen.frame.width
        let height = Self.panelHeight
        let rect = NSRect(x: 0, y: 0, width: width, height: height)

        let panel = NonActivatingPanel(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        // Set level last — `isFloatingPanel = true` flips it to `.floating`.
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(
            rootView: NotchIndicatorView(
                state: currentState,
                geometry: geometry,
                preset: currentPreset
            )
        )
        host.frame = rect
        panel.contentView = host

        self.panel = panel
        self.host = host
    }

    private func positionPanel(on screen: NSScreen) {
        guard let panel else { return }
        let width = screen.frame.width
        let height = Self.panelHeight
        let frame = screen.frame
        let x = frame.origin.x
        let y = frame.origin.y + frame.height - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }

    private func setRootView(state: HUDState) {
        host?.rootView = NotchIndicatorView(
            state: state,
            geometry: geometry,
            preset: currentPreset
        )
    }
}
