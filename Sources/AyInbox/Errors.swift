import Foundation

/// What the API said when it refused a request.
public struct APIErrorInfo: Sendable, Equatable {
    public let status: Int
    /// Stable machine key. Branch on this and `status`, never on `message`.
    public let code: String
    public let message: String
    public let reason: String?
    public let requestId: String?
    /// Seconds to wait, from `Retry-After`, `retry_after` or `retry_after_ms`.
    public let retryAfter: Double?
    /// The decoded body, or `nil` when it was not JSON.
    public let body: JSONValue?
    /// The raw body text.
    public let rawBody: String
    /// Response headers, keys lowercased.
    public let headers: [String: String]
}

/// Every error the SDK throws.
public enum AyInboxError: Error, Sendable {
    case badRequest(APIErrorInfo)
    case authentication(APIErrorInfo)
    case paymentRequired(APIErrorInfo)
    case permissionDenied(APIErrorInfo)
    case notFound(APIErrorInfo)
    case conflict(APIErrorInfo)
    case unprocessable(APIErrorInfo)
    case rateLimit(APIErrorInfo)
    case internalServer(APIErrorInfo)
    case serviceUnavailable(APIErrorInfo)
    /// Any other non-2xx status.
    case api(APIErrorInfo)
    /// No answer: DNS, TLS or a dropped connection.
    case connection(String)
    /// The request took longer than its timeout.
    case timeout
    /// A webhook signature did not verify.
    case signatureVerification(String)
    /// A 2xx body did not match the expected shape.
    case decoding(String)
    /// The client is misconfigured, for example no API key.
    case configuration(String)

    /// The API error details, for HTTP errors.
    public var info: APIErrorInfo? {
        switch self {
        case .badRequest(let i), .authentication(let i), .paymentRequired(let i), .permissionDenied(let i),
             .notFound(let i), .conflict(let i), .unprocessable(let i), .rateLimit(let i),
             .internalServer(let i), .serviceUnavailable(let i), .api(let i):
            return i
        default:
            return nil
        }
    }

    public var status: Int? { info?.status }
    public var code: String? { info?.code }
    public var requestId: String? { info?.requestId }
    /// True for 400 and 422.
    public var isValidation: Bool {
        switch self {
        case .badRequest, .unprocessable: return true
        default: return false
        }
    }

    static func from(status: Int, headers: [String: String], data: Data) -> AyInboxError {
        let raw = String(decoding: data, as: UTF8.self)
        let body = try? JSONDecoder().decode(JSONValue.self, from: data)
        let object = body?.objectValue
        var code = object?["code"]?.stringValue
        if code == nil || code!.isEmpty, let err = object?["error"]?.stringValue,
           !err.isEmpty, err.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }) {
            code = err
        }
        var retryAfter: Double?
        if let header = headers["retry-after"], let seconds = Double(header.trimmingCharacters(in: .whitespaces)) {
            retryAfter = seconds
        } else if let seconds = object?["retry_after"]?.doubleValue {
            retryAfter = seconds
        } else if let ms = object?["retry_after_ms"]?.doubleValue {
            retryAfter = (ms / 1000).rounded(.up)
        }
        let info = APIErrorInfo(
            status: status,
            code: (code?.isEmpty == false ? code! : defaultCode(status)),
            message: object?["message"]?.stringValue ?? raw,
            reason: object?["reason"]?.stringValue,
            requestId: object?["request_id"]?.stringValue ?? headers["x-request-id"],
            retryAfter: retryAfter,
            body: body,
            rawBody: raw,
            headers: headers
        )
        switch status {
        case 400: return .badRequest(info)
        case 401: return .authentication(info)
        case 402: return .paymentRequired(info)
        case 403: return .permissionDenied(info)
        case 404: return .notFound(info)
        case 409: return .conflict(info)
        case 422: return .unprocessable(info)
        case 429: return .rateLimit(info)
        case 503: return .serviceUnavailable(info)
        case 500...599: return .internalServer(info)
        default: return .api(info)
        }
    }

    static func defaultCode(_ status: Int) -> String {
        switch status {
        case 400: return "bad_request"
        case 401: return "unauthorized"
        case 402: return "insufficient_credits"
        case 403: return "forbidden"
        case 404: return "not_found"
        case 409: return "conflict"
        case 422: return "unprocessable"
        case 429: return "rate_limit_exceeded"
        case 501: return "not_implemented"
        case 503: return "service_unavailable"
        case 500...599: return "internal_error"
        default: return "http_\(status)"
        }
    }
}

extension AyInboxError: LocalizedError {
    public var errorDescription: String? {
        if let info {
            var text = "AY Inbox API error \(info.status) \(info.code): \(info.message)"
            if let id = info.requestId { text += " (request \(id))" }
            return text
        }
        switch self {
        case .connection(let m): return "Connection error: \(m)"
        case .timeout: return "The request timed out"
        case .signatureVerification(let m): return "Webhook signature verification failed: \(m)"
        case .decoding(let m): return "Could not decode the response: \(m)"
        case .configuration(let m): return m
        default: return nil
        }
    }
}
