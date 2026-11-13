import Foundation

// Every field is optional so a server-side change cannot break decoding. Unknown fields are ignored.

/// `GET /me`.
public struct Identity: Codable, Sendable, Equatable {
    public let userId: String?
    public let email: String?
    public let name: String?
    public let firstName: String?
    public let lastName: String?
    public let organizationId: String?
    public let organizationName: String?
    /// `api_key`, `oauth` or `jwt`.
    public let authType: String?
    /// Lowercased permission names, sorted.
    public let scopes: [String]?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", email, name, firstName = "first_name", lastName = "last_name"
        case organizationId = "organization_id", organizationName = "organization_name"
        case authType = "auth_type", scopes
    }
}

/// A mailbox that sends for a campaign.
public struct CampaignSender: Codable, Sendable, Equatable {
    public let emailAccountId: String?
    public let weight: Int?
    public let enabled: Bool?
    public let lastSentAt: Date?

    enum CodingKeys: String, CodingKey {
        case emailAccountId = "email_account_id", weight, enabled, lastSentAt = "last_sent_at"
    }
}

/// A campaign.
public struct Campaign: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String?
    public let organizationId: String?
    public let name: String?
    public let description: String?
    /// `draft`, `active`, `paused`, `completed`, `paused_undeliverable`, `paused_guardrail`, `paused_no_accounts`, or a newer value.
    public let status: String?
    public let stopOnReply: Bool?
    public let stopOnMeeting: Bool?
    public let openTracking: Bool?
    public let linkTracking: Bool?
    public let textOnly: Bool?
    public let unsubscribeHeader: Bool?
    public let riskyEmails: Bool?
    public let dailyLimit: Int?
    public let unsubscribeMode: String?
    public let cc: [String]?
    public let bcc: [String]?
    public let startDate: Date?
    public let endDate: Date?
    public let timezone: String?
    public let effectiveTimezone: String?
    public let days: Int?
    public let startTime: String?
    public let endTime: String?
    /// Seven arrays of `{start, end}` minutes since local midnight, index 0 is Sunday.
    public let scheduleWindows: JSONValue?
    public let emailTags: [String]?
    public let folders: [String]?
    public let contactOrderBy: String?
    public let contactOrderDir: String?
    public let contactOrderField: String?
    public let senderStrategy: String?
    public let rotationMode: String?
    public let senders: [CampaignSender]?
    public let rampEnabled: Bool?
    public let rampStart: Int?
    public let rampIncrement: Int?
    public let rampCeiling: Int?
    public let rampLevel: Int?
    public let rampLevelDate: Date?
    public let espMatchMode: String?
    public let maxNewLeadsPerDay: Int?
    public let prioritizeNewLeads: Bool?
    public let continuous: Bool?
    public let reviewFirstEmails: Bool?
    public let entryDelayMinutes: Int?
    public let idleSince: Date?
    public let guardrailEnabled: Bool?
    public let guardrailBounceRateMax: Double?
    public let guardrailComplaintRateMax: Double?
    public let guardrailReplyRateMin: Double?
    public let guardrailMinSample: Int?
    public let guardrailWindowDays: Int?
    public let guardrailTrippedAt: Date?
    public let guardrailReason: String?
    public let trackingDomain: String?
    public let trackingDomainVerified: Bool?
    public let trackingDomainVerifiedAt: Date?
    public let utmTracking: Bool?
    public let utmSource: String?
    public let utmMedium: String?
    public let utmCampaign: String?
    public let lastStatusChangeAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", organizationId = "organization_id", name, description, status
        case stopOnReply = "stop_on_reply", stopOnMeeting = "stop_on_meeting", openTracking = "open_tracking"
        case linkTracking = "link_tracking", textOnly = "text_only", unsubscribeHeader = "unsubscribe_header"
        case riskyEmails = "risky_emails", dailyLimit = "daily_limit", unsubscribeMode = "unsubscribe_mode"
        case cc, bcc, startDate = "start_date", endDate = "end_date", timezone
        case effectiveTimezone = "effective_timezone", days, startTime = "start_time", endTime = "end_time"
        case scheduleWindows = "schedule_windows", emailTags = "email_tags", folders
        case contactOrderBy = "contact_order_by", contactOrderDir = "contact_order_dir"
        case contactOrderField = "contact_order_field", senderStrategy = "sender_strategy"
        case rotationMode = "rotation_mode", senders, rampEnabled = "ramp_enabled", rampStart = "ramp_start"
        case rampIncrement = "ramp_increment", rampCeiling = "ramp_ceiling", rampLevel = "ramp_level"
        case rampLevelDate = "ramp_level_date", espMatchMode = "esp_match_mode"
        case maxNewLeadsPerDay = "max_new_leads_per_day", prioritizeNewLeads = "prioritize_new_leads"
        case continuous, reviewFirstEmails = "review_first_emails", entryDelayMinutes = "entry_delay_minutes"
        case idleSince = "idle_since", guardrailEnabled = "guardrail_enabled"
        case guardrailBounceRateMax = "guardrail_bounce_rate_max"
        case guardrailComplaintRateMax = "guardrail_complaint_rate_max"
        case guardrailReplyRateMin = "guardrail_reply_rate_min", guardrailMinSample = "guardrail_min_sample"
        case guardrailWindowDays = "guardrail_window_days", guardrailTrippedAt = "guardrail_tripped_at"
        case guardrailReason = "guardrail_reason", trackingDomain = "tracking_domain"
        case trackingDomainVerified = "tracking_domain_verified"
        case trackingDomainVerifiedAt = "tracking_domain_verified_at", utmTracking = "utm_tracking"
        case utmSource = "utm_source", utmMedium = "utm_medium", utmCampaign = "utm_campaign"
        case lastStatusChangeAt = "last_status_change_at", createdAt = "created_at", updatedAt = "updated_at"
    }
}

/// `POST /campaigns/{id}/stop`.
public struct PauseResult: Codable, Sendable, Equatable {
    public let status: String?
}

public struct ContactCampaignRef: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String?
}

public struct ContactLabel: Codable, Sendable, Equatable {
    public let id: String?
    public let title: String?
    public let color: String?
}

/// A contact. `contacts.get` also fills the detail fields.
public struct Contact: Codable, Sendable, Equatable {
    public let id: String
    public let firstName: String?
    public let lastName: String?
    public let email: String?
    public let company: String?
    public let phone: String?
    public let customFields: [String: String]?
    public let subscribed: Bool?
    public let campaigns: [ContactCampaignRef]?
    public let categories: [ContactLabel]?
    /// `valid`, `risky`, `invalid` or `unknown`.
    public let verificationStatus: String?
    public let verificationReason: String?
    public let isCatchAll: Bool?
    public let verificationCheckedAt: Date?
    public let verificationSource: String?
    public let verificationProvider: String?
    public let verificationSubStatus: String?
    public let verificationConfidence: Int?
    public let verificationRequestedAt: Date?
    public let mailHost: String?
    public let espProvider: String?
    public let espResolvedAt: Date?
    public let consentGivenAt: Date?
    public let consentSource: String?
    public let leadScore: JSONValue?
    /// Campaign progress, on rows of a search with exactly one campaign id.
    public let campaignLead: JSONValue?
    public let outreach: JSONValue?
    public let createdAt: Date?
    public let updatedAt: Date?
    // Detail fields (contacts.get).
    public let engagement: JSONValue?
    public let suppression: JSONValue?
    public let verification: JSONValue?
    public let source: String?
    public let sourceDetail: String?
    public let firstSeenAt: Date?
    public let consentCountry: String?
    public let consentRequired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, firstName = "first_name", lastName = "last_name", email, company, phone
        case customFields = "custom_fields", subscribed, campaigns, categories
        case verificationStatus = "verification_status", verificationReason = "verification_reason"
        case isCatchAll = "is_catch_all", verificationCheckedAt = "verification_checked_at"
        case verificationSource = "verification_source", verificationProvider = "verification_provider"
        case verificationSubStatus = "verification_sub_status", verificationConfidence = "verification_confidence"
        case verificationRequestedAt = "verification_requested_at", mailHost = "mail_host"
        case espProvider = "esp_provider", espResolvedAt = "esp_resolved_at", consentGivenAt = "consent_given_at"
        case consentSource = "consent_source", leadScore = "lead_score", campaignLead = "campaign_lead"
        case outreach, createdAt = "created_at", updatedAt = "updated_at", engagement, suppression
        case verification, source, sourceDetail = "source_detail", firstSeenAt = "first_seen_at"
        case consentCountry = "consent_country", consentRequired = "consent_required"
    }
}

/// One contact to create or update by address with `contacts.create`.
public struct ContactInput: Codable, Sendable, Equatable {
    public var email: String
    public var firstName: String?
    public var lastName: String?
    public var company: String?
    public var phone: String?
    /// Campaign ids. Adding a contact to an active campaign queues mail to it.
    public var campaigns: [String]?
    public var categories: [String]?
    public var segments: [String]?
    public var customFields: [String: String]?
    public var subscribed: Bool?
    public var verificationStatus: String?
    public var verificationProvider: String?

    public init(
        email: String, firstName: String? = nil, lastName: String? = nil, company: String? = nil,
        phone: String? = nil, campaigns: [String]? = nil, categories: [String]? = nil, segments: [String]? = nil,
        customFields: [String: String]? = nil, subscribed: Bool? = nil, verificationStatus: String? = nil,
        verificationProvider: String? = nil
    ) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.phone = phone
        self.campaigns = campaigns
        self.categories = categories
        self.segments = segments
        self.customFields = customFields
        self.subscribed = subscribed
        self.verificationStatus = verificationStatus
        self.verificationProvider = verificationProvider
    }

    enum CodingKeys: String, CodingKey {
        case email, firstName = "first_name", lastName = "last_name", company, phone, campaigns, categories
        case segments, customFields = "custom_fields", subscribed, verificationStatus = "verification_status"
        case verificationProvider = "verification_provider"
    }
}

/// A connected mailbox (`/emails`). Selected fields; use `request` for the rest.
public struct Mailbox: Codable, Sendable, Equatable {
    public let id: String
    public let userId: String?
    public let organizationId: String?
    public let workerId: String?
    public let email: String?
    public let name: String?
    public let signaturePlain: String?
    public let signatureHtml: String?
    public let sendAsEmail: String?
    /// `gmail`, `outlook` or `smtp_imap`.
    public let provider: String?
    public let status: String?
    public let mailHost: String?
    public let authMethod: String?
    public let avatarUrl: String?
    public let lastSyncedAt: Date?
    public let campaignLimit: Int?
    /// Seconds between sends.
    public let minWaitTime: Int?
    public let replyTo: String?
    public let trackingDomain: String?
    public let trackingDomainVerified: Bool?
    public let authState: String?
    public let authSpf: Bool?
    public let authDkim: Bool?
    public let authDmarc: Bool?
    public let authCheckedAt: Date?
    /// Set while warmup is on.
    public let warmup: Date?
    public let warmupPausedAt: Date?
    public let warmupBase: Int?
    public let warmupMax: Int?
    public let warmupIncrease: Int?
    public let warmupReplyRate: Int?
    public let warmupPoolType: String?
    public let timezone: String?
    public let saveToSent: Bool?
    public let relayFolderMoves: Bool?
    public let tags: [String]?
    public let createdAt: Date?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", organizationId = "organization_id", workerId = "worker_id", email, name
        case signaturePlain = "signature_plain", signatureHtml = "signature_html", sendAsEmail = "send_as_email"
        case provider, status, mailHost = "mail_host", authMethod = "auth_method", avatarUrl = "avatar_url"
        case lastSyncedAt = "last_synced_at", campaignLimit = "campaign_limit", minWaitTime = "min_wait_time"
        case replyTo = "reply_to", trackingDomain = "tracking_domain"
        case trackingDomainVerified = "tracking_domain_verified", authState = "auth_state", authSpf = "auth_spf"
        case authDkim = "auth_dkim", authDmarc = "auth_dmarc", authCheckedAt = "auth_checked_at", warmup
        case warmupPausedAt = "warmup_paused_at", warmupBase = "warmup_base", warmupMax = "warmup_max"
        case warmupIncrease = "warmup_increase", warmupReplyRate = "warmup_reply_rate"
        case warmupPoolType = "warmup_pool_type", timezone, saveToSent = "save_to_sent"
        case relayFolderMoves = "relay_folder_moves", tags, createdAt = "created_at", updatedAt = "updated_at"
    }
}

/// A unibox row: the newest message of a conversation, or one message of a thread.
public struct MessagePreview: Codable, Sendable, Equatable {
    public let id: String
    /// The mailbox id.
    public let emailId: String?
    /// A provider thread string, not a UUID.
    public let threadId: String?
    public let fromAddr: [String]?
    public let toAddr: [String]?
    public let subject: String?
    public let snippet: String?
    public let internalDate: Date?
    public let seen: Bool?
    public let messageCount: Int?
    public let hasUnread: Bool?
    public let labels: [ContactLabel]?
    public let answersMailboxId: String?
    public let campaignId: String?

    enum CodingKeys: String, CodingKey {
        case id, emailId = "email_id", threadId = "thread_id", fromAddr = "from_addr", toAddr = "to_addr"
        case subject, snippet, internalDate = "internal_date", seen, messageCount = "message_count"
        case hasUnread = "has_unread", labels, answersMailboxId = "answers_mailbox_id", campaignId = "campaign_id"
    }
}
