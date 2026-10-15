import Foundation

/// Captures the WAV buffer, emits `AppStateMachine.stop`, and surfaces
/// `tooShort` / `notRecording` / `capture` errors so the orchestrator can
/// silently reset (for `tooShort`) or notify the user.
public struct StopRecordingUseCase: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case notRecording
        case tooShort
        case capture(String)
    }

    /// ≈ 0.5 s × 16 kHz × 2 bytes (16-bit mono PCM) + 44-byte WAV header.
    public static let defaultMinBytes = 16_044

    private let recorder: AudioCapture
    private let state: StateMachineDriver
    private let minBytes: Int

    public init(
        recorder: AudioCapture,
        state: StateMachineDriver,
        minBytes: Int = StopRecordingUseCase.defaultMinBytes
    ) {
        self.recorder = recorder
        self.state = state
        self.minBytes = minBytes
    }

    public func execute() async throws -> Data {
        let current = await state.currentState()
        guard current == .recording else { throw Error.notRecording }

        let data: Data
        do {
            data = try await recorder.stop()
        } catch {
            throw Error.capture(String(describing: error))
        }
        await state.send(.stop)
        guard data.count >= minBytes else { throw Error.tooShort }
        return data
    }
}
