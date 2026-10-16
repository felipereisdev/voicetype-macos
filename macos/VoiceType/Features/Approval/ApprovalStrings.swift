import Core
import Foundation

/// pt-BR copy for the OpenKnowledge approvals: menu, discard alert and the
/// notifications of a vault write the launch had to finish or undo.
enum ApprovalStrings {
    static let windowTitle = "Aprovar reunião"
    static let noMeeting = "Nenhuma reunião selecionada."

    // Menu
    static func pendingMenu(_ count: Int) -> String {
        count == 1 ? "1 reunião aguardando aprovação" : "\(count) reuniões aguardando aprovação"
    }

    static func item(_ meeting: PendingMeeting) -> String {
        "\(meeting.title) — \(meeting.startedAt.formatted(itemDate))"
    }

    static let review = "Revisar…"
    static let discard = "Descartar…"

    private static let itemDate = Date.VerbatimFormatStyle(
        format: "\(day: .twoDigits)/\(month: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian)
    )

    // Discard
    static func discardTitle(_ title: String) -> String { "Descartar “\(title)”?" }
    static let discardBody = "Nada desta reunião será gravado no MegaBrain. O áudio e a transcrição continuam no Mac."
    static let discardConfirm = "Descartar"
    static let cancel = "Cancelar"
    static func discardBusyTitle(_ title: String) -> String { "“\(title)” não pode ser descartada agora" }
    static let discardBusyBody = "Uma gravação desta reunião no MegaBrain está em andamento ou foi interrompida. O VoiceType conclui ou desfaz essa gravação no próximo início ou ao abrir a reunião."

    // Recovery notifications
    static let partialTitle = "Gravação no MegaBrain concluída em parte"
    static func partialBody(count: Int, title: String, preserved: [String]) -> String {
        let changed = count == 1
            ? "1 item de “\(title)” mudou durante a gravação e voltou para revisão."
            : "\(count) itens de “\(title)” mudaram durante a gravação e voltaram para revisão."
        let kept = preserved.isEmpty ? "" : " Versões externas guardadas em \(preserved.joined(separator: ", "))."
        return changed + " O registro e a transcrição já estão no MegaBrain." + kept
    }

    static let incompleteTitle = "Gravação no MegaBrain incompleta"
    static func incompleteBody(_ paths: [String]) -> String {
        "Faltou gravar \(paths.joined(separator: ", ")). O VoiceType tenta de novo no próximo início ou ao abrir a reunião."
    }

    static let rolledBackTitle = "Gravação no MegaBrain desfeita"
    static func rolledBackBody(count: Int, title: String) -> String {
        let changed = count == 1 ? "1 doc mudou" : "\(count) docs mudaram"
        return "\(changed) durante a gravação. Revise de novo a reunião “\(title)”."
    }

    static let interruptedTitle = "Gravação no MegaBrain interrompida"
    static func divergencesBody(paths: [String], copies: [String]) -> String {
        let edited = paths.count == 1 ? "1 arquivo foi editado" : "\(paths.count) arquivos foram editados"
        let undone = paths.count == 1 ? "não foi desfeito" : "não foram desfeitos"
        return "\(edited) durante a gravação e \(undone): \(paths.joined(separator: ", ")). Cópias em \(copies.joined(separator: ", "))."
    }

    static func vaultUnavailableBody(_ root: String) -> String {
        "O vault \(root) não está acessível. Nada foi alterado; o VoiceType tenta de novo no próximo início."
    }

    static func recoveryFailedBody(_ error: String) -> String {
        "\(error) O VoiceType tenta de novo no próximo início ou ao abrir a reunião."
    }
}
