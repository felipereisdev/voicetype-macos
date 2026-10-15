import Testing
import Foundation
@testable import Core

@Suite("FallbackRefine")
struct FallbackRefineTests {
    private struct Boom: Error {}

    private func refineFn(primary: @escaping Pipeline.RefineFn,
                          fallback: @escaping Pipeline.RefineFn,
                          available: Bool,
                          timeout: Double = 1.0) -> Pipeline.RefineFn {
        FallbackRefine.make(primary: primary, fallback: fallback,
                            isPrimaryAvailable: { available }, timeoutSeconds: timeout)
    }

    @Test func usesPrimaryWhenAvailable() async throws {
        let f = refineFn(primary: { _ in "LOCAL" }, fallback: { _ in "GROQ" }, available: true)
        #expect(try await f("x") == "LOCAL")
    }

    @Test func usesFallbackWhenUnavailable() async throws {
        let f = refineFn(primary: { _ in "LOCAL" }, fallback: { _ in "GROQ" }, available: false)
        #expect(try await f("x") == "GROQ")
    }

    @Test func usesFallbackWhenPrimaryThrows() async throws {
        let f = refineFn(primary: { _ in throw Boom() }, fallback: { _ in "GROQ" }, available: true)
        #expect(try await f("x") == "GROQ")
    }

    @Test func usesFallbackOnTimeout() async throws {
        let f = refineFn(primary: { _ in try await Task.sleep(for: .seconds(2)); return "LOCAL" },
                         fallback: { _ in "GROQ" }, available: true, timeout: 0.05)
        #expect(try await f("x") == "GROQ")
    }

    @Test func propagatesCancellationWithoutFallback() async {
        let f = refineFn(primary: { _ in throw PipelineError.cancelled },
                         fallback: { _ in "GROQ" }, available: true)
        await #expect(throws: PipelineError.cancelled) { try await f("x") }
    }

    @Test func propagatesOuterCancellationDuringLocalCall() async {
        let f = FallbackRefine.make(
            primary: { _ in try await Task.sleep(for: .seconds(5)); return "LOCAL" },
            fallback: { _ in "GROQ" },
            isPrimaryAvailable: { true }, timeoutSeconds: 10)
        let task = Task { try await f("x") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: PipelineError.cancelled) { try await task.value }
    }
}

@Suite("FallbackTranslate")
struct FallbackTranslateTests {
    private struct Boom: Error {}

    @Test func usesPrimaryWhenAvailable() async throws {
        let f = FallbackTranslate.make(primary: { _,_ in "LOCAL" }, fallback: { _,_ in "GROQ" },
                                       isPrimaryAvailable: { true }, timeoutSeconds: 1.0)
        #expect(try await f("x", "en") == "LOCAL")
    }

    @Test func usesFallbackWhenUnavailable() async throws {
        let f = FallbackTranslate.make(primary: { _,_ in "LOCAL" }, fallback: { _,_ in "GROQ" },
                                       isPrimaryAvailable: { false }, timeoutSeconds: 1.0)
        #expect(try await f("x", "en") == "GROQ")
    }

    @Test func usesFallbackWhenPrimaryThrows() async throws {
        let f = FallbackTranslate.make(primary: { _,_ in throw Boom() }, fallback: { _,_ in "GROQ" },
                                       isPrimaryAvailable: { true }, timeoutSeconds: 1.0)
        #expect(try await f("x", "en") == "GROQ")
    }

    @Test func propagatesOuterCancellationDuringLocalCall() async {
        let f = FallbackTranslate.make(
            primary: { _,_ in try await Task.sleep(for: .seconds(5)); return "LOCAL" },
            fallback: { _,_ in "GROQ" },
            isPrimaryAvailable: { true }, timeoutSeconds: 10)
        let task = Task { try await f("x", "en") }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: PipelineError.cancelled) { try await task.value }
    }
}
