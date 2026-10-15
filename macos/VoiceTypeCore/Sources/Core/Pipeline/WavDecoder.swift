import Foundation

// Parses a canonical PCM16 mono little-endian WAV (as produced by WavEncoder)
// into normalized Float samples in [-1, 1]. Scans chunks to find "data" rather
// than assuming a fixed 44-byte header, so non-canonical-but-valid headers work.
public enum WavDecoder {
    public enum DecodeError: Error { case malformedHeader }

    public static func pcmFloatSamples(from wav: Data) throws -> [Float] {
        guard wav.count >= 12,
              wav[wav.startIndex ..< wav.startIndex + 4] == Data("RIFF".utf8),
              wav[wav.startIndex + 8 ..< wav.startIndex + 12] == Data("WAVE".utf8)
        else { throw DecodeError.malformedHeader }

        var i = wav.startIndex + 12
        while i + 8 <= wav.endIndex {
            let id = wav[i ..< i + 4]
            let size = Int(readLE32(wav, at: i + 4))
            let body = i + 8
            if id == Data("data".utf8) {
                guard body + size <= wav.endIndex else { throw DecodeError.malformedHeader }
                return floats(wav[body ..< body + size])
            }
            i = body + size + (size % 2)
        }
        throw DecodeError.malformedHeader
    }

    /// Reads a little-endian 32-bit unsigned integer from `d` at index `idx`.
    /// Precondition: caller must ensure `idx + 4 <= d.endIndex`.
    private static func readLE32(_ d: Data, at idx: Data.Index) -> UInt32 {
        var v: UInt32 = 0
        for k in 0..<4 { v |= UInt32(d[idx + k]) << (8 * k) }
        return v
    }

    private static func floats(_ pcm: Data) -> [Float] {
        var out = [Float]()
        out.reserveCapacity(pcm.count / 2)
        var idx = pcm.startIndex
        while idx + 2 <= pcm.endIndex {
            let lo = UInt16(pcm[idx])
            let hi = UInt16(pcm[idx + 1])
            let sample = Int16(bitPattern: lo | (hi << 8))
            out.append(Float(sample) / 32768.0)
            idx += 2
        }
        return out
    }
}
