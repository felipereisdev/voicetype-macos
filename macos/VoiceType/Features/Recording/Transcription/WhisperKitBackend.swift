import Foundation
import Core
import WhisperKit
import os

/// A loaded WhisperKit model.
///
/// **Concurrency invariant (não-Sendable off-actor, FU-N10):**
/// `WhisperKit` não é `Sendable`, mas o acesso é seguro aqui por duas razões combinadas:
///
/// 1. **Kit imutável pós-ready** — o backend só é criado depois que `loadModels()` e
///    `prewarmModels()` terminaram, ponto a partir do qual o objeto não é mais mutado.
///    Não há escrita concorrente enquanto `transcribe` está rodando.
///
/// 2. **Pipeline serializado** — cada nova gravação cancela a `Task` anterior antes de criar
///    uma nova (veja `RecordingOrchestrator`). Há no máximo um consumidor ativo de `kit`
///    por vez; não há corrida de leitura/escrita entre duas chamadas simultâneas.
///
/// **Revisão necessária na migração Swift 6 / strict concurrency:**
/// Ao habilitar `-strict-concurrency=complete` no App target, rever se a invariância
/// acima ainda vale antes de manter o `@unchecked Sendable`, ou isolar o backend num ator.
final class WhisperKitBackend: LocalSpeechBackend, @unchecked Sendable {
    private let kit: WhisperKit
    private static let logger = Logger(subsystem: "dev.voicetype.app", category: "LocalTranscriber")

    init(kit: WhisperKit) {
        self.kit = kit
    }

    func transcribe(samples: [Float], lang: String, vocabulary: String?) async throws -> String {
        let promptTokens = Self.promptTokens(tokenizer: kit.tokenizer, vocabulary: vocabulary)
        let options = DecodingOptions(
            verbose: false, task: .transcribe, language: lang,
            temperature: 0.0, temperatureFallbackCount: 0,
            usePrefillPrompt: true, detectLanguage: false,
            skipSpecialTokens: true, withoutTimestamps: false,
            promptTokens: promptTokens, chunkingStrategy: .vad
        )
        let audioSeconds = Double(samples.count) / 16_000.0
        let clock = ContinuousClock()
        let start = clock.now
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let elapsed = start.duration(to: clock.now)
        let text = results.map { $0.text }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Self.logger.info("local transcription done: \(elapsed.description, privacy: .public) for \(audioSeconds, format: .fixed(precision: 1), privacy: .public)s audio, \(text.count, privacy: .public) chars")
        return text
    }

    private static func promptTokens(tokenizer: WhisperTokenizer?, vocabulary: String?) -> [Int]? {
        guard let tokenizer, let raw = vocabulary else { return nil }
        let keywords = VocabularyTerms.parse(raw)
        guard !keywords.isEmpty else { return nil }
        let specialBegin = tokenizer.specialTokens.specialTokenBegin
        let tokens = tokenizer.encode(text: keywords.joined(separator: ", ")).filter { $0 < specialBegin }
        return tokens.isEmpty ? nil : tokens
    }
}
