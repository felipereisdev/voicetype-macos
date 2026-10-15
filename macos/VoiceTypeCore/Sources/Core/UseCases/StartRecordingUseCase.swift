import Foundation

/// Guards idle state, starts the audio capture, and emits
/// `AppStateMachine.start` on success. Errors short-circuit without state
/// mutation so the orchestrator can decide how to surface them in the UI.
public struct StartRecordingUseCase: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case notIdle
        case permissionDenied
    }

    private let recorder: AudioCapture
    private let state: StateMachineDriver

    public init(recorder: AudioCapture, state: StateMachineDriver) {
        self.recorder = recorder
        self.state = state
    }

    public func execute(deviceUID: String?) async throws {
        let current = await state.currentState()
        guard current == .idle else { throw Error.notIdle }

        do {
            try await recorder.start(deviceUID: deviceUID)
        } catch let mapped as Error {
            // Adapter already translated to a use-case-level error.
            throw mapped
        }
        await state.send(.start)
    }
}
