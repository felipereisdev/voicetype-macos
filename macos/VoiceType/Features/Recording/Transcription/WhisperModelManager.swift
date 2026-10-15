import Foundation
import Observation
import WhisperKit
import os

@Observable
@MainActor
final class WhisperModelManager {
    enum State: Equatable {
        case notReady
        case downloading(Double)
        case ready
        case failed(String)
    }

    static let variant = "openai_whisper-small"
    private static let logger = Logger(subsystem: "dev.voicetype.app", category: "WhisperModelManager")

    private(set) var state: State = .notReady
    private var kit: WhisperKit?
    private var loadTask: Task<Void, Never>?

    var isReady: Bool { kit != nil }
    func transcriber() -> WhisperKit? { kit }

    nonisolated static var modelsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceType/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func bootstrap() {
        guard kit == nil, loadTask == nil else { return }
        loadTask = Task { [weak self] in await self?.load() }
    }

    private func load() async {
        do {
            let kit = try await Self.loadKit(variant: Self.variant) { [weak self] fraction in
                Task { @MainActor in self?.state = .downloading(fraction) }
            }
            self.kit = kit
            self.state = .ready
            Self.logger.info("WhisperKit ready: \(Self.variant, privacy: .public)")
        } catch {
            self.state = .failed(error.localizedDescription)
            Self.logger.error("WhisperKit load failed: \(error.localizedDescription, privacy: .public)")
        }
        loadTask = nil
    }

    /// Downloads (first run) and loads a WhisperKit model into the app's
    /// models directory. Also used by the meeting pipeline for its own,
    /// short-lived large model.
    nonisolated static func loadKit(
        variant: String, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> WhisperKit {
        let folder = try await WhisperKit.download(variant: variant, downloadBase: modelsDirectory) { progress in
            onProgress(progress.fractionCompleted)
        }
        let config = WhisperKitConfig(
            // Without tokenizerFolder, swift-transformers' HubApi defaults to
            // ~/Documents/huggingface → TCC "access Documents" prompt per binary.
            modelFolder: folder.path, tokenizerFolder: modelsDirectory,
            verbose: false, logLevel: .error,
            prewarm: false, load: false, download: false
        )
        let kit = try await WhisperKit(config)
        try await kit.loadModels()
        try await kit.prewarmModels()
        return kit
    }
}
