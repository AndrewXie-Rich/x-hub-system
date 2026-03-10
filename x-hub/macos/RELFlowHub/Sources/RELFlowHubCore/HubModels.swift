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
    public var budgetTotalTokens: Int
    public var usedTotalTokens: Int
    public var layerUsage: [IPCMemoryContextLayerUsage]
    public var truncatedLayers: [String]
    public var redactedItems: Int
    public var privateDrops: Int

    public init(
        text: String,
        source: String,
        budgetTotalTokens: Int,
        usedTotalTokens: Int,
        layerUsage: [IPCMemoryContextLayerUsage],
        truncatedLayers: [String],
        redactedItems: Int,
        privateDrops: Int
    ) {
        self.text = text
        self.source = source
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
        case budgetTotalTokens = "budget_total_tokens"
        case usedTotalTokens = "used_total_tokens"
        case layerUsage = "layer_usage"
        case truncatedLayers = "truncated_layers"
        case redactedItems = "redacted_items"
        case privateDrops = "private_drops"
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

public struct IPCRequest: Codable, Sendable {
    public var type: String
    public var reqId: String?
    public var notification: HubNotification?
    public var project: HubProjectSnapshot?
    public var network: HubNetworkRequest?
    public var memoryContext: IPCMemoryContextRequestPayload?
    public var supervisorIncident: IPCSupervisorIncidentAuditPayload?

    public init(
        type: String,
        reqId: String? = nil,
        notification: HubNotification? = nil,
        project: HubProjectSnapshot? = nil,
        network: HubNetworkRequest? = nil,
        memoryContext: IPCMemoryContextRequestPayload? = nil,
        supervisorIncident: IPCSupervisorIncidentAuditPayload? = nil
    ) {
        self.type = type
        self.reqId = reqId
        self.notification = notification
        self.project = project
        self.network = network
        self.memoryContext = memoryContext
        self.supervisorIncident = supervisorIncident
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case notification
        case project
        case network
        case memoryContext = "memory_context"
        case supervisorIncident = "supervisor_incident"
    }
}

public struct IPCResponse: Codable, Sendable {
    public var type: String
    public var reqId: String?
    public var ok: Bool
    public var id: String?
    public var error: String?
    public var memoryContext: IPCMemoryContextResponsePayload?

    public init(
        type: String,
        reqId: String? = nil,
        ok: Bool,
        id: String? = nil,
        error: String? = nil,
        memoryContext: IPCMemoryContextResponsePayload? = nil
    ) {
        self.type = type
        self.reqId = reqId
        self.ok = ok
        self.id = id
        self.error = error
        self.memoryContext = memoryContext
    }

    public enum CodingKeys: String, CodingKey {
        case type
        case reqId = "req_id"
        case ok
        case id
        case error
        case memoryContext = "memory_context"
    }
}
