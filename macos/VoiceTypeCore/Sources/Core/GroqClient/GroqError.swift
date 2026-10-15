import Foundation

public enum GroqError: Error, Equatable, Sendable {
    case invalidKey
    /// HTTP 403: Groq refused the network (VPN/proxy egress IP), not the key.
    case networkBlocked(message: String)
    case rateLimited
    case serverError(status: Int)
    case network(underlying: URLError)
    case malformedResponse
    case cancelled

    public static func == (lhs: GroqError, rhs: GroqError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidKey, .invalidKey),
             (.rateLimited, .rateLimited),
             (.malformedResponse, .malformedResponse),
             (.cancelled, .cancelled):
            return true
        case let (.networkBlocked(a), .networkBlocked(b)):
            return a == b
        case let (.serverError(a), .serverError(b)):
            return a == b
        case let (.network(a), .network(b)):
            return a.code == b.code
        default:
            return false
        }
    }
}

extension GroqError: LocalizedError {
    public static let networkBlockedDescription =
        "A Groq bloqueou sua rede (VPN ou proxy?). Desligue a VPN ou use a transcrição local."

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "Chave inválida ou sem permissão."
        case .networkBlocked:
            return Self.networkBlockedDescription
        case .rateLimited:
            return "Limite de requisições atingido. Tente de novo em instantes."
        case .serverError(let status):
            return "Erro do servidor Groq (\(status)). Tente de novo."
        case .network(let underlying):
            switch underlying.code {
            case .notConnectedToInternet, .dnsLookupFailed, .cannotConnectToHost:
                return "Sem conexão. Verifique a internet."
            case .timedOut:
                return "Tempo esgotado. Tente de novo."
            default:
                return "Falha de rede ao falar com a Groq."
            }
        case .malformedResponse:
            return "Resposta inesperada da Groq."
        case .cancelled:
            return "Operação cancelada."
        }
    }
}
