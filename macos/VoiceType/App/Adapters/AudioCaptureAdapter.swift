import Core
import Foundation

// Bridges the @MainActor-bound `AudioRecorderProtocol` into the Sendable
// `Core.AudioCapture` use-case protocol. Translates the AppKit-bound
// `AudioRecorderError.permissionDenied` to the Core-level
// `StartRecordingUseCase.Error.permissionDenied` so the use case can branch
// on a single typed error without importing AppKit.
//
// `AudioRecorder` is @MainActor; we expose the bridging through @Sendable
// closures captured up-front so the adapter itself stays Sendable.
struct AudioCaptureAdapter: AudioCapture {
    private let startFn: @Sendable (_ deviceUID: String?) async throws -> Void
    private let stopFn: @Sendable () async throws -> Data

    init(recorder: AudioRecorderProtocol) {
        self.startFn = { deviceUID in
            do {
                try await recorder.start(deviceUID: deviceUID)
            } catch let error as AudioRecorderError where error == .permissionDenied {
                throw StartRecordingUseCase.Error.permissionDenied
            }
        }
        self.stopFn = {
            try await recorder.stop()
        }
    }

    func start(deviceUID: String?) async throws {
        try await startFn(deviceUID)
    }

    func stop() async throws -> Data {
        try await stopFn()
    }
}
