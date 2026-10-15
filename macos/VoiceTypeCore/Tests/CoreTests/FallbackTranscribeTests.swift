import Testing
import Foundation
@testable import Core

@Suite("FallbackTranscribe")
struct FallbackTranscribeTests {
    private struct Boom: Error {}

    private func fn(primary: @escaping Pipeline.TranscribeFn,
                   fallback: @escaping Pipeline.TranscribeFn,
                   ready: Bool) -> Pipeline.TranscribeFn {
        FallbackTranscribe.make(primary: primary, fallback: fallback, isPrimaryReady: { ready })
    }

    @Test func usesPrimaryWhenReady() async throws {
        let f = fn(primary: { _,_,_ in "LOCAL" }, fallback: { _,_,_ in "GROQ" }, ready: true)
        #expect(try await f(Data(), "pt", nil) == "LOCAL")
    }

    @Test func usesFallbackWhenNotReady() async throws {
        let f = fn(primary: { _,_,_ in "LOCAL" }, fallback: { _,_,_ in "GROQ" }, ready: false)
        #expect(try await f(Data(), "pt", nil) == "GROQ")
    }

    @Test func usesFallbackWhenPrimaryThrows() async throws {
        let f = fn(primary: { _,_,_ in throw Boom() }, fallback: { _,_,_ in "GROQ" }, ready: true)
        #expect(try await f(Data(), "pt", nil) == "GROQ")
    }

    @Test func propagatesCancellationWithoutFallback() async {
        let f = fn(primary: { _,_,_ in throw PipelineError.cancelled },
                   fallback: { _,_,_ in "GROQ" }, ready: true)
        await #expect(throws: PipelineError.cancelled) { try await f(Data(), "pt", nil) }
    }
}

@Suite("FallbackTranscribe.shouldFallback")
struct FallbackTranscribeGateTests {
    private func groqFirst(error: PipelineError, localReady: Bool) -> Pipeline.TranscribeFn {
        FallbackTranscribe.make(
            primary: { _,_,_ in throw error },
            fallback: { _,_,_ in "LOCAL" },
            isPrimaryReady: { true },
            shouldFallback: { ($0 as? PipelineError)?.isConnectivityFailure == true && localReady }
        )
    }

    @Test func blockedNetworkFallsBackToLocal() async throws {
        let f = groqFirst(error: .http(status: 403, message: "x"), localReady: true)
        #expect(try await f(Data(), "pt", nil) == "LOCAL")
    }

    @Test func timeoutFallsBackToLocal() async throws {
        #expect(try await groqFirst(error: .timeout, localReady: true)(Data(), "pt", nil) == "LOCAL")
    }

    @Test func rethrowsWhenLocalNotReady() async {
        let f = groqFirst(error: .http(status: 403, message: "x"), localReady: false)
        await #expect(throws: PipelineError.http(status: 403, message: "x")) { try await f(Data(), "pt", nil) }
    }

    @Test func badAudioDoesNotFallBack() async {
        let f = groqFirst(error: .emptyTranscription, localReady: true)
        await #expect(throws: PipelineError.emptyTranscription) { try await f(Data(), "pt", nil) }
    }
}
