import Foundation

// Runs `operation` with a wall-clock limit. On timeout, cancels the operation
// task and throws PipelineError.timeout. Ported from Sotto's withAITimeout,
// mapped to the Core error domain (no FoundationModels dependency).
//
// Cancellation contract:
// - Outer task cancelled → work is cancelled immediately via withTaskCancellationHandler;
//   throws PipelineError.cancelled so callers can distinguish user-abort from timeout.
// - Timeout fires first → work is cancelled by the timeout task; throws PipelineError.timeout.
public func withTimeout<T: Sendable>(
    seconds: Double,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    let work = Task { try await operation() }
    let timeout = Task {
        try await Task.sleep(for: .seconds(seconds))
        work.cancel()
    }
    return try await withTaskCancellationHandler {
        do {
            let result = try await work.value
            timeout.cancel()
            return result
        } catch is CancellationError {
            timeout.cancel()
            work.cancel()
            // If the outer task is cancelled, propagate as .cancelled.
            // If only work was cancelled by the timeout task, surface as .timeout.
            if Task.isCancelled { throw PipelineError.cancelled }
            throw PipelineError.timeout
        } catch {
            timeout.cancel()
            throw error
        }
    } onCancel: {
        // Outer task cancelled: propagate to work immediately so it can bail out
        // instead of running to completion. The CancellationError thrown by work
        // is then re-mapped to PipelineError.cancelled in the catch above.
        work.cancel()
        timeout.cancel()
    }
}
