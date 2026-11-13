import Crypto
import Foundation

/// Verifies webhook deliveries. Needs no client or key.
public struct Webhooks: Sendable {
    public static let defaultTolerance: TimeInterval = 300

    public init() {}

    /// True when `header` (`X-Ayinbox-Signature`) signs `payload` with `secret` within `tolerance` seconds of `now`.
    /// `payload` must be the raw request body, before any JSON parsing. `secret` keeps its `whsec_` prefix.
    public func verifySignature(
        payload: Data, header: String, secret: String,
        tolerance: TimeInterval = Webhooks.defaultTolerance, now: Date = Date()
    ) -> Bool {
        (try? check(payload: payload, header: header, secret: secret, tolerance: tolerance, now: now)) != nil
    }

    public func verifySignature(
        payload: String, header: String, secret: String,
        tolerance: TimeInterval = Webhooks.defaultTolerance, now: Date = Date()
    ) -> Bool {
        verifySignature(payload: Data(payload.utf8), header: header, secret: secret, tolerance: tolerance, now: now)
    }

    /// Verifies the signature, then parses the event. Throws `AyInboxError.signatureVerification` on failure.
    public func constructEvent(
        payload: Data, header: String, secret: String,
        tolerance: TimeInterval = Webhooks.defaultTolerance, now: Date = Date()
    ) throws -> JSONValue {
        try check(payload: payload, header: header, secret: secret, tolerance: tolerance, now: now)
        do {
            return try JSONDecoder().decode(JSONValue.self, from: payload)
        } catch {
            throw AyInboxError.signatureVerification("payload is not JSON")
        }
    }

    func check(payload: Data, header: String, secret: String, tolerance: TimeInterval, now: Date) throws {
        var timestamp: Int64?
        var signatures: [String] = []
        for part in header.split(separator: ",") {
            guard let eq = part.firstIndex(of: "=") else { continue }
            let key = part[..<eq].trimmingCharacters(in: .whitespaces)
            let value = part[part.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if key == "t" { timestamp = Int64(value) } else if key == "v1" { signatures.append(value) }
        }
        guard let timestamp else { throw AyInboxError.signatureVerification("no timestamp in header") }
        guard !signatures.isEmpty else { throw AyInboxError.signatureVerification("no v1 signature in header") }
        guard abs(now.timeIntervalSince1970 - Double(timestamp)) <= tolerance else {
            throw AyInboxError.signatureVerification("timestamp outside the tolerance")
        }
        var message = Data("\(timestamp).".utf8)
        message.append(payload)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: Data(secret.utf8)))
        let expected = Array(mac.map { String(format: "%02x", $0) }.joined().utf8)
        for signature in signatures where constantTimeEqual(expected, Array(signature.lowercased().utf8)) {
            return
        }
        throw AyInboxError.signatureVerification("signature does not match")
    }
}

func constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count { diff |= a[i] ^ b[i] }
    return diff == 0
}
