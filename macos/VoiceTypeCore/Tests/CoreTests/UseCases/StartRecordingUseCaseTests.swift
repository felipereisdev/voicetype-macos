import Testing
import Foundation
@testable import Core

@Suite("StartRecordingUseCase")
struct StartRecordingUseCaseTests {
    @Test func startsRecorder_and_transitionsToRecording() async throws {
        let recorder = SpyAudioCapture()
        let state = SpyStateMachine(initial: .idle)
        let useCase = StartRecordingUseCase(recorder: recorder, state: state)

        try await useCase.execute(deviceUID: nil)

        #expect(recorder.startCalls == [nil])
        #expect(state.sentEvents == [.start])
    }

    @Test func returnsEarly_if_notIdle() async throws {
        let recorder = SpyAudioCapture()
        let state = SpyStateMachine(initial: .recording)
        let useCase = StartRecordingUseCase(recorder: recorder, state: state)

        do {
            try await useCase.execute(deviceUID: nil)
            Issue.record("should throw")
        } catch let error as StartRecordingUseCase.Error {
            #expect(error == .notIdle)
        }

        #expect(recorder.startCalls.isEmpty)
        #expect(state.sentEvents.isEmpty)
    }

    @Test func propagatesPermissionDenied_without_sendingStart() async {
        let recorder = SpyAudioCapture(startError: .permissionDenied)
        let state = SpyStateMachine(initial: .idle)
        let useCase = StartRecordingUseCase(recorder: recorder, state: state)

        do {
            try await useCase.execute(deviceUID: nil)
            Issue.record("should throw")
        } catch let error as StartRecordingUseCase.Error {
            #expect(error == .permissionDenied)
        } catch {
            Issue.record("unexpected error: \(error)")
        }

        #expect(state.sentEvents.isEmpty, "state.start must NOT be sent when recorder fails")
    }
}
