import Foundation

// llama-3.3-70b occasionally degenerates into runaway repetition (the same line
// or short phrase emitted dozens of times) when it's unsure what to do with a
// transcription. Detect that so callers can fall back to the raw text instead of
// pasting a wall of garbage. Threshold is deliberately high — natural speech
// rarely repeats an identical non-trivial line four times.
func isDegenerate(_ text: String) -> Bool {
    let lines = text
        .split(whereSeparator: \.isNewline)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.count >= 3 }
    guard lines.count >= 4 else { return false }

    var counts: [String: Int] = [:]
    for line in lines {
        counts[line, default: 0] += 1
        if counts[line]! >= 4 { return true }
    }
    return false
}
