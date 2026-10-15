import Foundation

public enum AppCategory: String, CaseIterable, Sendable {
    case email, chat, ai, document, other
}

// Which tone the refiner uses for the focused app. Precedence:
// per-app override > category style > global `recording.refineStyle`.
// Unknown apps land in `.other`, which has no category style → global.
public enum RefineStyle {
    public static let styles = ["natural", "concise", "formal"]

    /// Shipped category → style defaults; categories absent here follow global.
    public static let defaultCategoryStyles: [String: String] = ["email": "formal"]

    // Keys lowercased — bundle IDs compare case-insensitively.
    static let categoryByBundleID: [String: AppCategory] = [
        "com.apple.mail": .email,
        "com.microsoft.outlook": .email,
        "com.superhuman.electron": .email,
        "com.tinyspeck.slackmacgap": .chat,
        "com.apple.mobilesms": .chat,
        "net.whatsapp.whatsapp": .chat,
        "ru.keepcoder.telegram": .chat,
        "com.hnc.discord": .chat,
        "com.microsoft.teams2": .chat,
        "com.openai.chat": .ai,
        "com.anthropic.claudefordesktop": .ai,
        "ai.perplexity.mac": .ai,
        "com.apple.iwork.pages": .document,
        "com.microsoft.word": .document,
        "notion.id": .document,
        "md.obsidian": .document,
        "com.apple.notes": .document,
        "com.apple.textedit": .document,
    ]

    public static func category(for bundleID: String) -> AppCategory {
        categoryByBundleID[bundleID.lowercased()] ?? .other
    }

    public static func resolve(
        bundleID: String,
        global: String,
        categoryStyles: [String: String],
        appOverrides: [String: String]
    ) -> String {
        if let style = appOverrides.first(where: { $0.key.caseInsensitiveCompare(bundleID) == .orderedSame })?.value,
           !style.isEmpty {
            return style
        }
        if let style = categoryStyles[category(for: bundleID).rawValue], !style.isEmpty {
            return style
        }
        return global
    }
}
