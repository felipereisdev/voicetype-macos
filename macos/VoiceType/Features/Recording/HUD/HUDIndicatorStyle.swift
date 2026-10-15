import Foundation

enum HUDIndicatorStyle: String, CaseIterable, Identifiable, Sendable {
    case auto
    case notch
    case pill

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: "Automático"
        case .notch: "Notch (Dynamic Island)"
        case .pill: "Barra flutuante"
        }
    }
}
