import Foundation
import Core
import WhisperKit
import os

struct LocalTranscriber: Sendable {
    let manager: WhisperModelManager
    private static let logger = Logger(subsystem: "dev.voicetype.app", category: "LocalTranscriber")

    enum LocalError: Error { case notReady }

    /// Transcribes audio using a WhisperKit pipeline.
    ///
    /// **Concurrency invariant (não-Sendable off-actor):**
    /// `WhisperKit` não é `Sendable`, mas o acesso é seguro aqui por duas razões combinadas:
    ///
    /// 1. **Kit imutável pós-ready** — `WhisperModelManager.transcriber()` retorna `kit` apenas
    ///    quando o estado é `.ready`, ponto a partir do qual o objeto não é mais mutado.
    ///    Não há escrita concorrente enquanto `transcribe` está rodando.
    ///
    /// 2. **Pipeline serializado** — cada nova gravação cancela a `Task` anterior antes de criar
    ///    uma nova (veja `RecordingOrchestrator`). Há no máximo um consumidor ativo de `kit`
    ///    por vez; não há corrida de leitura/escrita entre duas chamadas simultâneas.
    ///
    /// **Revisão necessária na migração Swift 6 / strict concurrency:**
    /// Ao habilitar `-strict-concurrency=complete` no App target, o compilador vai rejeitar
    /// a captura de `kit` (não-Sendable) fora de um ator. Será necessário isolar
    /// `LocalTranscriber` num ator próprio, marcar `WhisperKit` como `@unchecked Sendable`
    /// (se a invariância acima ainda valer), ou reestruturar o factory do pipeline.
    func transcribe(audio: Data, lang: String, vocabulary: String?) async throws -> String {
        guard let kit = await manager.transcriber() else { throw LocalError.notReady }
        let samples = try WavDecoder.pcmFloatSamples(from: audio)

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
        let keywords = raw
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !keywords.isEmpty else { return nil }
        let specialBegin = tokenizer.specialTokens.specialTokenBegin
        let tokens = tokenizer.encode(text: keywords.joined(separator: ", ")).filter { $0 < specialBegin }
        return tokens.isEmpty ? nil : tokens
    }
}
