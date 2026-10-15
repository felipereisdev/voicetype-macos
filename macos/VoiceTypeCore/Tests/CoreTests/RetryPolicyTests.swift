import Foundation
import Testing
@testable import Core

@Suite("RetryPolicy")
struct RetryPolicyTests {
    @Test("returns on first success without retry")
    func firstSuccess() async throws {
        let attempts = Counter()
        let value = try await withRetry(maxAttempts: 3, initialDelay: .milliseconds(1)) {
            await attempts.bump()
            return "ok"
        }
        #expect(value == "ok")
        #expect(await attempts.value == 1)
    }

    @Test("retries on retryable error then succeeds")
    func retryThenSucceed() async throws {
        let attempts = Counter()
        let value = try await withRetry(maxAttempts: 3, initialDelay: .milliseconds(1)) {
            let n = await attempts.bump()
            if n < 3 { throw GroqError.serverError(status: 503) }
            return "ok"
        }
        #expect(value == "ok")
        #expect(await attempts.value == 3)
    }

    @Test("does not retry on non-retryable error")
    func nonRetryable() async {
        let attempts = Counter()
        do {
            _ = try await withRetry(maxAttempts: 3, initialDelay: .milliseconds(1)) {
                await attempts.bump()
                throw GroqError.invalidKey
            } as String
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .invalidKey)
            #expect(await attempts.value == 1)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    @Test("exhausts retry budget then throws last error")
    func budgetExhausted() async {
        let attempts = Counter()
        do {
            _ = try await withRetry(maxAttempts: 3, initialDelay: .milliseconds(1)) {
                await attempts.bump()
                throw GroqError.serverError(status: 500)
            } as String
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .serverError(status: 500))
            #expect(await attempts.value == 3)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("respects task cancellation between attempts")
    func cancellation() async {
        let task = Task<String, Error> {
            try await withRetry(maxAttempts: 3, initialDelay: .milliseconds(50)) {
                throw GroqError.serverError(status: 500)
            }
        }
        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let err as GroqError {
            #expect(err == .cancelled)
        } catch is CancellationError {
            // also acceptable
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}

/// Sendable mutable counter for retry tests (replaces capture-list `var`).
actor Counter {
    private(set) var value: Int = 0
    @discardableResult
    func bump() -> Int {
        value += 1
        return value
    }
}
