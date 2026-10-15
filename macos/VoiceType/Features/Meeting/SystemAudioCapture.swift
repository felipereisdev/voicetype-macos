@preconcurrency import AVFoundation
import Core
import CoreAudio
import os

/// System-audio track of a meeting: a global process tap (every process except
/// VoiceType itself) → private aggregate device clocked by the default output →
/// IOProc writing straight to the segment file.
///
/// Global-minus-self instead of an include-list by bundle: an include-list is
/// static per PID, so every Teams helper that spawns mid-call forces a rebuild
/// and fragments the file (#74 spike 1).
///
/// The IOProc runs on `ioQueue`, never on the main actor (see gotchas: no
/// `MainActor.assumeIsolated` from CoreAudio callbacks). It only wraps the
/// buffer and writes it.
@MainActor
final class SystemAudioCapture {
    nonisolated static let aggregateUIDPrefix = "com.macsilva.VoiceType.meeting-tap."
    nonisolated static let aggregateName = "VoiceType Meeting Tap"

    enum Failure: Error, CustomStringConvertible {
        case unsupportedOS
        case noOutputDevice
        case unsupportedTapFormat
        case coreAudio(String, OSStatus)

        var description: String {
            switch self {
            case .unsupportedOS: return "captura do sistema exige macOS 14.2+"
            case .noOutputDevice: return "nenhuma saída de áudio padrão"
            case .unsupportedTapFormat: return "formato do tap não suportado"
            case .coreAudio(let op, let status): return "\(op) falhou (\(status))"
            }
        }
    }

    /// Called on the main actor when the tap must be rebuilt: default output
    /// changed, or the aggregate's nominal rate changed under us (AirPods
    /// A2DP→HFP switch keeps the same device but drops it to 24 kHz).
    var onNeedsRebuild: (() -> Void)?

    private(set) var sampleRate: Double = 0
    private var outputUID: String?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var rateListener: AudioObjectPropertyListenerBlock?
    private let ioQueue = DispatchQueue(label: "com.voicetype.meeting.system-io", qos: .userInitiated)
    nonisolated private static let log = Logger(subsystem: "VoiceType", category: "meeting")

    /// Builds tap + aggregate and returns the format the segment must be
    /// written in. Call `run(file:onFirstSample:)` next, or `stop()` to abort.
    func prepare() throws -> AVAudioFormat {
        stop()
        guard #available(macOS 14.2, *) else { throw Failure.unsupportedOS }
        guard let outUID = Self.defaultOutputUID() else { throw Failure.noOutputDevice }

        let excluded = Self.ownProcessObject().map { [$0] } ?? []
        let desc = CATapDescription(monoGlobalTapButExcludeProcesses: excluded)
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        desc.name = Self.aggregateName
        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else {
            tapID = AudioObjectID(kAudioObjectUnknown)
            throw Failure.coreAudio("AudioHardwareCreateProcessTap", status)
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: Self.aggregateName,
            kAudioAggregateDeviceUIDKey: Self.aggregateUIDPrefix + UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID)
        guard status == noErr else {
            aggregateID = AudioObjectID(kAudioObjectUnknown)
            stop()
            throw Failure.coreAudio("AudioHardwareCreateAggregateDevice", status)
        }

        var asbd = AudioStreamBasicDescription()
        var address = Self.address(kAudioTapPropertyFormat)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &asbd)
        guard status == noErr, asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32,
              asbd.mChannelsPerFrame > 0 else {
            stop()
            throw Failure.unsupportedTapFormat
        }

        // The tap's own rate can lie (spike: 48 kHz reported, aggregate at
        // 24 kHz under AirPods HFP → 2× speed). Write at the aggregate's clock.
        let aggregateRate = Self.nominalRate(of: aggregateID)
        let rate = MeetingCaptureRate.writeRate(aggregateNominal: aggregateRate, tapReported: asbd.mSampleRate)
        guard rate > 0, let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: rate,
            channels: asbd.mChannelsPerFrame,
            interleaved: asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
        ) else {
            stop()
            throw Failure.unsupportedTapFormat
        }

        outputUID = outUID
        sampleRate = rate
        addListeners()
        Self.log.info("system tap ready: out=\(outUID, privacy: .public) aggregateRate=\(aggregateRate) tapRate=\(asbd.mSampleRate) ch=\(asbd.mChannelsPerFrame)")
        return format
    }

    /// Starts IO into `file` (whose processing format is what `prepare()`
    /// returned). `onFirstSample` gets the host time of the first buffer.
    func run(file: AVAudioFile, onFirstSample: @escaping @Sendable (UInt64) -> Void) throws {
        let block = Self.makeIOBlock(file: file, onFirstSample: onFirstSample)
        var status = AudioDeviceCreateIOProcIDWithBlock(&ioProcID, aggregateID, ioQueue, block)
        guard status == noErr else { throw Failure.coreAudio("AudioDeviceCreateIOProcIDWithBlock", status) }
        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else { throw Failure.coreAudio("AudioDeviceStart", status) }
    }

    /// Stops IO, drains the IO queue (so the file closes after the last
    /// write), and destroys aggregate + tap. Idempotent.
    func stop() {
        removeListeners()
        if let ioProcID, aggregateID != kAudioObjectUnknown {
            AudioDeviceStop(aggregateID, ioProcID)
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
        }
        ioProcID = nil
        ioQueue.sync {}
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tapID) }
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        outputUID = nil
        sampleRate = 0
    }

    /// Aggregates left over from a crash while recording. Call at boot,
    /// before any capture starts — anything with our prefix is an orphan.
    nonisolated static func destroyOrphanAggregates() {
        for id in AudioDeviceResolver.allInputDeviceIDs() {
            guard let uid = AudioDeviceResolver.deviceUID(for: id), uid.hasPrefix(aggregateUIDPrefix) else { continue }
            let status = AudioHardwareDestroyAggregateDevice(id)
            log.info("destroyed orphan meeting aggregate \(uid, privacy: .public): \(status)")
        }
    }

    // MARK: - IO

    nonisolated private static func makeIOBlock(
        file: AVAudioFile,
        onFirstSample: @escaping @Sendable (UInt64) -> Void
    ) -> AudioDeviceIOBlock {
        let format = file.processingFormat
        // Only touched from the serial ioQueue.
        var sawFirst = false
        var loggedWriteError = false
        return { _, inputData, inputTime, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inputData, deallocator: nil),
                  buffer.frameLength > 0 else { return }
            if !sawFirst {
                sawFirst = true
                onFirstSample(inputTime.pointee.mHostTime)
            }
            do {
                try file.write(from: buffer)
            } catch where !loggedWriteError {
                loggedWriteError = true
                log.error("system segment write failed: \(error.localizedDescription, privacy: .public)")
            } catch {}
        }
    }

    // MARK: - Listeners

    private func addListeners() {
        let output: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.checkOutput() }
        }
        var outputAddress = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outputAddress, .main, output) == noErr {
            outputListener = output
        }
        let rate: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.checkRate() }
        }
        var rateAddress = Self.address(kAudioDevicePropertyNominalSampleRate)
        if AudioObjectAddPropertyListenerBlock(aggregateID, &rateAddress, .main, rate) == noErr {
            rateListener = rate
        }
    }

    private func removeListeners() {
        if let outputListener {
            var a = Self.address(kAudioHardwarePropertyDefaultSystemOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, outputListener)
        }
        if let rateListener, aggregateID != kAudioObjectUnknown {
            var a = Self.address(kAudioDevicePropertyNominalSampleRate)
            AudioObjectRemovePropertyListenerBlock(aggregateID, &a, .main, rateListener)
        }
        outputListener = nil
        rateListener = nil
    }

    private func checkOutput() {
        guard let outputUID, Self.defaultOutputUID() != outputUID else { return }
        Self.log.info("default output changed → rebuild system tap")
        onNeedsRebuild?()
    }

    private func checkRate() {
        guard aggregateID != kAudioObjectUnknown else { return }
        let rate = Self.nominalRate(of: aggregateID)
        guard rate > 0, rate != sampleRate else { return }
        Self.log.info("aggregate rate \(self.sampleRate) → \(rate) → rebuild system tap")
        onNeedsRebuild?()
    }

    // MARK: - HAL helpers

    nonisolated private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    nonisolated private static func defaultOutputUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return AudioDeviceResolver.deviceUID(for: device)
    }

    nonisolated private static func nominalRate(of device: AudioObjectID) -> Double {
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr else { return 0 }
        return rate
    }

    /// Our own CoreAudio process object, to exclude from the global tap. Nil
    /// when VoiceType hasn't touched audio yet — then there's nothing to exclude.
    nonisolated private static func ownProcessObject() -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = ProcessInfo.processInfo.processIdentifier
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        guard status == noErr, object != kAudioObjectUnknown else { return nil }
        return object
    }
}
