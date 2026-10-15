import Foundation

/// Three-state machine that drives recording lifecycle.
///
/// Mirrors `src/main/state-machine.ts`. States are `idle | recording | processing`.
/// Events are `START | STOP | TIMEOUT | ERROR | RESET`. Invalid transitions log a
/// warning and return — they never throw. `ERROR` from `idle` is a guarded no-op
/// (FU-003 parity) so `StateChange` is never emitted for a phantom self-transition.
///
/// The actor owns a 5-minute auto-timeout for the `recording` state. On fire it
/// calls the `onTimeout` handler when one is set (the app ends the take through
/// its normal release path, which sends STOP); otherwise it sends `TIMEOUT`.
/// Legitimate transitions out of `recording` cancel the timer.
public actor AppStateMachine {

    public enum State: String, Sendable, Equatable {
        case idle
        case recording
        case processing
    }

    public enum Event: Sendable, Equatable {
        case start
        case stop
        case timeout
        case error(reason: String)
        case reset
    }

    public struct StateChange: Sendable, Equatable {
        public let from: State
        public let to: State
        public let event: Event
    }

    // MARK: - Continuation registry (lock-protected, nonisolated-safe)

    private final class ContinuationRegistry: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [UUID: AsyncStream<StateChange>.Continuation] = [:]

        func register(_ continuation: AsyncStream<StateChange>.Continuation) -> UUID {
            let id = UUID()
            lock.lock()
            entries[id] = continuation
            lock.unlock()
            return id
        }

        func remove(_ id: UUID) {
            lock.lock()
            entries.removeValue(forKey: id)
            lock.unlock()
        }

        func snapshot() -> [AsyncStream<StateChange>.Continuation] {
            lock.lock()
            defer { lock.unlock() }
            return Array(entries.values)
        }

        func finishAll() {
            lock.lock()
            let all = Array(entries.values)
            entries.removeAll()
            lock.unlock()
            for c in all { c.finish() }
        }
    }

    // MARK: - Public state

    public private(set) var state: State = .idle

    /// Broadcast stream of state changes. Each call to `events` returns an
    /// independent `AsyncStream` so multiple subscribers can observe the same
    /// transitions. Continuation registration is synchronous and lock-protected
    /// so a `send` immediately following a property access will not race.
    public nonisolated var events: AsyncStream<StateChange> {
        let registry = self.registry
        return AsyncStream { continuation in
            let id = registry.register(continuation)
            continuation.onTermination = { _ in
                registry.remove(id)
            }
        }
    }

    // MARK: - Private

    private nonisolated let registry = ContinuationRegistry()
    private var timeoutTask: Task<Void, Never>?
    private let recordingTimeout: Duration
    private var timeoutHandler: (@Sendable () -> Void)?

    public init(recordingTimeout: Duration = .seconds(5 * 60)) {
        self.recordingTimeout = recordingTimeout
    }

    deinit {
        timeoutTask?.cancel()
        registry.finishAll()
    }

    // MARK: - Event entry point

    public func send(_ event: Event) {
        guard let next = computeNext(state: state, event: event) else {
            CoreLog.stateMachine.warning("ignored event \(String(describing: event), privacy: .public) in state \(self.state.rawValue, privacy: .public)")
            return
        }

        let from = state
        state = next

        // Manage the 5-min recording timer.
        cancelTimeout()
        if next == .recording {
            armTimeout()
        }

        let change = StateChange(from: from, to: next, event: event)
        // Snapshot before iterating: a subscriber's onTermination must not
        // mutate the live dictionary we're walking (FU-004 mitigation).
        let snapshot = registry.snapshot()
        for c in snapshot {
            c.yield(change)
        }
    }

    /// Replaces the TIMEOUT transition: the handler must end the take itself
    /// (e.g. synthesize the shortcut release). Without it the machine would
    /// jump to `processing` behind the recorder's back and drop the audio.
    public func onTimeout(_ handler: @escaping @Sendable () -> Void) {
        timeoutHandler = handler
    }

    /// Tear down the actor explicitly (used by tests; otherwise rely on `deinit`).
    public func shutdown() {
        cancelTimeout()
        registry.finishAll()
    }

    // MARK: - Transition table

    private func computeNext(state: State, event: Event) -> State? {
        switch (state, event) {
        case (.idle, .start):
            return .recording
        case (.recording, .stop):
            return .processing
        case (.recording, .timeout):
            return .processing
        case (.processing, .reset):
            return .idle

        // ERROR routes everything except idle back to idle (FU-003 guard).
        case (.recording, .error), (.processing, .error):
            return .idle
        case (.idle, .error):
            return nil

        default:
            return nil
        }
    }

    // MARK: - Timer

    private func armTimeout() {
        let duration = recordingTimeout
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            await self?.timerFired()
        }
    }

    private func timerFired() {
        guard state == .recording else { return }
        if let timeoutHandler {
            timeoutHandler()
        } else {
            send(.timeout)
        }
    }

    private func cancelTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }
}
