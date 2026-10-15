import Foundation
import os

// Wraps GroqClient.transcribe with PipelineError mapping + empty-string guard.
// Mirrors src/main/pipeline/transcribe.ts.
public struct Transcriber: Sendable {
    private let groq: GroqAPI
    private static let logger = Logger(subsystem: "dev.voicetype.core", category: "transcriber")

    public init(groq: GroqAPI) {
        self.groq = groq
    }

    public func transcribe(
        audio: Data,
        lang: String,
        vocabulary: String? = nil
    ) async throws -> String {
        do {
            let prompt = Self.buildPrompt(from: vocabulary)
            let raw = try await groq.transcribe(audio: audio, lang: lang, prompt: prompt)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw PipelineError.emptyTranscription }
            return trimmed
        } catch let error as PipelineError {
            throw error
        } catch let error as GroqError {
            throw PipelineError.from(error)
        } catch is CancellationError {
            throw PipelineError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw PipelineError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw PipelineError.timeout
        } catch let error as URLError {
            throw PipelineError.network(message: error.localizedDescription)
        } catch {
            throw PipelineError.unknown(message: error.localizedDescription)
        }
    }

    /// Splits user-entered vocabulary on newline AND comma, trims, drops empties.
    /// Order is kept — users put higher-priority terms first.
    public static func terms(from vocabulary: String?) -> [String] {
        guard let vocabulary else { return [] }
        return vocabulary.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Build a Whisper-friendly `prompt` string from user-entered vocabulary text.
    ///
    /// Parsing: splits on newline AND comma, trims, drops empties.
    /// Format: `"These words may appear: term1, term2, ..."` — the English
    /// meta-phrasing biases Whisper better regardless of audio language.
    /// Length cap: drops terms from the end one by one until the final string
    /// fits within `maxChars` (preserves higher-priority terms users put first).
    public static func buildPrompt(from vocabulary: String?, maxChars: Int = 900) -> String? {
        var terms = terms(from: vocabulary)
        guard !terms.isEmpty else { return nil }

        let prefix = "These words may appear: "
        let suffix = "."
        let initialCount = terms.count

        while !terms.isEmpty {
            let body = terms.joined(separator: ", ")
            let candidate = prefix + body + suffix
            if candidate.count <= maxChars {
                if terms.count < initialCount {
                    logger.warning("vocabulary truncated: dropped \(initialCount - terms.count, privacy: .public) of \(initialCount, privacy: .public) terms to fit \(maxChars, privacy: .public) char cap")
                }
                return candidate
            }
            terms.removeLast()
        }

        logger.warning("vocabulary fully dropped: all \(initialCount, privacy: .public) terms exceed \(maxChars, privacy: .public) char cap")
        return nil
    }
}
