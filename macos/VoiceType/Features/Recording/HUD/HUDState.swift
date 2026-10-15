import Foundation

enum HUDState: Equatable {
    case hidden
    case recording(level: Float, elapsed: TimeInterval, locked: Bool = false)
    case processing
    case permissionDenied
}
