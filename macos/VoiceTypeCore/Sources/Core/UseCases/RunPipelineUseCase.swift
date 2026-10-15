import Foundation

/// Runs Whisper -> refine/translate -> paste -> history record in a linear,
/// typed flow. Orchestrator no longer carries the logic inline; this use case
/// composes the three side-effect-bearing collaborators via abstract
/// protocols supplied by the App layer.
public struct RunPipelineUseCase: Sendable {
    private let pipeline: PipelineRunner
    private let paster: PasterDelivery
    private let history: HistoryRecorder

    public init(
        pipeline: PipelineRunner,
        paster: PasterDelivery,
        history: HistoryRecorder
    ) {
        self.pipeline = pipeline
        self.paster = paster
        self.history = history
    }

    public func execute(
        audio: Data,
        mode: Pipeline.Mode,
        lang: String,
        translateTarget: String?,
        targetBundleId: String,
        historyEnabled: Bool,
        historyCap: Int,
        autoEnter: Bool = false,
        vocabulary: String? = nil
    ) async throws {
        let text = try await pipeline.run(
            audio: audio,
            mode: mode,
            lang: lang,
            translateTarget: translateTarget,
            vocabulary: vocabulary
        )
        // Defense-in-depth: if the task was cancelled while the pipeline ran
        // (e.g. a late Groq fallback completing after user abandoned the take),
        // abort before pasting so stale text never reaches the focused app.
        try Task.checkCancellation()
        try await paster.paste(text: text, targetBundleId: targetBundleId, autoEnter: autoEnter)
        guard historyEnabled else { return }

        let entryMode: HistoryMode = (mode == .translate) ? .translate : .refine
        let entry = HistoryEntry(mode: entryMode, sourceApp: targetBundleId, text: text)
        await history.record(entry)
        _ = historyCap // Cap enforcement happens in the HistoryRecorder adapter.
    }
}
