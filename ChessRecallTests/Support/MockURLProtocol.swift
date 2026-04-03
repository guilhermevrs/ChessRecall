import Foundation

/// URLProtocol subclass that intercepts requests to lichess.org and returns
/// pre-recorded fixture responses. Register it before each test via setUp/tearDown.
final class MockURLProtocol: URLProtocol {

    /// Queue of responses to return in order. Each call pops the front element.
    static var responseQueue: [Result<Data, Error>] = []

    static func enqueue(_ data: Data) {
        responseQueue.append(.success(data))
    }

    static func enqueueError(_ error: Error) {
        responseQueue.append(.failure(error))
    }

    static func reset() {
        responseQueue.removeAll()
    }

    // MARK: - URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool {
        return request.url?.host?.contains("lichess.org") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard !MockURLProtocol.responseQueue.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }

        let result = MockURLProtocol.responseQueue.removeFirst()

        switch result {
        case .success(let data):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
