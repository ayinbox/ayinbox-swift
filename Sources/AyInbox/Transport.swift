import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One HTTP request as the SDK hands it to a transport.
public struct HTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval
}

/// One HTTP response. Header keys are lowercased.
public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }
}

/// Sends one HTTP request. Inject your own to add a proxy, logging or a test double.
/// Throw a `URLError` for a network failure (`.timedOut` maps to `AyInboxError.timeout`).
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// The default transport, built on `URLSession`.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = request.timeout
        urlRequest.httpBody = request.body
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let finalRequest = urlRequest
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: finalRequest) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                var headers: [String: String] = [:]
                for (key, value) in http.allHeaderFields {
                    headers[String(describing: key).lowercased()] = String(describing: value)
                }
                continuation.resume(returning: HTTPResponse(status: http.statusCode, headers: headers, body: data ?? Data()))
            }
            task.resume()
        }
    }
}
