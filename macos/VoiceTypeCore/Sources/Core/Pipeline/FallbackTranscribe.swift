import Foundation
import os

// Primary transcription with a fallback engine (auto: local→Groq; groq: Groq→local).
// Cancellation propagates; other primary failures (or not-ready) route to the
// fallback when `shouldFallback` agrees, otherwise the primary error is rethrown.
public enum FallbackTranscribe {
    private static let logger = Logger(subsystem: "dev.voicetype.core", category: "FallbackTranscribe")

    public static func make(
        primary: @escaping Pipeline.TranscribeFn,
        fallback: @escaping Pipeline.TranscribeFn,
        isPrimaryReady: @escaping @Sendable () -> Bool,
        shouldFallback: @escaping @Sendable (Error) async -> Bool = { _ in true }
    ) -> Pipeline.TranscribeFn {
        return { audio, lang, vocab in
            if isPrimaryReady() {
                do {
                    return try await primary(audio, lang, vocab)
                } catch PipelineError.cancelled {
                    throw PipelineError.cancelled
                } catch is CancellationError {
                    throw PipelineError.cancelled
                } catch {
                    guard await shouldFallback(error) else { throw error }
                    // Record why before routing to the fallback, so a silent switch is debuggable.
                    Self.logger.warning("primary transcription failed, using fallback: \(String(describing: error), privacy: .public)")
                }
            } else {
                Self.logger.info("primary transcription not ready, using fallback")
            }
            return try await fallback(audio, lang, vocab)
        }
    }
}
