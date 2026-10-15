import ApplicationServices
import Core
import Foundation
import os

// Learns dictionary terms from the user's corrections (#50). Only runs when
// `learnFromEditsEnabled`; the orchestrator never calls in otherwise.
//
// Right after a paste it pins the focused element + the exact pasted range
// (verified with AXStringForRange — the caret sits at the end of the paste),
// then re-reads ONLY that range once, `delay` later, and hands the word diff to
// `EditAlignment`. Never reads AXValue: text outside the pasted range is never
// read or stored. Secure field, destroyed element, focus moved, range no longer
// fits → discard silently. A new paste cancels the pending observation.
//
// MainActor-isolated end to end, so the AXUIElement never crosses actors and
// needs no Sendable wrapper. AX helpers are CursorContextReader's (#41).
@MainActor
final class EditObserver {
    private let store: SuggestionStore
    private let delay: Duration
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "VoiceType", category: "EditObserver")

    init(store: SuggestionStore, delay: Duration = .seconds(20)) {
        self.store = store
        self.delay = delay
    }

    func observe(pasted: String, vocabulary: String) {
        task?.cancel()
        task = Task { [weak self, delay] in
            // Let the target app commit the paste and move the caret first.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let pin = Self.pin(pasted: pasted) else { return }
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let edited = Self.readBack(pin) else { return }

            let known = Set(Transcriber.terms(from: vocabulary).map { $0.lowercased() })
            let subs = EditAlignment.substitutions(pasted: pasted, edited: edited)
                .filter { !known.contains($0.corrected.lowercased()) }
            self?.logger.info("learn: \(subs.count, privacy: .public) suggestion(s)")
            guard !subs.isEmpty, let store = self?.store else { return }
            await store.add(subs)
        }
    }

    private struct Pin {
        let element: AXUIElement
        let range: NSRange
        let fieldLength: Int
    }

    private static func pin(pasted: String) -> Pin? {
        guard let element = CursorContextReader.focusedTextElement(),
              let caret = CursorContextReader.selectedRange(of: element), caret.length == 0,
              let fieldLength: Int = CursorContextReader.attribute(kAXNumberOfCharactersAttribute, of: element)
        else { return nil }
        let length = (pasted as NSString).length
        let range = NSRange(location: caret.location - length, length: length)
        guard length > 0, range.location >= 0, CursorContextReader.string(in: range, of: element) == pasted else { return nil }
        return Pin(element: element, range: range, fieldLength: fieldLength)
    }

    /// Same element still focused → read the pasted range, grown/shrunk by the
    /// field's length delta (edits are assumed to land inside the paste; if they
    /// didn't, the misaligned text fails EditAlignment's rewrite guard).
    private static func readBack(_ pin: Pin) -> String? {
        guard let element = CursorContextReader.focusedTextElement(), CFEqual(element, pin.element),
              let fieldLength: Int = CursorContextReader.attribute(kAXNumberOfCharactersAttribute, of: element)
        else { return nil }
        let range = NSRange(location: pin.range.location, length: pin.range.length + fieldLength - pin.fieldLength)
        guard range.length > 0, NSMaxRange(range) <= fieldLength else { return nil }
        return CursorContextReader.string(in: range, of: element)
    }
}
