import Testing
import Foundation
@testable import Core

@Suite("WavDecoder")
struct WavDecoderTests {
    private func makeWav(samples: [Int16], sampleRate: UInt32 = 16_000) -> Data {
        var d = Data()
        let dataBytes = samples.count * 2
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func le16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        d.append("RIFF".data(using: .ascii)!)
        d.append(le32(UInt32(36 + dataBytes)))
        d.append("WAVE".data(using: .ascii)!)
        d.append("fmt ".data(using: .ascii)!)
        d.append(le32(16))
        d.append(le16(1))
        d.append(le16(1))
        d.append(le32(sampleRate))
        d.append(le32(sampleRate * 2))
        d.append(le16(2))
        d.append(le16(16))
        d.append("data".data(using: .ascii)!)
        d.append(le32(UInt32(dataBytes)))
        for s in samples { d.append(le16(UInt16(bitPattern: s))) }
        return d
    }

    @Test func decodesKnownSamplesNormalized() throws {
        let wav = makeWav(samples: [0, 16384, -32768, 32767])
        let out = try WavDecoder.pcmFloatSamples(from: wav)
        #expect(out.count == 4)
        #expect(abs(out[0] - 0.0) < 1e-6)
        #expect(abs(out[1] - 0.5) < 1e-3)
        #expect(out[2] >= -1.0 && out[2] <= -0.999)
        #expect(out[3] > 0.999 && out[3] <= 1.0)
    }

    @Test func throwsOnMalformedHeader() {
        #expect(throws: WavDecoder.DecodeError.malformedHeader) {
            try WavDecoder.pcmFloatSamples(from: Data([0x00, 0x01, 0x02]))
        }
    }
}
