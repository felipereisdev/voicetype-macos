import Foundation
@testable import Core

// Closure-driven GroqAPI stub. Lets pipeline tests assert per-call args
// without spinning up URLProtocolStub.
final class FakeGroq: GroqAPI, @unchecked Sendable {
    typealias TranscribeFn = @Sendable (Data, String, String?) async throws -> String
    typealias CompleteFn = @Sendable ([ChatMessage], String) async throws -> String

    var transcribeImpl: TranscribeFn = { _, _, _ in "" }
    var completeImpl: CompleteFn = { _, _ in "" }

    private(set) var transcribeCalls: [(audio: Data, lang: String, prompt: String?)] = []
    private(set) var completeCalls: [(messages: [ChatMessage], model: String, jsonObject: Bool)] = []
    private let lock = NSLock()

    func testKey() async throws {}

    func transcribe(audio: Data, lang: String, prompt: String?) async throws -> String {
        lock.lock()
        transcribeCalls.append((audio, lang, prompt))
        lock.unlock()
        return try await transcribeImpl(audio, lang, prompt)
    }

    func complete(messages: [ChatMessage], model: String, jsonObject: Bool) async throws -> String {
        lock.lock()
        completeCalls.append((messages, model, jsonObject))
        lock.unlock()
        return try await completeImpl(messages, model)
    }
}
