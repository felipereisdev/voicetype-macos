import Foundation

/// Abstract audio capture so use cases stay AppKit-free. The App target adapts
/// `AudioRecorder` to this protocol and is responsible for translating native
/// capture errors (e.g. `AudioRecorderError.permissionDenied`) into
/// `StartRecordingUseCase.Error.permissionDenied`.
public protocol AudioCapture: Sendable {
    /// Throws on permission denied or device error.
    func start(deviceUID: String?) async throws
    /// Stops + returns WAV data.
    func stop() async throws -> Data
}

/// Abstract paste delivery. The App target adapts `Paster` (which paste into a
/// `FrontmostAppSnapshot`) to this protocol keyed by bundle identifier.
public protocol PasterDelivery: Sendable {
    func paste(text: String, targetBundleId: String, autoEnter: Bool) async throws
}

public extension PasterDelivery {
    func paste(text: String, targetBundleId: String) async throws {
        try await paste(text: text, targetBundleId: targetBundleId, autoEnter: false)
    }
}

/// Abstract pipeline runner — mirrors `Pipeline.run` so use cases can compose
/// transcribe → refine/translate without depending on the concrete actor.
public protocol PipelineRunner: Sendable {
    func run(
        audio: Data,
        mode: Pipeline.Mode,
        lang: String,
        translateTarget: String?,
        vocabulary: String?
    ) async throws -> String
}

public extension PipelineRunner {
    func run(
        audio: Data,
        mode: Pipeline.Mode,
        lang: String,
        translateTarget: String?
    ) async throws -> String {
        try await run(
            audio: audio,
            mode: mode,
            lang: lang,
            translateTarget: translateTarget,
            vocabulary: nil
        )
    }
}

/// Abstract history recording. The App target adapts `HistoryStore.add(_:cap:)`.
public protocol HistoryRecorder: Sendable {
    func record(_ entry: HistoryEntry) async
}

/// Abstract state-machine driver. The App target adapts `AppStateMachine`.
public protocol StateMachineDriver: Sendable {
    func send(_ event: AppStateMachine.Event) async
    func currentState() async -> AppStateMachine.State
}
