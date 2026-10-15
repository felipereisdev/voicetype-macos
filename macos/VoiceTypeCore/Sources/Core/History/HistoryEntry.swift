import Foundation

public enum HistoryMode: String, Codable, Sendable, CaseIterable {
    case refine
    case translate
    case raw
}

public struct HistoryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let createdAt: Date
    public let mode: HistoryMode
    public let sourceApp: String   // bundle identifier; "" if unknown
    public let text: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        mode: HistoryMode,
        sourceApp: String,
        text: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.mode = mode
        self.sourceApp = sourceApp
        self.text = text
    }
}
