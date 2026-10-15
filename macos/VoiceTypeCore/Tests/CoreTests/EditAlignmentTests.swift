import Testing
import Foundation
@testable import Core

@Suite("EditAlignment")
struct EditAlignmentTests {
    private func subs(_ pasted: String, _ edited: String) -> [EditSubstitution] {
        EditAlignment.substitutions(pasted: pasted, edited: edited)
    }

    private func sub(_ o: String, _ c: String) -> EditSubstitution {
        EditSubstitution(original: o, corrected: c)
    }

    // MARK: - True positives

    @Test("troca de uma palavra parecida vira sugestão")
    func singleSubstitution() {
        #expect(subs("Abri o Kodex agora", "Abri o Codex agora") == [sub("Kodex", "Codex")])
    }

    @Test("pontuação colada à palavra é removida do termo")
    func trimsAttachedPunctuation() {
        #expect(subs("Falei com o Kodex, depois saí.", "Falei com o Codex, depois saí.") == [sub("Kodex", "Codex")])
    }

    @Test("duas palavras viram uma (junção)")
    func mergeTwoIntoOne() {
        #expect(subs("O mac silva mandou", "O Macsilva mandou") == [sub("mac silva", "Macsilva")])
    }

    @Test("uma palavra vira duas (separação)")
    func splitOneIntoTwo() {
        #expect(subs("Usa o fluidaudio aqui", "Usa o Fluid Audio aqui") == [sub("fluidaudio", "Fluid Audio")])
    }

    @Test("correção de acento conta")
    func diacriticFix() {
        #expect(subs("Fala com o Jose amanhã", "Fala com o José amanhã") == [sub("Jose", "José")])
    }

    @Test("várias correções separadas no mesmo ditado")
    func multipleSubstitutions() {
        let got = subs(
            "Hoje o Kodex e o wisper rodaram bem no meu mac de casa",
            "Hoje o Codex e o Whisper rodaram bem no meu mac de casa"
        )
        #expect(got == [sub("Kodex", "Codex"), sub("wisper", "Whisper")])
    }

    @Test("correção na primeira e na última palavra")
    func editsAtEdges() {
        #expect(subs("Kodex está pronto pro deploi", "Codex está pronto pro deploy")
            == [sub("Kodex", "Codex"), sub("deploi", "deploy")])
    }

    @Test("exatamente 4 correções passam")
    func fourIsAllowed() {
        let got = subs(
            "aa1 um bb1 dois cc1 tres dd1 quatro cinco seis sete oito",
            "aa2 um bb2 dois cc2 tres dd2 quatro cinco seis sete oito"
        )
        #expect(got.count == 4)
    }

    // MARK: - False positives (style edits ≠ ASR errors)

    @Test("texto inalterado não gera nada")
    func unchanged() {
        #expect(subs("Tudo certo por aqui", "Tudo certo por aqui").isEmpty)
    }

    @Test("só maiúscula/minúscula não conta")
    func caseOnly() {
        #expect(subs("github é ótimo", "GitHub é ótimo").isEmpty)
        #expect(subs("oi tudo bem", "Oi tudo bem").isEmpty)
    }

    @Test("só pontuação não conta")
    func punctuationOnly() {
        #expect(subs("oi tudo bem", "Oi, tudo bem?").isEmpty)
        #expect(subs("manda o e-mail hoje", "manda o email hoje").isEmpty)
    }

    @Test("espaços/quebras de linha diferentes não contam")
    func whitespaceOnly() {
        #expect(subs("linha um linha dois", "linha um\n\nlinha  dois").isEmpty)
    }

    @Test("sinônimo / troca de estilo não conta")
    func synonymRewrite() {
        #expect(subs("O resultado ficou bom demais", "O resultado ficou ótimo demais").isEmpty)
        #expect(subs("Eu vai lá amanhã cedo", "Eu vou lá amanhã cedo").isEmpty)
    }

    @Test("inserção pura não conta")
    func insertionOnly() {
        #expect(subs("Vamos amanhã cedo", "Vamos sim amanhã bem cedo").isEmpty)
    }

    @Test("remoção pura não conta")
    func deletionOnly() {
        #expect(subs("Então tipo vamos amanhã", "Vamos amanhã").isEmpty)
    }

    @Test("número por extenso → dígito não conta")
    func numberFormatting() {
        #expect(subs("chegam dez caixas", "chegam 10 caixas").isEmpty)
    }

    @Test("reescrita pesada não gera nada")
    func heavyRewrite() {
        #expect(subs("Preciso enviar o relatório amanhã", "Mandei tudo ontem à noite já").isEmpty)
    }

    @Test("mais de 4 correções = reescrita, descarta tudo")
    func moreThanFourDropsAll() {
        let got = subs(
            "aa1 um bb1 dois cc1 tres dd1 quatro ee1 cinco seis sete oito nove dez",
            "aa2 um bb2 dois cc2 tres dd2 quatro ee2 cinco seis sete oito nove dez"
        )
        #expect(got.isEmpty)
    }

    @Test("bloco grande substituído (> 3 palavras) não conta")
    func largeBlockIgnored() {
        #expect(subs(
            "Olha aaaa bbbb cccc dddd e mais coisa aqui pra ficar comprido",
            "Olha aaab bbbc cccd dddf e mais coisa aqui pra ficar comprido"
        ).isEmpty)
    }

    @Test("leitura vazia ou colado vazio não gera nada")
    func emptyInputs() {
        #expect(subs("", "algo").isEmpty)
        #expect(subs("algo", "").isEmpty)
        #expect(subs("algo", "   ").isEmpty)
    }

    @Test("leitura desalinhada (texto de fora do range) não gera nada")
    func misalignedReadBack() {
        #expect(subs("Kodex agora", "outra frase totalmente diferente que entrou").isEmpty)
    }

    // MARK: - Helpers

    @Test("similaridade de Levenshtein normalizada")
    func similarity() {
        #expect(EditAlignment.similarity("codex", "codex") == 1)
        #expect(EditAlignment.similarity("kodex", "codex") == 0.8)
        #expect(EditAlignment.similarity("bom", "ótimo") < 0.5)
        #expect(EditAlignment.similarity("", "") == 1)
        #expect(EditAlignment.similarity("a", "") == 0)
    }
}
