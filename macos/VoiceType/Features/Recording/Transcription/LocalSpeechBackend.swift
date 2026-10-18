import Foundation
import Core
import FluidAudio
import os

/// A loaded on-device speech model, ready to transcribe 16 kHz mono samples.
protocol LocalSpeechBackend: AnyObject, Sendable {
    func transcribe(samples: [Float], lang: String, vocabulary: String?) async throws -> String
}

enum LocalModelLoadProgress: Sendable {
    case downloading(Double)
    case preparing
}

/// Downloads, loads and deletes the catalog's models. Never called with a
/// load and a delete of the same id at once: `LocalModelManager` serializes them.
@MainActor
protocol LocalModelLoading {
    func isDownloaded(_ model: LocalModel) -> Bool
    func load(
        _ model: LocalModel, progress: @escaping @Sendable (LocalModelLoadProgress) -> Void
    ) async throws -> any LocalSpeechBackend
    func deleteFiles(_ model: LocalModel)
}

/// Every model lives under `modelsDirectory`:
/// - Whisper: `models/argmaxinc/whisperkit-coreml/<id>` (plus `completeMarker`
///   once its download finished), with its partial downloads in
///   `models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<id>`.
///   Tokenizers (`models/openai/…`) are shared and never deleted.
/// - Parakeet: `parakeet-ultra/`, partials (`*.partial`) included.
@MainActor
struct LiveLocalModelLoader: LocalModelLoading {
    private static let logger = Logger(subsystem: "dev.voicetype.app", category: "LiveLocalModelLoader")

    /// Fetches the missing files of a Whisper model and returns its folder.
    typealias WhisperDownload = @Sendable (
        _ variant: String, _ downloadBase: URL, _ onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
    /// Loads the Whisper model in a folder into Core ML.
    typealias WhisperLoad = @Sendable (_ modelFolder: URL, _ tokenizerFolder: URL) async throws -> any LocalSpeechBackend

    /// Written in a Whisper model's folder once a download that was not
    /// cancelled returned, i.e. every file is on disk. The folders alone prove
    /// nothing: an interrupted download leaves them without weights, and Core ML
    /// crashes (it does not throw) loading that.
    static let completeMarker = ".voicetype-complete"

    let modelsDirectory: URL
    private let downloadWhisper: WhisperDownload
    private let loadWhisper: WhisperLoad

    nonisolated init(
        modelsDirectory: URL = WhisperKitLoader.modelsDirectory,
        downloadWhisper: @escaping WhisperDownload = WhisperKitLoader.download(variant:downloadBase:onProgress:),
        loadWhisper: @escaping WhisperLoad = { folder, tokenizerFolder in
            WhisperKitBackend(kit: try await WhisperKitLoader.loadKit(modelFolder: folder, tokenizerFolder: tokenizerFolder))
        }
    ) {
        self.modelsDirectory = modelsDirectory
        self.downloadWhisper = downloadWhisper
        self.loadWhisper = loadWhisper
    }

    private var whisperRepo: URL {
        modelsDirectory.appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
    }

    private func whisperFolder(_ id: String) -> URL {
        whisperRepo.appendingPathComponent(id, isDirectory: true)
    }

    private func whisperPartials(_ id: String) -> URL {
        whisperRepo.appendingPathComponent(".cache/huggingface/download", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    private var parakeetFolder: URL {
        modelsDirectory.appendingPathComponent("parakeet-ultra", isDirectory: true)
    }

    func isDownloaded(_ model: LocalModel) -> Bool {
        switch model.engine {
        case .whisperKit:
            let folder = whisperFolder(model.id)
            return ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"].allSatisfy {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
        case .parakeet:
            return AsrModels.modelsExist(at: parakeetFolder, version: .ultra)
        }
    }

    /// The folder of a Whisper model whose download finished, which can be
    /// loaded without asking the repository anything; nil otherwise.
    func completeBundle(_ model: LocalModel) -> URL? {
        guard model.engine == .whisperKit else { return nil }
        let folder = whisperFolder(model.id)
        let marker = folder.appendingPathComponent(Self.completeMarker)
        return FileManager.default.fileExists(atPath: marker.path) ? folder : nil
    }

    func load(
        _ model: LocalModel, progress: @escaping @Sendable (LocalModelLoadProgress) -> Void
    ) async throws -> any LocalSpeechBackend {
        switch model.engine {
        case .whisperKit:
            if let folder = completeBundle(model) {
                // Offline or with the repository down, the files on disk still load.
                do {
                    return try await loadWhisper(folder, modelsDirectory)
                } catch {
                    try Task.checkCancellation()
                    // Fall through: the download fetches whatever file is missing.
                    Self.logger.error("Local load of \(model.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            let folder = try await downloadWhisper(model.id, modelsDirectory) { fraction in
                progress(fraction >= 1 ? .preparing : .downloading(fraction))
            }
            // Cancelled midway, the downloader returns without throwing
            // (`HubApi.snapshot`), so only an attempt still running has every file.
            try Task.checkCancellation()
            FileManager.default.createFile(atPath: folder.appendingPathComponent(Self.completeMarker).path, contents: nil)
            return try await loadWhisper(folder, modelsDirectory)
        case .parakeet:
            let folder = parakeetFolder
            try await AsrModels.download(to: folder, version: .ultra) { update in
                switch update.phase {
                case .listing, .downloading: progress(.downloading(update.fractionCompleted))
                case .compiling: progress(.preparing)
                }
            }
            try Task.checkCancellation()
            progress(.preparing)
            let models = try await AsrModels.load(from: folder, version: .ultra)
            try Task.checkCancellation()
            let manager = AsrManager()
            try await manager.loadModels(models)
            return ParakeetBackend(manager: manager)
        }
    }

    func deleteFiles(_ model: LocalModel) {
        let targets: [URL]
        switch model.engine {
        case .whisperKit: targets = [whisperFolder(model.id), whisperPartials(model.id)]
        case .parakeet: targets = [parakeetFolder]
        }
        for url in targets {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
