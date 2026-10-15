import Foundation
import Testing
@testable import Core

@Suite("GroqClient.testKey")
struct GroqClientTestKeyTests {
    private func makeClient(token: String, apiKey: String = "gsk_test") -> GroqClient {
        GroqClient(apiKey: apiKey, session: URLSession(configuration: .stubbed(token: token)))
    }

    @Test("returns void on 200 with correct URL + header")
    func success() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"data\":[]}".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        try await makeClient(token: token).testKey()
    }

    @Test("throws invalidKey on 401")
    func unauthorized() async {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        defer { URLProtocolStub.unregister(token: token) }
        do {
            try await makeClient(token: token).testKey()
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .invalidKey)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("throws network on connection failure")
    func networkFailure() async {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { URLProtocolStub.unregister(token: token) }
        do {
            try await makeClient(token: token).testKey()
            Issue.record("expected throw")
        } catch let err as GroqError {
            if case .network(let underlying) = err {
                #expect(underlying.code == .notConnectedToInternet)
            } else {
                Issue.record("expected .network, got \(err)")
            }
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}

@Suite("GroqClient.transcribe")
struct GroqClientTranscribeTests {
    private func makeClient(token: String) -> GroqClient {
        GroqClient(apiKey: "gsk_test", session: URLSession(configuration: .stubbed(token: token)))
    }

    @Test("posts multipart body with file field, model, language, response_format, temperature")
    func multipart() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/audio/transcriptions")
            #expect(request.httpMethod == "POST")
            let contentType = request.value(forHTTPHeaderField: "Content-Type") ?? ""
            #expect(contentType.hasPrefix("multipart/form-data; boundary="))
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("olá mundo".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        let audio = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
        let text = try await makeClient(token: token).transcribe(audio: audio, lang: "pt")
        #expect(text == "olá mundo")

        let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
        let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyStr.contains("name=\"file\"; filename=\"audio.wav\""))
        #expect(bodyStr.contains("Content-Type: audio/wav"))
        #expect(bodyStr.contains("name=\"model\""))
        #expect(bodyStr.contains("whisper-large-v3-turbo"))
        #expect(bodyStr.contains("name=\"language\""))
        #expect(bodyStr.contains("\r\npt\r\n"))
        #expect(bodyStr.contains("name=\"response_format\""))
        #expect(bodyStr.contains("\r\ntext\r\n"))
        #expect(bodyStr.contains("name=\"temperature\""))
        #expect(bodyStr.contains("\r\n0\r\n"))
    }

    @Test("retries on 5xx then succeeds")
    func retryOn5xx() async throws {
        let token = UUID().uuidString
        let calls = SyncCounter()
        URLProtocolStub.register(token: token) { request in
            let n = calls.bump()
            if n < 2 {
                let r = HTTPURLResponse(
                    url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                return (r, Data())
            }
            let r = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, Data("ok".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        let text = try await makeClient(token: token).transcribe(audio: Data([0x00]), lang: "pt")
        #expect(text == "ok")
        #expect(calls.value == 2)
    }

    @Test("throws serverError after retry budget exhausted")
    func budgetExhausted() async {
        let token = UUID().uuidString
        let calls = SyncCounter()
        URLProtocolStub.register(token: token) { request in
            _ = calls.bump()
            let r = HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (r, Data())
        }
        defer { URLProtocolStub.unregister(token: token) }
        do {
            _ = try await makeClient(token: token).transcribe(audio: Data([0x00]), lang: "pt")
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .serverError(status: 500))
            #expect(calls.value == 3)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("includes prompt multipart field when non-empty")
    func includesPrompt() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        _ = try await makeClient(token: token).transcribe(
            audio: Data([0x01]),
            lang: "pt",
            prompt: "These words may appear: Macsilva, Codex."
        )

        let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
        let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(bodyStr.contains("name=\"prompt\""))
        #expect(bodyStr.contains("These words may appear: Macsilva, Codex."))
    }

    @Test("omits prompt multipart field when nil")
    func omitsPromptWhenNil() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        _ = try await makeClient(token: token).transcribe(audio: Data([0x01]), lang: "pt", prompt: nil)

        let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
        let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(!bodyStr.contains("name=\"prompt\""))
    }

    @Test("omits prompt multipart field when empty/whitespace")
    func omitsPromptWhenEmpty() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("ok".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        _ = try await makeClient(token: token).transcribe(audio: Data([0x01]), lang: "pt", prompt: "   \n  ")

        let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
        let bodyStr = String(data: body, encoding: .isoLatin1) ?? ""
        #expect(!bodyStr.contains("name=\"prompt\""))
    }

    @Test("respects cancellation")
    func cancelled() async {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let r = HTTPURLResponse(
                url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (r, Data())
        }
        defer { URLProtocolStub.unregister(token: token) }
        let client = makeClient(token: token)
        let task = Task<String, Error> {
            try await client.transcribe(audio: Data([0x00]), lang: "pt")
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch let err as GroqError {
            #expect(err == .cancelled)
        } catch is CancellationError {
            // also acceptable
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}

@Suite("GroqClient.complete")
struct GroqClientCompleteTests {
    private func makeClient(token: String) -> GroqClient {
        GroqClient(apiKey: "gsk_test", session: URLSession(configuration: .stubbed(token: token)))
    }

    @Test("sends correct JSON body with model + messages + temperature + max_tokens")
    func happyPath() async throws {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gsk_test")
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let payload = """
            {"choices":[{"message":{"content":" hello back "}}]}
            """
            return (response, Data(payload.utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }

        let result = try await makeClient(token: token).complete(
            messages: [
                .init(role: "system", content: "you are a tester"),
                .init(role: "user", content: "say hi"),
            ],
            model: "llama-3.3-70b-versatile"
        )

        #expect(result == "hello back")

        let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
        #expect(json["model"] as? String == "llama-3.3-70b-versatile")
        #expect(json["temperature"] as? Double == 0.2)
        #expect(json["max_tokens"] as? Int == 1024)
        let msgs = json["messages"] as? [[String: String]] ?? []
        #expect(msgs.count == 2)
        #expect(msgs[0]["role"] == "system")
        #expect(msgs[0]["content"] == "you are a tester")
        #expect(msgs[1]["role"] == "user")
        #expect(msgs[1]["content"] == "say hi")
    }

    @Test("response_format omitted by default, set to json_object when requested")
    func jsonModeFlag() async throws {
        for jsonObject in [false, true] {
            let token = UUID().uuidString
            URLProtocolStub.register(token: token) { request in
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
            }
            defer { URLProtocolStub.unregister(token: token) }

            _ = try await makeClient(token: token).complete(
                messages: [.init(role: "user", content: "hi")],
                model: "llama-3.3-70b-versatile",
                jsonObject: jsonObject
            )

            let body = URLProtocolStub.capturedBodies(token: token).last ?? Data()
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
            let format = json["response_format"] as? [String: String]
            if jsonObject {
                #expect(format?["type"] == "json_object")
            } else {
                #expect(json["response_format"] == nil)
            }
        }
    }

    @Test("throws malformedResponse when choices missing")
    func malformed() async {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let r = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (r, Data("{}".utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        do {
            _ = try await makeClient(token: token).complete(
                messages: [.init(role: "user", content: "hi")],
                model: "llama-3.3-70b-versatile"
            )
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .malformedResponse)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }

    @Test("rateLimited on 429")
    func rateLimit() async {
        let token = UUID().uuidString
        let calls = SyncCounter()
        URLProtocolStub.register(token: token) { request in
            _ = calls.bump()
            let r = HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (r, Data())
        }
        defer { URLProtocolStub.unregister(token: token) }
        do {
            _ = try await makeClient(token: token).complete(
                messages: [.init(role: "user", content: "hi")],
                model: "llama-3.3-70b-versatile"
            )
            Issue.record("expected throw")
        } catch let err as GroqError {
            #expect(err == .rateLimited)
            #expect(calls.value == 3)
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}

/// Thread-safe sync counter for use inside @Sendable URLProtocolStub handlers
/// (which run on URLSession's delegate queue and can't await an actor).
final class SyncCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int = 0
    @discardableResult
    func bump() -> Int {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return count
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

@Suite("GroqClient 401 vs 403")
struct GroqClientAuthVsBlockedTests {
    private func run(status: Int, body: String) async -> (Error?, Int) {
        let token = UUID().uuidString
        URLProtocolStub.register(token: token) { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        defer { URLProtocolStub.unregister(token: token) }
        let client = GroqClient(apiKey: "gsk_test", session: URLSession(configuration: .stubbed(token: token)))
        do {
            _ = try await client.transcribe(audio: Data([0x01]), lang: "pt")
            return (nil, URLProtocolStub.capturedBodies(token: token).count)
        } catch {
            return (error, URLProtocolStub.capturedBodies(token: token).count)
        }
    }

    @Test("403 maps to networkBlocked with body message, no retry")
    func forbiddenIsNetworkBlocked() async {
        let (error, attempts) = await run(
            status: 403,
            body: #"{"error":{"message":"Access denied. Please check your network settings."}}"#)
        #expect(error as? GroqError == .networkBlocked(message: "Access denied. Please check your network settings."))
        #expect(attempts == 1)
    }

    @Test("401 maps to invalidKey, no retry")
    func unauthorizedIsInvalidKey() async {
        let (error, attempts) = await run(status: 401, body: "")
        #expect(error as? GroqError == .invalidKey)
        #expect(attempts == 1)
    }

    @Test("403 surfaces as connectivity failure with PT-BR copy")
    func pipelineMapping() {
        let mapped = PipelineError.from(.networkBlocked(message: ""))
        #expect(mapped == .http(status: 403, message: "network-blocked"))
        #expect(mapped.isConnectivityFailure)
        #expect(!PipelineError.http(status: 401, message: "invalid-key").isConnectivityFailure)
        #expect(!PipelineError.emptyTranscription.isConnectivityFailure)
        #expect(GroqError.networkBlocked(message: "x").errorDescription?.contains("VPN") == true)
    }
}
