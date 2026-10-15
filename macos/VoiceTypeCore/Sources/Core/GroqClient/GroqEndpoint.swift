import Foundation

/// Centralized Groq HTTP endpoints. Mirrors `src/main/api/test-key.ts`,
/// `src/main/pipeline/transcribe.ts`, `src/main/pipeline/refine.ts`,
/// `src/main/pipeline/translate.ts`.
enum GroqEndpoint {
    static let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    static let models = baseURL.appendingPathComponent("models")
    static let audioTranscriptions = baseURL.appendingPathComponent("audio/transcriptions")
    static let chatCompletions = baseURL.appendingPathComponent("chat/completions")
}

enum GroqModel {
    /// Whisper Turbo — matches Electron `MODEL` in `transcribe.ts`.
    static let transcribe = "whisper-large-v3-turbo"
    /// Chat model for refine/translate. Groq decommissioned llama-3.3-70b-versatile
    /// (chat/completions started 404ing while whisper kept working — G-025).
    static let chatDefault = "openai/gpt-oss-120b"
}
