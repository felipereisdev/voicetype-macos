import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case shortcuts
    case audio
    case localTranscription
    case localRefinement
    case refineStyle
    case vocabulary
    case appearance
    case history
    case meetings
    case startup
    case about

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general:           return SettingsStrings.sidebarGeneral
        case .shortcuts:         return SettingsStrings.sidebarShortcuts
        case .audio:             return SettingsStrings.sidebarAudio
        case .localTranscription: return SettingsStrings.sidebarLocalTranscription
        case .localRefinement:   return SettingsStrings.sidebarLocalRefinement
        case .refineStyle:       return SettingsStrings.sidebarRefineStyle
        case .vocabulary:        return SettingsStrings.sidebarVocabulary
        case .appearance:        return SettingsStrings.sidebarAppearance
        case .history:           return SettingsStrings.sidebarHistory
        case .meetings:          return SettingsStrings.sidebarMeetings
        case .startup:           return SettingsStrings.sidebarStartup
        case .about:             return SettingsStrings.sidebarAbout
        }
    }

    var systemImage: String {
        switch self {
        case .general:           return "gearshape"
        case .shortcuts:         return "keyboard"
        case .audio:             return "mic"
        case .localTranscription: return "cpu"
        case .localRefinement:   return "wand.and.sparkles"
        case .refineStyle:       return "textformat"
        case .vocabulary:        return "character.book.closed"
        case .appearance:        return "paintpalette"
        case .history:           return "clock.arrow.circlepath"
        case .meetings:          return "person.2.wave.2"
        case .startup:           return "power"
        case .about:             return "info.circle"
        }
    }
}
