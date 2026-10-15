import Testing
import Foundation
@testable import Core

@Suite("RunPipelineUseCase")
struct RunPipelineUseCaseTests {
    @Test func happyPath_refine_pastes_and_records() async throws {
        let pipeline = StubPipelineRunner(result: "texto refinado")
        let paster = SpyPasterDelivery()
        let history = SpyHistoryRecorder()
        let useCase = RunPipelineUseCase(
            pipeline: pipeline, paster: paster, history: history
        )

        try await useCase.execute(
            audio: Data(count: 32_000),
            mode: .refine,
            lang: "pt",
            translateTarget: nil,
            targetBundleId: "com.example.app",
            historyEnabled: true,
            historyCap: 500
        )

        #expect(paster.calls.count == 1)
        #expect(paster.calls.first?.text == "texto refinado")
        #expect(paster.calls.first?.target == "com.example.app")
        #expect(history.recorded.count == 1)
        #expect(history.recorded.first?.mode == .refine)
        #expect(history.recorded.first?.text == "texto refinado")
    }

    @Test func historyDisabled_skips_record() async throws {
        let pipeline = StubPipelineRunner(result: "x")
        let paster = SpyPasterDelivery()
        let history = SpyHistoryRecorder()
        let useCase = RunPipelineUseCase(
            pipeline: pipeline, paster: paster, history: history
        )

        try await useCase.execute(
            audio: Data(count: 32_000),
            mode: .refine, lang: "pt", translateTarget: nil,
            targetBundleId: "x", historyEnabled: false, historyCap: 500
        )
        #expect(history.recorded.isEmpty)
        #expect(paster.calls.count == 1)
    }

    @Test func translateMode_uses_target() async throws {
        let pipeline = StubPipelineRunner(result: "en text")
        let paster = SpyPasterDelivery()
        let history = SpyHistoryRecorder()
        let useCase = RunPipelineUseCase(
            pipeline: pipeline, paster: paster, history: history
        )

        try await useCase.execute(
            audio: Data(count: 32_000),
            mode: .translate, lang: "pt", translateTarget: "en",
            targetBundleId: "x", historyEnabled: true, historyCap: 500
        )

        #expect(pipeline.lastInvocation?.mode == .translate)
        #expect(pipeline.lastInvocation?.translateTarget == "en")
        #expect(history.recorded.first?.mode == .translate)
    }

    @Test func vocabularyForwardedToPipeline() async throws {
        let pipeline = StubPipelineRunner(result: "x")
        let useCase = RunPipelineUseCase(
            pipeline: pipeline,
            paster: SpyPasterDelivery(),
            history: SpyHistoryRecorder()
        )

        try await useCase.execute(
            audio: Data(count: 32_000),
            mode: .refine, lang: "pt", translateTarget: nil,
            targetBundleId: "x", historyEnabled: false, historyCap: 500,
            vocabulary: "Macsilva, Codex"
        )

        #expect(pipeline.lastInvocation?.vocabulary == "Macsilva, Codex")
    }

    @Test func cancellationError_propagates() async {
        struct CancelStub: PipelineRunner {
            func run(audio: Data, mode: Pipeline.Mode, lang: String, translateTarget: String?, vocabulary: String?) async throws -> String {
                throw CancellationError()
            }
        }
        let useCase = RunPipelineUseCase(
            pipeline: CancelStub(),
            paster: SpyPasterDelivery(),
            history: SpyHistoryRecorder()
        )

        do {
            try await useCase.execute(
                audio: Data(count: 32_000),
                mode: .refine, lang: "pt", translateTarget: nil,
                targetBundleId: "x", historyEnabled: true, historyCap: 500
            )
            Issue.record("should throw")
        } catch is CancellationError {
            // ok
        } catch {
            Issue.record("unexpected: \(error)")
        }
    }
}
