import Foundation

// User-visible recording mode. Captured at idle→recording, never overwritten
// mid-recording (parity with Electron orchestrator.ts:42-45, commit 5174d7b).
public enum Mode: String, Sendable, CaseIterable {
    case refine
    case translate
    /// #79: same pipeline, written to today's daily note instead of pasted.
    case voiceNote
}
