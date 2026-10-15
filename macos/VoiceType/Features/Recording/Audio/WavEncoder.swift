import Foundation

// Canonical 44-byte RIFF/WAVE PCM header + Int16 little-endian payload.
// Mirrors src/shared/lib/encodeWav.ts byte-for-byte so downstream players
// (and the Groq Whisper endpoint) see exactly the same shape the Electron
// build produced.
enum WavEncoder {

    static func encode(pcmInt16LE: Data, sampleRate: Int, channels: Int) -> Data {
        let bytesPerSample = 2
        let blockAlign = bytesPerSample * channels
        let byteRate = sampleRate * blockAlign
        let dataSize = pcmInt16LE.count
        let riffSize = 36 + dataSize

        var out = Data(capacity: 44 + dataSize)
        out.append(contentsOf: Array("RIFF".utf8))
        out.appendUInt32LE(UInt32(riffSize))
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        out.appendUInt32LE(16)
        out.appendUInt16LE(1)
        out.appendUInt16LE(UInt16(channels))
        out.appendUInt32LE(UInt32(sampleRate))
        out.appendUInt32LE(UInt32(byteRate))
        out.appendUInt16LE(UInt16(blockAlign))
        out.appendUInt16LE(16)
        out.append(contentsOf: Array("data".utf8))
        out.appendUInt32LE(UInt32(dataSize))
        out.append(pcmInt16LE)
        return out
    }

    // Negative scales by 0x8000, positive by 0x7FFF — matches the JS encoder.
    static func floatToInt16(_ raw: Float) -> Int16 {
        let s = max(-1.0, min(1.0, raw))
        if s < 0 {
            return Int16(s * Float(0x8000))
        }
        // Clamp +1.0 explicitly — Float(0x7FFF) * 1.0 fits in Int16, but 0x8000 scaling
        // for positive values would overflow.
        return Int16(s * Float(0x7FFF))
    }

    // Max absolute Int16 sample in a WAV produced by `encode()` (44-byte
    // header + Int16LE payload). Used to detect effectively-silent captures
    // (muted mic, or a wrong default device like AirPods in A2DP with no live
    // input). Full scale is 32767.
    static func peakAmplitude(inWav data: Data) -> Int {
        guard data.count > 44 else { return 0 }
        var peak = 0
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = 44
            while i + 1 < bytes.count {
                let sample = Int16(bitPattern: UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))
                let mag = Int(sample.magnitude)
                if mag > peak { peak = mag }
                i += 2
            }
        }
        return peak
    }

    static func encodeSamplesToInt16LE(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let i16 = floatToInt16(sample)
            withUnsafeBytes(of: i16.littleEndian) { data.append(contentsOf: $0) }
        }
        return data
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendUInt32LE(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
