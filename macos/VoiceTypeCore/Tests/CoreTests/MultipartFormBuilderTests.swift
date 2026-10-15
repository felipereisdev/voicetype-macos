import Foundation
import Testing
@testable import Core

@Suite("MultipartFormBuilder")
struct MultipartFormBuilderTests {
    @Test("body contains boundary, file headers, and all text fields")
    func bodyComposition() throws {
        var builder = MultipartFormBuilder(boundary: "----TestBoundary123")
        builder.appendText(name: "model", value: "whisper-large-v3-turbo")
        builder.appendText(name: "language", value: "pt")
        builder.appendText(name: "response_format", value: "text")
        builder.appendText(name: "temperature", value: "0")
        builder.appendFile(
            name: "file",
            filename: "audio.wav",
            contentType: "audio/wav",
            data: Data([0xDE, 0xAD, 0xBE, 0xEF])
        )

        let body = builder.finalize()
        // Body contains raw audio bytes that aren't valid UTF-8; use ISO Latin-1
        // for inspection so every byte maps 1:1.
        let asString = String(data: body, encoding: .isoLatin1) ?? ""

        #expect(asString.contains("------TestBoundary123"))
        #expect(asString.contains("Content-Disposition: form-data; name=\"model\""))
        #expect(asString.contains("whisper-large-v3-turbo"))
        #expect(asString.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\""))
        #expect(asString.contains("Content-Type: audio/wav"))
        #expect(asString.hasSuffix("------TestBoundary123--\r\n"))
        #expect(builder.contentTypeHeader == "multipart/form-data; boundary=----TestBoundary123")
    }
}
