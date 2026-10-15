import Foundation

/// A lightweight, value-typed cancellation handle.
///
/// Returned by `ConfigStore.subscribe(_:)`. Calling `cancel()` is idempotent;
/// subsequent calls are no-ops.
public struct Cancellable: Sendable {
    private let onCancel: @Sendable () -> Void
    private let state: State

    private final class State: @unchecked Sendable {
        var cancelled: Bool = false
        let lock = NSLock()
    }

    public init(_ onCancel: @escaping @Sendable () -> Void) {
        self.onCancel = onCancel
        self.state = State()
    }

    public func cancel() {
        state.lock.lock()
        let alreadyCancelled = state.cancelled
        state.cancelled = true
        state.lock.unlock()
        if !alreadyCancelled {
            onCancel()
        }
    }
}
