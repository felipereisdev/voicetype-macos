@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import os.log

// Test seam — production AudioRecorder + mocks both conform.
@MainActor
protocol AudioRecorderProtocol: AnyObject {
    var levelStream: AsyncStream<Float> { get }
    func start(deviceUID: String?) async throws
    func stop() async throws -> Data
}

// Captures microphone audio via AVAudioEngine, downsamples to 16 kHz mono
// Int16 PCM, and emits a finished WAV blob on stop. RMS dB levels are
// pushed to `levelStream` for the HUD waveform.
@MainActor
final class AudioRecorder: AudioRecorderProtocol {

    enum AuthProbe {
        case real
        case alwaysGranted
        case alwaysDenied
    }

    init(authProbe: AuthProbe = .real) {
        self.authProbe = authProbe
    }

    // Async stream of RMS dB-FS values (range roughly -60 ... 0).
    // Built lazily by `start()`. Subscribers fetched before `start()` get an
    // empty terminated stream; subscribers fetched after get the live one.
    var levelStream: AsyncStream<Float> {
        publicLevelStream ?? AsyncStream { $0.finish() }
    }

    func start(deviceUID: String?) async throws {
        guard !isRunning else { return }

        try await ensurePermission()

        // Fresh engine per session — reusing across device disconnects leaves the
        // graph in an inconsistent state and `installTap` crashes with a
        // sampleRate-mismatch assertion.
        let engine = AVAudioEngine()

        do {
            Self.configureInputDevice(uid: deviceUID, engine: engine)
            await Self.awaitStableInputFormat(engine)

            let stream = AsyncStream<Float> { cont in
                self.levelContinuation = cont
            }
            self.publicLevelStream = stream

            try buildEngine(engine: engine)
            try installTap(engine: engine)
            registerDeviceObservers(engine: engine)

            do {
                try await startWithRetry { try await Self.startEngine(engine) }
                os_log("AudioRecorder: engine started; hw=%{public}@",
                       log: .default, type: .info,
                       engine.inputNode.inputFormat(forBus: 0).description)
            } catch {
                // Clean up the locally-built graph before propagating. `self.engine`
                // is still nil at this point, so tearDown() can't reach it.
                engine.inputNode.removeTap(onBus: 0)
                engine.stop()
                unregisterDeviceObservers()
                levelContinuation?.finish()
                levelContinuation = nil
                publicLevelStream = nil
                accumulated.removeAll()
                throw AudioRecorderError.engineFailure(error.localizedDescription)
            }
        } catch {
            // Any failure before engine.start() succeeded — drop the local engine
            // and reset transient state.
            engine.inputNode.removeTap(onBus: 0)
            unregisterDeviceObservers()
            levelContinuation?.finish()
            levelContinuation = nil
            publicLevelStream = nil
            accumulated.removeAll()
            throw error
        }

        // Engine is fully started — commit it to instance state.
        self.engine = engine
        isRunning = true
        startedAt = Date()
    }

    func stop() async throws -> Data {
        guard isRunning, let engine = self.engine else {
            // Defensive reset in case isRunning drifted from engine state.
            isRunning = false
            self.engine = nil
            return Data()
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        unregisterDeviceObservers()
        isRunning = false
        self.engine = nil

        os_log("AudioRecorder: stop; captured %d samples (%.2fs @ %dHz)",
               log: .default, type: .info,
               accumulated.count,
               Double(accumulated.count) / Double(targetSampleRate),
               targetSampleRate)
        let pcm = WavEncoder.encodeSamplesToInt16LE(accumulated)
        accumulated.removeAll(keepingCapacity: false)
        levelContinuation?.finish()
        levelContinuation = nil
        publicLevelStream = nil

        return WavEncoder.encode(pcmInt16LE: pcm, sampleRate: targetSampleRate, channels: 1)
    }

    // AVAudioEngine.start() falha transientemente quando o HAL ainda está
    // renegociando sample rate após hot-swap de device. Sotto observa o mesmo
    // padrão (`AudioCaptureService.swift:186-199`); três tentativas com backoff
    // curto eliminam essa classe de falha. Total no pior caso: 0.95s.
    // `nonisolated` para que possa ser usada como default argument em
    // `startWithRetry(delays:start:)` — defaults são avaliados no contexto
    // do caller, que pode ser não-isolado em Swift 6.
    nonisolated static let defaultRetryDelays: [TimeInterval] = [0.15, 0.30, 0.50]

    // Dedicated queue for the *blocking* AVAudioEngine.start(). On macOS,
    // `engine.start()` calls into the HAL's StartAndWaitForState, which can
    // block for seconds when a USB device is slow to spin up its IO (HyperX
    // QuadCast returns `error 35` / EAGAIN a few times before the stream
    // comes up). Running that on the MainActor froze the UI long enough for
    // the OS to flag the app non-responsive (Force Quit). Hop off-main.
    nonisolated private static let startQueue = DispatchQueue(
        label: "com.voicetype.AudioRecorder.start", qos: .userInitiated
    )

    // Runs the blocking start off the main thread. `AVAudioEngine` is not
    // Sendable; capture is safe here because `start()` only commits the engine
    // to instance state *after* this returns, so no other context touches it
    // concurrently. `@preconcurrency import AVFoundation` suppresses the
    // Sendable diagnostic on the capture.
    nonisolated static func startEngine(_ engine: AVAudioEngine) async throws {
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

    /// Tenta `start` em loop com backoff. `delays.count` define o número de
    /// tentativas; `delays[i]` é o intervalo APÓS a tentativa `i` falhar.
    /// O último delay nunca é aplicado (sem sentido esperar após esgotar).
    /// `await Task.sleep` mantém MainActor cooperativo — `Thread.sleep`
    /// bloquearia a UI por até `delays.reduce(0, +)`.
    /// Re-lança o último erro capturado sem wrap; o caller decide como
    /// reportar (o site atual em `start(deviceUID:)` envolve em `engineFailure`).
    func startWithRetry(
        delays: [TimeInterval] = AudioRecorder.defaultRetryDelays,
        start: () async throws -> Void
    ) async throws {
        precondition(!delays.isEmpty, "retry delays must have at least one entry")
        var lastError: Error?
        for (index, delay) in delays.enumerated() {
            do {
                try await start()
                return
            } catch {
                lastError = error
                os_log(
                    "AudioRecorder: engine.start attempt %d/%d failed: %{public}@",
                    log: .default, type: .info,
                    index + 1, delays.count, error.localizedDescription
                )
                if index < delays.count - 1 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
        throw lastError ?? AudioRecorderError.engineFailure("engine.start failed")
    }

    private let targetSampleRate: Int = 16_000
    private let authProbe: AuthProbe

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var tapFormat: AVAudioFormat?
    private var accumulated: [Float] = []
    private var isRunning = false
    private var startedAt: Date?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var publicLevelStream: AsyncStream<Float>?
    private var configChangeObserver: NSObjectProtocol?

    private func ensurePermission() async throws {
        switch authProbe {
        case .alwaysGranted: return
        case .alwaysDenied: throw AudioRecorderError.permissionDenied
        case .real: break
        }
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw AudioRecorderError.permissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw AudioRecorderError.permissionDenied }
        @unknown default:
            throw AudioRecorderError.permissionDenied
        }
    }

    // Best-effort pinning to a HAL device. On failure, fall back to AVAudioEngine's
    // default input — keeps capture working when a previously-selected device has
    // disappeared (USB unplug, AirPods drop, aggregate device removed). Permission
    // and "no input at all" are checked elsewhere.
    //
    // Only pins when the caller asked for a specific device that differs from the
    // current default. A fresh engine already binds to the system default, and
    // re-pinning it forces an AUHAL reconfiguration — with AirPods that collided
    // with the A2DP→HFP switch and wedged the AVAudioIOUnit queue, hanging the
    // main thread in `inputFormat(forBus:)` for 50s+ (G-030).
    static func configureInputDevice(uid: String?, engine: AVAudioEngine) {
        guard let uid else { return }
        guard let deviceID = AudioDeviceResolver.deviceID(forUID: uid) else {
            os_log("AudioRecorder: input device %{public}@ not found; using system default", log: .default, type: .info, uid)
            return
        }
        guard deviceID != AudioDeviceResolver.defaultInputDeviceID() else { return }

        do {
            try engine.inputNode.auAudioUnit.setDeviceID(deviceID)
        } catch {
            os_log(
                "AudioRecorder: failed to pin input device %{public}u — falling back to default: %{public}@",
                log: .default, type: .info,
                deviceID, error.localizedDescription
            )
        }
    }

    // If the hardware input is multi-channel, downmix to mono *before* the
    // converter — multi-channel taps on some devices also trip the
    // sampleRate-mismatch assertion after a device hot-swap.
    static func monoTapFormat(for inputFormat: AVAudioFormat) -> AVAudioFormat {
        if inputFormat.channelCount > 1,
           let mono = AVAudioFormat(
               commonFormat: .pcmFormatFloat32,
               sampleRate: inputFormat.sampleRate,
               channels: 1,
               interleaved: false
           ) {
            return mono
        }
        return inputFormat
    }

    // After pinning a device, the HAL can still be renegotiating its nominal
    // sample rate (HyperX QuadCast first start, USB / aggregate hot-swap). In
    // that window the node's hardware input format and its output format
    // diverge, and reading too early feeds `installTap` a mismatched rate —
    // whose assertion is fatal and uncatchable. Poll until the hardware input
    // format is nonzero and agrees with the output format before building the
    // graph. Stable devices return on the first check with no sleep; only a
    // flaky device pays the backoff (worst case ~0.5s).
    static func awaitStableInputFormat(_ engine: AVAudioEngine) async {
        let inputNode = engine.inputNode
        for delay in [0.05, 0.10, 0.15, 0.20] {
            let hw = inputNode.inputFormat(forBus: 0)
            if hw.sampleRate > 0,
               hw.sampleRate == inputNode.outputFormat(forBus: 0).sampleRate {
                return
            }
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    private func buildEngine(engine: AVAudioEngine) throws {
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioRecorderError.formatUnsupported
        }

        let tapFormat = Self.monoTapFormat(for: inputFormat)
        self.tapFormat = tapFormat

        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(targetSampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.formatUnsupported
        }
        self.targetFormat = target

        // Converter must take the format that will actually arrive at the tap
        // callback — that's tapFormat, not the raw hardware format.
        guard let converter = AVAudioConverter(from: tapFormat, to: target) else {
            throw AudioRecorderError.formatUnsupported
        }
        self.converter = converter
        engine.prepare()
    }

    private func installTap(engine: AVAudioEngine) throws {
        // `installTap` fatally asserts `tapFormat.sampleRate ==
        // inputHWFormat.sampleRate`, where `inputHWFormat` is the node's live
        // *hardware input* format — `inputFormat(forBus:)`, NOT
        // `outputFormat(forBus:)`. The two normally agree, but while a device
        // renegotiates its sample rate (HyperX QuadCast on first start, USB /
        // aggregate hot-swap) they diverge, and an `outputFormat`-derived tap
        // format crashes. Derive the tap format from the very format the
        // assertion checks against, and realign the converter to it.
        let hwFormat = engine.inputNode.inputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            throw AudioRecorderError.formatUnsupported
        }
        let tapFormat = Self.monoTapFormat(for: hwFormat)
        self.tapFormat = tapFormat
        if let target = targetFormat {
            guard let converter = AVAudioConverter(from: tapFormat, to: target) else {
                throw AudioRecorderError.formatUnsupported
            }
            self.converter = converter
        }

        // Defensive: any tap left over from a prior session would crash installTap.
        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleTap(buffer: buffer)
            }
        }
    }

    // RMS → dB-FS conversion, clamped to [-60, 0]. Differs from the Electron HUD
    // which uses raw peak with exponential decay (see useAudioCapture.ts). dB is
    // friendlier for a bar visualizer because it compresses the dynamic range;
    // the HUD applies its own decay before rendering.
    private func handleTap(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)
        guard let outBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outCapacity
        ) else { return }

        var consumed = false
        let status = converter.convert(to: outBuffer, error: nil) { _, statusOut in
            if consumed { statusOut.pointee = .noDataNow; return nil }
            consumed = true
            statusOut.pointee = .haveData
            return buffer
        }
        guard status != .error,
              let channelData = outBuffer.floatChannelData?[0] else { return }

        let frameLength = Int(outBuffer.frameLength)
        guard frameLength > 0 else { return }
        let samples = UnsafeBufferPointer(start: channelData, count: frameLength)

        var sumSquares: Float = 0
        for sample in samples { sumSquares += sample * sample }
        let rms = sqrtf(sumSquares / Float(frameLength))
        let db = 20 * log10f(max(rms, 1e-6))
        let clamped = max(-60, min(0, db))
        levelContinuation?.yield(clamped)

        accumulated.append(contentsOf: samples)
    }

    private func registerDeviceObservers(engine: AVAudioEngine) {
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }

        // CoreAudio HAL listener for device list changes (USB unplug, AirPods drop).
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        _ = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address, DispatchQueue.main
        ) { [weak self] _, _ in
            Task { @MainActor in self?.handleDeviceListChange() }
        }
    }

    private func unregisterDeviceObservers() {
        if let token = configChangeObserver {
            NotificationCenter.default.removeObserver(token)
            configChangeObserver = nil
        }
        // The block listener is anonymous; CoreAudio cleans it up on process exit.
        // Removal would require holding the same block reference, which Swift's
        // escaping closure does not preserve. Phase 4 may revisit if Instruments
        // shows a leak.
    }

    private func handleConfigurationChange() {
        guard isRunning, let engine = self.engine else { return }
        if engine.inputNode.outputFormat(forBus: 0).sampleRate == 0 {
            emitDisconnect()
        }
    }

    private func handleDeviceListChange() {
        guard isRunning, self.engine != nil else { return }
        if AudioDeviceResolver.defaultInputDeviceID() == nil {
            emitDisconnect()
        }
    }

    private func emitDisconnect() {
        levelContinuation?.finish()
        levelContinuation = nil
        Task { @MainActor in
            _ = try? await self.stop()
            NotificationCenter.default.post(
                name: .audioRecorderDisconnected,
                object: self
            )
        }
    }

    private func tearDown() {
        if let engine = self.engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        self.engine = nil
        unregisterDeviceObservers()
        levelContinuation?.finish()
        levelContinuation = nil
        publicLevelStream = nil
        accumulated.removeAll()
        isRunning = false
    }
}

extension Notification.Name {
    static let audioRecorderDisconnected = Notification.Name("voicetype.AudioRecorder.disconnected")
}
