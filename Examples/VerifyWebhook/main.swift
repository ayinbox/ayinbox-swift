import AyInbox
import Foundation

// Verifies a webhook delivery. Run with: swift run verify-webhook
// In a real handler, pass the raw request body and the X-Ayinbox-Signature header.
let secret = ProcessInfo.processInfo.environment["AYINBOX_WEBHOOK_SECRET"] ?? "whsec_test_secret"
let body = #"{"id":"00000000-0000-4000-8000-000000000001","event_type":"campaign.reply_received","organization_id":"00000000-0000-4000-8000-0000000000aa","created_at":"2023-11-14T22:13:20Z","data":{}}"#
let header = "t=1700000000,v1=d1efe3010ae2523566985158ab4852f8f3569365a06941ef87e3a641e3171342"

do {
    let event = try Webhooks().constructEvent(
        payload: Data(body.utf8),
        header: header,
        secret: secret,
        now: Date(timeIntervalSince1970: 1_700_000_000)
    )
    print("Verified \(event["event_type"]?.stringValue ?? "?") \(event["id"]?.stringValue ?? "?")")
} catch {
    print("Rejected: \(error.localizedDescription)")
}
