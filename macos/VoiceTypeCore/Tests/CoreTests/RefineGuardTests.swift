import Testing
import Foundation
@testable import Core

@Suite("RefineGuard")
struct RefineGuardTests {
    // MARK: length sanity

    @Test func acceptsCleanRefinement() {
        // Real refinement: same words, punctuation/casing added.
        #expect(RefineGuard.isPlausibleRefinement(
            input: "ahn então eu acho que a gente devia começar agora né",
            output: "Eu acho que a gente devia começar agora."))
    }

    @Test func acceptsShortInputGainingPunctuation() {
        #expect(RefineGuard.isPlausibleRefinement(input: "oi tudo bem", output: "Oi, tudo bem?"))
    }

    @Test func rejectsBallooning() {
        #expect(!RefineGuard.isPlausibleRefinement(
            input: "o que você faz",
            output: String(repeating: "blá ", count: 60)))
    }

    @Test func rejectsEmptyOutput() {
        #expect(!RefineGuard.isPlausibleRefinement(input: "alguma fala qualquer", output: "   "))
    }

    // MARK: word-overlap sanity (obedience + translation)

    @Test func rejectsAnsweredMathQuestion() {
        // "some dois mais dois" → model answered "2 + 2 = 4": no shared words.
        #expect(!RefineGuard.isPlausibleRefinement(input: "some dois mais dois", output: "2 + 2 = 4"))
    }

    @Test func rejectsAnsweredQuestion() {
        #expect(!RefineGuard.isPlausibleRefinement(
            input: "qual o resultado da soma de dois mais dois",
            output: "O resultado é quatro."))
    }

    @Test func rejectsPortugueseTranslatedToEnglish() {
        // Refine must keep the language; a translation shares no words.
        #expect(!RefineGuard.isPlausibleRefinement(
            input: "bom dia pessoal tudo certo por aí",
            output: "Good morning everyone, all good there?"))
    }

    @Test func acceptsFillerRemovalKeepingContentWords() {
        // Fillers dropped, content words preserved → high overlap.
        #expect(RefineGuard.isPlausibleRefinement(
            input: "tipo assim a reunião é amanhã sabe",
            output: "A reunião é amanhã."))
    }

    @Test func diacriticInsensitiveOverlap() {
        // "começar" vs "Comecar" must count as the same word.
        #expect(RefineGuard.isPlausibleRefinement(input: "vamos começar agora", output: "Vamos comecar agora."))
    }
}
