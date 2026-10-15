import Foundation

// A refine pass must CLEAN a transcription (punctuation, casing, fillers), never
// elaborate, answer, or translate it. On-device models (FoundationModels) ignore
// this on adversarial inputs: a question gets answered ("some 2+2" → "2+2=4"), a
// phrase gets translated (PT spoken → English pasted), or a short dictation gets
// expanded into paragraphs. The Sotto reference has no such guard — it trusts the
// model and only falls back on throw/timeout. We add two cheap, pure checks so the
// caller can reject a bad refinement and fall back to Groq (which holds the
// instruction far better — see G-018).
public enum RefineGuard {
    // True when `output` is a plausible refinement of `input`:
    //  1. non-empty,
    //  2. not ballooned past `maxGrowth`× the input length (floor for tiny inputs),
    //  3. preserves enough of the input's words (a refinement keeps the words and
    //     only fixes punctuation/casing/fillers; an *answer* or a *translation*
    //     shares almost no words with the input). Overlap is only judged when the
    //     input has enough words to be meaningful (`minWordsForOverlap`).
    public static func isPlausibleRefinement(
        input: String,
        output: String,
        maxGrowth: Double = 3.0,
        floor: Int = 40,
        minWordOverlap: Double = 0.5,
        minWordsForOverlap: Int = 3
    ) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }

        // (2) length sanity
        let cap = max(floor, Int(Double(input.count) * maxGrowth))
        if trimmed.count > cap { return false }

        // (3) word-overlap sanity
        let inputWords = words(input)
        if inputWords.count >= minWordsForOverlap {
            let outputWords = Set(words(output))
            let preserved = inputWords.filter { outputWords.contains($0) }.count
            let overlap = Double(preserved) / Double(inputWords.count)
            if overlap < minWordOverlap { return false }
        }
        return true
    }

    // True when `output` carries a run of `minRun` consecutive words that exists
    // in the cursor context but NOT in the transcription — the model copied the
    // surrounding text (or obeyed it) into what gets pasted. The overlap check
    // above stays transcription × output only; this is the context-side check.
    public static func leaksContext(
        input: String,
        output: String,
        context: CursorContext?,
        minRun: Int = 5
    ) -> Bool {
        guard let context, !context.isEmpty else { return false }
        let spoken = ngrams(words(input), minRun)
        let leakable = [context.before, context.selected, context.after]
            .reduce(into: Set<[String]>()) { $0.formUnion(ngrams(words($1), minRun)) }
            .subtracting(spoken)
        guard !leakable.isEmpty else { return false }
        return !ngrams(words(output), minRun).isDisjoint(with: leakable)
    }

    private static func ngrams(_ tokens: [String], _ n: Int) -> Set<[String]> {
        guard n > 0, tokens.count >= n else { return [] }
        return Set((0...(tokens.count - n)).map { Array(tokens[$0..<($0 + n)]) })
    }

    // Normalized word tokens: lowercased, diacritic-folded, split on non-alphanumerics.
    // Folding makes "começar" == "comecar"; digit runs ("2") stay as tokens so an
    // answer like "4" shares nothing with a spoken "dois mais dois".
    static func words(_ text: String) -> [String] {
        text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
