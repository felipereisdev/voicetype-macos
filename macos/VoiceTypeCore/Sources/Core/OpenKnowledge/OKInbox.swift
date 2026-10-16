import Darwin
import Foundation

/// Voice notes in OpenKnowledge mode: the same daily + idea flow as
/// `DailyNote`/`IdeaNote`, under `<vault>/_inbox/` (outside every project),
/// with OK frontmatter and relative Markdown links instead of `[[wikilinks]]`.
public enum OKInbox {
    public static let folder = "_inbox"
    static let dailyFolder = "diario"
    static let ideasFolder = "ideias"
    static let metadata = "title: Inbox\ndescription: Notas de voz do VoiceType (diário e ideias), fora dos projetos.\ntags:\n  - inbox\n"

    /// `<vault>/_inbox/diario/YYYY-MM-DD.md`
    public static func dailyURL(in vault: URL, for date: Date, timeZone: TimeZone = .current) -> URL {
        vault.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(dailyFolder, isDirectory: true)
            .appendingPathComponent("\(day(date, timeZone)).md")
    }

    /// The idea note with OK frontmatter; the body is `IdeaNote.render`'s.
    public static func renderIdea(_ idea: IdeaNote, timeZone: TimeZone = .current) -> String {
        let f = { MeetingNoteRenderer.formatter($0, timeZone).string(from: idea.createdAt) }
        let tags = ["ideia"] + idea.tags.filter { $0 != "ideia" }
        return """
        ---
        id: \(idea.id.uuidString)
        title: \(MeetingNoteRenderer.yamlString(idea.title))
        description: \(MeetingNoteRenderer.yamlString(description(of: idea.text)))
        type: ideia
        date: \(f("yyyy-MM-dd"))
        created: \(f("yyyy-MM-dd'T'HH:mm:ssxxx"))
        tags: [\(tags.joined(separator: ", "))]
        ---

        \(idea.text)

        ## Transcrição original

        \(idea.original.trimmingCharacters(in: .whitespacesAndNewlines))

        """
    }

    /// Writes atomically to `_inbox/ideias/YYYY-MM-DD-<slug>.md` (empty slug →
    /// `ideia`); another idea gets `-2`, `-3`…, the same id overwrites.
    @discardableResult
    public static func writeIdea(
        _ idea: IdeaNote,
        to vault: URL,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        try writeIdea(idea, to: vault, timeZone: timeZone, fileManager: fileManager, beforeRename: nil)
    }

    /// `beforeRename` sees the staged file right before it is moved in (tests).
    static func writeIdea(
        _ idea: IdeaNote,
        to vault: URL,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default,
        beforeRename: ((URL) throws -> Void)?
    ) throws -> URL {
        let dir = vault.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(ideasFolder, isDirectory: true)
        try prepare(dir, in: vault, fileManager: fileManager)
        let slug = OKSlug.make(from: idea.title)
        let base = "\(day(idea.createdAt, timeZone))-\(slug.isEmpty ? "ideia" : slug)"
        let url = OKPath.uniqueDestination(base: base, id: idea.id, in: dir, fileManager: fileManager)
        try stagedWrite(Data(renderIdea(idea, timeZone: timeZone).utf8), to: url, vault: vault,
                        replacing: true, fileManager: fileManager, beforeRename: beforeRename)
        return url
    }

    /// `[Título](../ideias/<arquivo>.md)` — the daily's entry for an idea.
    /// `[ ] ( )` and line breaks leave the label so they can't break the link.
    public static func link(toIdea idea: URL, title: String, vault: URL) -> String {
        let label = title.unicodeScalars
            .map { "[]()".unicodeScalars.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        let root = vault.standardizedFileURL.path + "/"
        let path = idea.standardizedFileURL.path
        let target = path.hasPrefix(root) ? String(path.dropFirst(root.count)) : "\(folder)/\(ideasFolder)/\(idea.lastPathComponent)"
        let from = "\(folder)/\(dailyFolder)/daily.md"
        return "[\(label.isEmpty ? "ideia" : label)](\(OKPath.relativeLink(from: from, to: target)))"
    }

    /// `DailyNote.append` for `_inbox/diario/`: a new day starts with the OK
    /// frontmatter; an existing note only gains lines.
    @discardableResult
    public static func appendToDaily(
        _ text: String,
        at date: Date = Date(),
        to vault: URL,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default
    ) throws -> URL {
        try appendToDaily(text, at: date, to: vault, timeZone: timeZone, fileManager: fileManager, beforeRename: nil)
    }

    /// `beforeRename` sees the staged file right before it is moved in (tests).
    static func appendToDaily(
        _ text: String,
        at date: Date = Date(),
        to vault: URL,
        timeZone: TimeZone = .current,
        fileManager: FileManager = .default,
        beforeRename: ((URL) throws -> Void)?
    ) throws -> URL {
        let url = dailyURL(in: vault, for: date, timeZone: timeZone)
        try prepare(url.deletingLastPathComponent(), in: vault, fileManager: fileManager)
        let existing = fileManager.fileExists(atPath: url.path) ? try String(contentsOf: url, encoding: .utf8) : nil
        let day = day(date, timeZone)
        let header = "---\ntitle: \(MeetingNoteRenderer.yamlString("Diário \(day)"))\n"
            + "description: \(MeetingNoteRenderer.yamlString("Notas de voz de \(day)."))\n"
            + "type: diario\ndate: \(day)\ntags: [diario]\n---\n\n"
        let out = DailyNote.inserting(text, at: date, into: existing, timeZone: timeZone, newFileHeader: header)
        try stagedWrite(Data(out.utf8), to: url, vault: vault, replacing: true, fileManager: fileManager, beforeRename: beforeRename)
        return url
    }

    // MARK: - Helpers

    private static func day(_ date: Date, _ timeZone: TimeZone) -> String {
        MeetingNoteRenderer.formatter("yyyy-MM-dd", timeZone).string(from: date)
    }

    /// First non-empty line of the text, at most 160 characters.
    private static func description(of text: String) -> String {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return String(line.prefix(160)).trimmingCharacters(in: .whitespaces)
    }

    private static func prepare(_ dir: URL, in vault: URL, fileManager: FileManager) throws {
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try ensureMetadata(in: vault, fileManager: fileManager)
    }

    /// `_inbox/.ok/frontmatter.yml` (the folder's title in OpenKnowledge),
    /// created when missing and never replaced: moved in with `RENAME_EXCL`,
    /// so a file someone else wrote in the meantime wins.
    private static func ensureMetadata(in vault: URL, fileManager: FileManager) throws {
        let url = vault.appendingPathComponent(folder, isDirectory: true)
            .appendingPathComponent(".ok", isDirectory: true)
            .appendingPathComponent("frontmatter.yml")
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try stagedWrite(Data(metadata.utf8), to: url, vault: vault, replacing: false, fileManager: fileManager, beforeRename: nil)
    }

    /// Writes `data` to a uniquely named file under `.ok/local/voicetype-staging/`
    /// (ignored by OpenKnowledge's git) and renames it onto `url`, so no
    /// temporary or partial copy ever sits in a content folder, where the OK
    /// auto-commit would pick it up. `replacing: false` uses `RENAME_EXCL` and
    /// keeps an existing file. A failure leaves `url` as it was.
    private static func stagedWrite(
        _ data: Data,
        to url: URL,
        vault: URL,
        replacing: Bool,
        fileManager: FileManager,
        beforeRename: ((URL) throws -> Void)?
    ) throws {
        let staging = vault.appendingPathComponent(".ok/local/voicetype-staging", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        let tmp = staging.appendingPathComponent("inbox-\(UUID().uuidString).\(url.pathExtension)")
        try data.write(to: tmp, options: .withoutOverwriting)
        defer { try? fileManager.removeItem(at: tmp) }
        try beforeRename?(tmp)
        if renamex_np(tmp.path, url.path, replacing ? 0 : UInt32(RENAME_EXCL)) != 0 {
            let code = errno
            guard !replacing, code == EEXIST else { throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO) }
        }
    }
}
