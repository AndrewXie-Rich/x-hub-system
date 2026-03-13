import Foundation

public struct HubNotification: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var source: String
    public var title: String
    public var body: String
    public var createdAt: Double
    public var dedupeKey: String?
    public var actionURL: String?
    public var snoozedUntil: Double?
    public var unread: Bool

    // Keep IPC stable and tolerant of both snake_case and camelCase.
    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case title
        case body
        case createdAt
        case created_at
        case dedupeKey
        case dedupe_key
        case actionURL
        case actionUrl
        case action_url
        case snoozedUntil
        case snoozed_until
        case unread
    }

    public init(
        id: String,
        source: String,
        title: String,
        body: String,
        createdAt: Double,
        dedupeKey: String?,
        actionURL: String?,
        snoozedUntil: Double?,
        unread: Bool
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.dedupeKey = dedupeKey
        self.actionURL = actionURL
        self.snoozedUntil = snoozedUntil
        self.unread = unread
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(String.self, forKey: .id)) ?? ""
        self.source = (try? c.decode(String.self, forKey: .source)) ?? ""
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.body = (try? c.decode(String.self, forKey: .body)) ?? ""

        if let v = try? c.decode(Double.self, forKey: .createdAt) {
            self.createdAt = v
        } else if let v = try? c.decode(Double.self, forKey: .created_at) {
            self.createdAt = v
        } else {
            self.createdAt = Date().timeIntervalSince1970
        }

        if let v = try? c.decode(String.self, forKey: .dedupeKey) {
            self.dedupeKey = v
        } else if let v = try? c.decode(String.self, forKey: .dedupe_key) {
            self.dedupeKey = v
        } else {
            self.dedupeKey = nil
        }

        if let v = try? c.decode(String.self, forKey: .actionURL) {
            self.actionURL = v
        } else if let v = try? c.decode(String.self, forKey: .actionUrl) {
            self.actionURL = v
        } else if let v = try? c.decode(String.self, forKey: .action_url) {
            self.actionURL = v
        } else {
            self.actionURL = nil
        }

        if let v = try? c.decode(Double.self, forKey: .snoozedUntil) {
            self.snoozedUntil = v
        } else if let v = try? c.decode(Double.self, forKey: .snoozed_until) {
            self.snoozedUntil = v
        } else {
            self.snoozedUntil = nil
        }

        self.unread = (try? c.decode(Bool.self, forKey: .unread)) ?? true
        if self.id.isEmpty {
            self.id = UUID().uuidString
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(source, forKey: .source)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        // Prefer snake_case for IPC.
        try c.encode(createdAt, forKey: .created_at)
        try c.encodeIfPresent(dedupeKey, forKey: .dedupe_key)
        try c.encodeIfPresent(actionURL, forKey: .action_url)
        try c.encodeIfPresent(snoozedUntil, forKey: .snoozed_until)
        try c.encode(unread, forKey: .unread)
    }

    public static func make(
        id: String? = nil,
        source: String,
        title: String,
        body: String,
        createdAt: Double? = nil,
        dedupeKey: String? = nil,
        actionURL: String? = nil
    ) -> HubNotification {
        HubNotification(
            id: id ?? UUID().uuidString,
            source: source,
            title: title,
            body: body,
            createdAt: createdAt ?? Date().timeIntervalSince1970,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            snoozedUntil: nil,
            unread: true
        )
    }
}

public struct IPCMemoryContextBudgets: Codable, Sendable, Equatable {
    public var totalTokens: Int?
    public var l0Tokens: Int?
    public var l1Tokens: Int?
    public var l2Tokens: Int?
    public var l3Tokens: Int?
    public var l4Tokens: Int?

    public init(
        totalTokens: Int? = nil,
        l0Tokens: Int? = nil,
        l1Tokens: Int? = nil,
        l2Tokens: Int? = nil,
        l3Tokens: Int? = nil,
        l4Tokens: Int? = nil
    ) {
        self.totalTokens = totalTokens
        self.l0Tokens = l0Tokens
        self.l1Tokens = l1Tokens
        self.l2Tokens = l2Tokens
        self.l3Tokens = l3Tokens
        self.l4Tokens = l4Tokens
    }

    public enum CodingKeys: String, CodingKey {
        case totalTokens = "total_tokens"
        case l0Tokens = "l0_tokens"
        case l1Tokens = "l1_tokens"
        case l2Tokens = "l2_tokens"
        case l3Tokens = "l3_tokens"
        case l4Tokens = "l4_tokens"
    }
}

public struct IPCMemoryContextRequestPayload: Codable, Sendable, Equatable {
    public var mode: String?
    public var projectId: String?
    public var projectRoot: String?
    public var displayName: String?
    public var latestUser: String
    public var constitutionHint: String?
    public var canonicalText: String?
    public var observationsText: String?
    public var workingSetText: String?
    public var rawEvidenceText: String?
    public var servingProfile: String?
    public var budgets: IPCMemoryContextBudgets?

    public init(
        mode: String? = nil,
        projectId: String? = nil,
        projectRoot: String? = nil,
        displayName: String? = nil,
        latestUser: String,
        constitutionHint: String? = nil,
        canonicalText: String? = nil,
        observationsText: String? = nil,
        workingSetText: String? = nil,
        rawEvidenceText: String? = nil,
        servingProfile: String? = nil,
        budgets: IPCMemoryContextBudgets? = nil
    ) {
        self.mode = mode
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.latestUser = latestUser
        self.constitutionHint = constitutionHint
        self.canonicalText = canonicalText
        self.observationsText = observationsText
        self.workingSetText = workingSetText
        self.rawEvidenceText = rawEvidenceText
        self.servingProfile = servingProfile
        self.budgets = budgets
    }

    public enum CodingKeys: String, CodingKey {
        case mode
        case projectId = "project_id"
        case projectRoot = "project_root"
        case displayName = "display_name"
        case latestUser = "latest_user"
        case constitutionHint = "constitution_hint"
        case canonicalText = "canonical_text"
        case observationsText = "observations_text"
        case workingSetText = "working_set_text"
        case rawEvidenceText = "raw_evidence_text"
        case servingProfile = "serving_profile"
        case budgets
    }
}

public struct IPCMemoryContextLayerUsage: Codable, Sendable, Equatable {
    public var layer: String
    public var usedTokens: Int
    public var budgetTokens: Int

    public init(layer: String, usedTokens: Int, budgetTokens: Int) {
        self.layer = layer
        self.usedTokens = usedTokens
        self.budgetTokens = budgetTokens
    }

    public enum CodingKeys: String, CodingKey {
        case layer
        case usedTokens = "used_tokens"
        case budgetTokens = "budget_tokens"
    }
}

public struct IPCMemoryContextResponsePayload: Codable, Sendable, Equatable {
    public var text: String
    public var source: String
    public var resolvedProfile: String?
    public var longtermMode: String?
    public var retrievalAvailable: Bool?
    public var fulltextNotLoaded: Bool?
    public var budgetTotalTokens: Int
    public var usedTotalTokens: Int
    public var layerUsage: [IPCMemoryContextLayerUsage]
    public var truncatedLayers: [String]
    public var redactedItems: Int
    public var privateDrops: Int

    public init(
        text: String,
        source: String,
        resolvedProfile: String? = nil,
        longtermMode: String? = nil,
        retrievalAvailable: Bool? = nil,
        fulltextNotLoaded: Bool? = nil,
        budgetTotalTokens: Int,
        usedTotalTokens: Int,
        layerUsage: [IPCMemoryContextLayerUsage],
        truncatedLayers: [String],
        redactedItems: Int,
        privateDrops: Int
    ) {
        self.text = text
        self.source = source
        self.resolvedProfile = resolvedProfile
        self.longtermMode = longtermMode
        self.retrievalAvailable = retrievalAvailable
        self.fulltextNotLoaded = fulltextNotLoaded
        self.budgetTotalTokens = budgetTotalTokens
        self.usedTotalTokens = usedTotalTokens
        self.layerUsage = layerUsage
        self.truncatedLayers = truncatedLayers
        self.redactedItems = redactedItems
        self.privateDrops = privateDrops
    }

    public enum CodingKeys: String, CodingKey {
        case text
        case source
        case resolvedProfile = "resolved_profile"
        case longtermMode = "longterm_mode"
        case retrievalAvailable = "retrieval_available"
        case fulltextNotLoaded = "fulltext_not_loaded"
        case budgetTotalTokens = "budget_total_tokens"
        case usedTotalTokens = "used_total_tokens"
        case layerUsage = "layer_usage"
        case truncatedLayers = "truncated_layers"
        case redactedItems = "redacted_items"
        case privateDrops = "private_drops"
    }
}

public struct IPCMemoryRetrievalRequestPayload: Codable, Sendable, Equatable {
    public var scope: String
    public var requesterRole: String
    public var projectId: String?
    public var projectRoot: String?
    public var displayName: String?
    public var latestUser: String
    public var reason: String?
    public var requestedKinds: [String]
    public var explicitRefs: [String]
    public var maxSnippets: Int
    public var maxSnippetChars: Int
    public var auditRef: String

    public init(
        scope: String,
        requesterRole: String,
        projectId: String? = nil,
        projectRoot: String? = nil,
        displayName: String? = nil,
        latestUser: String,
        reason: String? = nil,
        requestedKinds: [String] = [],
        explicitRefs: [String] = [],
        maxSnippets: Int = 3,
        maxSnippetChars: Int = 420,
        auditRef: String
    ) {
        self.scope = scope
        self.requesterRole = requesterRole
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.latestUser = latestUser
        self.reason = reason
        self.requestedKinds = requestedKinds
        self.explicitRefs = explicitRefs
        self.maxSnippets = maxSnippets
        self.maxSnippetChars = maxSnippetChars
        self.auditRef = auditRef
    }

    public enum CodingKeys: String, CodingKey {
        case scope
        case requesterRole = "requester_role"
        case projectId = "project_id"
        case projectRoot = "project_root"
        case displayName = "display_name"
        case latestUser = "latest_user"
        case reason
        case requestedKinds = "requested_kinds"
        case explicitRefs = "explicit_refs"
        case maxSnippets = "max_snippets"
        case maxSnippetChars = "max_snippet_chars"
        case auditRef = "audit_ref"
    }
}

public struct IPCMemoryRetrievalSnippet: Codable, Sendable, Equatable {
    public var snippetId: String
    public var sourceKind: String
    public var title: String
    public var ref: String
    public var text: String
    public var score: Int
    public var truncated: Bool

    public init(
        snippetId: String,
        sourceKind: String,
        title: String,
        ref: String,
        text: String,
        score: Int,
        truncated: Bool
    ) {
        self.snippetId = snippetId
        self.sourceKind = sourceKind
        self.title = title
        self.ref = ref
        self.text = text
        self.score = score
        self.truncated = truncated
    }

    public enum CodingKeys: String, CodingKey {
        case snippetId = "snippet_id"
        case sourceKind = "source_kind"
        case title
        case ref
        case text
        case score
        case truncated
    }
}

public struct IPCMemoryRetrievalResponsePayload: Codable, Sendable, Equatable {
    public var source: String
    public var scope: String
    public var auditRef: String
    public var reasonCode: String?
    public var denyCode: String?
    public var snippets: [IPCMemoryRetrievalSnippet]
    public var truncatedItems: Int
    public var redactedItems: Int

    public init(
        source: String,
        scope: String,
        auditRef: String,
        reasonCode: String? = nil,
        denyCode: String? = nil,
        snippets: [IPCMemoryRetrievalSnippet],
        truncatedItems: Int,
        redactedItems: Int
    ) {
        self.source = source
        self.scope = scope
        self.auditRef = auditRef
        self.reasonCode = reasonCode
        self.denyCode = denyCode
        self.snippets = snippets
        self.truncatedItems = truncatedItems
        self.redactedItems = redactedItems
    }

    public enum CodingKeys: String, CodingKey {
        case source
        case scope
        case auditRef = "audit_ref"
        case reasonCode = "reason_code"
        case denyCode = "deny_code"
        case snippets
        case truncatedItems = "truncated_items"
        case redactedItems = "redacted_items"
    }
}

public struct IPCSupervisorIncidentAuditPayload: Codable, Sendable, Equatable {
    public var incidentId: String
    public var laneId: String
    public var taskId: String
    public var projectId: String?
    public var incidentCode: String
    public var eventType: String
    public var denyCode: String
    public var proposedAction: String
    public var severity: String
    public var category: String
    public var detectedAtMs: Int64
    public var handledAtMs: Int64?
    public var takeoverLatencyMs: Int64?
    public var auditRef: String
    public var detail: String?
    public var status: String
    public var source: String?

    public init(
        incidentId: String,
        laneId: String,
        taskId: String,
        projectId: String? = nil,
        incidentCode: String,
        eventType: String,
        denyCode: String,
        proposedAction: String,
        severity: String,
        category: String,
        detectedAtMs: Int64,
        handledAtMs: Int64? = nil,
        takeoverLatencyMs: Int64? = nil,
        auditRef: String,
        detail: String? = nil,
        status: String,
        source: String? = nil
    ) {
        self.incidentId = incidentId
        self.laneId = laneId
        self.taskId = taskId
        self.projectId = projectId
        self.incidentCode = incidentCode
        self.eventType = eventType
        self.denyCode = denyCode
        self.proposedAction = proposedAction
        self.severity = severity
        self.category = category
        self.detectedAtMs = detectedAtMs
        self.handledAtMs = handledAtMs
        self.takeoverLatencyMs = takeoverLatencyMs
        self.auditRef = auditRef
        self.detail = detail
        self.status = status
        self.source = source
    }

    public enum CodingKeys: String, CodingKey {
        case incidentId = "incident_id"
        case laneId = "lane_id"
        case taskId = "task_id"
        case projectId = "project_id"
        case incidentCode = "incident_code"
        case eventType = "event_type"
        case denyCode = "deny_code"
        case proposedAction = "proposed_action"
        case severity
        case category
        case detectedAtMs = "detected_at_ms"
        case handledAtMs = "handled_at_ms"
        case takeoverLatencyMs = "takeover_latency_ms"
        case auditRef = "audit_ref"
        case detail
        case status
        case source
    }
}

public struct IPCSupervisorProjectActionAuditPayload: Codable, Sendable, Equatable {
    public var eventId: String
    public var projectId: String
    public var projectName: String
    public var eventType: String
    public var severity: String
    public var actionTitle: String
    public var actionSummary: String
    public var whyItMatters: String
    public var nextAction: String
    public var occurredAtMs: Int64
    public var deliveryChannel: String
    public var deliveryStatus: String
    public var jurisdictionRole: String?
    public var grantedScope: String?
    public var auditRef: String
    public var source: String?

    public init(
        eventId: String,
        projectId: String,
        projectName: String,
        eventType: String,
        severity: String,
        actionTitle: String,
        actionSummary: String,
        whyItMatters: String,
        nextAction: String,
        occurredAtMs: Int64,
        deliveryChannel: String,
        deliveryStatus: String,
        jurisdictionRole: String? = nil,
        grantedScope: String? = nil,
        auditRef: String,
        source: String? = nil
    ) {
        self.eventId = eventId
        self.projectId = projectId
        self.projectName = projectName
        self.eventType = eventType
        self.severity = severity
        self.actionTitle = actionTitle
        self.actionSummary = actionSummary
        self.whyItMatters = whyItMatters
        self.nextAction = nextAction
        self.occurredAtMs = occurredAtMs
        self.deliveryChannel = deliveryChannel
        self.deliveryStatus = deliveryStatus
        self.jurisdictionRole = jurisdictionRole
        self.grantedScope = grantedScope
        self.auditRef = auditRef
        self.source = source
    }

    public enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case projectId = "project_id"
        case projectName = "project_name"
        case eventType = "event_type"
        case severity
        case actionTitle = "action_title"
        case actionSummary = "action_summary"
        case whyItMatters = "why_it_matters"
        case nextAction = "next_action"
        case occurredAtMs = "occurred_at_ms"
        case deliveryChannel = "delivery_channel"
        case deliveryStatus = "delivery_status"
        case jurisdictionRole = "jurisdiction_role"
        case grantedScope = "granted_scope"
        case auditRef = "audit_ref"
        case source
    }
}

public struct IPCVoiceWakeProfileRequestPayload: Codable, Sendable, Equatable {
    public var desiredWakeMode: String

    public init(desiredWakeMode: String) {
        self.desiredWakeMode = desiredWakeMode
    }

    public enum CodingKeys: String, CodingKey {
        case desiredWakeMode = "desired_wake_mode"
    }
}

public struct IPCVoiceWakeProfile: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var profileID: String
    public var triggerWords: [String]
    public var updatedAtMs: Int64
    public var scope: String
    public var source: String
    public var wakeMode: String
    public var requiresPairingReady: Bool
    public var auditRef: String?

    public init(
        schemaVersion: String,
        profileID: String,
        triggerWords: [String],
        updatedAtMs: Int64,
        scope: String,
        source: String,
        wakeMode: String,
        requiresPairingReady: Bool,
        auditRef: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.triggerWords = triggerWords
        self.updatedAtMs = updatedAtMs
        self.scope = scope
        self.source = source
        self.wakeMode = wakeMode
        self.requiresPairingReady = requiresPairingReady
        self.auditRef = auditRef
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profileID = "profile_id"
        case triggerWords = "trigger_words"
        case updatedAtMs = "updated_at_ms"
        case scope
        case source
        case wakeMode = "wake_mode"
        case requiresPairingReady = "requires_pairing_ready"
        case auditRef = "audit_ref"
    }
}

public struct IPCSecretVaultItem: Codable, Sendable, Equatable {
    public var itemID: String
    public var scope: String
    public var name: String
    public var sensitivity: String
    public var createdAtMs: Int64
    public var updatedAtMs: Int64

    public init(
        itemID: String,
        scope: String,
        name: String,
        sensitivity: String,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) {
        self.itemID = itemID
        self.scope = scope
        self.name = name
        self.sensitivity = sensitivity
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    public enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case scope
        case name
        case sensitivity
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }
}

public struct IPCSecretVaultSnapshot: Codable, Sendable, Equatable {
    public var source: String
    public var updatedAtMs: Int64
    public var items: [IPCSecretVaultItem]

    public init(source: String, updatedAtMs: Int64, items: [IPCSecretVaultItem]) {
        self.source = source
        self.updatedAtMs = updatedAtMs
        self.items = items
    }

    public enum CodingKeys: String, CodingKey {
        case source
        case updatedAtMs = "updated_at_ms"
        case items
    }
}

public struct IPCSecretVaultCreateRequestPayload: Codable, Sendable, Equatable {
    public var scope: String
    public var name: String
    public var plaintext: String
    public var sensitivity: String
    public var projectID: String?
    public var displayName: String?
    public var reason: String?

    public init(
        scope: String,
        name: String,
        plaintext: String,
        sensitivity: String,
        projectID: String? = nil,
        displayName: String? = nil,
        reason: String? = nil
    ) {
        self.scope = scope
        self.name = name
        self.plaintext = plaintext
        self.sensitivity = sensitivity
        self.projectID = projectID
        self.displayName = displayName
        self.reason = reason
    }

    public enum CodingKeys: String, CodingKey {
        case scope
        case name
        case plaintext
        case sensitivity
        case projectID = "project_id"
        case displayName = "display_name"
        case reason
    }
}

public struct IPCSecretVaultListRequestPayload: Codable, Sendable, Equatable {
    public var scope: String?
    public var namePrefix: String?
    public var projectID: String?
    public var limit: Int

    public init(
        scope: String? = nil,
        namePrefix: String? = nil,
        projectID: String? = nil,
        limit: Int
    ) {
        self.scope = scope
        self.namePrefix = namePrefix
        self.projectID = projectID
        self.limit = limit
    }

    public enum CodingKeys: String, CodingKey {
        case scope
        case namePrefix = "name_prefix"
        case projectID = "project_id"
        case limit
    }
}

public struct IPCSecretVaultUseRequestPayload: Codable, Sendable, Equatable {
    public var itemID: String?
    public var scope: String?
    public var name: String?
    public var projectID: String?
    public var purpose: String
    public var target: String?
    public var ttlMs: Int

    public init(
        itemID: String? = nil,
        scope: String? = nil,
        name: String? = nil,
        projectID: String? = nil,
        purpose: String,
        target: String? = nil,
        ttlMs: Int
    ) {
        self.itemID = itemID
        self.scope = scope
        self.name = name
        self.projectID = projectID
        self.purpose = purpose
        self.target = target
        self.ttlMs = ttlMs
    }

    public enum CodingKeys: String, CodingKey {
        case itemID = "item_id"
        case scope
        case name
        case projectID = "project_id"
        case purpose
        case target
        case ttlMs = "ttl_ms"
    }
}

public struct IPCSecretVaultUseResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var source: String
    public var leaseID: String?
    public var useToken: String?
    public var itemID: String?
    public var expiresAtMs: Int64?
    public var reasonCode: String?

    public init(
        ok: Bool,
        source: String,
        leaseID: String? = nil,
        useToken: String? = nil,
        itemID: String? = nil,
        expiresAtMs: Int64? = nil,
        reasonCode: String? = nil
    ) {
        self.ok = ok
        self.source = source
        self.leaseID = leaseID
        self.useToken = useToken
        self.itemID = itemID
        self.expiresAtMs = expiresAtMs
        self.reasonCode = reasonCode
    }

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case leaseID = "lease_id"
        case useToken = "use_token"
        case itemID = "item_id"
        case expiresAtMs = "expires_at_ms"
        case reasonCode = "reason_code"
    }
}

public struct IPCSecretVaultRedeemRequestPayload: Codable, Sendable, Equatable {
    public var useToken: String
    public var projectID: String?

    public init(
        useToken: String,
        projectID: String? = nil
    ) {
        self.useToken = useToken
        self.projectID = projectID
    }

    public enum CodingKeys: String, CodingKey {
        case useToken = "use_token"
        case projectID = "project_id"
    }
}

public struct IPCSecretVaultRedeemResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var source: String
    public var leaseID: String?
    public var itemID: String?
    public var plaintext: String?
    public var reasonCode: String?

    public init(
        ok: Bool,
        source: String,
        leaseID: String? = nil,
        itemID: String? = nil,
        plaintext: String? = nil,
        reasonCode: String? = nil
    ) {
        self.ok = ok
        self.source = source
        self.leaseID = leaseID
        self.itemID = itemID
        self.plaintext = plaintext
        self.reasonCode = reasonCode
    }

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case leaseID = "lease_id"
        case itemID = "item_id"
        case plaintext
        case reasonCode = "reason_code"
    }
}

public struct IPCProjectCanonicalMemoryItem: Codable, Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct IPCProjectCanonicalMemoryPayload: Codable, Sendable, Equatable {
    public var projectId: String
    public var projectRoot: String?
    public var displayName: String?
    public var updatedAt: Double?
    public var items: [IPCProjectCanonicalMemoryItem]

    public init(
        projectId: String,
        projectRoot: String? = nil,
        displayName: String? = nil,
        updatedAt: Double? = nil,
        items: [IPCProjectCanonicalMemoryItem]
    ) {
        self.projectId = projectId
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.items = items
    }

    public enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case projectRoot = "project_root"
        case displayName = "display_name"
        case updatedAt = "updated_at"
        case items
    }
}

public struct IPCDeviceCanonicalMemoryPayload: Codable, Sendable, Equatable {
    public var supervisorId: String
    public var displayName: String?
    public var updatedAt: Double?
    public var items: [IPCProjectCanonicalMemoryItem]

    public init(
        supervisorId: String,
        displayName: String? = nil,
        updatedAt: Double? = nil,
        items: [IPCProjectCanonicalMemoryItem]
    ) {
        self.supervisorId = supervisorId
        self.displayName = displayName
        self.updatedAt = updatedAt
        self.items = items
    }

    public enum CodingKeys: String, CodingKey {
        case supervisorId = "supervisor_id"
        case displayName = "display_name"
        case updatedAt = "updated_at"
        case items
    }
}

public struct IPCRequest: Codable, Sendable {
    public var type: String
    public var reqId: String?
    public var notification: HubNotification?
    public var project: HubProjectSnapshot?
    public var projectCanonicalMemory: IPCProjectCanonicalMemoryPayload?
    public var deviceCanonicalMemory: IPCDeviceCanonicalMemoryPayload?
    public var network: HubNetworkRequest?
    public var memoryContext: IPCMemoryContextRequestPayload?
    public var memoryRetrieval: IPCMemoryRetrievalRequestPayload?
    public var supervisorIncident: IPCSupervisorIncidentAuditPayload?
    public var supervisorProjectAction: IPCSupervisorProjectActionAuditPayload?
    public var voiceWakeProfileRequest: IPCVoiceWakeProfileRequestPayload?
    public var voiceWakeProfile: IPCVoiceWakeProfile?
    public var secretVaultCreate: IPCSecretVaultCreateRequestPayload?
    public var secretVaultList: IPCSecretVaultListRequestPayload?
    public var secretVaultUse: IPCSecretVaultUseRequestPayload?
    public var secretVaultRedeem: IPCSecretVaultRedeemRequestPayload?

    public init(
        type: String,
        reqId: String? = nil,
        notification: HubNotification? = nil,
        project: HubProjectSnapshot? = nil,
        projectCanonicalMemory: IPCProjectCanonicalMemoryPayload? = nil,
        deviceCanonicalMemory: IPCDeviceCanonicalMemoryPayload? = nil,
        network: HubNetworkRequest? = nil,
        memoryContext: IPCMemoryContextRequestPayload? = nil,
        memoryRetrieval: IPCMemoryRetrievalRequestPayload? = nil,
        supervisorIncident: IPCSupervisorIncidentAuditPayload? = nil,
        supervisorProjectAction: IPCSupervisorProjectActionAuditPayload? = nil,
        voiceWakeProfileRequest: IPCVoiceWakeProfileRequestPayload? = nil,
        voiceWakeProfile: IPCVoiceWakeProfile? = nil,
        secretVaultCreate: IPCSecretVaultCreateRequestPayload? = nil,
        secretVaultList: IPCSecretVaultListRequestPayload? = nil,
        secretVaultUse: IPCSecretVaultUseRequestPayload? = nil,
        secretVaultRedeem: IPCSecretVaultRedeemRequestPayload? = nil
    ) {
        self.type = type
        self.reqId = reqId
        self.notification = notification
        self.project = project
        self.projectCanonicalMemory = projectCanonicalMemory
        self.deviceCanonicalMemory = deviceCanonicalMemory
        self.network = network
        self.memoryContext = memoryContext
        self.memoryRetrieval = memoryRetrieval
        self.supervisorIncident = supervisorIncident
        self.supervisorProjectAction = supervisorProjectAction
        self.voiceWakeProfileRequest = voiceWakeProfileRequest
        self.voiceWakeProfile = voiceWakeProfile
        self.secretVaultCreate = secretVaultCreate
        self.secretVaultList = secretVaultList
        self.secretVaultUse = secretVaultUse
        self.secretVaultRedeem = secretVaultRedeem
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case notification
        case project
        case projectCanonicalMemory = "project_canonical_memory"
        case deviceCanonicalMemory = "device_canonical_memory"
        case network
        case memoryContext = "memory_context"
        case memoryRetrieval = "memory_retrieval"
        case supervisorIncident = "supervisor_incident"
        case supervisorProjectAction = "supervisor_project_action"
        case voiceWakeProfileRequest = "voice_wake_profile_request"
        case voiceWakeProfile = "voice_wake_profile"
        case secretVaultCreate = "secret_vault_create"
        case secretVaultList = "secret_vault_list"
        case secretVaultUse = "secret_vault_use"
        case secretVaultRedeem = "secret_vault_redeem"
    }
}

public struct IPCResponse: Codable, Sendable {
    public var type: String
    public var reqId: String?
    public var ok: Bool
    public var id: String?
    public var error: String?
    public var memoryContext: IPCMemoryContextResponsePayload?
    public var memoryRetrieval: IPCMemoryRetrievalResponsePayload?
    public var voiceWakeProfile: IPCVoiceWakeProfile?
    public var secretVaultItem: IPCSecretVaultItem?
    public var secretVaultSnapshot: IPCSecretVaultSnapshot?
    public var secretVaultUse: IPCSecretVaultUseResult?
    public var secretVaultRedeem: IPCSecretVaultRedeemResult?

    public init(
        type: String,
        reqId: String? = nil,
        ok: Bool,
        id: String? = nil,
        error: String? = nil,
        memoryContext: IPCMemoryContextResponsePayload? = nil,
        memoryRetrieval: IPCMemoryRetrievalResponsePayload? = nil,
        voiceWakeProfile: IPCVoiceWakeProfile? = nil,
        secretVaultItem: IPCSecretVaultItem? = nil,
        secretVaultSnapshot: IPCSecretVaultSnapshot? = nil,
        secretVaultUse: IPCSecretVaultUseResult? = nil,
        secretVaultRedeem: IPCSecretVaultRedeemResult? = nil
    ) {
        self.type = type
        self.reqId = reqId
        self.ok = ok
        self.id = id
        self.error = error
        self.memoryContext = memoryContext
        self.memoryRetrieval = memoryRetrieval
        self.voiceWakeProfile = voiceWakeProfile
        self.secretVaultItem = secretVaultItem
        self.secretVaultSnapshot = secretVaultSnapshot
        self.secretVaultUse = secretVaultUse
        self.secretVaultRedeem = secretVaultRedeem
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case ok
        case id
        case error
        case memoryContext = "memory_context"
        case memoryRetrieval = "memory_retrieval"
        case voiceWakeProfile = "voice_wake_profile"
        case secretVaultItem = "secret_vault_item"
        case secretVaultSnapshot = "secret_vault_snapshot"
        case secretVaultUse = "secret_vault_use"
        case secretVaultRedeem = "secret_vault_redeem"
    }
}
