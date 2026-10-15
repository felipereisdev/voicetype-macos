import Foundation

// Org → client catalog for classifying meeting notes (#74). Lives in
// AppConfig; the canonical names go into the LLM schema as enums and the
// model's answer is normalized back here — never a new variant.
public struct MeetingClient: Codable, Sendable, Equatable {
    public var name: String
    public var aliases: [String]

    public init(name: String, aliases: [String] = []) {
        self.name = name
        self.aliases = aliases
    }

    // Hand-edited config.json may omit `aliases`; a throw here would fail the whole AppConfig.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

public struct MeetingOrg: Codable, Sendable, Equatable {
    public var name: String
    public var aliases: [String]
    public var clients: [MeetingClient]

    public init(name: String, aliases: [String] = [], clients: [MeetingClient] = []) {
        self.name = name
        self.aliases = aliases
        self.clients = clients
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        clients = try c.decodeIfPresent([MeetingClient].self, forKey: .clients) ?? []
    }

    /// Personal data (orgs/clients) lives only in the user's config.json.
    public static let defaults: [MeetingOrg] = [MeetingOrg(name: "Pessoal")]

    /// Org used when the model can't tell (or answers outside the catalog),
    /// so every note lands in some org index. Only if it exists in the catalog.
    public static let fallbackName = "Pessoal"

    /// Maps the model's org/client (canonical name or alias, any case or
    /// accents) to canonical names. Unknown/null org → `fallbackName` (when in
    /// the catalog, else nil); a client only survives when it belongs to the
    /// resolved org.
    public static func resolve(org: String?, client: String?, in orgs: [MeetingOrg]) -> (org: String?, client: String?) {
        guard let org, let match = orgs.first(where: { matches(org, $0.name, $0.aliases) }) else {
            return (orgs.first { $0.name == fallbackName }?.name, nil)
        }
        let resolvedClient = client.flatMap { c in match.clients.first { matches(c, $0.name, $0.aliases) }?.name }
        return (match.name, resolvedClient)
    }

    private static func matches(_ value: String, _ name: String, _ aliases: [String]) -> Bool {
        let key = normalized(value)
        return !key.isEmpty && ([name] + aliases).contains { normalized($0) == key }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

// MARK: - Settings editor helpers

extension MeetingOrg {
    /// "a, b ,c" → ["a", "b", "c"]; blanks dropped.
    public static func parseAliases(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// pt-BR problems that block saving the catalog: empty names, duplicate
    /// orgs, duplicate clients within an org (trimmed, case-insensitive).
    public static func validationIssues(_ orgs: [MeetingOrg]) -> [String] {
        var issues: [String] = []
        func check(_ names: [String], empty: String, duplicate: (String) -> String) {
            var seen = Set<String>()
            for raw in names {
                let name = raw.trimmingCharacters(in: .whitespaces)
                if name.isEmpty { issues.append(empty) }
                else if !seen.insert(name.lowercased()).inserted { issues.append(duplicate(name)) }
            }
        }
        check(orgs.map(\.name), empty: "Organização sem nome.", duplicate: { "Organização duplicada: \($0)." })
        for org in orgs {
            check(org.clients.map(\.name), empty: "Cliente sem nome em \(org.name).",
                  duplicate: { "Cliente duplicado em \(org.name): \($0)." })
        }
        return issues
    }
}
