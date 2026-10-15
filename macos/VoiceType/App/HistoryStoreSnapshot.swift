import Core
import Foundation
import Observation

/// MainActor @Observable view over a `HistoryStore` actor. Subscribes on init;
/// the store fires the current snapshot immediately upon subscribe, so we get
/// the initial value without a separate `list()` call. Views consume entries
/// via `@Environment(AppDependencies.self)` → `deps.historySnapshot.entries`.
@MainActor
@Observable
final class HistoryStoreSnapshot {
    private(set) var entries: [HistoryEntry] = []

    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var subscription: HistoryCancellable?
    @ObservationIgnored private var setupTask: Task<Void, Never>?

    init(store: HistoryStore) {
        self.store = store
        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cancellable = await self.store.subscribe { [weak self] snap in
                Task { @MainActor in
                    self?.entries = snap
                }
            }
            self.subscription = cancellable
        }
    }

    deinit {
        setupTask?.cancel()
        subscription?.cancel()
    }
}
