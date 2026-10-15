import Foundation

// Orchestrates the transcribe → (refine | translate | raw) chain.
// Honors Task.cancellation between every step.
public actor Pipeline {
    public enum Mode: Sendable, Equatable {
        case refine
        case translate
        case raw
    }

    public typealias TranscribeFn = @Sendable (Data, String, String?) async throws -> String
    public typealias RefineFn = @Sendable (String) async throws -> String
    public typealias TranslateFn = @Sendable (String, String) async throws -> String

    private let transcribeFn: TranscribeFn
    private let refineFn: RefineFn
    private let translateFn: TranslateFn
    /// The ASR output of the last `run` (before refine/translate). The voice
    /// note keeps it as "Transcrição original".
    public private(set) var lastRawTranscript: String?

    public init(
        transcriber: Transcriber,
        refiner: Refiner,
        translator: Translator
    ) {
        self.transcribeFn = { audio, lang, vocabulary in
            try await transcriber.transcribe(audio: audio, lang: lang, vocabulary: vocabulary)
        }
        self.refineFn = { text in
            try await refiner.refine(text: text)
        }
        self.translateFn = { text, target in
            try await translator.translate(text: text, target: target)
        }
    }

    // Test-only seam: inject closures directly.
    public init(
        transcribe: @escaping TranscribeFn,
        refine: @escaping RefineFn,
        translate: @escaping TranslateFn
    ) {
        self.transcribeFn = transcribe
        self.refineFn = refine
        self.translateFn = translate
    }

    public func run(
        audio: Data,
        mode: Mode,
        lang: String,
        translateTarget: String?,
        vocabulary: String? = nil
    ) async throws -> String {
        if case .translate = mode, translateTarget == nil {
            throw PipelineError.missingTranslateTarget
        }

        try Task.checkCancellation()
        let raw = try await transcribeFn(audio, lang, vocabulary)
        lastRawTranscript = raw
        try Task.checkCancellation()

        switch mode {
        case .refine:
            return try await refineFn(raw)
        case .translate:
            return try await translateFn(raw, translateTarget!)
        case .raw:
            return raw
        }
    }
}
