import XCTest
import Core
@testable import VoiceType

/// Fails every request on the shared session, where WhisperKit asks the
/// repository for its file list before downloading anything.
private final class OfflineURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requests: Int { lock.withLock { count } }
    static func reset() { lock.withLock { count = 0 } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.withLock { Self.count += 1 }
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

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

    /// What an interrupted download leaves: every compiled-model folder and its
    /// graph metadata, but the encoder weights never arrived.
    private func makeInterruptedBundle(_ id: String) throws -> URL {
        let folder = whisperRepo.appendingPathComponent(id)
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            let compiled = folder.appendingPathComponent("\(name).mlmodelc")
            for file in ["model.mil", "coremldata.bin", "metadata.json"] {
                try makeFile(compiled.appendingPathComponent(file))
            }
            if name != "AudioEncoder" {
                try makeFile(compiled.appendingPathComponent("weights/weight.bin"))
            }
        }
        return folder
    }

    // Regression (review 6 r2): Core ML crashes loading a bundle without its
    // weights, so only a finished download is loaded straight from disk.
    func test_interrupted_whisper_bundle_is_not_a_complete_bundle() throws {
        let loader = LiveLocalModelLoader(modelsDirectory: base)
        let turbo = try model(turboID)
        let folder = try makeInterruptedBundle(turboID)

        XCTAssertTrue(loader.isDownloaded(turbo))
        XCTAssertNil(loader.completeBundle(turbo))

        try makeFile(folder.appendingPathComponent(LiveLocalModelLoader.completeMarker))
        XCTAssertEqual(loader.completeBundle(turbo)?.standardizedFileURL, folder.standardizedFileURL)
        XCTAssertNil(loader.completeBundle(try model(smallID)))
    }

    func test_offline_load_of_interrupted_bundle_fails_through_download_and_keeps_files() async throws {
        let loader = LiveLocalModelLoader(modelsDirectory: base)
        let turbo = try model(turboID)
        let folder = try makeInterruptedBundle(turboID)
        OfflineURLProtocol.reset()
        URLProtocol.registerClass(OfflineURLProtocol.self)
        defer { URLProtocol.unregisterClass(OfflineURLProtocol.self) }

        do {
            _ = try await loader.load(turbo) { _ in }
            XCTFail("an offline load of an interrupted bundle cannot succeed")
        } catch {
            XCTAssertFalse(error is CancellationError)
        }

        XCTAssertGreaterThan(OfflineURLProtocol.requests, 0, "went to the download, which repairs the bundle")
        XCTAssertTrue(exists(folder.appendingPathComponent("AudioEncoder.mlmodelc/model.mil")))
        XCTAssertTrue(exists(folder.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin")))
        XCTAssertNil(loader.completeBundle(turbo))
    }
}
