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

enum LocalModelLoadError: LocalizedError {
    /// Files on disk do not match their recorded hashes; they were removed, and
    /// picking the model again downloads them.
    case damagedFiles

    var errorDescription: String? { SettingsStrings.localModelDamaged }
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
    /// Models whose load was under way when the app last died (Core ML crashes
    /// on damaged weights instead of throwing) and that have not loaded since.
    func crashedModels(_ models: [LocalModel]) -> Set<String>
    /// The app quits normally: a load under way now is not a crash.
    func endSession()
}

/// Every model lives under `modelsDirectory`:
/// - Whisper: `models/argmaxinc/whisperkit-coreml/<id>` (plus `completeMarker`
///   once its download finished), with its partial downloads in
///   `models/argmaxinc/whisperkit-coreml/.cache/huggingface/download/<id>`.
///   Tokenizers (`models/openai/…`) are shared and never deleted.
/// - Parakeet: `parakeet-ultra/`, partials (`*.partial`) included.
/// - `.voicetype-loading-<id>` while Core ML loads a model, and
///   `.voicetype-crashed-<id>` when the app died during that load.
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
    /// cancelled returned and every file matched its record, i.e. every file is
    /// on disk. It lists those files, one path per line: the inventory later
    /// loads check against. The folders alone prove nothing: an interrupted
    /// download leaves them without weights, and Core ML crashes (it does not
    /// throw) loading that.
    static let completeMarker = ".voicetype-complete"

    let modelsDirectory: URL
    private let downloadWhisper: WhisperDownload
    private let loadWhisper: WhisperLoad

    nonisolated init(
        modelsDirectory: URL = WhisperKitLoader.modelsDirectory,
        downloadWhisper: @escaping WhisperDownload = { variant, downloadBase, onProgress in
            try await WhisperKitLoader.download(variant: variant, downloadBase: downloadBase, onProgress: onProgress)
        },
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

    private func loadingSentinel(_ id: String) -> URL {
        modelsDirectory.appendingPathComponent(".voicetype-loading-\(id)")
    }

    private func crashRecord(_ id: String) -> URL {
        modelsDirectory.appendingPathComponent(".voicetype-crashed-\(id)")
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
    /// loaded without asking the repository anything; nil otherwise. A marker
    /// without an inventory (written by an earlier build) does not count.
    func completeBundle(_ model: LocalModel) -> URL? {
        guard model.engine == .whisperKit else { return nil }
        let folder = whisperFolder(model.id)
        return inventory(of: folder).isEmpty ? nil : folder
    }

    private func inventory(of folder: URL) -> Set<String> {
        let marker = folder.appendingPathComponent(Self.completeMarker)
        guard let text = try? String(contentsOf: marker, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }

    func load(
        _ model: LocalModel, progress: @escaping @Sendable (LocalModelLoadProgress) -> Void
    ) async throws -> any LocalSpeechBackend {
        switch model.engine {
        case .whisperKit:
            if let folder = completeBundle(model) {
                try await checkIntegrity(of: folder)
                // Offline or with the repository down, the files on disk still load.
                do {
                    return try await guardedLoad(model) { try await loadWhisper(folder, modelsDirectory) }
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
            // The downloader returns the files it already had without reading them.
            try await checkIntegrity(of: folder)
            return try await guardedLoad(model) { try await loadWhisper(folder, modelsDirectory) }
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
            return try await guardedLoad(model) {
                let models = try await AsrModels.load(from: folder, version: .ultra)
                try Task.checkCancellation()
                let manager = AsrManager()
                try await manager.loadModels(models)
                return ParakeetBackend(manager: manager)
            }
        }
    }

    /// Throws `damagedFiles`, before Core ML ever sees them, when a file is
    /// missing or does not match its recorded hash. The damaged files and the
    /// marker are removed, so the next download fetches just those. A bundle
    /// that passes gets (or refreshes) its marker with its inventory.
    private func checkIntegrity(of folder: URL) async throws {
        let records = whisperPartials(folder.lastPathComponent)
        let marker = folder.appendingPathComponent(Self.completeMarker)
        let damaged = await WhisperBundleIntegrity.damagedFiles(
            in: folder, metadataFolder: records, expected: inventory(of: folder), ignoring: [Self.completeMarker]
        )
        try Task.checkCancellation()
        guard !damaged.isEmpty else {
            let files = WhisperBundleIntegrity.files(in: folder).filter { $0 != Self.completeMarker }.sorted()
            try? files.joined(separator: "\n").write(to: marker, atomically: true, encoding: .utf8)
            return
        }
        Self.logger.error("Damaged files in \(folder.lastPathComponent, privacy: .public): \(damaged.joined(separator: ", "), privacy: .public)")
        let fm = FileManager.default
        try? fm.removeItem(at: marker)
        for path in damaged {
            try? fm.removeItem(at: folder.appendingPathComponent(path))
            try? fm.removeItem(at: records.appendingPathComponent(path + ".metadata"))
        }
        throw LocalModelLoadError.damagedFiles
    }

    /// Runs a Core ML load with a sentinel on disk, so that if the app dies in
    /// it the next launch knows (`crashedModels`) and does not load it again.
    private func guardedLoad(
        _ model: LocalModel, _ body: () async throws -> any LocalSpeechBackend
    ) async throws -> any LocalSpeechBackend {
        let fm = FileManager.default
        let sentinel = loadingSentinel(model.id)
        fm.createFile(atPath: sentinel.path, contents: nil)
        defer { try? fm.removeItem(at: sentinel) }
        let backend = try await body()
        try? fm.removeItem(at: crashRecord(model.id))
        return backend
    }

    func crashedModels(_ models: [LocalModel]) -> Set<String> {
        let fm = FileManager.default
        var crashed: Set<String> = []
        for model in models {
            let sentinel = loadingSentinel(model.id), record = crashRecord(model.id)
            if fm.fileExists(atPath: sentinel.path) {
                try? fm.removeItem(at: record)
                try? fm.moveItem(at: sentinel, to: record)
            }
            if fm.fileExists(atPath: record.path) { crashed.insert(model.id) }
        }
        return crashed
    }

    func endSession() {
        for model in LocalModelCatalog.all {
            try? FileManager.default.removeItem(at: loadingSentinel(model.id))
        }
    }

    func deleteFiles(_ model: LocalModel) {
        let targets: [URL]
        switch model.engine {
        case .whisperKit: targets = [whisperFolder(model.id), whisperPartials(model.id)]
        case .parakeet: targets = [parakeetFolder]
        }
        for url in targets + [crashRecord(model.id)] {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
