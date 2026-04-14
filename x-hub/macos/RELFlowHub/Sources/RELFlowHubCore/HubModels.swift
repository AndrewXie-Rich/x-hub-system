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
    public var reviewLevelHint: String?
    public var constitutionHint: String?
    public var dialogueWindowText: String?
    public var portfolioBriefText: String?
    public var focusedProjectAnchorPackText: String?
    public var longtermOutlineText: String?
    public var deltaFeedText: String?
    public var conflictSetText: String?
    public var contextRefsText: String?
    public var evidencePackText: String?
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
        reviewLevelHint: String? = nil,
        constitutionHint: String? = nil,
        dialogueWindowText: String? = nil,
        portfolioBriefText: String? = nil,
        focusedProjectAnchorPackText: String? = nil,
        longtermOutlineText: String? = nil,
        deltaFeedText: String? = nil,
        conflictSetText: String? = nil,
        contextRefsText: String? = nil,
        evidencePackText: String? = nil,
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
        self.reviewLevelHint = reviewLevelHint
        self.constitutionHint = constitutionHint
        self.dialogueWindowText = dialogueWindowText
        self.portfolioBriefText = portfolioBriefText
        self.focusedProjectAnchorPackText = focusedProjectAnchorPackText
        self.longtermOutlineText = longtermOutlineText
        self.deltaFeedText = deltaFeedText
        self.conflictSetText = conflictSetText
        self.contextRefsText = contextRefsText
        self.evidencePackText = evidencePackText
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
        case reviewLevelHint = "review_level_hint"
        case constitutionHint = "constitution_hint"
        case dialogueWindowText = "dialogue_window_text"
        case portfolioBriefText = "portfolio_brief_text"
        case focusedProjectAnchorPackText = "focused_project_anchor_pack_text"
        case longtermOutlineText = "longterm_outline_text"
        case deltaFeedText = "delta_feed_text"
        case conflictSetText = "conflict_set_text"
        case contextRefsText = "context_refs_text"
        case evidencePackText = "evidence_pack_text"
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
    public var schemaVersion: String
    public var requestId: String?
    public var scope: String
    public var requesterRole: String
    public var mode: String?
    public var projectId: String?
    public var crossProjectTargetIds: [String]
    public var projectRoot: String?
    public var displayName: String?
    public var query: String?
    public var latestUser: String
    public var allowedLayers: [String]
    public var retrievalKind: String?
    public var maxResults: Int?
    public var reason: String?
    public var requireExplainability: Bool?
    public var requestedKinds: [String]
    public var explicitRefs: [String]
    public var maxSnippets: Int
    public var maxSnippetChars: Int
    public var auditRef: String

    public init(
        schemaVersion: String = "xt.memory_retrieval_request.v1",
        requestId: String? = nil,
        scope: String,
        requesterRole: String,
        mode: String? = nil,
        projectId: String? = nil,
        crossProjectTargetIds: [String] = [],
        projectRoot: String? = nil,
        displayName: String? = nil,
        query: String? = nil,
        latestUser: String,
        allowedLayers: [String] = [],
        retrievalKind: String? = nil,
        maxResults: Int? = nil,
        reason: String? = nil,
        requireExplainability: Bool? = nil,
        requestedKinds: [String] = [],
        explicitRefs: [String] = [],
        maxSnippets: Int = 3,
        maxSnippetChars: Int = 420,
        auditRef: String
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.scope = scope
        self.requesterRole = requesterRole
        self.mode = mode
        self.projectId = projectId
        self.crossProjectTargetIds = crossProjectTargetIds
        self.projectRoot = projectRoot
        self.displayName = displayName
        self.query = query
        self.latestUser = latestUser
        self.allowedLayers = allowedLayers
        self.retrievalKind = retrievalKind
        self.maxResults = maxResults
        self.reason = reason
        self.requireExplainability = requireExplainability
        self.requestedKinds = requestedKinds
        self.explicitRefs = explicitRefs
        self.maxSnippets = maxSnippets
        self.maxSnippetChars = maxSnippetChars
        self.auditRef = auditRef
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case scope
        case requesterRole = "requester_role"
        case mode
        case projectId = "project_id"
        case crossProjectTargetIds = "cross_project_target_ids"
        case projectRoot = "project_root"
        case displayName = "display_name"
        case query
        case latestUser = "latest_user"
        case allowedLayers = "allowed_layers"
        case retrievalKind = "retrieval_kind"
        case maxResults = "max_results"
        case reason
        case requireExplainability = "require_explainability"
        case requestedKinds = "requested_kinds"
        case explicitRefs = "explicit_refs"
        case maxSnippets = "max_snippets"
        case maxSnippetChars = "max_snippet_chars"
        case auditRef = "audit_ref"
    }
}

public struct IPCMemoryRetrievalResultItem: Codable, Sendable, Equatable {
    public var ref: String
    public var sourceKind: String
    public var summary: String
    public var snippet: String
    public var score: Double
    public var redacted: Bool

    public init(
        ref: String,
        sourceKind: String,
        summary: String,
        snippet: String,
        score: Double,
        redacted: Bool
    ) {
        self.ref = ref
        self.sourceKind = sourceKind
        self.summary = summary
        self.snippet = snippet
        self.score = score
        self.redacted = redacted
    }

    public enum CodingKeys: String, CodingKey {
        case ref
        case sourceKind = "source_kind"
        case summary
        case snippet
        case score
        case redacted
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
    public var schemaVersion: String?
    public var requestId: String?
    public var status: String?
    public var resolvedScope: String?
    public var source: String
    public var scope: String
    public var auditRef: String
    public var reasonCode: String?
    public var denyCode: String?
    public var results: [IPCMemoryRetrievalResultItem]?
    public var snippets: [IPCMemoryRetrievalSnippet]
    public var truncated: Bool?
    public var budgetUsedChars: Int?
    public var truncatedItems: Int
    public var redactedItems: Int

    public init(
        schemaVersion: String? = nil,
        requestId: String? = nil,
        status: String? = nil,
        resolvedScope: String? = nil,
        source: String,
        scope: String,
        auditRef: String,
        reasonCode: String? = nil,
        denyCode: String? = nil,
        results: [IPCMemoryRetrievalResultItem]? = nil,
        snippets: [IPCMemoryRetrievalSnippet],
        truncated: Bool? = nil,
        budgetUsedChars: Int? = nil,
        truncatedItems: Int,
        redactedItems: Int
    ) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.status = status
        self.resolvedScope = resolvedScope
        self.source = source
        self.scope = scope
        self.auditRef = auditRef
        self.reasonCode = reasonCode
        self.denyCode = denyCode
        self.results = results
        self.snippets = snippets
        self.truncated = truncated
        self.budgetUsedChars = budgetUsedChars
        self.truncatedItems = truncatedItems
        self.redactedItems = redactedItems
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestId = "request_id"
        case status
        case resolvedScope = "resolved_scope"
        case source
        case scope
        case auditRef = "audit_ref"
        case reasonCode = "reason_code"
        case denyCode = "deny_code"
        case results
        case snippets
        case truncated
        case budgetUsedChars = "budget_used_chars"
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

public struct IPCVoiceTTSRequestPayload: Codable, Sendable, Equatable {
    public var preferredModelID: String
    public var text: String
    public var localeIdentifier: String?
    public var voiceColor: String?
    public var speechRate: Double?

    public init(
        preferredModelID: String,
        text: String,
        localeIdentifier: String? = nil,
        voiceColor: String? = nil,
        speechRate: Double? = nil
    ) {
        self.preferredModelID = preferredModelID
        self.text = text
        self.localeIdentifier = localeIdentifier
        self.voiceColor = voiceColor
        self.speechRate = speechRate
    }

    public enum CodingKeys: String, CodingKey {
        case preferredModelID = "preferred_model_id"
        case text
        case localeIdentifier = "locale_identifier"
        case voiceColor = "voice_color"
        case speechRate = "speech_rate"
    }
}

public struct IPCVoiceTTSReadinessRequestPayload: Codable, Sendable, Equatable {
    public var preferredModelID: String

    public init(preferredModelID: String) {
        self.preferredModelID = preferredModelID
    }

    public enum CodingKeys: String, CodingKey {
        case preferredModelID = "preferred_model_id"
    }
}

public struct IPCVoiceTTSReadinessResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var source: String
    public var provider: String?
    public var modelID: String?
    public var reasonCode: String?
    public var detail: String?

    public init(
        ok: Bool,
        source: String,
        provider: String? = nil,
        modelID: String? = nil,
        reasonCode: String? = nil,
        detail: String? = nil
    ) {
        self.ok = ok
        self.source = source
        self.provider = provider
        self.modelID = modelID
        self.reasonCode = reasonCode
        self.detail = detail
    }

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case provider
        case modelID = "model_id"
        case reasonCode = "reason_code"
        case detail
    }
}

public struct IPCVoiceTTSAudit: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var ok: Bool
    public var taskKind: String
    public var requestID: String
    public var capability: String
    public var provider: String
    public var requestedModelID: String
    public var modelID: String
    public var resolvedModelID: String
    public var routeSource: String
    public var sourceKind: String
    public var outputRefKind: String
    public var engineName: String
    public var speakerId: String
    public var nativeTTSUsed: Bool?
    public var fallbackUsed: Bool
    public var fallbackMode: String
    public var fallbackReasonCode: String
    public var denyCode: String
    public var rawDenyCode: String
    public var locale: String
    public var voiceColor: String
    public var speechRate: Double

    public init(
        schemaVersion: String,
        ok: Bool,
        taskKind: String,
        requestID: String,
        capability: String,
        provider: String,
        requestedModelID: String,
        modelID: String,
        resolvedModelID: String,
        routeSource: String,
        sourceKind: String,
        outputRefKind: String,
        engineName: String,
        speakerId: String,
        nativeTTSUsed: Bool? = nil,
        fallbackUsed: Bool,
        fallbackMode: String,
        fallbackReasonCode: String,
        denyCode: String,
        rawDenyCode: String,
        locale: String,
        voiceColor: String,
        speechRate: Double
    ) {
        self.schemaVersion = schemaVersion
        self.ok = ok
        self.taskKind = taskKind
        self.requestID = requestID
        self.capability = capability
        self.provider = provider
        self.requestedModelID = requestedModelID
        self.modelID = modelID
        self.resolvedModelID = resolvedModelID
        self.routeSource = routeSource
        self.sourceKind = sourceKind
        self.outputRefKind = outputRefKind
        self.engineName = engineName
        self.speakerId = speakerId
        self.nativeTTSUsed = nativeTTSUsed
        self.fallbackUsed = fallbackUsed
        self.fallbackMode = fallbackMode
        self.fallbackReasonCode = fallbackReasonCode
        self.denyCode = denyCode
        self.rawDenyCode = rawDenyCode
        self.locale = locale
        self.voiceColor = voiceColor
        self.speechRate = speechRate
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case ok
        case taskKind = "task_kind"
        case requestID = "request_id"
        case capability
        case provider
        case requestedModelID = "requested_model_id"
        case modelID = "model_id"
        case resolvedModelID = "resolved_model_id"
        case routeSource = "route_source"
        case sourceKind = "source_kind"
        case outputRefKind = "output_ref_kind"
        case engineName = "engine_name"
        case speakerId = "speaker_id"
        case nativeTTSUsed = "native_tts_used"
        case fallbackUsed = "fallback_used"
        case fallbackMode = "fallback_mode"
        case fallbackReasonCode = "fallback_reason_code"
        case denyCode = "deny_code"
        case rawDenyCode = "raw_deny_code"
        case locale
        case voiceColor = "voice_color"
        case speechRate = "speech_rate"
    }
}

public struct IPCVoiceTTSResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var source: String
    public var provider: String?
    public var modelID: String?
    public var taskKind: String?
    public var audioFilePath: String?
    public var audioFormat: String?
    public var voiceName: String?
    public var engineName: String?
    public var speakerId: String?
    public var deviceBackend: String?
    public var nativeTTSUsed: Bool?
    public var fallbackMode: String?
    public var fallbackReasonCode: String?
    public var reasonCode: String?
    public var runtimeReasonCode: String?
    public var error: String?
    public var detail: String?
    public var ttsAudit: IPCVoiceTTSAudit?
    public var ttsAuditLine: String?

    public init(
        ok: Bool,
        source: String,
        provider: String? = nil,
        modelID: String? = nil,
        taskKind: String? = nil,
        audioFilePath: String? = nil,
        audioFormat: String? = nil,
        voiceName: String? = nil,
        engineName: String? = nil,
        speakerId: String? = nil,
        deviceBackend: String? = nil,
        nativeTTSUsed: Bool? = nil,
        fallbackMode: String? = nil,
        fallbackReasonCode: String? = nil,
        reasonCode: String? = nil,
        runtimeReasonCode: String? = nil,
        error: String? = nil,
        detail: String? = nil,
        ttsAudit: IPCVoiceTTSAudit? = nil,
        ttsAuditLine: String? = nil
    ) {
        self.ok = ok
        self.source = source
        self.provider = provider
        self.modelID = modelID
        self.taskKind = taskKind
        self.audioFilePath = audioFilePath
        self.audioFormat = audioFormat
        self.voiceName = voiceName
        self.engineName = engineName
        self.speakerId = speakerId
        self.deviceBackend = deviceBackend
        self.nativeTTSUsed = nativeTTSUsed
        self.fallbackMode = fallbackMode
        self.fallbackReasonCode = fallbackReasonCode
        self.reasonCode = reasonCode
        self.runtimeReasonCode = runtimeReasonCode
        self.error = error
        self.detail = detail
        self.ttsAudit = ttsAudit
        self.ttsAuditLine = ttsAuditLine
    }

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case provider
        case modelID = "model_id"
        case taskKind = "task_kind"
        case audioFilePath = "audio_file_path"
        case audioFormat = "audio_format"
        case voiceName = "voice_name"
        case engineName = "engine_name"
        case speakerId = "speaker_id"
        case deviceBackend = "device_backend"
        case nativeTTSUsed = "native_tts_used"
        case fallbackMode = "fallback_mode"
        case fallbackReasonCode = "fallback_reason_code"
        case reasonCode = "reason_code"
        case runtimeReasonCode = "runtime_reason_code"
        case error
        case detail
        case ttsAudit = "tts_audit"
        case ttsAuditLine = "tts_audit_line"
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

public enum IPCJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: IPCJSONValue])
    case array([IPCJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
            var object: [String: IPCJSONValue] = [:]
            for key in container.allKeys {
                object[key.stringValue] = (try? container.decode(IPCJSONValue.self, forKey: key)) ?? .null
            }
            self = .object(object)
            return
        }
        if var container = try? decoder.unkeyedContainer() {
            var array: [IPCJSONValue] = []
            while !container.isAtEnd {
                array.append((try? container.decode(IPCJSONValue.self)) ?? .null)
            }
            self = .array(array)
            return
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .number(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, nested) in value {
                try container.encode(nested, forKey: DynamicCodingKey(key))
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for nested in value {
                try container.encode(nested)
            }
        case .null:
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int? = nil

        init(_ value: String) {
            self.stringValue = value
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            return nil
        }
    }
}

extension IPCJSONValue {
    public var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        default:
            return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value):
            return value
        case .number(let value):
            return value != 0
        case .string(let value):
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                return nil
            }
        default:
            return nil
        }
    }

    public var objectValue: [String: IPCJSONValue]? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    public var arrayValue: [IPCJSONValue]? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    public var foundationValue: Any {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value
        case .bool(let value):
            return value
        case .object(let value):
            return value.mapValues(\.foundationValue)
        case .array(let value):
            return value.map(\.foundationValue)
        case .null:
            return NSNull()
        }
    }

    public static func fromFoundation(_ value: Any) -> IPCJSONValue {
        switch value {
        case let value as IPCJSONValue:
            return value
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Double:
            return .number(value)
        case let value as Float:
            return .number(Double(value))
        case let value as Int:
            return .number(Double(value))
        case let value as Int8:
            return .number(Double(value))
        case let value as Int16:
            return .number(Double(value))
        case let value as Int32:
            return .number(Double(value))
        case let value as Int64:
            return .number(Double(value))
        case let value as UInt:
            return .number(Double(value))
        case let value as UInt8:
            return .number(Double(value))
        case let value as UInt16:
            return .number(Double(value))
        case let value as UInt32:
            return .number(Double(value))
        case let value as UInt64:
            return .number(Double(value))
        case let value as NSNumber:
            return .number(value.doubleValue)
        case let value as [String: Any]:
            return .object(value.mapValues(IPCJSONValue.fromFoundation))
        case let value as [Any]:
            return .array(value.map(IPCJSONValue.fromFoundation))
        case _ as NSNull:
            return .null
        default:
            return .string(String(describing: value))
        }
    }
}

public struct IPCLocalTaskRequestPayload: Codable, Sendable, Equatable {
    public var schemaVersion: String
    public var taskKind: String
    public var modelID: String
    public var deviceID: String?
    public var timeoutSec: Double?
    public var parameters: [String: IPCJSONValue]

    public init(
        schemaVersion: String = "xhub.local_task_ipc.v1",
        taskKind: String,
        modelID: String,
        deviceID: String? = nil,
        timeoutSec: Double? = nil,
        parameters: [String: IPCJSONValue] = [:]
    ) {
        self.schemaVersion = schemaVersion
        self.taskKind = taskKind
        self.modelID = modelID
        self.deviceID = deviceID
        self.timeoutSec = timeoutSec
        self.parameters = parameters
    }

    public enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case taskKind = "task_kind"
        case modelID = "model_id"
        case deviceID = "device_id"
        case timeoutSec = "timeout_sec"
        case parameters
    }
}

public struct IPCLocalTaskResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var source: String
    public var runtimeSource: String?
    public var provider: String?
    public var modelID: String?
    public var taskKind: String?
    public var reasonCode: String?
    public var runtimeReasonCode: String?
    public var error: String?
    public var detail: String?
    public var payload: [String: IPCJSONValue]

    public init(
        ok: Bool,
        source: String,
        runtimeSource: String? = nil,
        provider: String? = nil,
        modelID: String? = nil,
        taskKind: String? = nil,
        reasonCode: String? = nil,
        runtimeReasonCode: String? = nil,
        error: String? = nil,
        detail: String? = nil,
        payload: [String: IPCJSONValue] = [:]
    ) {
        self.ok = ok
        self.source = source
        self.runtimeSource = runtimeSource
        self.provider = provider
        self.modelID = modelID
        self.taskKind = taskKind
        self.reasonCode = reasonCode
        self.runtimeReasonCode = runtimeReasonCode
        self.error = error
        self.detail = detail
        self.payload = payload
    }

    public enum CodingKeys: String, CodingKey {
        case ok
        case source
        case runtimeSource = "runtime_source"
        case provider
        case modelID = "model_id"
        case taskKind = "task_kind"
        case reasonCode = "reason_code"
        case runtimeReasonCode = "runtime_reason_code"
        case error
        case detail
        case payload
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

public struct IPCNotificationDismissPayload: Codable, Sendable, Equatable {
    public var id: String?
    public var dedupeKey: String?

    public init(id: String? = nil, dedupeKey: String? = nil) {
        self.id = id
        self.dedupeKey = dedupeKey
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case dedupeKey = "dedupe_key"
    }
}

public struct IPCRequest: Codable, Sendable {
    public var type: String
    public var reqId: String?
    public var notification: HubNotification?
    public var notificationDismiss: IPCNotificationDismissPayload?
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
    public var voiceTTSReadiness: IPCVoiceTTSReadinessRequestPayload?
    public var voiceTTS: IPCVoiceTTSRequestPayload?
    public var localTask: IPCLocalTaskRequestPayload?
    public var secretVaultCreate: IPCSecretVaultCreateRequestPayload?
    public var secretVaultList: IPCSecretVaultListRequestPayload?
    public var secretVaultUse: IPCSecretVaultUseRequestPayload?
    public var secretVaultRedeem: IPCSecretVaultRedeemRequestPayload?

    public init(
        type: String,
        reqId: String? = nil,
        notification: HubNotification? = nil,
        notificationDismiss: IPCNotificationDismissPayload? = nil,
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
        voiceTTSReadiness: IPCVoiceTTSReadinessRequestPayload? = nil,
        voiceTTS: IPCVoiceTTSRequestPayload? = nil,
        localTask: IPCLocalTaskRequestPayload? = nil,
        secretVaultCreate: IPCSecretVaultCreateRequestPayload? = nil,
        secretVaultList: IPCSecretVaultListRequestPayload? = nil,
        secretVaultUse: IPCSecretVaultUseRequestPayload? = nil,
        secretVaultRedeem: IPCSecretVaultRedeemRequestPayload? = nil
    ) {
        self.type = type
        self.reqId = reqId
        self.notification = notification
        self.notificationDismiss = notificationDismiss
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
        self.voiceTTSReadiness = voiceTTSReadiness
        self.voiceTTS = voiceTTS
        self.localTask = localTask
        self.secretVaultCreate = secretVaultCreate
        self.secretVaultList = secretVaultList
        self.secretVaultUse = secretVaultUse
        self.secretVaultRedeem = secretVaultRedeem
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case notification
        case notificationDismiss = "notification_dismiss"
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
        case voiceTTSReadiness = "voice_tts_readiness"
        case voiceTTS = "voice_tts"
        case localTask = "local_task"
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
    public var voiceTTSReadiness: IPCVoiceTTSReadinessResult?
    public var voiceTTS: IPCVoiceTTSResult?
    public var localTask: IPCLocalTaskResult?
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
        voiceTTSReadiness: IPCVoiceTTSReadinessResult? = nil,
        voiceTTS: IPCVoiceTTSResult? = nil,
        localTask: IPCLocalTaskResult? = nil,
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
        self.voiceTTSReadiness = voiceTTSReadiness
        self.voiceTTS = voiceTTS
        self.localTask = localTask
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
        case voiceTTSReadiness = "voice_tts_readiness"
        case voiceTTS = "voice_tts"
        case localTask = "local_task"
        case secretVaultItem = "secret_vault_item"
        case secretVaultSnapshot = "secret_vault_snapshot"
        case secretVaultUse = "secret_vault_use"
        case secretVaultRedeem = "secret_vault_redeem"
    }
}
