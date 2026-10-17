import XCTest
import Core
@testable import VoiceType

@MainActor
final class LiveLocalModelLoaderTests: XCTestCase {
    private var base: URL!
    private let fm = FileManager.default

    private let smallID = "openai_whisper-small"
    private let turboID = "openai_whisper-large-v3-v20240930_turbo_632MB"
    private let turboSiblingID = "openai_whisper-large-v3-v20240930_turbo"

    override func setUp() async throws {
        base = fm.temporaryDirectory.appendingPathComponent("LiveLocalModelLoaderTests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? fm.removeItem(at: base)
    }

    private var whisperRepo: URL { base.appendingPathComponent("models/argmaxinc/whisperkit-coreml") }

    private func makeDir(_ url: URL) throws {
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private func makeFile(_ url: URL) throws {
        try makeDir(url.deletingLastPathComponent())
        XCTAssertTrue(fm.createFile(atPath: url.path, contents: Data("x".utf8)))
    }

    private func exists(_ url: URL) -> Bool { fm.fileExists(atPath: url.path) }

    private func model(_ id: String) throws -> LocalModel {
        try XCTUnwrap(LocalModelCatalog.model(id: id))
    }

    func test_delete_whisper_removes_model_and_its_partials_only() throws {
        let turbo = whisperRepo.appendingPathComponent(turboID)
        let turboCache = whisperRepo.appendingPathComponent(".cache/huggingface/download/\(turboID)")
        let sibling = whisperRepo.appendingPathComponent(turboSiblingID)
        let siblingCache = whisperRepo.appendingPathComponent(".cache/huggingface/download/\(turboSiblingID)")
        let small = whisperRepo.appendingPathComponent(smallID)
        let tokenizer = base.appendingPathComponent("models/openai/whisper-small/tokenizer.json")
        try makeDir(turbo.appendingPathComponent("AudioEncoder.mlmodelc"))
        try makeFile(turboCache.appendingPathComponent("x.abc.incomplete"))
        try makeDir(sibling.appendingPathComponent("AudioEncoder.mlmodelc"))
        try makeFile(siblingCache.appendingPathComponent("y.def.incomplete"))
        try makeDir(small.appendingPathComponent("AudioEncoder.mlmodelc"))
        try makeFile(tokenizer)

        LiveLocalModelLoader(modelsDirectory: base).deleteFiles(try model(turboID))

        XCTAssertFalse(exists(turbo))
        XCTAssertFalse(exists(turboCache))
        XCTAssertTrue(exists(sibling))
        XCTAssertTrue(exists(siblingCache))
        XCTAssertTrue(exists(small))
        XCTAssertTrue(exists(tokenizer))
    }

    func test_delete_parakeet_removes_folder_including_partials() throws {
        let parakeet = base.appendingPathComponent("parakeet-ultra")
        try makeDir(parakeet.appendingPathComponent("Encoder.mlmodelc"))
        try makeFile(parakeet.appendingPathComponent("x.partial"))
        try makeDir(whisperRepo.appendingPathComponent(smallID))

        LiveLocalModelLoader(modelsDirectory: base).deleteFiles(try model("parakeet-ultra"))

        XCTAssertFalse(exists(parakeet))
        XCTAssertTrue(exists(base.appendingPathComponent("models")))
        XCTAssertTrue(exists(whisperRepo.appendingPathComponent(smallID)))
    }

    func test_isDownloaded_whisper_requires_encoder_and_decoder() throws {
        let loader = LiveLocalModelLoader(modelsDirectory: base)
        let turbo = try model(turboID)
        let folder = whisperRepo.appendingPathComponent(turboID)

        XCTAssertFalse(loader.isDownloaded(turbo))
        try makeDir(folder.appendingPathComponent("AudioEncoder.mlmodelc"))
        XCTAssertFalse(loader.isDownloaded(turbo))
        try makeDir(folder.appendingPathComponent("TextDecoder.mlmodelc"))
        XCTAssertTrue(loader.isDownloaded(turbo))
        XCTAssertFalse(loader.isDownloaded(try model(smallID)))
    }
}
