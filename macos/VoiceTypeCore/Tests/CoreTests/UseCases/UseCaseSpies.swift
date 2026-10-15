import Foundation
@testable import Core

// MARK: - SpyAudioCapture

final class SpyAudioCapture: AudioCapture, @unchecked Sendable {
    enum FakeError: Error { case permissionDenied, other }

    var startCalls: [String?] = []
    var stopReturns: Data = Data()
    var startError: FakeError?
    var stopError: Error?

    init(startError: FakeError? = nil, stopError: Error? = nil) {
        self.startError = startError
        self.stopError = stopError
    }

    func start(deviceUID: String?) async throws {
        if let err = startError {
            switch err {
            case .permissionDenied:
                throw StartRecordingUseCase.Error.permissionDenied
            case .other:
                throw FakeError.other
            }
        }
        startCalls.append(deviceUID)
    }

    func stop() async throws -> Data {
        if let stopError { throw stopError }
        return stopReturns
    }
}

// MARK: - SpyStateMachine

final class SpyStateMachine: StateMachineDriver, @unchecked Sendable {
    private(set) var sentEvents: [AppStateMachine.Event] = []
    private var state: AppStateMachine.State

    init(initial: AppStateMachine.State) { state = initial }

    func send(_ event: AppStateMachine.Event) async {
        sentEvents.append(event)
        switch event {
        case .start:
            state = .recording
        case .stop, .timeout:
            state = .processing
        case .reset, .error:
            state = .idle
        }
    }

    func currentState() async -> AppStateMachine.State { state }
}

// MARK: - StubPipelineRunner

final class StubPipelineRunner: PipelineRunner, @unchecked Sendable {
    struct Invocation: Equatable {
        let mode: Pipeline.Mode
        let lang: String
        let translateTarget: String?
        let vocabulary: String?
    }
    var lastInvocation: Invocation?
    let result: String
    init(result: String) { self.result = result }
    func run(
        audio: Data,
        mode: Pipeline.Mode,
        lang: String,
        translateTarget: String?,
        vocabulary: String?
    ) async throws -> String {
        lastInvocation = Invocation(
            mode: mode,
            lang: lang,
            translateTarget: translateTarget,
            vocabulary: vocabulary
        )
        return result
    }
}

// MARK: - SpyPasterDelivery

final class SpyPasterDelivery: PasterDelivery, @unchecked Sendable {
    struct Call: Equatable { let text: String; let target: String; let autoEnter: Bool }
    var calls: [Call] = []
    var error: Error?
    func paste(text: String, targetBundleId: String, autoEnter: Bool) async throws {
        if let error { throw error }
        calls.append(Call(text: text, target: targetBundleId, autoEnter: autoEnter))
    }
}

// MARK: - SpyHistoryRecorder

final class SpyHistoryRecorder: HistoryRecorder, @unchecked Sendable {
    var recorded: [HistoryEntry] = []
    func record(_ entry: HistoryEntry) async {
        recorded.append(entry)
    }
}
