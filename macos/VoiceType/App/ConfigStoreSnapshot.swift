import Core
import Foundation
import Observation

/// MainActor @Observable view over a `ConfigStore` actor. Initial value loads
/// from the store on init; later updates arrive via the store's subscribe
/// callback. Writes via `update(_:)` route through the actor so persistence
/// stays atomic.
@MainActor
@Observable
final class ConfigStoreSnapshot {
    private(set) var config: AppConfig = AppConfig()
    private(set) var lastError: Error?

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private var subscription: Cancellable?

    init(store: ConfigStore) {
        self.store = store
        // Subscribe synchronously (nonisolated) so we never miss a save that
        // races the initial load Task below.
        self.subscription = store.subscribe { [weak self] next in
            Task { @MainActor in
                self?.config = next
            }
        }
        Task { await self.initialLoad() }
    }

    func update(_ mutate: (inout AppConfig) -> Void) async {
        var next = config
        mutate(&next)
        do {
            try await store.save(next)
            self.config = next
            self.lastError = nil
        } catch {
            self.lastError = error
        }
    }

    private func initialLoad() async {
        do {
            let initial = try await store.load()
            self.config = initial
        } catch {
            self.lastError = error
        }
    }

    deinit {
        subscription?.cancel()
    }
}
