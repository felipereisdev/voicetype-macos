import Foundation
import Core
import FluidAudio

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
/// - Whisper: `models/argmaxinc/whisperkit-coreml/<id>`, with its partial
///   downloads in `models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<id>`.
///   Tokenizers (`models/openai/…`) are shared and never deleted.
/// - Parakeet: `parakeet-ultra/`, partials (`*.partial`) included.
@MainActor
struct LiveLocalModelLoader: LocalModelLoading {
    let modelsDirectory: URL

    nonisolated init(modelsDirectory: URL = WhisperKitLoader.modelsDirectory) {
        self.modelsDirectory = modelsDirectory
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

    func load(
        _ model: LocalModel, progress: @escaping @Sendable (LocalModelLoadProgress) -> Void
    ) async throws -> any LocalSpeechBackend {
        switch model.engine {
        case .whisperKit:
            let kit = try await WhisperKitLoader.loadKit(variant: model.id, downloadBase: modelsDirectory) { fraction in
                progress(fraction >= 1 ? .preparing : .downloading(fraction))
            }
            return WhisperKitBackend(kit: kit)
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
