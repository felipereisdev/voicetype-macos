import Testing
import Foundation
@testable import Core

@Suite("StopRecordingUseCase")
struct StopRecordingUseCaseTests {
    @Test func stops_recorder_and_transitionsToProcessing() async throws {
        let payload = Data(repeating: 0x01, count: 32_000)
        let recorder = SpyAudioCapture()
        recorder.stopReturns = payload
        let state = SpyStateMachine(initial: .recording)
        let useCase = StopRecordingUseCase(recorder: recorder, state: state)

        let data = try await useCase.execute()
        #expect(data == payload)
        #expect(state.sentEvents == [.stop])
    }

    @Test func returnsEarly_if_notRecording() async {
        let recorder = SpyAudioCapture()
        let state = SpyStateMachine(initial: .idle)
        let useCase = StopRecordingUseCase(recorder: recorder, state: state)

        do {
            _ = try await useCase.execute()
            Issue.record("should throw")
        } catch let error as StopRecordingUseCase.Error {
            #expect(error == .notRecording)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        #expect(state.sentEvents.isEmpty)
    }

    @Test func belowMinBytes_returnsTooShort() async {
        let recorder = SpyAudioCapture()
        recorder.stopReturns = Data(repeating: 0x01, count: 1024)
        let state = SpyStateMachine(initial: .recording)
        let useCase = StopRecordingUseCase(
            recorder: recorder, state: state, minBytes: 16_044
        )

        do {
            _ = try await useCase.execute()
            Issue.record("should throw")
        } catch let error as StopRecordingUseCase.Error {
            #expect(error == .tooShort)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
        // Stop was sent before validating bytes — orchestrator decides reset.
        #expect(state.sentEvents == [.stop])
    }
}
