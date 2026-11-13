import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Per-call options.
public struct RequestOptions: Sendable {
    /// Sent as `Idempotency-Key`. The server replays the first answer for 24 hours.
    public var idempotencyKey: String?
    /// Overrides the client timeout for this call, per attempt.
    public var timeout: TimeInterval?
    /// Extra headers for this call.
    public var headers: [String: String]

    public init(idempotencyKey: String? = nil, timeout: TimeInterval? = nil, headers: [String: String] = [:]) {
        self.idempotencyKey = idempotencyKey
        self.timeout = timeout
        self.headers = headers
    }
}

/// A raw response from `requestRaw`.
public struct RawResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
}

/// The AY Inbox API client.
public final class AyInbox: @unchecked Sendable, CustomStringConvertible {
    public static let version = "0.1.0"
    public static let defaultBaseURL = "https://api.ayinbox.com/v1"

    public let baseURL: String
    public let timeout: TimeInterval
    public let maxRetries: Int
    private let apiKey: String
    private let transport: HTTPTransport
    let sleeper: @Sendable (Double) async throws -> Void

    public var me: MeResource { MeResource(client: self) }
    public var campaigns: CampaignsResource { CampaignsResource(client: self) }
    public var contacts: ContactsResource { ContactsResource(client: self) }
    public var mailboxes: MailboxesResource { MailboxesResource(client: self) }
    public var unibox: UniboxResource { UniboxResource(client: self) }
    public var webhooks: Webhooks { Webhooks() }

    /// - Parameters:
    ///   - apiKey: An API key (`aybox_...`) or OAuth access token (`ayat_...`). Falls back to `AYINBOX_API_KEY`.
    ///   - baseURL: Falls back to `AYINBOX_BASE_URL`, then `https://api.ayinbox.com/v1`.
    ///   - timeout: Seconds per attempt. Default 30.
    ///   - maxRetries: Retries after the first attempt. Default 2; 0 turns them off.
    ///   - transport: Sends the HTTP requests. Default `URLSessionTransport()`.
    public convenience init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        timeout: TimeInterval = 30,
        maxRetries: Int = 2,
        transport: HTTPTransport = URLSessionTransport()
    ) throws {
        try self.init(apiKey: apiKey, baseURL: baseURL, timeout: timeout, maxRetries: maxRetries, transport: transport,
                      sleeper: { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) })
    }

    init(
        apiKey: String?,
        baseURL: String?,
        timeout: TimeInterval,
        maxRetries: Int,
        transport: HTTPTransport,
        sleeper: @escaping @Sendable (Double) async throws -> Void
    ) throws {
        let env = ProcessInfo.processInfo.environment
        guard let key = apiKey ?? env["AYINBOX_API_KEY"], !key.isEmpty else {
            throw AyInboxError.configuration("No API key: pass apiKey or set AYINBOX_API_KEY.")
        }
        var base = baseURL ?? env["AYINBOX_BASE_URL"] ?? AyInbox.defaultBaseURL
        if base.isEmpty { base = AyInbox.defaultBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        self.apiKey = key
        self.baseURL = base
        self.timeout = timeout
        self.maxRetries = max(0, maxRetries)
        self.transport = transport
        self.sleeper = sleeper
    }

    public var description: String { "AyInbox(baseURL: \(baseURL), apiKey: [redacted])" }

    // MARK: Generic request

    /// Calls any route. `path` is relative to the base URL, for example `/campaigns-overview`.
    /// Returns the decoded JSON, `.null` for an empty body, or `.string` with the text of a non-JSON body.
    @discardableResult
    public func request(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: JSONValue? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> JSONValue {
        let response = try await requestRaw(method, path, query: query, body: body, options: options)
        if response.body.isEmpty { return .null }
        if let value = try? JSONDecoder().decode(JSONValue.self, from: response.body) { return value }
        return .string(String(decoding: response.body, as: UTF8.self))
    }

    /// Calls any route and decodes the body into `T`.
    public func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: JSONValue? = nil,
        options: RequestOptions = RequestOptions(),
        as type: T.Type
    ) async throws -> T {
        let response = try await requestRaw(method, path, query: query, body: body, options: options)
        return try decode(T.self, from: response.body)
    }

    /// Calls any route and returns the status, headers and raw bytes.
    public func requestRaw(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: JSONValue? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> RawResponse {
        let data = try body.map { try JSONEncoder().encode($0) }
        let response = try await perform(method, path, query: sortedQuery(query), body: data, options: options)
        return RawResponse(status: response.status, headers: response.headers, body: response.body)
    }

    /// Walks every page of a paginated route, following `next_cursor`.
    /// For `POST /contacts/search` pass `method: "POST"` and the search body; it is resent on every page.
    public func paginate(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: JSONValue? = nil,
        options: RequestOptions = RequestOptions()
    ) -> PageSequence<JSONValue> {
        PageSequence { cursor in
            var q = query
            if let cursor { q["cursor"] = cursor }
            let data = try body.map { try JSONEncoder().encode($0) }
            let response = try await self.perform(method, path, query: self.sortedQuery(q), body: data,
                                                  options: options, readOnly: true)
            return try self.decode(Page<JSONValue>.self, from: response.body)
        }
    }

    // MARK: Internals

    func sortedQuery(_ query: [String: String]) -> [(String, String)] {
        query.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [(String, String)] = [],
        body: Encodable? = nil,
        options: RequestOptions,
        readOnly: Bool = false,
        as type: T.Type
    ) async throws -> T {
        var data: Data?
        if let body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            data = try encoder.encode(AnyEncodable(body))
        }
        let response = try await perform(method, path, query: query, body: data, options: options, readOnly: readOnly)
        return try decode(T.self, from: response.body)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do {
            return try AyInbox.decoder.decode(T.self, from: data.isEmpty ? Data("null".utf8) : data)
        } catch {
            throw AyInboxError.decoding(String(describing: error))
        }
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseRFC3339(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an RFC 3339 time: \(text)")
            }
            return date
        }
        return decoder
    }

    func perform(
        _ method: String,
        _ path: String,
        query: [(String, String)],
        body: Data?,
        options: RequestOptions,
        readOnly: Bool = false
    ) async throws -> HTTPResponse {
        let upper = method.uppercased()
        guard let url = URL(string: baseURL + (path.hasPrefix("/") ? path : "/" + path) + encodeQuery(query)) else {
            throw AyInboxError.configuration("Invalid URL for path \(path)")
        }
        var headers: [String: String] = [
            "Authorization": "Bearer \(apiKey)",
            "User-Agent": "ayinbox-swift/\(AyInbox.version)",
            "Accept": "application/json",
        ]
        if body != nil { headers["Content-Type"] = "application/json" }
        if let key = options.idempotencyKey { headers["Idempotency-Key"] = key }
        for (name, value) in options.headers {
            if let existing = headers.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                headers.removeValue(forKey: existing)
            }
            headers[name] = value
        }
        let request = HTTPRequest(method: upper, url: url, headers: headers, body: body,
                                  timeout: options.timeout ?? timeout)
        // A POST or PATCH without a key may have run; only a 429 proves it did not.
        let replaySafe = readOnly || options.idempotencyKey != nil || !(upper == "POST" || upper == "PATCH")

        var attempt = 0
        while true {
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch let error as AyInboxError {
                throw error
            } catch {
                let mapped = AyInboxError.fromTransport(error)
                if attempt < maxRetries, replaySafe {
                    try await sleeper(backoff(attempt: attempt, retryAfter: nil))
                    attempt += 1
                    continue
                }
                throw mapped
            }
            if (200..<300).contains(response.status) { return response }
            let error = AyInboxError.from(status: response.status, headers: response.headers, data: response.body)
            let retryable = response.status == 429 || ([502, 503, 504].contains(response.status) && replaySafe)
            if retryable, attempt < maxRetries, error.code != "idempotency_outcome_unknown" {
                try await sleeper(backoff(attempt: attempt, retryAfter: error.info?.retryAfter))
                attempt += 1
                continue
            }
            throw error
        }
    }

    func backoff(attempt: Int, retryAfter: Double?) -> Double {
        if let retryAfter, retryAfter >= 0 { return min(retryAfter, 120) }
        let ceiling = min(8.0, 0.5 * pow(2.0, Double(attempt)))
        return Double.random(in: 0...ceiling)
    }

    func encodeQuery(_ query: [(String, String)]) -> String {
        if query.isEmpty { return "" }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let parts = query.map { key, value in
            "\(key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return "?" + parts.joined(separator: "&")
    }
}

extension AyInboxError {
    static func fromTransport(_ error: Error) -> AyInboxError {
        if let urlError = error as? URLError {
            if urlError.code == .timedOut { return .timeout }
            return .connection(urlError.localizedDescription)
        }
        return .connection(String(describing: error))
    }
}

struct EmptyResponse: Decodable {}

struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Parses an RFC 3339 time with or without fractional seconds.
func parseRFC3339(_ text: String) -> Date? {
    var base = text
    var fraction = 0.0
    if let dot = text.firstIndex(of: "."), let tIndex = text.firstIndex(where: { $0 == "T" || $0 == "t" }), dot > tIndex {
        var end = text.index(after: dot)
        while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
        fraction = Double("0" + text[dot..<end]) ?? 0
        base = String(text[..<dot]) + String(text[end...])
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    guard let date = formatter.date(from: base) else { return nil }
    return date.addingTimeInterval(fraction)
}
