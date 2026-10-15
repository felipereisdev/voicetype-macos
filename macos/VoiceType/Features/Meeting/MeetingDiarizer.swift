import AVFoundation
import Core
import FluidAudio
import Foundation
import os

/// Who's who on the system track: FluidAudio offline diarization (local Core
/// ML) over the meeting's system segments, so remote voices become "Outro 1",
/// "Outro 2"… instead of one "Outros". The mic track is never diarized — it's
/// always "Você", and keeping the tracks apart means a remote voice can't be
/// clustered with the user.
///
/// Best effort: any failure (or macOS 14) returns nil and the transcript keeps
/// the plain "Você" / "Outros" split.
enum MeetingDiarizer {
    static let fileName = "diarization.json"
    private static let sampleRate = 16_000.0
    private static let log = Logger(subsystem: "VoiceType", category: "meeting-diarization")

    /// Turns on the meeting clock, checkpointed in `diarization.json`.
    static func turns(for dir: URL, manifest: MeetingManifest) async -> [MeetingSpeakerTurn]? {
        let cacheURL = dir.appendingPathComponent(fileName)
        if let cached = try? JSONDecoder().decode([MeetingSpeakerTurn].self, from: Data(contentsOf: cacheURL)) {
            return cached
        }
        // macOS 14 crashes in BNNS on this Core ML path; fixed in 15 (FluidAudio #878).
        guard #available(macOS 15, *) else { return nil }
        do {
            let started = Date()
            guard let turns = try await diarize(dir, manifest) else { return nil }
            try JSONEncoder().encode(turns).write(to: cacheURL, options: .atomic)
            log.info("diarized \(dir.lastPathComponent, privacy: .public): \(Set(turns.map(\.speaker)).count) speakers in \(Int(Date().timeIntervalSince(started)))s")
            return turns
        } catch {
            log.error("diarization failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// One diarizer run over every system segment back to back (one run keeps
    /// the speaker IDs consistent across segments), mapped back to meeting
    /// time. Audio is read from disk: a lone segment (the usual case) goes in
    /// as is; several are resampled one at a time into a temp 16 kHz file.
    private static func diarize(_ dir: URL, _ manifest: MeetingManifest) async throws -> [MeetingSpeakerTurn]? {
        struct Piece { let bufferStart: Double; let meetingStart: Double; let duration: Double }
        let segments = manifest.segments.compactMap { segment -> (URL, Double)? in
            let url = dir.appendingPathComponent(segment.fileName)
            guard segment.track == .system, let first = segment.firstSampleAt,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return (url, first.timeIntervalSince(manifest.startedAt))
        }
        guard !segments.isEmpty else { return nil }

        var pieces: [Piece] = []
        let input: URL
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("voicetype-diarization-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temp) }
        if segments.count == 1 {
            input = segments[0].0
            pieces = [Piece(bufferStart: 0, meetingStart: segments[0].1, duration: .infinity)]
        } else {
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
            var out: AVAudioFile? = try AVAudioFile(forWriting: temp, settings: format.settings)
            var written = 0
            for (url, meetingStart) in segments {
                let audio = try AudioConverter().resampleAudioFile(url)
                guard !audio.isEmpty,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.count))
                else { continue }
                buffer.frameLength = buffer.frameCapacity
                audio.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: audio.count) }
                try out?.write(from: buffer)
                pieces.append(Piece(
                    bufferStart: Double(written) / sampleRate,
                    meetingStart: meetingStart,
                    duration: Double(audio.count) / sampleRate
                ))
                written += audio.count
            }
            out = nil // closes the file before the diarizer reads it
            guard written > 0 else { return nil }
            input = temp
        }

        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        let result = try await manager.process(input)

        // A turn crossing two pieces is split, each half on its own clock.
        return result.segments.flatMap { seg in
            pieces.compactMap { p -> MeetingSpeakerTurn? in
                let lo = max(Double(seg.startTimeSeconds), p.bufferStart)
                let hi = min(Double(seg.endTimeSeconds), p.bufferStart + p.duration)
                guard hi > lo else { return nil }
                return MeetingSpeakerTurn(
                    start: p.meetingStart + lo - p.bufferStart,
                    end: p.meetingStart + hi - p.bufferStart,
                    speaker: seg.speakerId
                )
            }
        }
    }
}
