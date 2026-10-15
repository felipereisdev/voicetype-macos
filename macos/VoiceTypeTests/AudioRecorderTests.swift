import Testing
import AVFoundation
import Foundation
@testable import VoiceType

@Suite("AudioRecorder")
@MainActor
struct AudioRecorderTests {

    @Test("stop on a never-started recorder returns empty Data")
    func stopWithoutStartReturnsEmpty() async throws {
        let recorder = AudioRecorder()
        let wav = try await recorder.stop()
        #expect(wav.isEmpty)
    }

    @Test("requesting mic permission while denied surfaces typed error")
    func deniedPermissionThrows() async {
        let recorder = AudioRecorder(authProbe: .alwaysDenied)
        await #expect(throws: AudioRecorderError.permissionDenied) {
            try await recorder.start(deviceUID: nil)
        }
    }

    @Test("defaultInputDeviceID is non-nil on a host with a built-in mic")
    func defaultInputIsResolvable() {
        let id = AudioDeviceResolver.defaultInputDeviceID()
        #expect(id != nil)
        if let id { #expect(AudioDeviceResolver.deviceUID(for: id) != nil) }
    }

    // Requires real microphone hardware + permission. Disabled by default —
    // enable locally to verify level stream once mic permission is granted.
    @Test("level stream yields at least one value during a synthetic capture",
          .disabled("requires microphone hardware + TCC grant"))
    func levelStreamProducesValues() async throws {
        let recorder = AudioRecorder(authProbe: .alwaysGranted)
        try await recorder.start(deviceUID: nil)
        var firstLevel: Float?
        for await value in recorder.levelStream {
            firstLevel = value
            break
        }
        _ = try await recorder.stop()
        #expect(firstLevel != nil)
    }

    // MAC-370 — engine.start retry with exponential backoff.

    @Test("startWithRetry succeeds on first attempt")
    func retrySucceedsFirstTry() async throws {
        let recorder = AudioRecorder()
        var attempts = 0
        try await recorder.startWithRetry(delays: [0.001, 0.001, 0.001]) {
            attempts += 1
        }
        #expect(attempts == 1)
    }

    @Test("startWithRetry retries until success and stops calling")
    func retrySucceedsAfterTransientFailures() async throws {
        let recorder = AudioRecorder()
        var attempts = 0
        try await recorder.startWithRetry(delays: [0.001, 0.001, 0.001]) {
            attempts += 1
            if attempts < 2 { throw AudioRecorderError.engineFailure("transient") }
        }
        #expect(attempts == 2)
    }

    @Test("startWithRetry throws last error after exhausting delays")
    func retryGivesUpAndRethrowsLast() async {
        let recorder = AudioRecorder()
        var attempts = 0
        await #expect(throws: AudioRecorderError.engineFailure("fatal")) {
            try await recorder.startWithRetry(delays: [0.001, 0.001, 0.001]) {
                attempts += 1
                throw AudioRecorderError.engineFailure("fatal")
            }
        }
        #expect(attempts == 3)
    }

    @Test("startWithRetry honours requested attempt count via delays length")
    func retryAttemptCountMatchesDelays() async {
        let recorder = AudioRecorder()
        var attempts = 0
        await #expect(throws: AudioRecorderError.self) {
            try await recorder.startWithRetry(delays: [0.001, 0.001]) {
                attempts += 1
                throw AudioRecorderError.engineFailure("nope")
            }
        }
        #expect(attempts == 2)
    }

    @Test("default retry schedule matches spec")
    func defaultRetryDelaysMatchSpec() {
        #expect(AudioRecorder.defaultRetryDelays == [0.15, 0.30, 0.50])
    }
}
