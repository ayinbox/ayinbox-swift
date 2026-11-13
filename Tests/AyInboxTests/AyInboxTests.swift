import Foundation
import XCTest
@testable import AyInbox

extension NSLock {
    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

final class MockTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (HTTPRequest) throws -> HTTPResponse
    private let lock = NSLock()
    private var handlers: [Handler]
    private(set) var requests: [HTTPRequest] = []

    init(_ handlers: [Handler]) { self.handlers = handlers }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let handler: Handler = lock.locked {
            requests.append(request)
            return handlers.count > 1 ? handlers.removeFirst() : handlers[0]
        }
        return try handler(request)
    }
}

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: "Fixtures/" + name, withExtension: nil)!
    return try! Data(contentsOf: url)
}

let successHeaders = ["Content-Type": "application/json; charset=utf-8", "X-Request-Id": "req-fixture-0001"]

func ok(_ name: String, status: Int = 200) -> MockTransport.Handler {
    { _ in HTTPResponse(status: status, headers: successHeaders, body: fixture(name)) }
}

func errorFixture(_ status: Int, _ name: String, _ extra: [String: String] = [:]) -> MockTransport.Handler {
    { _ in
        var headers = successHeaders
        for (k, v) in extra { headers[k] = v }
        return HTTPResponse(status: status, headers: headers, body: fixture("errors/" + name))
    }
}

final class Sleeps: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var all: [Double] { lock.locked { values } }
    func record(_ v: Double) { lock.locked { values.append(v) } }
}

func makeClient(_ transport: MockTransport, maxRetries: Int = 2, sleeps: Sleeps = Sleeps()) throws -> AyInbox {
    try AyInbox(apiKey: "aybox_testkey", baseURL: "https://api.test/v1/", timeout: 30, maxRetries: maxRetries,
                transport: transport, sleeper: { sleeps.record($0) })
}

final class ClientTests: XCTestCase {
    func testHeadersAndMe() async throws {
        let transport = MockTransport([ok("me.json")])
        let client = try makeClient(transport)
        let me = try await client.me.get()
        XCTAssertEqual(me.email, "dana@example.com")
        XCTAssertEqual(me.authType, "api_key")
        XCTAssertEqual(me.scopes?.count, 3)
        let request = transport.requests[0]
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://api.test/v1/me")
        XCTAssertEqual(request.headers["Authorization"], "Bearer aybox_testkey")
        XCTAssertEqual(request.headers["User-Agent"], "ayinbox-swift/0.1.0")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertNil(request.headers["Idempotency-Key"])
        XCTAssertFalse(client.description.contains("aybox_testkey"))
    }

    func testMissingKeyIsConfigurationError() {
        XCTAssertThrowsError(try AyInbox(apiKey: "", transport: MockTransport([ok("me.json")])))
    }

    func testTypedErrors() async throws {
        let cases: [(Int, String, String)] = [
            (400, "400_bad_request.json", "bad_request"),
            (400, "400_invalid_cursor.json", "bad_request"),
            (401, "401_unauthorized.json", "unauthorized"),
            (401, "401_api_key_holder_left.json", "api_key_holder_left"),
            (402, "402_insufficient_credits.json", "insufficient_credits"),
            (403, "403_forbidden.json", "forbidden"),
            (403, "403_api_key_mailbox_limited.json", "api_key_mailbox_limited"),
            (404, "404_not_found.json", "not_found"),
            (409, "409_conflict.json", "conflict"),
            (409, "409_idempotency_outcome_unknown.json", "idempotency_outcome_unknown"),
            (409, "409_idempotent_secret_withheld.json", "idempotent_secret_withheld"),
            (422, "422_unprocessable.json", "unprocessable"),
            (500, "500_internal_error.json", "internal_error"),
        ]
        for (status, name, code) in cases {
            let client = try makeClient(MockTransport([errorFixture(status, name)]), maxRetries: 0)
            do {
                _ = try await client.me.get()
                XCTFail("expected an error for \(name)")
            } catch let error as AyInboxError {
                XCTAssertEqual(error.status, status, name)
                XCTAssertEqual(error.code, code, name)
                XCTAssertEqual(error.requestId, "req-fixture-0001", name)
                switch (status, error) {
                case (400, .badRequest), (401, .authentication), (402, .paymentRequired), (403, .permissionDenied),
                     (404, .notFound), (409, .conflict), (422, .unprocessable), (500, .internalServer):
                    break
                default:
                    XCTFail("wrong case \(error) for \(name)")
                }
                XCTAssertFalse(error.localizedDescription.contains("aybox_testkey"))
            }
        }
    }

    func testValidationGrouping() {
        let info = APIErrorInfo(status: 422, code: "unprocessable", message: "", reason: nil, requestId: nil,
                                retryAfter: nil, body: nil, rawBody: "", headers: [:])
        XCTAssertTrue(AyInboxError.unprocessable(info).isValidation)
        XCTAssertFalse(AyInboxError.notFound(info).isValidation)
    }

    func testRateLimitWithoutCode() async throws {
        let transport = MockTransport([{ _ in
            HTTPResponse(status: 429, headers: ["Content-Type": "application/json"],
                         body: fixture("errors/429_category_rate_limited.json"))
        }])
        let client = try makeClient(transport, maxRetries: 0)
        do {
            _ = try await client.me.get()
            XCTFail("expected rate limit")
        } catch let AyInboxError.rateLimit(info) {
            XCTAssertEqual(info.code, "rate_limit_exceeded")
            XCTAssertNil(info.requestId)
            XCTAssertEqual(info.retryAfter, 12)
        }
    }

    func testApiKeyRateLimitBody() async throws {
        let transport = MockTransport([{ _ in
            HTTPResponse(status: 429, body: fixture("errors/429_api_key_rate_limited.json"))
        }])
        let client = try makeClient(transport, maxRetries: 0)
        do {
            _ = try await client.me.get()
            XCTFail("expected rate limit")
        } catch let AyInboxError.rateLimit(info) {
            XCTAssertEqual(info.code, "rate_limit_exceeded")
            XCTAssertEqual(info.retryAfter, 12)
            XCTAssertEqual(info.requestId, "req-fixture-0001")
        }
    }

    func testNonJSONErrorBody() async throws {
        let transport = MockTransport([{ _ in HTTPResponse(status: 502, body: Data("bad gateway".utf8)) }])
        let client = try makeClient(transport, maxRetries: 0)
        do {
            _ = try await client.me.get()
            XCTFail("expected error")
        } catch let AyInboxError.internalServer(info) {
            XCTAssertEqual(info.code, "internal_error")
            XCTAssertEqual(info.rawBody, "bad gateway")
        }
    }

    func testRetryOn503ThenSuccess() async throws {
        let sleeps = Sleeps()
        let transport = MockTransport([errorFixture(503, "503_service_unavailable.json", ["Retry-After": "5"]), ok("me.json")])
        let client = try makeClient(transport, sleeps: sleeps)
        let me = try await client.me.get()
        XCTAssertEqual(me.firstName, "Dana")
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(sleeps.all, [5])
    }

    func testRetryOn429WithRetryAfterThenSuccess() async throws {
        let sleeps = Sleeps()
        let transport = MockTransport([errorFixture(429, "429_api_key_rate_limited.json", ["Retry-After": "12"]), ok("me.json")])
        let client = try makeClient(transport, sleeps: sleeps)
        _ = try await client.me.get()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(sleeps.all, [12])
    }

    func testKeylessPostIsNotRetriedOn503() async throws {
        let transport = MockTransport([errorFixture(503, "503_service_unavailable.json"), ok("campaign.json")])
        let client = try makeClient(transport)
        do {
            _ = try await client.campaigns.create(name: "Q4")
            XCTFail("expected error")
        } catch AyInboxError.serviceUnavailable {
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testKeylessPostIsNotRetriedOnConnectionError() async throws {
        let transport = MockTransport([{ _ in throw URLError(.networkConnectionLost) }, ok("campaign.json")])
        let client = try makeClient(transport)
        do {
            _ = try await client.campaigns.create(name: "Q4")
            XCTFail("expected error")
        } catch AyInboxError.connection {
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testKeylessPostIsRetriedOn429() async throws {
        let transport = MockTransport([errorFixture(429, "429_category_rate_limited.json"), ok("campaign.json")])
        let client = try makeClient(transport)
        _ = try await client.campaigns.create(name: "Q4")
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testPostWithKeyIsRetriedWithSameKey() async throws {
        let transport = MockTransport([errorFixture(503, "503_service_unavailable.json"), ok("campaign.json")])
        let client = try makeClient(transport)
        _ = try await client.campaigns.create(name: "Q4", options: RequestOptions(idempotencyKey: "create-q4"))
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests.map { $0.headers["Idempotency-Key"] }, ["create-q4", "create-q4"])
    }

    func testTimeoutIsRetriedForGetAndMapped() async throws {
        let transport = MockTransport([{ _ in throw URLError(.timedOut) }])
        let client = try makeClient(transport, maxRetries: 1)
        do {
            _ = try await client.me.get()
            XCTFail("expected timeout")
        } catch AyInboxError.timeout {
            XCTAssertEqual(transport.requests.count, 2)
        }
    }

    func test500IsNotRetried() async throws {
        let transport = MockTransport([errorFixture(500, "500_internal_error.json"), ok("me.json")])
        let client = try makeClient(transport)
        do {
            _ = try await client.me.get()
            XCTFail("expected error")
        } catch AyInboxError.internalServer {
            XCTAssertEqual(transport.requests.count, 1)
        }
    }

    func testBackoffIsBounded() throws {
        let client = try makeClient(MockTransport([ok("me.json")]))
        for attempt in 0..<10 {
            XCTAssertLessThanOrEqual(client.backoff(attempt: attempt, retryAfter: nil), 8)
        }
        XCTAssertEqual(client.backoff(attempt: 0, retryAfter: 600), 120)
    }

    func testPaginatedWalkAcrossTwoPages() async throws {
        let transport = MockTransport([ok("campaigns_list.json"), ok("campaigns_list_page2.json")])
        let client = try makeClient(transport)
        var names: [String] = []
        for try await campaign in client.campaigns.listAll(limit: 2) {
            names.append(campaign.name ?? "")
        }
        XCTAssertEqual(names, ["Q4 outreach", "Webinar follow-up", "Partner intro"])
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url.query, "limit=2")
        XCTAssertEqual(transport.requests[1].url.query, "cursor=c1_ZmFrZS1jdXJzb3ItcGFnZS0y&limit=2")
    }

    func testGenericPaginate() async throws {
        let transport = MockTransport([ok("campaigns_list.json"), ok("campaigns_list_page2.json")])
        let client = try makeClient(transport)
        var count = 0
        for try await row in client.paginate("/campaigns") {
            XCTAssertNotNil(row["id"]?.stringValue)
            count += 1
        }
        XCTAssertEqual(count, 3)
    }

    func testGenericRequest() async throws {
        let transport = MockTransport([ok("campaign_stop.json"), { _ in HTTPResponse(status: 204) }])
        let client = try makeClient(transport)
        let result = try await client.request("POST", "/campaigns/abc/stop", options: RequestOptions(idempotencyKey: "k1"))
        XCTAssertEqual(result["status"], "stopped")
        XCTAssertEqual(transport.requests[0].headers["Idempotency-Key"], "k1")
        let empty = try await client.request("DELETE", "/templates/abc")
        XCTAssertEqual(empty, .null)
    }
}

final class ResourceTests: XCTestCase {
    func testCampaigns() async throws {
        let transport = MockTransport([ok("campaigns_list.json"), ok("campaign.json"), ok("campaign.json"), ok("campaign_stop.json")])
        let client = try makeClient(transport)
        let page = try await client.campaigns.list(status: "active", limit: 10)
        XCTAssertEqual(page.data.count, 2)
        XCTAssertEqual(page.nextCursor, "c1_ZmFrZS1jdXJzb3ItcGFnZS0y")
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.total, 3)
        XCTAssertEqual(transport.requests[0].url.query, "status=active&limit=10")

        let campaign = try await client.campaigns.get("11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(campaign.dailyLimit, 50)
        XCTAssertEqual(campaign.senders?.first?.weight, 1)
        XCTAssertNotNil(campaign.createdAt)

        _ = try await client.campaigns.create(name: "Q4", fields: ["daily_limit": 30],
                                              options: RequestOptions(idempotencyKey: "idem-1"))
        let create = transport.requests[2]
        XCTAssertEqual(create.method, "POST")
        XCTAssertEqual(create.headers["Idempotency-Key"], "idem-1")
        XCTAssertEqual(create.headers["Content-Type"], "application/json")
        let body = try JSONDecoder().decode(JSONValue.self, from: create.body!)
        XCTAssertEqual(body, ["name": "Q4", "daily_limit": 30])

        let paused = try await client.campaigns.pause("abc")
        XCTAssertEqual(paused.status, "stopped")
        XCTAssertEqual(transport.requests[3].url.path, "/v1/campaigns/abc/stop")
    }

    func testContacts() async throws {
        let created = HTTPResponse(status: 200, body: fixture("contacts_create.json"))
        let first = try JSONDecoder().decode(JSONValue.self, from: fixture("contacts_create.json"))[0]!
        let transport = MockTransport([
            ok("contacts_list.json"), ok("contact.json"), { _ in created },
            { _ in HTTPResponse(status: 200, body: try JSONEncoder().encode(first)) },
            { _ in HTTPResponse(status: 204) },
        ])
        let client = try makeClient(transport)

        let page = try await client.contacts.list(search: ["query": "example"], limit: 50)
        XCTAssertEqual(page.data.count, 2)
        XCTAssertEqual(page.data[0].customFields?["title"], "Head of Ops")
        XCTAssertEqual(transport.requests[0].method, "POST")
        XCTAssertEqual(transport.requests[0].url.path, "/v1/contacts/search")

        let detail = try await client.contacts.get("22222222-2222-4222-8222-111111111111")
        XCTAssertEqual(detail.source, "api")
        XCTAssertEqual(detail.engagement, [:])

        let made = try await client.contacts.create(ContactInput(email: "lee@example.com", firstName: "Lee"),
                                                    options: RequestOptions(idempotencyKey: "c-1"))
        XCTAssertFalse(made.isEmpty)
        let sent = try JSONDecoder().decode(JSONValue.self, from: transport.requests[2].body!)
        XCTAssertEqual(sent, [["email": "lee@example.com", "first_name": "Lee"]])

        let updated = try await client.contacts.update("id-1", fields: ["company": "Acme"])
        XCTAssertFalse(updated.id.isEmpty)
        XCTAssertEqual(transport.requests[3].method, "PATCH")

        try await client.contacts.delete("id-1")
        XCTAssertEqual(transport.requests[4].method, "DELETE")
        XCTAssertEqual(transport.requests[4].url.path, "/v1/contacts/id-1")
    }

    func testContactsListIsRetriedWithoutKey() async throws {
        let transport = MockTransport([errorFixture(503, "503_service_unavailable.json"), ok("contacts_list.json")])
        let client = try makeClient(transport)
        _ = try await client.contacts.list()
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testMailboxes() async throws {
        let transport = MockTransport([ok("mailboxes_list.json")])
        let client = try makeClient(transport)
        let page = try await client.mailboxes.list(q: "sales")
        XCTAssertEqual(page.data.first?.provider, "gmail")
        XCTAssertNil(page.data.first?.workerId)
        XCTAssertNotNil(page.data.first?.warmup)
        XCTAssertFalse(page.hasMore)
    }

    func testUnibox() async throws {
        let transport = MockTransport([ok("unibox_threads.json"), ok("unibox_thread.json")])
        let client = try makeClient(transport)
        let threads = try await client.unibox.listThreads(filters: ["folder": "inbox", "unseen": "true"])
        XCTAssertFalse(threads.data.isEmpty)
        XCTAssertEqual(transport.requests[0].url.query, "folder=inbox&unseen=true")
        let thread = try await client.unibox.getThread(threadId: "thread-example-001")
        XCTAssertEqual(thread.data.first?.threadId, "thread-example-001")
        XCTAssertNil(thread.nextCursor)
        XCTAssertEqual(transport.requests[1].url.query, "thread_id=thread-example-001")
    }

    func testUnknownFieldsAndFractionalTimes() throws {
        let json = #"{"id":"x","name":"n","brand_new_field":{"a":1},"created_at":"2026-11-13T09:30:00.123456Z","status":"some_new_status"}"#
        let campaign = try AyInbox.decoder.decode(Campaign.self, from: Data(json.utf8))
        XCTAssertEqual(campaign.status, "some_new_status")
        XCTAssertEqual(campaign.createdAt!.timeIntervalSince1970, 1_794_562_200.123456, accuracy: 0.001)
    }
}

final class WebhookTests: XCTestCase {
    struct Vector: Decodable {
        let secret: String
        let timestamp: Int
        let body: String
        let header: String
    }

    func vector() throws -> Vector {
        try JSONDecoder().decode(Vector.self, from: fixture("webhook_signature.json"))
    }

    func testValidSignature() throws {
        let v = try vector()
        let now = Date(timeIntervalSince1970: TimeInterval(v.timestamp))
        XCTAssertTrue(Webhooks().verifySignature(payload: v.body, header: v.header, secret: v.secret, now: now))
        let event = try Webhooks().constructEvent(payload: Data(v.body.utf8), header: v.header, secret: v.secret, now: now)
        XCTAssertEqual(event["event_type"], "campaign.reply_received")
    }

    func testTamperedBody() throws {
        let v = try vector()
        let now = Date(timeIntervalSince1970: TimeInterval(v.timestamp))
        XCTAssertFalse(Webhooks().verifySignature(payload: v.body + " ", header: v.header, secret: v.secret, now: now))
    }

    func testWrongSecret() throws {
        let v = try vector()
        let now = Date(timeIntervalSince1970: TimeInterval(v.timestamp))
        XCTAssertFalse(Webhooks().verifySignature(payload: v.body, header: v.header, secret: "whsec_other", now: now))
        XCTAssertThrowsError(try Webhooks().constructEvent(payload: Data(v.body.utf8), header: v.header,
                                                            secret: "whsec_other", now: now))
    }

    func testToleranceAndMalformedHeader() throws {
        let v = try vector()
        let late = Date(timeIntervalSince1970: TimeInterval(v.timestamp + 301))
        XCTAssertFalse(Webhooks().verifySignature(payload: v.body, header: v.header, secret: v.secret, now: late))
        let now = Date(timeIntervalSince1970: TimeInterval(v.timestamp))
        XCTAssertFalse(Webhooks().verifySignature(payload: v.body, header: "v1=abc", secret: v.secret, now: now))
        XCTAssertFalse(Webhooks().verifySignature(payload: v.body, header: "t=1700000000", secret: v.secret, now: now))
        let multi = "t=1700000000,v1=00,v0=zz," + v.header.split(separator: ",")[1]
        XCTAssertTrue(Webhooks().verifySignature(payload: v.body, header: multi, secret: v.secret, now: now))
    }
}
