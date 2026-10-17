import Foundation
import Core

struct LocalTranscriber: Sendable {
    let manager: LocalModelManager

    enum LocalError: Error { case notReady }

    /// Transcribes with the active local model. Model and backend are read once,
    /// together: a switch that lands mid-transcription never changes which
    /// backend runs or whether it gets the vocabulary.
    func transcribe(audio: Data, lang: String, vocabulary: String?) async throws -> String {
        guard let target = await manager.transcriptionTarget() else { throw LocalError.notReady }
        let samples = try WavDecoder.pcmFloatSamples(from: audio)
        // Large Whisper models return empty text when given promptTokens.
        let vocabulary = target.model.supportsVocabulary ? vocabulary : nil
        return try await target.backend.transcribe(samples: samples, lang: lang, vocabulary: vocabulary)
    }
}
