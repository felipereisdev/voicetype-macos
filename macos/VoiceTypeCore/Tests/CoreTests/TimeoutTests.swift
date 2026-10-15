import Testing
import Foundation
@testable import Core

@Suite("withTimeout")
struct TimeoutTests {
    @Test func returnsValueWhenFastEnough() async throws {
        let v = try await withTimeout(seconds: 1.0) { "OK" }
        #expect(v == "OK")
    }

    @Test func throwsTimeoutWhenTooSlow() async {
        await #expect(throws: PipelineError.timeout) {
            try await withTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(2))
                return "TOO LATE"
            }
        }
    }

    @Test func throwsCancelledWhenParentCancelled() async {
        let task = Task { try await withTimeout(seconds: 10) { try await Task.sleep(for: .seconds(5)); return "X" } }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await #expect(throws: PipelineError.cancelled) { try await task.value }
    }
}
