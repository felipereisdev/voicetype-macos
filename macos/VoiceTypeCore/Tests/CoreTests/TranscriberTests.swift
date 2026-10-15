import Testing
import Foundation
@testable import Core

@Suite("Transcriber")
struct TranscriberTests {

    @Test func returnsTrimmedTranscript() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "  olá mundo  \n" }
        let transcriber = Transcriber(groq: groq)
        let out = try await transcriber.transcribe(audio: Data(), lang: "pt")
        #expect(out == "olá mundo")
    }

    @Test func emptyResponseThrows() async {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "   \n" }
        let transcriber = Transcriber(groq: groq)
        await #expect(throws: PipelineError.emptyTranscription) {
            try await transcriber.transcribe(audio: Data(), lang: "pt")
        }
    }

    @Test func http401MapsToHttpStatus() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in throw GroqError.invalidKey }
        let transcriber = Transcriber(groq: groq)
        do {
            _ = try await transcriber.transcribe(audio: Data(), lang: "pt")
            Issue.record("expected throw")
        } catch let error as PipelineError {
            if case .http(let status, _) = error {
                #expect(status == 401)
            } else {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    @Test func passesLangToGroq() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "ok" }
        let transcriber = Transcriber(groq: groq)
        _ = try await transcriber.transcribe(audio: Data(), lang: "pt")
        #expect(groq.transcribeCalls.first?.lang == "pt")
    }

    // MARK: - buildPrompt

    @Test func buildPrompt_nilInput_returnsNil() {
        #expect(Transcriber.buildPrompt(from: nil) == nil)
    }

    @Test func buildPrompt_emptyInput_returnsNil() {
        #expect(Transcriber.buildPrompt(from: "") == nil)
    }

    @Test func buildPrompt_whitespaceOnly_returnsNil() {
        #expect(Transcriber.buildPrompt(from: "   \n  \n  ") == nil)
    }

    @Test func buildPrompt_singleTerm() {
        let result = Transcriber.buildPrompt(from: "Macsilva")
        #expect(result == "These words may appear: Macsilva.")
    }

    @Test func buildPrompt_mixedNewlineAndComma() {
        let input = "Macsilva, FluidAudio\nCodex,Groq\n\nWhisper"
        let result = Transcriber.buildPrompt(from: input)
        #expect(result == "These words may appear: Macsilva, FluidAudio, Codex, Groq, Whisper.")
    }

    @Test func buildPrompt_trimsAndDropsEmpty() {
        let input = "  foo  , , \n  bar  "
        let result = Transcriber.buildPrompt(from: input)
        #expect(result == "These words may appear: foo, bar.")
    }

    @Test func buildPrompt_truncatesWhenOverCap() {
        let term = String(repeating: "a", count: 50)
        let many = Array(repeating: term, count: 40).joined(separator: ",")
        let result = Transcriber.buildPrompt(from: many, maxChars: 200)
        #expect(result != nil)
        if let result {
            #expect(result.count <= 200)
            #expect(result.hasPrefix("These words may appear: "))
            #expect(result.hasSuffix("."))
        }
    }

    @Test func buildPrompt_keepsHighPriorityFirstTerms() {
        let head = "FIRST, SECOND, THIRD"
        let tail = String(repeating: ", " + String(repeating: "x", count: 30), count: 50)
        let result = Transcriber.buildPrompt(from: head + tail, maxChars: 120)
        #expect(result != nil)
        if let result {
            #expect(result.contains("FIRST"))
            #expect(result.count <= 120)
        }
    }

    @Test func transcribe_forwardsBuiltPromptToGroq() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "ok" }
        let transcriber = Transcriber(groq: groq)
        _ = try await transcriber.transcribe(audio: Data(), lang: "pt", vocabulary: "Macsilva,Codex")
        #expect(groq.transcribeCalls.first?.prompt == "These words may appear: Macsilva, Codex.")
    }

    @Test func transcribe_nilVocabulary_passesNilPrompt() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "ok" }
        let transcriber = Transcriber(groq: groq)
        _ = try await transcriber.transcribe(audio: Data(), lang: "pt", vocabulary: nil)
        #expect(groq.transcribeCalls.first?.prompt == nil)
    }

    @Test func transcribe_emptyVocabulary_passesNilPrompt() async throws {
        let groq = FakeGroq()
        groq.transcribeImpl = { _, _, _ in "ok" }
        let transcriber = Transcriber(groq: groq)
        _ = try await transcriber.transcribe(audio: Data(), lang: "pt", vocabulary: "")
        #expect(groq.transcribeCalls.first?.prompt == nil)
    }
}
