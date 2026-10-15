import Foundation

enum AudioRecorderError: LocalizedError, Equatable {
    case permissionDenied
    case noInputDevice
    case deviceDisconnected
    case engineFailure(String)
    case formatUnsupported

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permita o microfone em Configurações."
        case .noInputDevice:
            return "Nenhum microfone disponível."
        case .deviceDisconnected:
            return "Microfone desconectado durante a gravação."
        case .engineFailure(let message):
            return "Falha no motor de áudio: \(message)"
        case .formatUnsupported:
            return "Formato de áudio não suportado."
        }
    }
}
