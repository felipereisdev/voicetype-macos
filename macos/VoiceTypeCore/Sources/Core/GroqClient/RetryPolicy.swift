import Foundation

/// Returns whether a thrown error from a Groq call is worth retrying.
/// Mirrors `defaultIsRetryable` in `src/shared/lib/retry.ts`.
func isRetryable(_ error: Error) -> Bool {
    if let groq = error as? GroqError {
        switch groq {
        case .rateLimited, .serverError, .network:
            return true
        case .invalidKey, .networkBlocked, .malformedResponse, .cancelled:
            return false
        }
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotConnectToHost:
            return true
        default:
            return false
        }
    }
    return false
}

/// Run `operation` up to `maxAttempts` times with exponential backoff.
/// Honors `Task.checkCancellation()` between attempts.
func withRetry<T: Sendable>(
    maxAttempts: Int = 3,
    initialDelay: Duration = .milliseconds(500),
    maxDelay: Duration = .seconds(5),
    operation: @Sendable () async throws -> T
) async throws -> T {
    precondition(maxAttempts >= 1)
    var attempt = 0
    var delay = initialDelay
    while true {
        attempt += 1
        do {
            try Task.checkCancellation()
            return try await operation()
        } catch is CancellationError {
            throw GroqError.cancelled
        } catch {
            if Task.isCancelled { throw GroqError.cancelled }
            if attempt >= maxAttempts || !isRetryable(error) {
                throw error
            }
            do {
                try await Task.sleep(for: delay)
            } catch {
                throw GroqError.cancelled
            }
            delay = min(delay * 2, maxDelay)
        }
    }
}
