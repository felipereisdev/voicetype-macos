import Testing
import Foundation
@testable import Core

@Suite("RawFallback")
struct RawFallbackTests {
    private struct Boom: Error {}

    /// Collects the errors handed to `onDegraded`. The callback fires from
    /// whatever task the pipeline runs on, so the box locks.
    private final class Degradations: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [PipelineError] = []
        var recorded: [PipelineError] { lock.withLock { errors } }
        func record(_ error: PipelineError) { lock.withLock { errors.append(error) } }
    }

    @Test func refineSuccessPassesThrough() async throws {
        let fn = RawFallbackRefine.make(refine: { _ in "REFINED" })
        #expect(try await fn("raw") == "REFINED")
    }

    @Test func refineFailurePastesRawTranscription() async throws {
        let fn = RawFallbackRefine.make(refine: { _ in throw Boom() })
        #expect(try await fn("raw text") == "raw text")
    }

    @Test func refineCancellationPropagatesWithoutPasting() async {
        let fn = RawFallbackRefine.make(refine: { _ in throw PipelineError.cancelled })
        await #expect(throws: PipelineError.cancelled) { try await fn("raw") }
    }

    @Test func translateSuccessPassesThrough() async throws {
        let fn = RawFallbackTranslate.make(translate: { _, _ in "HELLO" })
        #expect(try await fn("olá", "en") == "HELLO")
    }

    @Test func translateFailurePastesRawTranscription() async throws {
        let fn = RawFallbackTranslate.make(translate: { _, _ in throw Boom() })
        #expect(try await fn("olá mundo", "en") == "olá mundo")
    }

    @Test func translateCancellationPropagatesWithoutPasting() async {
        let fn = RawFallbackTranslate.make(translate: { _, _ in throw CancellationError() })
        await #expect(throws: PipelineError.cancelled) { try await fn("olá", "en") }
    }

    // A 4xx is a permanent server rejection — a dead model, a bad key, a
    // malformed request. Pasting raw forever with only an oslog line is how a
    // decommissioned model went unnoticed for weeks (G-025), so the user is told
    // — and still gets the dictation.
    @Test func refineNotifiesOnPermanentRejection() async throws {
        let seen = Degradations()
        let fn = RawFallbackRefine.make(
            refine: { _ in throw PipelineError.http(status: 404, message: "groq-404") },
            onDegraded: { seen.record($0) }
        )

        #expect(try await fn("texto cru") == "texto cru")
        #expect(seen.recorded == [.http(status: 404, message: "groq-404")])
    }

    @Test func translateNotifiesOnPermanentRejection() async throws {
        let seen = Degradations()
        let fn = RawFallbackTranslate.make(
            translate: { _, _ in throw PipelineError.http(status: 401, message: "invalid-key") },
            onDegraded: { seen.record($0) }
        )

        #expect(try await fn("olá mundo", "en") == "olá mundo")
        #expect(seen.recorded == [.http(status: 401, message: "invalid-key")])
    }

    // Offline is the case RawFallback was built for: pasting raw IS the right
    // outcome and nothing is wrong with the config. Notifying here would fire on
    // every dictation for the whole time the network is down.
    @Test func refineStaysSilentOnNetworkFailure() async throws {
        let seen = Degradations()
        let fn = RawFallbackRefine.make(
            refine: { _ in throw PipelineError.network(message: "offline") },
            onDegraded: { seen.record($0) }
        )

        #expect(try await fn("texto cru") == "texto cru")
        #expect(seen.recorded.isEmpty)
    }

    // 429 is 4xx but transient — the next dictation may well succeed.
    @Test func refineStaysSilentOnRateLimit() async throws {
        let seen = Degradations()
        let fn = RawFallbackRefine.make(
            refine: { _ in throw PipelineError.http(status: 429, message: "rate-limited") },
            onDegraded: { seen.record($0) }
        )

        #expect(try await fn("texto cru") == "texto cru")
        #expect(seen.recorded.isEmpty)
    }

    @Test func refineStaysSilentOnCancellation() async {
        let seen = Degradations()
        let fn = RawFallbackRefine.make(
            refine: { _ in throw PipelineError.cancelled },
            onDegraded: { seen.record($0) }
        )

        await #expect(throws: PipelineError.cancelled) { try await fn("texto cru") }
        #expect(seen.recorded.isEmpty)
    }
}
