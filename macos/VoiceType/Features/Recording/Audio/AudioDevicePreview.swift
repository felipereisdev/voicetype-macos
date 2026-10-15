@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import Observation
import os.log

// Live mic level preview for Settings → Áudio. Owns a dedicated AVAudioEngine
// kept entirely separate from `AudioRecorder`: production capture and preview
// must never share an engine instance, otherwise the HAL input-bus claim
// collides on hot-swap.
//
// macOS allows multiple AVAudioEngine instances to coexist, but only one can
// hold a given input device exclusively at a time. Callers are expected to
// stop the preview before triggering production recording — handled today by
// Settings.onDisappear (window dismissal precedes the global shortcut).
@MainActor
@Observable
final class AudioDevicePreview {

    var level: Float = 0

    var isActive: Bool { engine != nil }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var currentUID: String?
    @ObservationIgnored private var lastEmittedAt: CFTimeInterval = 0
    @ObservationIgnored private var lastReconfigAt: CFTimeInterval = 0
    @ObservationIgnored private var reconfigBurst = 0
    @ObservationIgnored private nonisolated(unsafe) var configChangeObserver: NSObjectProtocol?

    private let logger = Logger(subsystem: "VoiceType", category: "AudioDevicePreview")
    // ~30 Hz cap to avoid SwiftUI churn under high tap rates.
    private let minInterval: CFTimeInterval = 1.0 / 30.0

    func start(deviceUID: String?) {
        let normalized = (deviceUID?.isEmpty == true) ? nil : deviceUID
        if engine != nil, normalized == currentUID { return }
        stop()

        let engine = AVAudioEngine()
        configureInputDevice(uid: normalized, engine: engine)

        // Tap the live *hardware input* format. `inputFormat(forBus:)` is what
        // `installTap` validates against — `outputFormat(forBus:)` can report a
        // different rate while the device renegotiates (e.g. HyperX QuadCast
        // settles at 24 kHz), producing a "Format mismatch" / "config change
        // pending" tap failure and a HAL error storm.
        let hwFormat = engine.inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            logger.warning("Preview: invalid input format for device \(normalized ?? "<default>", privacy: .public)")
            return
        }

        installLevelTap(on: engine, format: hwFormat)
        // Commit provisionally so `isActive` and the start-dedup reflect intent
        // while the (blocking) engine.start() runs off-main.
        self.engine = engine
        self.currentUID = normalized

        Task { [weak self] in
            for attempt in 1...3 {
                do {
                    try await Self.startEngine(engine)
                    // A newer start()/stop() may have replaced the engine while
                    // we were starting — if so, this one is orphaned; tear down.
                    guard let self, self.engine === engine else {
                        engine.stop()
                        return
                    }
                    self.installConfigObserver(for: engine)
                    return
                } catch {
                    guard let self, self.engine === engine else {
                        engine.stop()
                        return
                    }
                    self.logger.warning("Preview start attempt \(attempt, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    // -10868 (Initialize / format mismatch) fires when the HW
                    // input format shifts after we read it — e.g. AirPods
                    // switching A2DP→HFP drops from 48 kHz stereo to 24 kHz
                    // mono. Re-read the live format, rebuild the tap, retry.
                    if attempt < 3 {
                        let hw = engine.inputNode.inputFormat(forBus: 0)
                        if hw.sampleRate > 0, hw.channelCount > 0 {
                            self.installLevelTap(on: engine, format: hw)
                        }
                        try? await Task.sleep(for: .seconds(0.2))
                    } else {
                        self.stop()
                    }
                }
            }
        }
    }

    func stop() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        if let engine {
            teardown(engine)
        }
        engine = nil
        currentUID = nil
        level = 0
        lastEmittedAt = 0
        lastReconfigAt = 0
        reconfigBurst = 0
    }

    // Stop + release an engine safely. Deallocating an AVAudioEngine
    // synchronously while CoreAudio is mid device-swap races the HAL property
    // listener still firing on the AVAudioIOUnit queue → EXC_BAD_ACCESS in
    // -[AVAudioEngine dealloc]. Hold the last strong ref and drop it on the
    // next main-loop turn so that in-flight listener drains first.
    private func teardown(_ engine: AVAudioEngine) {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        DispatchQueue.main.async { _ = engine }
    }

    deinit {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // Dedicated queue for the *blocking* AVAudioEngine.start(). The HAL's
    // StartAndWaitForState can block for seconds when a USB device is slow to
    // spin up its IO (HyperX QuadCast returns error 35 / EAGAIN a few times
    // first). Running it on the MainActor froze the Settings UI.
    nonisolated private static let startQueue = DispatchQueue(
        label: "com.voicetype.AudioDevicePreview.start", qos: .userInitiated
    )

    nonisolated private static func startEngine(_ engine: AVAudioEngine) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            startQueue.async {
                do {
                    try engine.start()
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func updateLevel(_ value: Float) {
        let now = CACurrentMediaTime()
        if now - lastEmittedAt < minInterval { return }
        lastEmittedAt = now
        level = value
    }

    // Mirror AudioRecorder.configureInputDevice: pin only an explicit,
    // non-default device; the engine already binds to the default (G-030).
    private func configureInputDevice(uid: String?, engine: AVAudioEngine) {
        guard let uid,
              let deviceID = AudioDeviceResolver.deviceID(forUID: uid),
              deviceID != AudioDeviceResolver.defaultInputDeviceID() else { return }
        do {
            try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            logger.info("Preview: failed to pin device \(deviceID), falling back to default: \(error.localizedDescription, privacy: .public)")
        }
    }

    // RMS level tap. Runs on AVFoundation's render thread; hops to the main
    // actor only to publish the level.
    private func installLevelTap(on engine: AVAudioEngine, format: AVAudioFormat) {
        let inputNode = engine.inputNode
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            guard frames > 0 else { return }
            let samples = UnsafeBufferPointer(start: channels[0], count: frames)
            var sum: Float = 0
            for sample in samples { sum += sample * sample }
            let rms = sqrtf(sum / Float(frames))
            // Normalize RMS into [0, 1]. Speech RMS sits around 0.05 – 0.3;
            // clamp + light gain so the bar reads naturally for casual talk.
            let normalized = min(1, max(0, rms * 4))
            Task { @MainActor in self.updateLevel(normalized) }
        }
    }

    private func installConfigObserver(for engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigChange() }
        }
    }

    // Re-arm after an AirPods/AirPlay/device swap. The engine has already
    // re-routed to the new hardware, so reinstall the (invalidated) tap in
    // place and restart it — never tear the engine down here. Deallocating
    // mid-swap is exactly what crashed -[AVAudioEngine dealloc] against the
    // still-live HAL listener. Only fall back to a full restart if the route
    // vanished and the engine can no longer report a valid input format.
    private func handleConfigChange() {
        guard let engine else { return }

        // Storm guard: some devices (HyperX QuadCast) renegotiate their sample
        // rate in a tight loop, firing config-change repeatedly. Chasing every
        // one re-pokes the HAL and feeds an endless -10877 error storm. If we
        // see a burst of rapid changes, stop the preview entirely rather than
        // fight it — the meter is non-essential.
        let now = CACurrentMediaTime()
        if now - lastReconfigAt < 0.4 {
            reconfigBurst += 1
            if reconfigBurst > 5 {
                logger.warning("Preview: configuration-change storm, stopping preview")
                stop()
                return
            }
        } else {
            reconfigBurst = 0
        }
        lastReconfigAt = now

        let uid = currentUID
        let hwFormat = engine.inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            stop()
            start(deviceUID: uid)
            return
        }
        installLevelTap(on: engine, format: hwFormat)
        guard !engine.isRunning else { return }
        Task { [weak self] in
            do {
                try await Self.startEngine(engine)
            } catch {
                self?.logger.warning("Preview reconfig restart failed: \(error.localizedDescription, privacy: .public)")
                if self?.engine === engine { self?.stop() }
            }
        }
    }
}
