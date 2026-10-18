import Foundation

// What keeps a practice step from working, in the order the step lists them.
public enum OnboardingBlocker: Equatable, Sendable {
    case accessibility, microphone, groqKeyMissing, localModelNotReady, translateDisabled, translatorUnavailable, handsFreeDisabled
}

// Apple Intelligence as the translator sees it; below macOS 26 it is `.unsupportedOS`.
public enum AppleIntelligenceState: Equatable, Sendable { case unsupportedOS, unavailable, available }

// Which blockers each practice step shows before the user tries it. The engine
// rules mirror the orchestrator's `preflight` and `defaultPipelineFactory`, so a
// step only warns about what would really make its take fail or come out raw.
public enum OnboardingReadiness {
    public static func blockers(for step: OnboardingStep, config: AppConfig,
                                microphoneGranted: Bool, accessibilityGranted: Bool,
                                localModelReady: Bool,
                                appleIntelligence: AppleIntelligenceState) -> [OnboardingBlocker] {
        guard step.isPractice else { return [] }
        let hasKey = !config.groq.apiKey.isEmpty
        var blockers: [OnboardingBlocker] = []

        if !accessibilityGranted { blockers.append(.accessibility) }
        if !microphoneGranted { blockers.append(.microphone) }

        switch config.transcriptionEngine {
        case "groq":
            if !hasKey { blockers.append(.groqKeyMissing) }
        case "local":
            if !localModelReady { blockers.append(.localModelNotReady) }
        default:
            if !hasKey && !localModelReady { blockers.append(.localModelNotReady) }
        }

        if step == .translation {
            if !config.translate.enabled {
                blockers.append(.translateDisabled)
            } else if !translatorAvailable(config.translateEngine, hasKey: hasKey, appleIntelligence: appleIntelligence) {
                blockers.append(.translatorUnavailable)
            }
        }

        if step == .handsFree && !config.handsFreeEnabled { blockers.append(.handsFreeDisabled) }
        return blockers
    }

    // Below macOS 26 translation is always Groq; "groq" needs the key, "local"
    // needs Apple Intelligence, auto needs either.
    private static func translatorAvailable(_ engine: String, hasKey: Bool,
                                            appleIntelligence: AppleIntelligenceState) -> Bool {
        if appleIntelligence == .unsupportedOS { return hasKey }
        switch engine {
        case "groq":  return hasKey
        case "local": return appleIntelligence == .available
        default:      return hasKey || appleIntelligence == .available
        }
    }
}
