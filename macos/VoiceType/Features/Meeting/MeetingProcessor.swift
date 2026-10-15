import Core
import Foundation
import WhisperKit
import os

/// Post-capture pipeline for one meeting directory (#74 step 2):
/// WhisperKit large-v3 per segment → system-track diarization (FluidAudio)
/// → hallucination filter + echo dedupe + merge (Core) → summary via the
/// assistant CLI → Markdown note.
///
/// Resumable: per-segment ASR output is checkpointed in `transcript.json` and
/// the note identity/paths in `pipeline.json`, so a quit, crash or sleep never
/// forces re-transcribing. Runs are serialized; the actor keeps everything
/// off the main thread.
actor MeetingProcessor {
    /// large-v3 (626 MB, not turbo): ~10× real time on a 75 min meeting (spike 4). Separate from the
    /// dictation whisper-small and only held in memory while processing.
    static let modelVariant = "openai_whisper-large-v3-v20240930_626MB"

    private let configStore: ConfigStore
    private let notifier: Notifier
    private var tail: Task<Void, Never>?
    private static let log = Logger(subsystem: "VoiceType", category: "meeting-pipeline")

    init(configStore: ConfigStore, notifier: Notifier) {
        self.configStore = configStore
        self.notifier = notifier
    }

    /// Queues `directory` behind any run in progress.
    func enqueue(_ directory: URL) {
        let previous = tail
        tail = Task {
            await previous?.value
            await run(directory)
            await purge()
        }
    }

    /// Queues an audio-retention sweep; serialized with the runs so it never
    /// deletes audio a run is reading.
    func enqueuePurge() {
        let previous = tail
        tail = Task {
            await previous?.value
            await purge()
        }
    }

    private func purge() async {
        let days = ((try? await configStore.load()) ?? AppConfig()).meetingAudioRetentionDays
        let deleted = MeetingAudioRetention.purge(base: MeetingRecorder.baseDirectory, days: days)
        for file in deleted {
            Self.log.info("retention: deleted \(file.path, privacy: .public)")
        }
    }

    private func run(_ dir: URL) async {
        // Idle sleep froze a spike run for 55 min of wall time (#74 spike 5).
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Processando reunião"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        await notifier.info(title: "Processando reunião…", body: dir.lastPathComponent)

        do {
            let manifest = try MeetingManifest.decode(Data(contentsOf: dir.appendingPathComponent(MeetingManifest.fileName)))
            let utterances = try await transcribe(dir, manifest)
            let turns = await MeetingDiarizer.turns(for: dir, manifest: manifest) ?? []
            // After process(): dropped hallucinations must not claim a speaker number.
            let transcript = MeetingTranscript.render(MeetingTranscript.assignSpeakers(
                MeetingTranscript.process(utterances), turns: turns
            ))
            let cfg = (try? await configStore.load()) ?? AppConfig()

            let (summary, failure) = await summarize(
                transcript, cliPath: cfg.claudeCLIPath, meetingDate: manifest.startedAt, orgs: cfg.meetingOrgs
            )
            var state = Self.loadState(dir) ?? MeetingPipelineState()
            let end = manifest.endedAt ?? manifest.segments.compactMap(\.closedAt).max() ?? manifest.startedAt
            let note = MeetingNote(
                id: state.noteID, startedAt: manifest.startedAt,
                duration: end.timeIntervalSince(manifest.startedAt),
                platform: manifest.platform, summary: summary,
                transcript: transcript.isEmpty ? nil : transcript
            )
            let folder = URL(fileURLWithPath: (cfg.meetingNotesFolder as NSString).expandingTildeInPath, isDirectory: true)
            let written = try MeetingNoteWriter.write(note, to: folder)

            // A retry with a real summary renames the note (title changed), and
            // notes saved before the Meetings/YYYY layout live elsewhere: drop
            // the files of the previous attempt so the vault has one copy.
            for (old, new) in [(state.notePath, written.note.path), (state.transcriptPath, written.transcript?.path)]
            where old != nil && old != new {
                try? FileManager.default.removeItem(atPath: old!)
            }
            state.notePath = written.note.path
            state.transcriptPath = written.transcript?.path
            state.summarized = failure == nil
            try JSONEncoder().encode(state).write(to: dir.appendingPathComponent(MeetingPipelineState.stateFileName), options: .atomic)

            if let failure {
                await notifier.error(title: "Nota salva sem resumo", body: failure)
            } else {
                await notifier.success(title: "Nota da reunião salva", body: written.note.lastPathComponent)
            }
            Self.log.info("meeting processed: \(written.note.path, privacy: .public) summarized=\(failure == nil)")
        } catch {
            Self.log.error("meeting pipeline failed: \(String(describing: error), privacy: .public)")
            await notifier.error(
                title: "Falha ao processar reunião",
                body: "\(error.localizedDescription) — use \"Reprocessar última reunião\"."
            )
        }
    }

    // MARK: - Transcription

    /// ASR for every segment not yet in `transcript.json`, checkpointing after
    /// each one. The large model is loaded only when there's work, and
    /// unloaded before returning.
    private func transcribe(_ dir: URL, _ manifest: MeetingManifest) async throws -> [MeetingUtterance] {
        let cacheURL = dir.appendingPathComponent(MeetingPipelineState.transcriptFileName)
        var cache = (try? JSONDecoder().decode([String: [MeetingUtterance]].self, from: Data(contentsOf: cacheURL))) ?? [:]
        // Audio purged by retention: its transcript is already cached, so a
        // reprocess only redoes the summary (no model load for missing files).
        let pending = manifest.segments.filter {
            $0.firstSampleAt != nil && cache[$0.fileName] == nil
                && FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.fileName).path)
        }

        if !pending.isEmpty {
            let kit = try await WhisperModelManager.loadKit(variant: Self.modelVariant) { _ in }
            do {
                for segment in pending {
                    cache[segment.fileName] = try await transcribe(segment, in: dir, startedAt: manifest.startedAt, kit: kit)
                    try JSONEncoder().encode(cache).write(to: cacheURL, options: .atomic)
                }
            } catch {
                await kit.unloadModels()
                throw error
            }
            await kit.unloadModels()
        }
        return manifest.segments.flatMap { cache[$0.fileName] ?? [] }
    }

    private func transcribe(
        _ segment: MeetingSegment, in dir: URL, startedAt: Date, kit: WhisperKit
    ) async throws -> [MeetingUtterance] {
        guard let first = segment.firstSampleAt else { return [] }
        let offset = first.timeIntervalSince(startedAt)
        let options = DecodingOptions(
            verbose: false, task: .transcribe,
            language: nil, // auto per window: forcing pt on an English call hallucinated a translation (spike 4)
            temperature: 0, usePrefillPrompt: true, detectLanguage: true,
            skipSpecialTokens: true, withoutTimestamps: false,
            chunkingStrategy: .vad
        )
        let started = Date()
        let results: [TranscriptionResult]
        do {
            results = try await kit.transcribe(audioPath: dir.appendingPathComponent(segment.fileName).path, decodeOptions: options)
        } catch {
            // A broken/empty file must not block the rest of the meeting; an
            // empty entry also keeps reprocess from retrying it forever.
            Self.log.error("ASR failed for \(segment.fileName, privacy: .public): \(String(describing: error), privacy: .public)")
            return []
        }
        let utterances = results.flatMap(\.segments).map {
            MeetingUtterance(
                track: segment.track, start: offset + Double($0.start), end: offset + Double($0.end),
                text: $0.text, compressionRatio: Double($0.compressionRatio)
            )
        }
        Self.log.info("ASR \(segment.fileName, privacy: .public): \(utterances.count) segments in \(Int(Date().timeIntervalSince(started)))s")
        return utterances
    }

    // MARK: - Summary

    /// Never throws: on any failure the note still gets written with the
    /// transcript and a "Resumo indisponível" placeholder.
    private func summarize(
        _ transcript: String, cliPath: String?, meetingDate: Date, orgs: [MeetingOrg]
    ) async -> (MeetingSummary, String?) {
        func unavailable(_ reason: String) -> (MeetingSummary, String?) {
            (MeetingSummary(title: "Reunião", summary: "Resumo indisponível: \(reason)"), reason)
        }
        guard !transcript.isEmpty else { return unavailable("nenhuma fala detectada") }
        guard let cli = ClaudeCLISummarizer.locate(configured: cliPath) else {
            return unavailable("Claude CLI não encontrado (instale ou defina claudeCLIPath)")
        }
        do {
            let summary = try await ClaudeCLISummarizer(executableURL: cli)
                .summarize(transcript: transcript, meetingDate: meetingDate, orgs: orgs)
            return (summary, nil)
        } catch let error as ClaudeCLISummarizer.CLIError {
            return unavailable(error.reason)
        } catch {
            return unavailable(String(describing: error))
        }
    }

    // MARK: - Checkpoint files

    private static func loadState(_ dir: URL) -> MeetingPipelineState? {
        try? JSONDecoder().decode(
            MeetingPipelineState.self,
            from: Data(contentsOf: dir.appendingPathComponent(MeetingPipelineState.stateFileName))
        )
    }
}
