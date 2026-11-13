# AY Inbox Swift SDK

The official Swift client for the [AY Inbox](https://ayinbox.com) REST API. It runs on macOS, iOS, tvOS, watchOS and Linux.

AY Inbox is a hosted cold email platform. It sends cold email at a paced daily volume, brings every reply into one inbox (Unibox), drafts answers from a per-campaign brain and can offer a meeting time from Cal.com or Calendly.

AY Inbox is a hosted service. This repository holds the Swift client library for its public REST API. The service itself is not open source.

Access to the hosted service is invite only for now: ask at team@ayinbox.com.

## Install

Add the package with Swift Package Manager:

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ayinbox/ayinbox-swift.git", from: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "AyInbox", package: "ayinbox-swift")]),
]
```

In Xcode, use File > Add Package Dependencies with the same URL. It needs Swift 5.9 or later and macOS 12, iOS 15, tvOS 15, watchOS 8 or Linux.

## Quick start

```swift
import AyInbox

let client = try AyInbox() // reads AYINBOX_API_KEY
let me = try await client.me.get()
print("Signed in as \(me.email ?? "") with \(me.scopes ?? [])")

for try await campaign in client.campaigns.listAll() {
    print("\(campaign.name ?? ""): \(campaign.status ?? "")")
}

do {
    let saved = try await client.contacts.create(
        ContactInput(email: "lee@example.com", firstName: "Lee"),
        options: RequestOptions(idempotencyKey: "contact-lee-2026-11-13")
    )
    print("Saved \(saved.first?.id ?? "")")
} catch AyInboxError.permissionDenied(let info) {
    print("Missing scope: \(info.code) (request \(info.requestId ?? "-"))")
}
```

## Configuration

| Argument | Default | Notes |
|---|---|---|
| `apiKey` | `AYINBOX_API_KEY` | An API key (`aybox_...`) or an OAuth access token (`ayat_...`), sent as `Authorization: Bearer`. The initializer throws when there is none. |
| `baseURL` | `AYINBOX_BASE_URL`, then `https://api.ayinbox.com/v1` | A trailing slash is removed. |
| `timeout` | 30 seconds | Per attempt. |
| `maxRetries` | 2 | Retries after the first attempt. 0 turns them off. |
| `transport` | `URLSessionTransport()` | Any type that conforms to `HTTPTransport`. Pass `URLSessionTransport(session:)` for your own `URLSession`, or your own type for a proxy, logging or tests. |

The key never appears in `description`, in error messages or in errors. On iOS, tvOS and watchOS there is no environment to read in a shipped app: pass `apiKey` yourself, and never ship a secret key inside an app.

## Resources

| Resource | Method | HTTP route | Scope |
|---|---|---|---|
| `me` | `get()` | `GET /me` | none |
| `campaigns` | `list()`, `listAll()` | `GET /campaigns` | `READ_CAMPAIGNS` |
| `campaigns` | `get(_:)` | `GET /campaigns/{id}` | `READ_CAMPAIGNS` |
| `campaigns` | `create(name:fields:)` | `POST /campaigns` | `WRITE_CAMPAIGNS` |
| `campaigns` | `pause(_:)` | `POST /campaigns/{id}/stop` | `WRITE_CAMPAIGNS`, `START_CAMPAIGNS` or `SEND_CAMPAIGNS` |
| `contacts` | `list()`, `listAll()` | `POST /contacts/search` | `READ_CONTACTS` |
| `contacts` | `get(_:)` | `GET /contacts/{id}` | `READ_CONTACTS` |
| `contacts` | `create(_:)` | `POST /contacts` | `WRITE_CONTACTS` |
| `contacts` | `update(_:fields:)` | `PATCH /contacts/{id}` | `WRITE_CONTACTS` |
| `contacts` | `delete(_:)` | `DELETE /contacts/{id}` | `WRITE_CONTACTS` |
| `mailboxes` | `list()`, `listAll()` | `GET /emails` | `READ_EMAILS` |
| `unibox` | `listThreads()`, `listThreadsAll()` | `GET /unibox` | `READ_UNIBOX` |
| `unibox` | `getThread(threadId:)` | `GET /unibox/thread` | `READ_UNIBOX` |
| `webhooks` | `verifySignature()`, `constructEvent()` | local, no HTTP | none |

Results are `Codable` structs (`Identity`, `Campaign`, `Contact`, `Mailbox`, `MessagePreview`) with camel-case properties for the documented fields. Every property is optional except `id`, unknown fields are ignored, and fields whose shape the API does not pin down (`lead_score`, `campaign_lead`, `engagement`, `schedule_windows` and similar) are a `JSONValue`.

Every other route is reachable through `request`, with the same authentication, retries and errors:

```swift
let overview = try await client.request("GET", "/campaigns-overview")
print(overview["active"]?.intValue ?? 0)

let started = try await client.request(
    "POST", "/campaigns/\(campaignId)/start",
    options: RequestOptions(idempotencyKey: "start-q4")
)

struct Overview: Decodable { let total: Int; let active: Int }
let typed = try await client.request("GET", "/campaigns-overview", as: Overview.self)
```

`request` returns a `JSONValue`: the decoded JSON, `.null` for an empty body, or `.string` with the text of a non-JSON body. `requestRaw` returns the status, headers and bytes.

## Errors

Every error is an `AyInboxError`. HTTP errors carry an `APIErrorInfo` with `status`, `code`, `message`, `reason`, `requestId`, `retryAfter`, the decoded `body`, the raw body text and the response `headers`. Branch on `code` and `status`, never on `message`.

| Case | Status |
|---|---|
| `.badRequest` | 400 |
| `.authentication` | 401 |
| `.paymentRequired` | 402 |
| `.permissionDenied` | 403 |
| `.notFound` | 404 |
| `.conflict` | 409 |
| `.unprocessable` | 422 |
| `.rateLimit` (with `retryAfter`) | 429 |
| `.internalServer` | 500, 501, 502, 504 and other 5xx |
| `.serviceUnavailable` (with `retryAfter`) | 503 |
| `.api` | any other non-2xx status |
| `.connection` | no answer: DNS, TLS, dropped connection |
| `.timeout` | the request took longer than its timeout |
| `.signatureVerification` | a webhook signature did not verify |
| `.decoding` | a 2xx body did not have the expected shape |
| `.configuration` | no API key, or an invalid URL |

`error.status`, `error.code`, `error.requestId` and `error.isValidation` (400 or 422) work on any case. Some 429 answers carry no `code` and no `request_id`; the SDK still reports `.rateLimit` with code `rate_limit_exceeded` and reads the wait from `Retry-After`, `retry_after` or `retry_after_ms`.

## Retries and timeouts

The SDK retries 429, 502, 503, 504, connection errors and timeouts, up to `maxRetries` times. It waits for `Retry-After` when the server sends one (capped at 120 seconds), otherwise an exponential backoff with full jitter (base 0.5 seconds, cap 8 seconds).

A `POST` or `PATCH` without an idempotency key is never retried, except on 429 (the server did not run the request). A 500 is never retried, and neither is `409 idempotency_outcome_unknown`. `contacts.list` is a POST that only reads, so it is retried like a GET.

Override the timeout for one call with `RequestOptions(timeout: 60)`, and add headers with `RequestOptions(headers: [...])`.

## Pagination

`list` methods return one `Page` with `data`, `nextCursor`, `hasMore` and an optional `total`. Pass `nextCursor` back as `cursor` for the next page. The `listAll` methods return a `PageSequence`, an `AsyncSequence` that follows the cursor for you:

```swift
for try await contact in client.contacts.listAll(search: ["query": "acme"]) {
    print(contact.email ?? "")
}
```

For any other paginated route, use `client.paginate("/suppressions")` (or `client.paginate("/contacts/search", method: "POST", body: [...])`), which yields `JSONValue` rows. Use a `limit` between 1 and 100.

## Idempotency

Every call takes `RequestOptions(idempotencyKey: "...")`, sent as the `Idempotency-Key` header and reused on every retry of that call. The server keeps the outcome for 24 hours: the same key with the same request replays the first answer, and the same key with a different request answers `409`. The SDK does not generate keys for you, so a POST or PATCH you want retried needs one you choose. Use a new key for each distinct change.

## Webhooks

Verify each delivery against the raw body before parsing it. The secret is the endpoint secret including its `whsec_` prefix.

```swift
let event = try Webhooks().constructEvent(
    payload: rawBody, // Data, exactly as received
    header: signatureHeader, // X-Ayinbox-Signature
    secret: endpointSecret
) // throws AyInboxError.signatureVerification
print(event["event_type"]?.stringValue ?? "")
```

`verifySignature` returns a `Bool` instead. Both reject a timestamp more than 300 seconds from now (change it with `tolerance`) and compare in constant time. HMAC-SHA256 comes from `swift-crypto`, so it works on Linux too. Deduplicate on the event `id`, which equals the `X-Ayinbox-Event-Id` header.

## Calls that send email

- These calls put real email on the wire:
  - `campaigns.start` (`POST /campaigns/{id}/start`, through `request`): needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS`.
  - `campaigns.update` (`PATCH /campaigns/{id}`, through `request`) with `status: "active"` (and `completed` or `paused_undeliverable`): needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS` in addition to `WRITE_CAMPAIGNS`.
  - `campaigns.leads.resume` (`POST /campaigns/{id}/leads/{contactId}/resume`, through `request`) on a finished campaign: needs `START_CAMPAIGNS` or `SEND_CAMPAIGNS`.
  - `unibox.reply` (`POST /unibox/reply`) and `unibox.approveAgentDraft` (`POST /unibox/agent-drafts/{id}/approve`), through `request`: need `WRITE_UNIBOX`. A key with `WRITE_UNIBOX` can send replies from any mailbox it can reach.
  - Through `request`: `POST /unibox/compose`, `POST /emails/{id}/send`, `POST /campaigns/{id}/test-email`, the first-email review queue (`/campaigns/{id}/reviews/...`), placement tests: `SEND_CAMPAIGNS` (compose: `WRITE_UNIBOX`).
- Adding contacts can send mail without calling start: contacts added to an `active` campaign are queued; a `completed` campaign starts again on its own when leads are added; a contact that comes to match a segment linked to a sending campaign is enrolled. This applies to `contacts.create` and `contacts.update` with `campaigns`.
- `START_CAMPAIGNS` starts, resumes and pauses campaigns and nothing else. `SEND_CAMPAIGNS` covers everything `START_CAMPAIGNS` covers plus the other sending actions. `WRITE_CAMPAIGNS` alone edits drafts and pauses, and cannot start anything.
- A key for a model that reads the inbox should use the "Agent: read and draft" preset (84574239): every read scope plus `AI_DRAFT`, with nothing that writes or sends.
- Some calls spend workspace credits (AI drafts, research, enrichment, paid tools). They answer `402 insufficient_credits` when the balance is out.
- Retrying a send without an idempotency key can send twice. Pass an idempotency key on every mutating call you might retry.

## Examples

- [`Examples/ListCampaigns/main.swift`](Examples/ListCampaigns/main.swift): list every campaign.
- [`Examples/VerifyWebhook/main.swift`](Examples/VerifyWebhook/main.swift): verify a webhook delivery.

Run them from a checkout with `AYINBOX_API_KEY=aybox_... swift run list-campaigns` and `swift run verify-webhook`.

## Documentation

- API reference: https://docs.ayinbox.com/api/
- Endpoints and scopes: https://docs.ayinbox.com/api/endpoints/
- Permissions: https://docs.ayinbox.com/api/permissions/
- Error codes: https://docs.ayinbox.com/api/error-codes/

## License

MIT. See [LICENSE](LICENSE).
