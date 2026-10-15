import Foundation

public struct ChatMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

private struct ChatCompletionRequest: Encodable {
    struct ResponseFormat: Encodable { let type: String }
    let model: String
    let temperature: Double
    let max_tokens: Int
    let messages: [ChatMessage]
    let response_format: ResponseFormat?
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message?
    }
    let choices: [Choice]?
}

/// Protocol allowing UI layer to inject test doubles without touching URLSession.
public protocol GroqAPI: Sendable {
    func testKey() async throws
    /// Transcribes audio. When `prompt` is non-nil and non-empty, it is forwarded as the
    /// Whisper `prompt` field to bias recognition (proper nouns, jargon).
    /// Callers are responsible for honoring Whisper's ~224 token (~900 char) ceiling —
    /// this client does not enforce it.
    func transcribe(audio: Data, lang: String, prompt: String?) async throws -> String
    func complete(messages: [ChatMessage], model: String, jsonObject: Bool) async throws -> String
}

public extension GroqAPI {
    func complete(messages: [ChatMessage], model: String) async throws -> String {
        try await complete(messages: messages, model: model, jsonObject: false)
    }
}

public struct GroqClient: Sendable {
    public let apiKey: String
    private let session: URLSession

    public init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 5   // idle: max gap between packets, not connect
            config.timeoutIntervalForResource = 60 // resource
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Public surface (spec §5.1)

    /// GET /models, validates that the key returns 200. Throws `GroqError`.
    /// Mirrors `src/main/api/test-key.ts`.
    public func testKey() async throws {
        try await withRetry {
            var request = URLRequest(url: GroqEndpoint.models)
            request.httpMethod = "GET"
            applyAuth(to: &request)
            let (data, response) = try await perform(request)
            try expectOK(response, data: data)
        }
    }

    /// POST /audio/transcriptions with multipart body.
    /// Mirrors `src/main/pipeline/transcribe.ts`.
    public func transcribe(audio: Data, lang: String, prompt: String? = nil) async throws -> String {
        try await withRetry {
            var builder = MultipartFormBuilder()
            builder.appendText(name: "model", value: GroqModel.transcribe)
            builder.appendText(name: "language", value: lang)
            builder.appendText(name: "response_format", value: "text")
            builder.appendText(name: "temperature", value: "0")
            if let prompt {
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    builder.appendText(name: "prompt", value: trimmed)
                }
            }
            builder.appendFile(
                name: "file",
                filename: "audio.wav",
                contentType: "audio/wav",
                data: audio
            )
            var request = URLRequest(url: GroqEndpoint.audioTranscriptions)
            request.httpMethod = "POST"
            applyAuth(to: &request)
            request.setValue(builder.contentTypeHeader, forHTTPHeaderField: "Content-Type")
            let body = builder.finalize()
            request.httpBody = body
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

            let (data, response) = try await perform(request)
            try expectOK(response, data: data)
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty { throw GroqError.malformedResponse }
            return text
        }
    }

    /// POST /chat/completions. Mirrors `src/main/pipeline/refine.ts`
    /// and `src/main/pipeline/translate.ts`.
    public func complete(messages: [ChatMessage], model: String, jsonObject: Bool = false) async throws -> String {
        try await withRetry {
            let payload = ChatCompletionRequest(
                model: model,
                temperature: 0.2,
                max_tokens: 1024,
                messages: messages,
                response_format: jsonObject ? .init(type: "json_object") : nil
            )
            let body = try JSONEncoder().encode(payload)

            var request = URLRequest(url: GroqEndpoint.chatCompletions)
            request.httpMethod = "POST"
            applyAuth(to: &request)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            request.httpBody = body

            let (data, response) = try await perform(request)
            try expectOK(response, data: data)
            let decoded: ChatCompletionResponse
            do {
                decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            } catch {
                throw GroqError.malformedResponse
            }
            let content = decoded.choices?.first?.message?.content?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if content.isEmpty { throw GroqError.malformedResponse }
            return content
        }
    }

    // MARK: - Internals

    func applyAuth(to request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    /// Run a request through the session, translating `URLError` → `GroqError.network`.
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw GroqError.malformedResponse
            }
            return (data, http)
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw GroqError.cancelled }
            throw GroqError.network(underlying: urlError)
        }
    }

    /// Map HTTP status to a `GroqError`, or return on 2xx.
    func expectOK(_ response: HTTPURLResponse, data: Data = Data()) throws {
        switch response.statusCode {
        case 200...299:
            return
        case 401:
            throw GroqError.invalidKey
        case 403:
            // Groq answers 403 for blocked egress IPs (VPN/proxy), not bad keys (G-032).
            throw GroqError.networkBlocked(message: Self.errorMessage(in: data))
        case 429:
            throw GroqError.rateLimited
        case 500...599:
            throw GroqError.serverError(status: response.statusCode)
        default:
            throw GroqError.serverError(status: response.statusCode)
        }
    }

    /// `{"error":{"message":"…"}}` → the message, or "" when absent.
    static func errorMessage(in data: Data) -> String {
        struct Body: Decodable { struct E: Decodable { let message: String? }; let error: E? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message ?? ""
    }
}

extension GroqClient: GroqAPI {}
