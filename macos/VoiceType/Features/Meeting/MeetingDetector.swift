import AppKit
import Core
import CoreAudio
import Darwin
import Foundation
import os
import SwiftUI

/// Watches which apps hold the mic and starts/stops `MeetingRecorder` when a
/// meeting app does (#74). Mode comes from `AppConfig.meetingDetectionMode`:
/// `ask` shows `MeetingPromptPanel` (records after a countdown unless dismissed), `auto` records right
/// away, `off` stops scanning.
///
/// Polls CoreAudio every 2 s off the main thread (no subprocess); the
/// debounce/grace logic lives in Core (`MeetingDetection`). Only recordings
/// it started stop on their own when the meeting ends.
@MainActor
final class MeetingDetector {
    private let recorder: MeetingRecorder
    private let config: ConfigStoreSnapshot
    private let notifier: Notifier
    private var detection = MeetingDetection()
    private let prompt = MeetingPromptPanel()
    private var loop: Task<Void, Never>?
    private static let log = Logger(subsystem: "VoiceType", category: "meeting-detect")

    init(recorder: MeetingRecorder, config: ConfigStoreSnapshot, notifier: Notifier) {
        self.recorder = recorder
        self.config = config
        self.notifier = notifier
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func poll() async {
        let mode = config.config.meetingDetectionMode
        guard mode == "ask" || mode == "auto" else {
            detection.reset()
            return
        }
        let selfPID = getpid()
        let apps = await Task.detached(priority: .utility) {
            MicUsers.meetingApps(excluding: selfPID)
        }.value

        switch detection.tick(now: Date(), apps: apps) {
        case .started(let app)?:
            Self.log.notice("meeting detected: \(app.name, privacy: .public) mode=\(mode, privacy: .public)")
            guard !recorder.isRecording else { return }
            if mode == "auto" {
                await recorder.start(detected: app)
                if recorder.isRecording {
                    await notifier.info(title: "Gravando reunião no \(app.name)", body: "para sozinha quando a chamada terminar.")
                }
            } else {
                prompt.show(appName: app.name, onRecord: { [weak self] in
                    Task { await self?.recordFromPrompt() }
                })
            }
        case .ended(let app)?:
            prompt.hide()
            Self.log.notice("meeting ended: \(app.name, privacy: .public)")
            if recorder.isRecording && recorder.startedByDetection { recorder.stop() }
        case nil:
            break
        }
    }

    /// "Gravar" (or the countdown ran out). Detection may have flapped since
    /// the prompt (device switch, etc.); it's explicit intent, so record
    /// anyway — without an active meeting it is a manual recording.
    private func recordFromPrompt() async {
        let app = detection.activeApp
        Self.log.notice("prompt accepted: active=\(app?.name ?? "nil", privacy: .public) recording=\(self.recorder.isRecording)")
        guard !recorder.isRecording else { return }
        await recorder.start(detected: app)
    }
}

/// Who is capturing from the mic right now, via CoreAudio's process objects
/// (`kAudioProcessPropertyIsRunningInput`, macOS 14+). Validated on macOS 26:
/// a test AVAudioEngine shows up while open and drops after stop; Chrome's
/// audio-service helper reports `com.google.Chrome.helper`.
enum MicUsers {
    static func meetingApps(excluding selfPID: pid_t) -> [MeetingApp] {
        var apps: [MeetingApp] = []
        for object in processObjects() where read(object, kAudioProcessPropertyIsRunningInput, UInt32(0)) != 0 {
            let pid = read(object, kAudioProcessPropertyPID, pid_t(-1))
            guard pid != selfPID, let bundle = bundleID(object),
                  let app = MeetingApps.classify(bundleID: bundle), !apps.contains(app) else { continue }
            if app.isBrowser && !hasWebRTC(micPID: pid, bundleID: bundle) { continue }
            apps.append(app)
        }
        return apps
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func processObjects() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func read<T: BinaryInteger>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ fallback: T) -> T {
        var addr = address(selector)
        var value = fallback
        var size = UInt32(MemoryLayout<T>.size)
        let status = Swift.withUnsafeMutableBytes(of: &value) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!)
        }
        return status == noErr ? value : fallback
    }

    private static func bundleID(_ object: AudioObjectID) -> String? {
        var addr = address(kAudioProcessPropertyBundleID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: - WebRTC check (libproc)

    /// A browser holding the mic is a call only if it has WebRTC sockets. The
    /// mic and the sockets live in different processes: Chrome's audio and
    /// network services are sibling helpers (same parent); WebKit's GPU and
    /// Networking processes are XPC services of launchd.
    private static func hasWebRTC(micPID: pid_t, bundleID: String) -> Bool {
        let candidates: [pid_t]
        if bundleID.hasPrefix("com.apple.WebKit") || bundleID.hasPrefix("com.apple.Safari") {
            candidates = allPIDs().filter { executablePath($0).hasSuffix("/com.apple.WebKit.Networking") }
        } else {
            let parent = parentPID(micPID)
            let root = parent > 1 ? parent : micPID
            candidates = [root] + childPIDs(root)
        }
        return candidates.contains(where: hasWebRTCSocket)
    }

    private static func hasWebRTCSocket(_ pid: pid_t) -> Bool {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return false }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
        let got = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, bytes)
        guard got > 0 else { return false }
        for fd in fds.prefix(Int(got) / MemoryLayout<proc_fdinfo>.stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, size) == size,
                  info.psi.soi_protocol == IPPROTO_UDP else { continue }
            let inet = info.psi.soi_proto.pri_in
            if MeetingApps.isWebRTCSocket(
                localPort: UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_lport)),
                remotePort: UInt16(bigEndian: UInt16(truncatingIfNeeded: inet.insi_fport))
            ) { return true }
        }
        return false
    }

    private static func parentPID(_ pid: pid_t) -> pid_t {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? pid_t(info.pbi_ppid) : 0
    }

    private static func childPIDs(_ pid: pid_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 1024)
        let count = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    private static func allPIDs() -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 8192)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(pids.prefix(Int(count))) : []
    }

    private static func executablePath(_ pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        return proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 ? String(cString: buffer) : ""
    }
}

/// "Reunião detectada" card (Granola/Wispr pattern): top-right, non-activating,
/// on every Space incl. full-screen. Records when the countdown ends unless
/// dismissed; hovering pauses it. Replaces the system notification, whose
/// action never reached us on macOS 26.
@MainActor
final class MeetingPromptPanel {
    static let countdownSeconds = 10
    private static let size = NSSize(width: 340, height: 92)
    private var panel: NonActivatingPanel?

    func show(appName: String, onRecord: @escaping @MainActor () -> Void) {
        hide()
        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: MeetingPromptView(
            appName: appName,
            onRecord: { [weak self] in self?.hide(); onRecord() },
            onDismiss: { [weak self] in self?.hide() }
        ))
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: v.maxX - Self.size.width - 12, y: v.maxY - Self.size.height - 8))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct MeetingPromptView: View {
    let appName: String
    let onRecord: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    @State private var remaining = MeetingPromptPanel.countdownSeconds
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill").foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reunião detectada no \(appName)").font(.headline)
                    Text(hovering ? "Contagem pausada" : "Gravando em \(remaining) s…")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            HStack {
                Spacer()
                Button("Agora não", action: onDismiss)
                Button("Gravar", action: onRecord).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 340, height: 92)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .onHover { hovering = $0 }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if !hovering { remaining -= 1 }
            }
            onRecord()
        }
    }
}
