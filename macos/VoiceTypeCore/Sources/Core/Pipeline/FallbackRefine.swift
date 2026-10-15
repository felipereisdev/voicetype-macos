import Foundation
import os

// Local-primary refine/translate with Groq fallback. Primary unavailable, throw,
// or timeout routes to the fallback. User cancellation propagates (never falls
// back). Mirrors FallbackTranscribe.

public enum FallbackRefine {
    private static let logger = Logger(subsystem: "dev.voicetype.core", category: "FallbackRefine")

    public static func make(
        primary: @escaping Pipeline.RefineFn,
        fallback: @escaping Pipeline.RefineFn,
        isPrimaryAvailable: @escaping @Sendable () -> Bool,
        timeoutSeconds: Double
    ) -> Pipeline.RefineFn {
        return { text in
            if isPrimaryAvailable() {
                do {
                    return try await withTimeout(seconds: timeoutSeconds) { try await primary(text) }
                } catch PipelineError.cancelled {
                    throw PipelineError.cancelled
                } catch is CancellationError {
                    throw PipelineError.cancelled
                } catch {
                    Self.logger.warning("local refine failed/timed out, falling back to Groq: \(String(describing: error), privacy: .public)")
                }
            } else {
                Self.logger.info("local refine unavailable, using Groq")
            }
            return try await fallback(text)
        }
    }
}

public enum FallbackTranslate {
    private static let logger = Logger(subsystem: "dev.voicetype.core", category: "FallbackTranslate")

    public static func make(
        primary: @escaping Pipeline.TranslateFn,
        fallback: @escaping Pipeline.TranslateFn,
        isPrimaryAvailable: @escaping @Sendable () -> Bool,
        timeoutSeconds: Double
    ) -> Pipeline.TranslateFn {
        return { text, target in
            if isPrimaryAvailable() {
                do {
                    return try await withTimeout(seconds: timeoutSeconds) { try await primary(text, target) }
                } catch PipelineError.cancelled {
                    throw PipelineError.cancelled
                } catch is CancellationError {
                    throw PipelineError.cancelled
                } catch {
                    Self.logger.warning("local translate failed/timed out, falling back to Groq: \(String(describing: error), privacy: .public)")
                }
            } else {
                Self.logger.info("local translate unavailable, using Groq")
            }
            return try await fallback(text, target)
        }
    }
}
