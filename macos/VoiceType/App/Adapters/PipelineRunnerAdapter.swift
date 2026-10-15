import Core
import Foundation

// Bridges the `Pipeline` actor to the Sendable `Core.PipelineRunner`
// use-case protocol. Pass-through with no extra logic.
struct PipelineRunnerAdapter: PipelineRunner {
    let pipeline: Pipeline

    func run(
        audio: Data,
        mode: Pipeline.Mode,
        lang: String,
        translateTarget: String?,
        vocabulary: String?
    ) async throws -> String {
        try await pipeline.run(
            audio: audio,
            mode: mode,
            lang: lang,
            translateTarget: translateTarget,
            vocabulary: vocabulary
        )
    }
}
