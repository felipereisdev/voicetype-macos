import Foundation
import os

// When refinement or translation fails (e.g. Groq unreachable while offline,
// but the transcription already succeeded — typical with local ASR), paste the
// raw transcription instead of aborting and losing the dictation. Cancellation
// still propagates (a cancelled take must not paste anything).
private let logger = Logger(subsystem: "dev.voicetype.core", category: "RawFallback")

// Shared tail for both fallbacks: log, hand back the raw transcription, and —
// only for a permanent server rejection — tell the caller so it can surface it.
// Offline and rate limits stay silent: pasting raw is the correct outcome there,
// and notifying would fire on every dictation for as long as the network is down.
private func degrade(
    _ error: Error,
    pass: String,
    text: String,
    onDegraded: @Sendable (PipelineError) -> Void
) -> String {
    logger.warning("\(pass, privacy: .public) failed, pasting raw transcription: \(String(describing: error), privacy: .public)")
    if let pipelineError = error as? PipelineError, pipelineError.isPermanentRejection {
        onDegraded(pipelineError)
    }
    return text
}

public enum RawFallbackRefine {
    public static func make(
        refine: @escaping Pipeline.RefineFn,
        onDegraded: @escaping @Sendable (PipelineError) -> Void = { _ in }
    ) -> Pipeline.RefineFn {
        return { text in
            do {
                return try await refine(text)
            } catch PipelineError.cancelled {
                throw PipelineError.cancelled
            } catch is CancellationError {
                throw PipelineError.cancelled
            } catch {
                return degrade(error, pass: "refine", text: text, onDegraded: onDegraded)
            }
        }
    }
}

public enum RawFallbackTranslate {
    public static func make(
        translate: @escaping Pipeline.TranslateFn,
        onDegraded: @escaping @Sendable (PipelineError) -> Void = { _ in }
    ) -> Pipeline.TranslateFn {
        return { text, target in
            do {
                return try await translate(text, target)
            } catch PipelineError.cancelled {
                throw PipelineError.cancelled
            } catch is CancellationError {
                throw PipelineError.cancelled
            } catch {
                return degrade(error, pass: "translate", text: text, onDegraded: onDegraded)
            }
        }
    }
}
