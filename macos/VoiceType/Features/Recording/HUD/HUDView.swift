import SwiftUI
import AppKit

struct HUDView: View {
    let state: HUDState
    let onOpenMicSettings: () -> Void
    var preset: WaveformColorPreset = .aurora

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(width: 296, height: 96)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .recording(let level, let elapsed, let locked):
            HStack(spacing: 12) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.red)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                }
                AuroraWaveform(level: normalizedLevel(level), preset: preset)
                Text(formatElapsed(elapsed))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.white)
            }
        case .processing:
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Processando…")
                    .foregroundStyle(.white)
            }
        case .permissionDenied:
            VStack(spacing: 6) {
                Text("Permita o microfone em Configurações")
                    .font(.system(.callout))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Button("Abrir Configurações") {
                    onOpenMicSettings()
                }
                .controlSize(.small)
            }
        }
    }

    private func normalizedLevel(_ dB: Float) -> Float {
        max(0, min(1, (dB + 60) / 60))
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let secs = Int(t)
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }
}

#Preview("Recording") {
    HUDView(state: .recording(level: -12, elapsed: 4.2), onOpenMicSettings: {})
        .padding()
        .background(Color.black)
}

#Preview("Processing") {
    HUDView(state: .processing, onOpenMicSettings: {})
        .padding()
        .background(Color.black)
}

#Preview("Permission denied") {
    HUDView(state: .permissionDenied, onOpenMicSettings: {})
        .padding()
        .background(Color.black)
}
