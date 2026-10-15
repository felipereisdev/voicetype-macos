import Foundation
import FoundationModels

// Wraps Apple Intelligence model availability. macOS 26-only; the composition
// root gates calls with #available and treats < 26 as unavailable (Groq path).
@available(macOS 26, *)
struct AIAvailability {
    private let model = SystemLanguageModel.default

    var isAvailable: Bool {
        if case .available = model.availability { return true }
        return false
    }

    var unavailableReason: String? {
        switch model.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "Este Mac não suporta Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Ative o Apple Intelligence em Ajustes do Sistema."
        case .unavailable(.modelNotReady):
            return "O modelo de linguagem ainda está sendo baixado."
        case .unavailable(_):
            return "O modelo de linguagem está indisponível no momento."
        }
    }
}
