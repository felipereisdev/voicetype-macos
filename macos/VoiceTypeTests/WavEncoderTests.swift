import Testing
import Foundation
@testable import VoiceType

@Suite("WavEncoder")
struct WavEncoderTests {

    @Test("44-byte header for empty PCM")
    func emptyPayloadHeader() throws {
        let wav = WavEncoder.encode(pcmInt16LE: Data(), sampleRate: 16_000, channels: 1)
        #expect(wav.count == 44)

        #expect(wav[0..<4] == Data("RIFF".utf8))
        #expect(readUInt32LE(wav, at: 4) == 36)
        #expect(wav[8..<12] == Data("WAVE".utf8))

        #expect(wav[12..<16] == Data("fmt ".utf8))
        #expect(readUInt32LE(wav, at: 16) == 16)
        #expect(readUInt16LE(wav, at: 20) == 1)
        #expect(readUInt16LE(wav, at: 22) == 1)
        #expect(readUInt32LE(wav, at: 24) == 16_000)
        #expect(readUInt32LE(wav, at: 28) == 16_000 * 2)
        #expect(readUInt16LE(wav, at: 32) == 2)
        #expect(readUInt16LE(wav, at: 34) == 16)

        #expect(wav[36..<40] == Data("data".utf8))
        #expect(readUInt32LE(wav, at: 40) == 0)
    }

    @Test("payload bytes are preserved after header")
    func payloadCopied() {
        var payload = Data()
        for s: Int16 in [0, 1, -1, Int16.max, Int16.min] {
            withUnsafeBytes(of: s.littleEndian) { payload.append(contentsOf: $0) }
        }
        let wav = WavEncoder.encode(pcmInt16LE: payload, sampleRate: 16_000, channels: 1)
        #expect(wav.count == 44 + payload.count)
        #expect(wav[44...] == payload)
        #expect(readUInt32LE(wav, at: 4) == UInt32(36 + payload.count))
        #expect(readUInt32LE(wav, at: 40) == UInt32(payload.count))
    }

    @Test("floatToInt16 clamps and scales like JS encoder")
    func floatClamp() {
        #expect(WavEncoder.floatToInt16(0) == 0)
        #expect(WavEncoder.floatToInt16(1) == 0x7FFF)
        #expect(WavEncoder.floatToInt16(-1) == -0x8000)
        #expect(WavEncoder.floatToInt16(2) == 0x7FFF)
        #expect(WavEncoder.floatToInt16(-2) == -0x8000)
        #expect(WavEncoder.floatToInt16(0.5) == Int16(0.5 * Float(0x7FFF)))
    }

    private func readUInt32LE(_ d: Data, at offset: Int) -> UInt32 {
        d.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }
    private func readUInt16LE(_ d: Data, at offset: Int) -> UInt16 {
        d.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }
}
