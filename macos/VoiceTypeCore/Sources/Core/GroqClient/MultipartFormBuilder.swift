import Foundation

/// Builds a `multipart/form-data` body matching the request that
/// `src/main/pipeline/transcribe.ts` builds via `FormData`.
struct MultipartFormBuilder {
    let boundary: String
    private var data = Data()

    init(boundary: String = "----VoiceTypeBoundary\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentTypeHeader: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func appendText(name: String, value: String) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        data.append("\(value)\r\n")
    }

    mutating func appendFile(name: String, filename: String, contentType: String, data fileData: Data) {
        data.append("--\(boundary)\r\n")
        data.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        data.append("Content-Type: \(contentType)\r\n\r\n")
        data.append(fileData)
        data.append("\r\n")
    }

    func finalize() -> Data {
        var out = data
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
