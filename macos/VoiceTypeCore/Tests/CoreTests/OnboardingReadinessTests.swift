import Testing
@testable import Core

@Suite("OnboardingReadiness")
struct OnboardingReadinessTests {

    private func blockers(
        _ step: OnboardingStep,
        _ config: AppConfig = AppConfig(),
        mic: Bool = true,
        ax: Bool = true,
        model: Bool = true,
        ai: AppleIntelligenceState = .available
    ) -> [OnboardingBlocker] {
        OnboardingReadiness.blockers(
            for: step, config: config,
            microphoneGranted: mic, accessibilityGranted: ax,
            localModelReady: model, appleIntelligence: ai
        )
    }

    private func config(
        transcriptionEngine: String = "auto",
        translateEngine: String = "auto",
        key: String = "",
        translateEnabled: Bool = false,
        handsFreeEnabled: Bool = true
    ) -> AppConfig {
        var cfg = AppConfig()
        cfg.transcriptionEngine = transcriptionEngine
        cfg.translateEngine = translateEngine
        cfg.groq.apiKey = key
        cfg.translate.enabled = translateEnabled
        cfg.handsFreeEnabled = handsFreeEnabled
        return cfg
    }

    @Test func explanationStepsHaveNoBlockers() {
        let cfg = config(transcriptionEngine: "groq", translateEnabled: false, handsFreeEnabled: false)
        for step in [OnboardingStep.prepare, .voiceNote, .history, .meetings, .personalize] {
            #expect(blockers(step, cfg, mic: false, ax: false, model: false, ai: .unsupportedOS) == [], "\(step)")
        }
    }

    @Test func allMissingInFixedOrder() {
        #expect(blockers(.dictation, config(), mic: false, ax: false, model: false)
                == [.accessibility, .microphone, .localModelNotReady])
    }

    @Test func groqEngineNeedsKeyNotModel() {
        #expect(blockers(.dictation, config(transcriptionEngine: "groq"), model: false) == [.groqKeyMissing])
        #expect(blockers(.dictation, config(transcriptionEngine: "groq", key: "gsk_x"), model: false) == [])
    }

    @Test func autoEngineWithKeyDoesNotNeedModel() {
        #expect(blockers(.dictation, config(key: "gsk_x"), model: false) == [])
    }

    @Test func localEngineAlwaysNeedsModel() {
        #expect(blockers(.dictation, config(transcriptionEngine: "local", key: "gsk_x"), model: false)
                == [.localModelNotReady])
    }

    @Test func translationNeedsTranslateEnabled() {
        #expect(blockers(.translation, config(translateEnabled: false)) == [.translateDisabled])
        #expect(blockers(.dictation, config(translateEnabled: false)) == [])
    }

    @Test func handsFreeNeedsHandsFreeEnabled() {
        #expect(blockers(.handsFree, config(handsFreeEnabled: false)) == [.handsFreeDisabled])
        #expect(blockers(.handsFree, config(handsFreeEnabled: true)) == [])
    }

    // Mirrors `defaultPipelineFactory`: below macOS 26 translation is always Groq;
    // "groq" needs the key, "local" needs Apple Intelligence, auto needs either.
    @Test func translatorAvailability() {
        #expect(blockers(.translation, config(translateEnabled: true), ai: .unsupportedOS)
                == [.translatorUnavailable])
        #expect(blockers(.translation, config(translateEngine: "local", key: "gsk_x", translateEnabled: true),
                         ai: .unsupportedOS) == [])

        #expect(blockers(.translation, config(translateEngine: "groq", translateEnabled: true))
                == [.translatorUnavailable])

        #expect(blockers(.translation, config(translateEngine: "local", key: "gsk_x", translateEnabled: true),
                         ai: .unavailable) == [.translatorUnavailable])

        #expect(blockers(.translation, config(translateEnabled: true), ai: .unavailable)
                == [.translatorUnavailable])
        #expect(blockers(.translation, config(key: "gsk_x", translateEnabled: true), ai: .unavailable) == [])
        #expect(blockers(.translation, config(translateEnabled: true), ai: .available) == [])

        #expect(blockers(.translation, config(translateEnabled: false), ai: .unsupportedOS)
                == [.translateDisabled])
    }
}
