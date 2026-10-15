@preconcurrency import AVFoundation
import os

/// Microphone track of a meeting. Its own `AVAudioEngine`, independent from
/// the dictation recorder, fresh per segment (G-016: a reused engine after a
/// device swap trips the installTap sample-rate assertion).
///
/// The engine stops on `AVAudioEngineConfigurationChange` (device swap, e.g.
/// switching to AirPods — #74 spike 1), so that notification is surfaced via
/// `onConfigurationChange` and the owner restarts into a new segment.
@MainActor
final class MicCapture {
    var onConfigurationChange: (() -> Void)?

    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    /// Bumped by every start/stop; an in-flight start that sees it change bails.
    private var generation = 0
    nonisolated private static let log = Logger(subsystem: "VoiceType", category: "meeting")

    /// Starts a fresh engine on `deviceUID` (nil = system default).
    /// `openSegment` receives the format to write in and returns the file plus
    /// the first-sample callback. Throws `CancellationError` if `stop()` (or a
    /// newer `start`) ran while this one was awaiting.
    func start(
        deviceUID: String?,
        openSegment: (AVAudioFormat) throws -> (AVAudioFile, @Sendable (UInt64) -> Void)
    ) async throws {
        stop()
        let gen = generation
        let engine = AVAudioEngine()
        AudioRecorder.configureInputDevice(uid: deviceUID, engine: engine)
        await AudioRecorder.awaitStableInputFormat(engine)
        guard gen == generation else { throw CancellationError() }

        // installTap asserts against inputFormat(forBus:), not outputFormat (G-016).
        let hw = engine.inputNode.inputFormat(forBus: 0)
        guard hw.sampleRate > 0, hw.channelCount > 0 else { throw AudioRecorderError.formatUnsupported }
        let (file, onFirstSample) = try openSegment(AudioRecorder.monoTapFormat(for: hw))

        engine.inputNode.removeTap(onBus: 0)
        engine.inputNode.installTap(
            onBus: 0, bufferSize: 4096, format: file.processingFormat,
            block: Self.makeTapBlock(file: file, onFirstSample: onFirstSample)
        )
        engine.prepare()
        self.engine = engine
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onConfigurationChange?() }
        }

        // engine.start() can block for seconds on slow USB devices → off-main (G-017).
        var lastError: Error?
        for (attempt, delay) in AudioRecorder.defaultRetryDelays.enumerated() {
            do {
                try await AudioRecorder.startEngine(engine)
                guard gen == generation else {
                    engine.inputNode.removeTap(onBus: 0)
                    engine.stop()
                    throw CancellationError()
                }
                Self.log.info("mic started: \(file.processingFormat.description, privacy: .public)")
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                Self.log.info("mic start attempt \(attempt + 1) failed: \(error.localizedDescription, privacy: .public)")
                guard gen == generation else { throw CancellationError() }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        stop()
        throw AudioRecorderError.engineFailure(lastError?.localizedDescription ?? "engine.start failed")
    }

    /// Idempotent. Removing the tap releases the block, which closes the file.
    func stop() {
        generation += 1
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
    }

    // Runs on AVAudioEngine's tap thread (serial), never on the main actor.
    nonisolated private static func makeTapBlock(
        file: AVAudioFile,
        onFirstSample: @escaping @Sendable (UInt64) -> Void
    ) -> AVAudioNodeTapBlock {
        var sawFirst = false
        var loggedWriteError = false
        return { buffer, when in
            if !sawFirst {
                sawFirst = true
                onFirstSample(when.isHostTimeValid ? when.hostTime : mach_absolute_time())
            }
            do {
                try file.write(from: buffer)
            } catch where !loggedWriteError {
                loggedWriteError = true
                log.error("mic segment write failed: \(error.localizedDescription, privacy: .public)")
            } catch {}
        }
    }
}
