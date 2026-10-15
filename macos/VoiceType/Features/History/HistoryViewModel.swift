import Foundation
import Observation
import AppKit
import Core

/// Abstraction so HistoryViewModel can be tested without the real Paster /
/// frontmost-window snapshot. Live implementation captures FrontmostApp at
/// call time and forwards to Core's Paster.
protocol PasterProtocol: Sendable {
    func paste(_ text: String) async
}

struct LivePaster: PasterProtocol {
    let paster: Paster

    func paste(_ text: String) async {
        let target = await MainActor.run { FocusedApp.snapshot() }
        guard let target else { return }
        try? await paster.paste(text: text, target: target)
    }
}

@Observable
@MainActor
final class HistoryViewModel {
    var query: String = ""

    @ObservationIgnored private let snapshot: HistoryStoreSnapshot
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private let paster: PasterProtocol

    init(snapshot: HistoryStoreSnapshot, store: HistoryStore, paster: PasterProtocol) {
        self.snapshot = snapshot
        self.store = store
        self.paster = paster
    }

    var entries: [HistoryEntry] { snapshot.entries }

    var filteredEntries: [HistoryEntry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return entries }
        let needle = query.lowercased()
        return entries.filter { entry in
            entry.text.lowercased().contains(needle)
                || AppIconResolver.displayName(forBundleID: entry.sourceApp).lowercased().contains(needle)
        }
    }

    func delete(id: UUID) async {
        await store.delete(id: id)
    }

    func clearAll() async {
        await store.clear()
    }

    func copy(_ entry: HistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
    }

    func repaste(_ entry: HistoryEntry) async {
        await paster.paste(entry.text)
    }
}
