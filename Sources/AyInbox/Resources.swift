import Foundation

func segment(_ value: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

func pageQuery(_ base: [(String, String?)], cursor: String?, limit: Int?) -> [(String, String)] {
    var items = base.compactMap { key, value in value.map { (key, $0) } }
    if let cursor { items.append(("cursor", cursor)) }
    if let limit { items.append(("limit", String(limit))) }
    return items
}

/// `GET /me`.
public struct MeResource: Sendable {
    let client: AyInbox

    /// Validates the credential and returns who it acts for. Needs no scope.
    public func get(options: RequestOptions = RequestOptions()) async throws -> Identity {
        try await client.send("GET", "/me", options: options, as: Identity.self)
    }
}

/// `/campaigns`.
public struct CampaignsResource: Sendable {
    let client: AyInbox

    /// One page of campaigns. Scope `READ_CAMPAIGNS`. Use a `limit` between 1 and 100.
    public func list(
        q: String? = nil, status: String? = nil, folder: String? = nil,
        cursor: String? = nil, limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) async throws -> Page<Campaign> {
        let query = pageQuery([("q", q), ("status", status), ("folder", folder)], cursor: cursor, limit: limit)
        return try await client.send("GET", "/campaigns", query: query, options: options, as: Page<Campaign>.self)
    }

    /// Every campaign, following the cursor.
    public func listAll(
        q: String? = nil, status: String? = nil, folder: String? = nil,
        limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) -> PageSequence<Campaign> {
        PageSequence { cursor in
            try await list(q: q, status: status, folder: folder, cursor: cursor, limit: limit, options: options)
        }
    }

    /// One campaign. Scope `READ_CAMPAIGNS`.
    public func get(_ id: String, options: RequestOptions = RequestOptions()) async throws -> Campaign {
        try await client.send("GET", "/campaigns/\(segment(id))", options: options, as: Campaign.self)
    }

    /// Creates a draft campaign. Never sends mail. Scope `WRITE_CAMPAIGNS`.
    /// `fields` holds any other body field from the API reference, for example `steps` or `daily_limit`.
    public func create(
        name: String, fields: [String: JSONValue] = [:], options: RequestOptions = RequestOptions()
    ) async throws -> Campaign {
        var body = fields
        body["name"] = .string(name)
        return try await client.send("POST", "/campaigns", body: JSONValue.object(body), options: options,
                                     as: Campaign.self)
    }

    /// Pauses an active campaign (`POST /campaigns/{id}/stop`). Sends nothing.
    /// Scope `WRITE_CAMPAIGNS`, `START_CAMPAIGNS` or `SEND_CAMPAIGNS`.
    public func pause(_ id: String, options: RequestOptions = RequestOptions()) async throws -> PauseResult {
        try await client.send("POST", "/campaigns/\(segment(id))/stop", options: options, as: PauseResult.self)
    }
}

/// `/contacts`.
public struct ContactsResource: Sendable {
    let client: AyInbox

    /// One page of contacts (`POST /contacts/search`, a read). Scope `READ_CONTACTS`.
    /// `search` is the search body (`query`, `campaign_ids`, `sort_by` and so on); empty matches everything.
    public func list(
        search: [String: JSONValue] = [:], category: String? = nil,
        cursor: String? = nil, limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) async throws -> Page<Contact> {
        let query = pageQuery([("category", category)], cursor: cursor, limit: limit)
        return try await client.send("POST", "/contacts/search", query: query, body: JSONValue.object(search),
                                     options: options, readOnly: true, as: Page<Contact>.self)
    }

    /// Every matching contact, resending the same search on each page.
    public func listAll(
        search: [String: JSONValue] = [:], category: String? = nil,
        limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) -> PageSequence<Contact> {
        PageSequence { cursor in
            try await list(search: search, category: category, cursor: cursor, limit: limit, options: options)
        }
    }

    /// One contact with its detail fields. Scope `READ_CONTACTS`.
    public func get(_ id: String, options: RequestOptions = RequestOptions()) async throws -> Contact {
        try await client.send("GET", "/contacts/\(segment(id))", options: options, as: Contact.self)
    }

    /// Creates or updates contacts by address (up to 10,240). Scope `WRITE_CONTACTS`.
    /// Contacts added to an active campaign are queued for mail.
    public func create(_ contacts: [ContactInput], options: RequestOptions = RequestOptions()) async throws -> [Contact] {
        try await client.send("POST", "/contacts", body: contacts, options: options, as: [Contact].self)
    }

    /// Creates or updates one contact. The API answers with an array.
    public func create(_ contact: ContactInput, options: RequestOptions = RequestOptions()) async throws -> [Contact] {
        try await create([contact], options: options)
    }

    /// Updates a contact. Omitted fields are left alone. Scope `WRITE_CONTACTS`.
    public func update(
        _ id: String, fields: [String: JSONValue], options: RequestOptions = RequestOptions()
    ) async throws -> Contact {
        try await client.send("PATCH", "/contacts/\(segment(id))", body: JSONValue.object(fields), options: options,
                              as: Contact.self)
    }

    /// Deletes a contact. Scope `WRITE_CONTACTS`.
    public func delete(_ id: String, options: RequestOptions = RequestOptions()) async throws {
        _ = try await client.send("DELETE", "/contacts/\(segment(id))", options: options, as: EmptyResponse.self)
    }
}

/// `/emails`.
public struct MailboxesResource: Sendable {
    let client: AyInbox

    /// One page of mailboxes. Scope `READ_EMAILS`.
    public func list(
        q: String? = nil, tag: String? = nil, cursor: String? = nil, limit: Int? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> Page<Mailbox> {
        let query = pageQuery([("q", q), ("tag", tag)], cursor: cursor, limit: limit)
        return try await client.send("GET", "/emails", query: query, options: options, as: Page<Mailbox>.self)
    }

    /// Every mailbox, following the cursor.
    public func listAll(
        q: String? = nil, tag: String? = nil, limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) -> PageSequence<Mailbox> {
        PageSequence { cursor in try await list(q: q, tag: tag, cursor: cursor, limit: limit, options: options) }
    }
}

/// `/unibox`.
public struct UniboxResource: Sendable {
    let client: AyInbox

    /// One page of conversations, newest message first. Scope `READ_UNIBOX`.
    /// `filters` takes the query parameters from the API reference, for example `["folder": "inbox", "unseen": "true"]`.
    public func listThreads(
        filters: [String: String] = [:], cursor: String? = nil, limit: Int? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> Page<MessagePreview> {
        let base = filters.sorted { $0.key < $1.key }.map { ($0.key, Optional($0.value)) }
        let query = pageQuery(base, cursor: cursor, limit: limit)
        return try await client.send("GET", "/unibox", query: query, options: options, as: Page<MessagePreview>.self)
    }

    /// Every conversation matching `filters`.
    public func listThreadsAll(
        filters: [String: String] = [:], limit: Int? = nil, options: RequestOptions = RequestOptions()
    ) -> PageSequence<MessagePreview> {
        PageSequence { cursor in try await listThreads(filters: filters, cursor: cursor, limit: limit, options: options) }
    }

    /// The messages of one thread (previews; read bodies with `GET /unibox/{id}` through `request`).
    /// Omit `emailId` to read across every mailbox. Scope `READ_UNIBOX`.
    public func getThread(
        threadId: String, emailId: String? = nil, cursor: String? = nil, limit: Int? = nil,
        options: RequestOptions = RequestOptions()
    ) async throws -> Page<MessagePreview> {
        let query = pageQuery([("thread_id", threadId), ("email_id", emailId)], cursor: cursor, limit: limit)
        return try await client.send("GET", "/unibox/thread", query: query, options: options,
                                     as: Page<MessagePreview>.self)
    }
}
