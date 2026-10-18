import XCTest
import CryptoKit
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

/// Counts the injected Whisper download and Core ML load calls.
private final class WhisperCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var downloadCount = 0
    private var loadCount = 0
    var downloads: Int { lock.withLock { downloadCount } }
    var loads: Int { lock.withLock { loadCount } }
    func downloaded() { lock.withLock { downloadCount += 1 } }
    func loaded() { lock.withLock { loadCount += 1 } }
}

/// Holds a fake Core ML load open until the test lets it end.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Error>?
    private var outcome: Result<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                if let outcome { continuation.resume(with: outcome) } else { waiter = continuation }
            }
        }
    }

    func open(_ result: Result<Void, Error> = .success(())) {
        lock.withLock {
            if let waiter { waiter.resume(with: result) } else { outcome = result }
            waiter = nil
        }
    }
}

private final class StubBackend: LocalSpeechBackend, @unchecked Sendable {
    func transcribe(samples: [Float], lang: String, vocabulary: String?) async throws -> String { "" }
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

    private func loader(
        _ calls: WhisperCalls, gate: Gate? = nil, download: @escaping LiveLocalModelLoader.WhisperDownload
    ) -> LiveLocalModelLoader {
        LiveLocalModelLoader(
            modelsDirectory: base,
            downloadWhisper: { variant, downloadBase, onProgress in
                calls.downloaded()
                return try await download(variant, downloadBase, onProgress)
            },
            loadWhisper: { _, _ in
                calls.loaded()
                try await gate?.wait()
                return StubBackend()
            }
        )
    }

    private func records(_ id: String) -> URL {
        whisperRepo.appendingPathComponent(".cache/huggingface/download/\(id)")
    }

    private func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A finished download: every file with the record the downloader writes,
    /// a SHA-256 etag for LFS files (weights), the git blob SHA-1 for the rest.
    private func makeIntactBundle(_ id: String) throws -> URL {
        let folder = whisperRepo.appendingPathComponent(id)
        var files = ["config.json": Data("{}".utf8)]
        for name in ["MelSpectrogram", "AudioEncoder", "TextDecoder"] {
            files["\(name).mlmodelc/model.mil"] = Data("program \(name)".utf8)
            files["\(name).mlmodelc/weights/weight.bin"] = Data(repeating: 7, count: 4096)
        }
        for (path, content) in files {
            try makeDir(folder.appendingPathComponent(path).deletingLastPathComponent())
            try content.write(to: folder.appendingPathComponent(path))
            let etag: String
            if path.hasSuffix(".bin") {
                etag = hex(SHA256.hash(data: content))
            } else {
                etag = hex(Insecure.SHA1.hash(data: Data("blob \(content.count)\0".utf8) + content))
            }
            let record = records(id).appendingPathComponent(path + ".metadata")
            try makeDir(record.deletingLastPathComponent())
            try Data("\(String(repeating: "a", count: 40))\n\(etag)\n1792286632.0\n".utf8).write(to: record)
        }
        return folder
    }

    /// Waits for the fake Core ML load to start, failing instead of hanging.
    private func waitUntilLoading(_ calls: WhisperCalls) async throws {
        for _ in 0..<2_000 where calls.loads == 0 {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        try XCTSkipUnless(calls.loads > 0, "the load never reached Core ML")
    }

    private func markComplete(_ folder: URL) throws {
        try makeFile(folder.appendingPathComponent(LiveLocalModelLoader.completeMarker))
    }

    // Regression (review 6 r3): cancelled midway, the downloader returns the
    // folder without throwing. That partial bundle must not be marked complete,
    // or the next load hands it to Core ML, which crashes.
    func test_cancelled_resumed_download_is_not_marked_complete() async throws {
        let turbo = try model(turboID)
        let folder = try makeInterruptedBundle(turboID)
        let calls = WhisperCalls()
        let cancelling = loader(calls) { _, _, _ in
            // Like `HubApi.snapshot`: stop at cancellation and return, no throw.
            while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000) }
            return folder
        }

        let task = Task { try await cancelling.load(turbo) { _ in } }
        while calls.downloads == 0 { await Task.yield() }
        task.cancel()
        let result = await task.result

        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(calls.loads, 0, "a cancelled download never reaches Core ML")
        XCTAssertNil(cancelling.completeBundle(turbo))
        XCTAssertFalse(exists(folder.appendingPathComponent(LiveLocalModelLoader.completeMarker)))
        XCTAssertFalse(exists(folder.appendingPathComponent("AudioEncoder.mlmodelc/weights/weight.bin")))
        XCTAssertTrue(cancelling.isDownloaded(turbo))

        // The next attempt goes through the download (the repair) and, offline,
        // fails without entering Core ML.
        let offline = loader(calls) { _, _, _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await offline.load(turbo) { _ in }
            XCTFail("an offline repair cannot succeed")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet)
        }
        XCTAssertEqual(calls.downloads, 2)
        XCTAssertEqual(calls.loads, 0)
    }

    func test_finished_download_is_marked_complete_and_later_loads_from_disk() async throws {
        let turbo = try model(turboID)
        let folder = try makeIntactBundle(turboID)
        let calls = WhisperCalls()
        let online = loader(calls) { _, _, _ in folder }

        _ = try await online.load(turbo) { _ in }
        XCTAssertEqual(calls.downloads, 1)
        XCTAssertEqual(calls.loads, 1)
        XCTAssertNotNil(online.completeBundle(turbo))

        let offline = loader(calls) { _, _, _ in throw URLError(.notConnectedToInternet) }
        _ = try await offline.load(turbo) { _ in }
        XCTAssertEqual(calls.downloads, 1, "a complete bundle loads without the repository")
        XCTAssertEqual(calls.loads, 2)
    }

    func test_integrity_accepts_intact_bundle_and_flags_files_without_record() async throws {
        let folder = try makeIntactBundle(turboID)
        try markComplete(folder)
        let clean = await WhisperBundleIntegrity.damagedFiles(
            in: folder, metadataFolder: records(turboID), ignoring: [LiveLocalModelLoader.completeMarker]
        )
        XCTAssertEqual(clean, [])

        try makeFile(folder.appendingPathComponent("stray.bin"))
        let flagged = await WhisperBundleIntegrity.damagedFiles(
            in: folder, metadataFolder: records(turboID), ignoring: [LiveLocalModelLoader.completeMarker]
        )
        XCTAssertEqual(flagged, ["stray.bin"])
    }

    // QA F15: a complete bundle whose weights were emptied, truncated or
    // corrupted afterwards crashed the app inside Core ML. The load now fails
    // with a reason before Core ML, and drops just the damaged files.
    func test_damaged_weights_of_complete_bundle_fail_before_core_ml() async throws {
        let turbo = try model(turboID)
        let encoder = "AudioEncoder.mlmodelc/weights/weight.bin"
        let damage: [(Data) -> Data] = [
            { _ in Data() },                                       // `: > weight.bin`
            { $0.prefix(1000) },                                   // truncated
            { var d = $0; d[100] ^= 0xFF; return d },              // same size, one byte off
        ]
        for corrupt in damage {
            let folder = try makeIntactBundle(turboID)
            try markComplete(folder)
            let weights = folder.appendingPathComponent(encoder)
            try corrupt(try Data(contentsOf: weights)).write(to: weights)
            let calls = WhisperCalls()
            let offline = loader(calls) { _, _, _ in throw URLError(.notConnectedToInternet) }

            do {
                _ = try await offline.load(turbo) { _ in }
                XCTFail("a damaged bundle cannot load")
            } catch {
                XCTAssertEqual(error as? LocalModelLoadError, .damagedFiles)
                XCTAssertEqual(error.localizedDescription, SettingsStrings.localModelDamaged)
            }
            XCTAssertEqual(calls.loads, 0, "never handed to Core ML")
            XCTAssertEqual(calls.downloads, 0)
            XCTAssertFalse(exists(weights))
            XCTAssertFalse(exists(records(turboID).appendingPathComponent(encoder + ".metadata")))
            XCTAssertNil(offline.completeBundle(turbo))
            XCTAssertTrue(exists(folder.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin")))
            XCTAssertTrue(offline.isDownloaded(turbo))
            try fm.removeItem(at: whisperRepo)
        }
    }

    func test_download_that_kept_a_damaged_file_is_not_marked_complete() async throws {
        let turbo = try model(turboID)
        let folder = try makeIntactBundle(turboID)
        try Data().write(to: folder.appendingPathComponent("TextDecoder.mlmodelc/weights/weight.bin"))
        let calls = WhisperCalls()
        let online = loader(calls) { _, _, _ in folder }

        do {
            _ = try await online.load(turbo) { _ in }
            XCTFail("a damaged bundle cannot load")
        } catch {
            XCTAssertEqual(error as? LocalModelLoadError, .damagedFiles)
        }
        XCTAssertEqual(calls.downloads, 1)
        XCTAssertEqual(calls.loads, 0)
        XCTAssertNil(online.completeBundle(turbo))
    }

    // QA F15/K8: what the hashes cannot catch still must not crash every
    // launch. A load under way when the app dies is reported at the next one.
    func test_load_under_way_when_app_dies_is_reported_at_next_launch() async throws {
        let turbo = try model(turboID)
        try markComplete(try makeIntactBundle(turboID))
        let calls = WhisperCalls(), gate = Gate()
        let running = loader(calls, gate: gate) { _, _, _ in throw URLError(.notConnectedToInternet) }

        let task = Task { try await running.load(turbo) { _ in } }
        try await waitUntilLoading(calls)
        let relaunched = LiveLocalModelLoader(modelsDirectory: base)
        XCTAssertEqual(relaunched.crashedModels(LocalModelCatalog.all), [turboID])
        XCTAssertEqual(relaunched.crashedModels(LocalModelCatalog.all), [turboID], "stays until it loads")

        gate.open()
        _ = try await task.value
        XCTAssertEqual(relaunched.crashedModels(LocalModelCatalog.all), [], "a successful load clears it")
    }

    func test_quit_or_thrown_error_during_load_is_not_a_crash() async throws {
        let turbo = try model(turboID)
        try markComplete(try makeIntactBundle(turboID))
        let offline: LiveLocalModelLoader.WhisperDownload = { _, _, _ in throw URLError(.notConnectedToInternet) }

        let calls = WhisperCalls(), gate = Gate()
        let quitting = loader(calls, gate: gate, download: offline)
        let task = Task { try await quitting.load(turbo) { _ in } }
        try await waitUntilLoading(calls)
        quitting.endSession()
        XCTAssertEqual(quitting.crashedModels(LocalModelCatalog.all), [])
        gate.open()
        _ = try await task.value

        let failing = Gate()
        failing.open(.failure(FakeLoadError()))
        _ = try? await loader(WhisperCalls(), gate: failing, download: offline).load(turbo) { _ in }
        XCTAssertEqual(quitting.crashedModels(LocalModelCatalog.all), [])
    }

    func test_delete_clears_crash_record() async throws {
        let turbo = try model(turboID)
        try markComplete(try makeIntactBundle(turboID))
        let calls = WhisperCalls(), gate = Gate()
        let running = loader(calls, gate: gate) { _, _, _ in throw URLError(.notConnectedToInternet) }
        let task = Task { try await running.load(turbo) { _ in } }
        try await waitUntilLoading(calls)
        XCTAssertEqual(running.crashedModels(LocalModelCatalog.all), [turboID])
        gate.open(.failure(FakeLoadError()))
        _ = try? await task.value

        running.deleteFiles(turbo)
        XCTAssertEqual(running.crashedModels(LocalModelCatalog.all), [])
    }
}

private struct FakeLoadError: Error {}
