import Foundation

/// URLProtocol subclass that lets each test answer requests synchronously via
/// a handler keyed by an `X-Test-Token` header. Isolating per-session is
/// necessary because swift-testing runs suites in parallel and a global
/// handler would race between concurrent tests.
final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    static let tokenHeader = "X-Test-Token"

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]
    private static var captured: [String: [Data]] = [:]

    static func register(token: String, handler: @escaping Handler) {
        lock.lock()
        defer { lock.unlock() }
        handlers[token] = handler
        captured[token] = []
    }

    static func unregister(token: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: token)
        captured.removeValue(forKey: token)
    }

    static func capturedBodies(token: String) -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return captured[token, default: []]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: URLProtocolStub.tokenHeader) ?? ""

        // Capture body
        var bodyData: Data? = nil
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = Data()
            let bufSize = 4096
            let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
            defer { chunk.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(chunk, maxLength: bufSize)
                if read <= 0 { break }
                buffer.append(chunk, count: read)
            }
            bodyData = buffer
        } else if let body = request.httpBody {
            bodyData = body
        }

        URLProtocolStub.lock.lock()
        if let bodyData {
            URLProtocolStub.captured[token, default: []].append(bodyData)
        }
        let handler = URLProtocolStub.handlers[token]
        URLProtocolStub.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension URLSessionConfiguration {
    /// Creates a stubbed config that injects an `X-Test-Token` header on every
    /// request. The token routes to a per-test handler registered via
    /// `URLProtocolStub.register(token:handler:)`.
    static func stubbed(token: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [URLProtocolStub.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 60
        config.httpAdditionalHeaders = [URLProtocolStub.tokenHeader: token]
        return config
    }
}
