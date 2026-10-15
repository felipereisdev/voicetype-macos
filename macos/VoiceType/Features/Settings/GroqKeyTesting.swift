import Core
import Foundation

/// Result of probing a Groq API key against `/models`.
struct TestKeyResult: Equatable, Sendable {
    let ok: Bool
    let status: Int?
}

/// Phase 6 view-models depend on this narrow surface — production wires
/// `GroqClient`, tests inject stubs. Mapping from `GroqError` to the result
/// shape happens inside `LiveGroqKeyTester` so call sites don't deal with
/// HTTP status reconstruction.
protocol GroqKeyTesting: Sendable {
    func testKey(_ apiKey: String) async -> TestKeyResult
}

struct LiveGroqKeyTester: GroqKeyTesting {
    private let makeClient: @Sendable (String) -> GroqAPI

    init(makeClient: @Sendable @escaping (String) -> GroqAPI = { GroqClient(apiKey: $0) }) {
        self.makeClient = makeClient
    }

    func testKey(_ apiKey: String) async -> TestKeyResult {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TestKeyResult(ok: false, status: 401)
        }
        let client = makeClient(trimmed)
        do {
            try await client.testKey()
            return TestKeyResult(ok: true, status: nil)
        } catch let err as GroqError {
            switch err {
            case .invalidKey:                  return TestKeyResult(ok: false, status: 401)
            case .networkBlocked:              return TestKeyResult(ok: false, status: 403)
            case .rateLimited:                 return TestKeyResult(ok: false, status: 429)
            case .serverError(let s):          return TestKeyResult(ok: false, status: s)
            case .malformedResponse,
                 .network,
                 .cancelled:                   return TestKeyResult(ok: false, status: nil)
            }
        } catch {
            return TestKeyResult(ok: false, status: nil)
        }
    }
}
