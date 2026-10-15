import Core
import Foundation

// Bridges the `HistoryStore` actor to the Sendable `Core.HistoryRecorder`
// use-case protocol. The retention cap is captured up-front so the use case
// stays oblivious to storage details.
struct HistoryRecorderAdapter: HistoryRecorder {
    let store: HistoryStore
    let cap: Int

    func record(_ entry: HistoryEntry) async {
        await store.add(entry, cap: cap)
    }
}
