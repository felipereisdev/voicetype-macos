import Testing
import Foundation
@testable import Core

private func u(_ track: MeetingTrack, _ start: Double, _ end: Double, _ text: String, cr: Double = 1.2) -> MeetingUtterance {
    MeetingUtterance(track: track, start: start, end: end, text: text, compressionRatio: cr)
}

@Suite("MeetingTranscript.hallucination")
struct MeetingHallucinationTests {
    @Test func dropsLowDiversityRepetition() {
        #expect(MeetingTranscript.isHallucination(u(.mic, 0, 3, "E aí E aí E aí E aí E aí E aí")))
    }

    @Test func dropsHighCompressionRatio() {
        #expect(MeetingTranscript.isHallucination(u(.mic, 0, 3, "we will see you next time", cr: 2.6)))
    }

    @Test func dropsShortFillerStretchedOverSilence() {
        #expect(MeetingTranscript.isHallucination(u(.mic, 0, 22.5, "E aí")))
        #expect(MeetingTranscript.isHallucination(u(.mic, 10, 30, "Thank you.")))
    }

    @Test func dropsEmptyAndSpecialTokenOnly() {
        #expect(MeetingTranscript.isHallucination(u(.mic, 0, 1, "<|en|><|0.00|>")))
        #expect(MeetingTranscript.isHallucination(u(.mic, 0, 1, "  ")))
    }

    @Test func keepsRealSpeech() {
        #expect(!MeetingTranscript.isHallucination(u(.mic, 0, 3, "I think you can close it for now")))
        #expect(!MeetingTranscript.isHallucination(u(.mic, 0, 1, "Okay.")))
    }

    @Test func cleanStripsSpecialTokens() {
        #expect(MeetingTranscript.clean("<|startoftranscript|><|pt|> Olá, pessoal <|endoftext|>") == "Olá, pessoal")
    }
}

@Suite("MeetingTranscript.echo")
struct MeetingEchoTests {
    let system = [u(.system, 10, 15, "So the deploy is scheduled for Friday, right after the review.")]

    @Test func identicalEchoIsDropped() {
        let mic = [u(.mic, 10.3, 15.2, "So the deploy is scheduled for Friday, right after the review.")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system).isEmpty)
    }

    @Test func echoWithSmallVariationsIsDropped() {
        let mic = [u(.mic, 11, 14, "so deploy is scheduled Friday right after review")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system).isEmpty)
    }

    @Test func genuineUserSpeechIsKept() {
        let mic = [u(.mic, 16, 18, "Pode ser, eu preparo o changelog hoje.")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system) == mic)
    }

    @Test func talkingOverOthersIsKept() {
        // Overlaps in time, but the mic picked up the user's own (different) words.
        let mic = [u(.mic, 12, 15, "wait, I still need to finish the migration first")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system) == mic)
    }

    @Test func sameWordsOutsideTheWindowAreKept() {
        let mic = [u(.mic, 60, 64, "So the deploy is scheduled for Friday, right after the review.")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system) == mic)
    }

    @Test func echoSplitAcrossTwoSystemSegmentsIsDropped() {
        // Real case (#74): tracks split the sentence at different points.
        let system = [u(.system, 41, 52.4, "pagasse lá 500 reais por dia cinco dias na"),
                      u(.system, 52.4, 60, "semana cara não faz sentido sabe")]
        let mic = [u(.mic, 52.3, 53.3, "na semana.")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system).isEmpty)
    }

    @Test func echoWithinTwoSecondsOfTheEdgeIsDropped() {
        let mic = [u(.mic, 16.5, 19, "right after the review")]
        #expect(MeetingTranscript.removeEcho(mic: mic, system: system).isEmpty)
    }
}

@Suite("MeetingTranscript.merge")
struct MeetingMergeTests {
    @Test func rendersSpeakersAndCoalescesConsecutiveTurns() {
        let out = MeetingTranscript.render(MeetingTranscript.process([
            u(.system, 0, 3, "Bom dia, pessoal."),
            u(.system, 3, 6, "Vamos começar pela sprint."),
            u(.mic, 65, 67, "Bom dia, eu começo."),
            u(.mic, 67, 89, "E aí"),                       // hallucination → dropped
            u(.system, 125, 127, "<|en|>Perfeito, obrigado."),
        ]))
        #expect(out == """
        [00:00] Outros: Bom dia, pessoal. Vamos começar pela sprint.
        [01:05] Você: Bom dia, eu começo.
        [02:05] Outros: Perfeito, obrigado.
        """)
    }

    @Test func echoDoesNotBreakTheOthersTurn() {
        let out = MeetingTranscript.render(MeetingTranscript.process([
            u(.system, 0, 4, "Can everyone see my screen now?"),
            u(.mic, 0.4, 4.2, "can everyone see my screen now"),
            u(.system, 4, 8, "Great, let's go through the numbers."),
        ]))
        #expect(out == "[00:00] Outros: Can everyone see my screen now? Great, let's go through the numbers.")
    }

    @Test func diarizedSystemVoicesGetNumberedSpeakers() {
        let turns = [MeetingSpeakerTurn(start: 0, end: 5, speaker: "S7"),
                     MeetingSpeakerTurn(start: 5, end: 12, speaker: "S2"),
                     MeetingSpeakerTurn(start: 12, end: 20, speaker: "S7")]
        let utterances = MeetingTranscript.assignSpeakers([
            u(.system, 0, 4, "Bom dia."),
            u(.system, 4.5, 11, "Eu trago os números."),   // mostly inside S2
            u(.mic, 11, 12, "Pode ir."),                  // mic is never diarized
            u(.system, 13, 16, "Fechado então."),
            u(.system, 21.5, 23, "Até mais."),           // no overlap, 1.5 s after S7
            u(.system, 40, 41, "Alô?"),                  // nothing within 3 s
        ], turns: turns)
        #expect(utterances.map(\.speaker) == [1, 2, nil, 1, 1, nil])
        #expect(MeetingTranscript.render(utterances) == """
        [00:00] Outro 1: Bom dia.
        [00:04] Outro 2: Eu trago os números.
        [00:11] Você: Pode ir.
        [00:13] Outro 1: Fechado então. Até mais.
        [00:40] Outros: Alô?
        """)
    }

    @Test func droppedHallucinationDoesNotClaimASpeaker() {
        let turns = [MeetingSpeakerTurn(start: 0, end: 10, speaker: "S1"),
                     MeetingSpeakerTurn(start: 10, end: 20, speaker: "S2")]
        let kept = MeetingTranscript.process([
            u(.system, 0, 9, "E aí"),          // S1, hallucination → dropped
            u(.system, 11, 14, "Vamos lá."),   // S2
        ])
        #expect(MeetingTranscript.render(MeetingTranscript.assignSpeakers(kept, turns: turns)) == "[00:11] Outros: Vamos lá.")
    }

    @Test func singleRemoteSpeakerStaysOutros() {
        let utterances = MeetingTranscript.assignSpeakers(
            [u(.system, 0, 4, "Oi."), u(.system, 5, 8, "Tudo bem?")],
            turns: [MeetingSpeakerTurn(start: 0, end: 10, speaker: "S1")]
        )
        #expect(utterances.allSatisfy { $0.speaker == nil })
        #expect(MeetingTranscript.render(utterances) == "[00:00] Outros: Oi. Tudo bem?")
    }

    @Test func minutesGoPastAnHour() {
        #expect(MeetingTranscript.render([u(.mic, 4512, 4514, "Tchau.")]) == "[75:12] Você: Tchau.")
    }
}

@Suite("ClaudeCLISummarizer.locate")
struct ClaudeCLILocateTests {
    @Test func configuredPathWinsAndExpandsTilde() {
        let url = ClaudeCLISummarizer.locate(configured: "~/bin/claude", home: "/Users/x", isExecutable: { _ in false })
        #expect(url?.path == "/Users/x/bin/claude")
    }

    @Test func firstExecutableCandidate() {
        let url = ClaudeCLISummarizer.locate(configured: nil, home: "/Users/x", isExecutable: { $0 == "/opt/homebrew/bin/claude" || $0 == "/usr/local/bin/claude" })
        #expect(url?.path == "/opt/homebrew/bin/claude")
        let local = ClaudeCLISummarizer.locate(configured: " ", home: "/Users/x", isExecutable: { _ in true })
        #expect(local?.path == "/Users/x/.local/bin/claude")
    }

    @Test func nilWhenNothingInstalled() {
        #expect(ClaudeCLISummarizer.locate(configured: nil, home: "/Users/x", isExecutable: { _ in false }) == nil)
    }
}
