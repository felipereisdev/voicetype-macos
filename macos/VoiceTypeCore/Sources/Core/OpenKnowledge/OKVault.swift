import Foundation

/// Where meeting notes and voice notes go: the Obsidian folder (unchanged
/// behavior) or an OpenKnowledge project such as the MegaBrain.
public enum MeetingVaultKind: String, Codable, Sendable, CaseIterable {
    case obsidian
    case openKnowledge = "openknowledge"
}

public enum OKVault {
    /// The configured vault path with `~` expanded, as a directory URL.
    public static func url(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// An OpenKnowledge project root holds a `.ok/` directory (a plain file
    /// named `.ok` doesn't count).
    public static func isProjectRoot(_ url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.appendingPathComponent(".ok").path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
