import Testing
import Foundation
@testable import Core

@Suite("SuggestionStore")
struct SuggestionStoreTests {
    private func makeStore() -> (SuggestionStore, URL) {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceTypeTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("suggestions.json")
        return (SuggestionStore(fileURL: file), file)
    }

    private let kodex = EditSubstitution(original: "Kodex", corrected: "Codex")

    @Test("começa vazio")
    func emptyOnFirstUse() async {
        let (store, _) = makeStore()
        #expect(await store.pending().isEmpty)
    }

    @Test("add persiste como pendente e sobrevive a reload")
    func addPersists() async {
        let (store, file) = makeStore()
        await store.add([kodex])
        let reloaded = SuggestionStore(fileURL: file)
        let pending = await reloaded.pending()
        #expect(pending.map(\.corrected) == ["Codex"])
        #expect(pending.first?.status == .pending)
    }

    @Test("par repetido (case-insensitive) não duplica")
    func dedupes() async {
        let (store, _) = makeStore()
        await store.add([kodex])
        await store.add([EditSubstitution(original: "kodex", corrected: "codex")])
        #expect(await store.pending().count == 1)
    }

    @Test("rejeitada some da lista e não volta a ser sugerida")
    func rejectIsSticky() async {
        let (store, file) = makeStore()
        await store.add([kodex])
        let id = await store.pending()[0].id
        await store.reject(id: id)
        #expect(await store.pending().isEmpty)
        await store.add([kodex])
        #expect(await store.pending().isEmpty)
        #expect(await SuggestionStore(fileURL: file).pending().isEmpty)
    }

    @Test("apagar remove de vez (pode voltar a ser sugerida)")
    func removeForgets() async {
        let (store, _) = makeStore()
        await store.add([kodex])
        await store.remove(id: await store.pending()[0].id)
        #expect(await store.pending().isEmpty)
        await store.add([kodex])
        #expect(await store.pending().count == 1)
    }

    @Test("cap de 200 descarta as mais antigas")
    func capEnforced() async {
        let (store, _) = makeStore()
        for i in 0..<205 {
            await store.add([EditSubstitution(original: "a\(i)", corrected: "b\(i)")])
        }
        let pending = await store.pending()
        #expect(pending.count == SuggestionStore.cap)
        #expect(pending.first?.corrected == "b204")
    }

    @Test("aprovar acrescenta termo ao dicionário sem duplicar")
    func vocabularyAppend() {
        #expect(LearnedSuggestion.vocabulary("", adding: "Codex") == "Codex")
        #expect(LearnedSuggestion.vocabulary("Macsilva, FluidAudio\n", adding: "Codex") == "Macsilva, FluidAudio\nCodex")
        #expect(LearnedSuggestion.vocabulary("Macsilva, codex", adding: "Codex") == "Macsilva, codex")
    }
}
