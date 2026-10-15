import Testing
import Foundation
@testable import Core

@Suite("Pipeline")
struct PipelineTests {

    @Test func refineModeRunsTranscribeThenRefine() async throws {
        var transcribeArgs: (Data, String, String?)?
        var refineArg: String?

        let pipeline = Pipeline(
            transcribe: { audio, lang, vocabulary in
                transcribeArgs = (audio, lang, vocabulary)
                return "olá mundo este é um teste"
            },
            refine: { text in
                refineArg = text
                return "Olá, mundo. Este é um teste."
            },
            translate: { _, _ in "should-not-call" }
        )

        let result = try await pipeline.run(
            audio: Data([1, 2, 3]),
            mode: .refine,
            lang: "pt",
            translateTarget: nil
        )

        #expect(result == "Olá, mundo. Este é um teste.")
        #expect(transcribeArgs?.1 == "pt")
        #expect(transcribeArgs?.2 == nil)
        #expect(refineArg == "olá mundo este é um teste")
    }

    @Test func translateModeRunsTranscribeThenTranslate() async throws {
        var translateArgs: (String, String)?

        let pipeline = Pipeline(
            transcribe: { _, _, _ in "olá mundo" },
            refine: { _ in "should-not-call" },
            translate: { text, target in
                translateArgs = (text, target)
                return "Hello world."
            }
        )

        let result = try await pipeline.run(
            audio: Data(),
            mode: .translate,
            lang: "pt",
            translateTarget: "en"
        )

        #expect(result == "Hello world.")
        #expect(translateArgs?.0 == "olá mundo")
        #expect(translateArgs?.1 == "en")
    }

    @Test func translateModeWithoutTargetThrows() async {
        var transcribeCalled = false
        let pipeline = Pipeline(
            transcribe: { _, _, _ in
                transcribeCalled = true
                return "x"
            },
            refine: { _ in "x" },
            translate: { _, _ in "x" }
        )

        await #expect(throws: PipelineError.missingTranslateTarget) {
            try await pipeline.run(audio: Data(), mode: .translate, lang: "pt", translateTarget: nil)
        }
        #expect(transcribeCalled == false)
    }

    @Test func rawModeReturnsTranscriptUnmodified() async throws {
        var refineCalled = false
        var translateCalled = false

        let pipeline = Pipeline(
            transcribe: { _, _, _ in "olá mundo" },
            refine: { _ in refineCalled = true; return "x" },
            translate: { _, _ in translateCalled = true; return "x" }
        )

        let result = try await pipeline.run(
            audio: Data(),
            mode: .raw,
            lang: "pt",
            translateTarget: nil
        )

        #expect(result == "olá mundo")
        #expect(refineCalled == false)
        #expect(translateCalled == false)
    }

    @Test func vocabularyForwardedToTranscribe() async throws {
        var capturedVocabulary: String?
        let pipeline = Pipeline(
            transcribe: { _, _, vocabulary in
                capturedVocabulary = vocabulary
                return "x"
            },
            refine: { _ in "x" },
            translate: { _, _ in "x" }
        )

        _ = try await pipeline.run(
            audio: Data(),
            mode: .raw,
            lang: "pt",
            translateTarget: nil,
            vocabulary: "Macsilva, Codex"
        )

        #expect(capturedVocabulary == "Macsilva, Codex")
    }
}
