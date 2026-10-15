import Foundation

public enum PipelineError: Error, Equatable, Sendable {
    case missingApiKey
    case missingTranslateTarget
    case emptyTranscription
    case http(status: Int, message: String)
    case network(message: String)
    case cancelled
    case timeout
    case unknown(message: String)

    /// True when the server rejected the request for a reason retrying won't fix:
    /// a bad key (401), a decommissioned model (404), a malformed request (400).
    /// 429 is deliberately excluded — rate limiting is transient and the next
    /// dictation may well succeed. Callers use this to tell a permanent
    /// misconfiguration apart from simply being offline, which the raw-text
    /// fallback absorbs silently by design (G-025).
    public var isPermanentRejection: Bool {
        guard case .http(let status, _) = self else { return false }
        return (400..<500).contains(status) && status != 429
    }

    /// True when Groq couldn't be reached or refused our network (VPN 403,
    /// offline, timeout) — the audio itself was fine, so another engine may succeed.
    public var isConnectivityFailure: Bool {
        switch self {
        case .network, .timeout: return true
        case .http(let status, _): return status == 403
        default: return false
        }
    }

    // Maps a GroqError to its closest PipelineError counterpart.
    public static func from(_ error: GroqError) -> PipelineError {
        switch error {
        case .invalidKey:
            return .http(status: 401, message: "invalid-key")
        case .networkBlocked(let message):
            return .http(status: 403, message: message.isEmpty ? "network-blocked" : message)
        case .rateLimited:
            return .http(status: 429, message: "rate-limited")
        case .serverError(let status):
            return .http(status: status, message: "groq-\(status)")
        case .network(let underlying):
            if underlying.code == .timedOut {
                return .timeout
            }
            return .network(message: underlying.localizedDescription)
        case .malformedResponse:
            return .unknown(message: "malformed-response")
        case .cancelled:
            return .cancelled
        }
    }
}
