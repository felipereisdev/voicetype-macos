import Foundation

/// pt-BR copy table for the Phase 7 History window. Mirrors keys from
/// `src/shared/messages.ts` `HISTORY.*` for the Electron Vue history view.
enum HistoryStrings {
    static let title = "Histórico"
    static let searchPlaceholder = "Buscar transcrições"
    static let clearAll = "Apagar tudo"
    static let clearAllConfirmTitle = "Apagar todo o histórico?"
    static let clearAllConfirmMessage = "Esta ação não pode ser desfeita."
    static let clearAllConfirmOK = "Apagar tudo"
    static let clearAllConfirmCancel = "Cancelar"
    static let copy = "Copiar"
    static let repaste = "Recolar"
    static let delete = "Apagar"
    static let empty = "Nenhuma transcrição ainda."

    static let modeRefine = "Refinar"
    static let modeTranslate = "Traduzir"
    static let modeRaw = "Bruto"

    static let columnWhen = "Quando"
    static let columnMode = "Modo"
    static let columnApp = "App"
    static let columnText = "Texto"
    static let columnActions = "Ações"
}
