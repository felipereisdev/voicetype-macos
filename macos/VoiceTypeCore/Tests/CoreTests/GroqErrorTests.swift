import Foundation
import Testing
@testable import Core

@Suite("GroqError")
struct GroqErrorTests {
    @Test("invalidKey describes invalid API key")
    func invalidKey() {
        #expect(GroqError.invalidKey.errorDescription == "Chave inválida ou sem permissão.")
    }

    @Test("rateLimited describes throttling")
    func rateLimited() {
        #expect(GroqError.rateLimited.errorDescription == "Limite de requisições atingido. Tente de novo em instantes.")
    }

    @Test("serverError includes the status")
    func serverError() {
        #expect(GroqError.serverError(status: 503).errorDescription == "Erro do servidor Groq (503). Tente de novo.")
    }

    @Test("network includes a readable hint")
    func network() {
        let url = URLError(.notConnectedToInternet)
        #expect(GroqError.network(underlying: url).errorDescription == "Sem conexão. Verifique a internet.")
    }

    @Test("malformedResponse describes parse failure")
    func malformed() {
        #expect(GroqError.malformedResponse.errorDescription == "Resposta inesperada da Groq.")
    }

    @Test("cancelled describes cancellation")
    func cancelled() {
        #expect(GroqError.cancelled.errorDescription == "Operação cancelada.")
    }
}
