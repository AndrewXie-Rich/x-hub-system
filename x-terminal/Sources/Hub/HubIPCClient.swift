import Foundation
import Darwin

enum HubIPCClient {
    private static let remoteMemorySnapshotCache = HubRemoteMemorySnapshotCache(ttlSeconds: 15.0)
    private static let remoteAutonomyPolicyOverrideCache = HubRemoteAutonomyPolicyOverrideCache(ttlSeconds: 3.0)
    private static let testingOverrideLock = NSLock()
    private static var secretUseOverrideForTesting: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    private static var secretRedeemOverrideForTesting: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?

    struct AutonomyPolicyOverrideItem: Equatable, Sendable {
        var projectId: String
        var overrideMode: AXProjectAutonomyHubOverrideMode
        var updatedAtMs: Int64
        var reason: String
        var auditRef: String
    }

    struct AutonomyPolicyOverridesSnapshot: Equatable, Sendable {
        var source: String
        var updatedAtMs: Int64
        var items: [AutonomyPolicyOverrideItem]
    }

    struct AgentImportStageResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var preflightStatus: String?
        var skillId: String?
        var policyScope: String?
        var findingsCount: Int
        var vetterStatus: String?
        var vetterCriticalCount: Int
        var vetterWarnCount: Int
        var vetterAuditRef: String?
        var recordPath: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case preflightStatus = "preflight_status"
            case skillId = "skill_id"
            case policyScope = "policy_scope"
            case findingsCount = "findings_count"
            case vetterStatus = "vetter_status"
            case vetterCriticalCount = "vetter_critical_count"
            case vetterWarnCount = "vetter_warn_count"
            case vetterAuditRef = "vetter_audit_ref"
            case recordPath = "record_path"
            case reasonCode = "reason_code"
        }
    }

    struct AgentImportRecordResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var schemaVersion: String?
        var skillId: String?
        var recordJSON: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case schemaVersion = "schema_version"
            case skillId = "skill_id"
            case recordJSON = "record_json"
            case reasonCode = "reason_code"
        }
    }

    struct SkillPackageUploadResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var packageSHA256: String?
        var alreadyPresent: Bool
        var skillId: String?
        var version: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case alreadyPresent = "already_present"
            case skillId = "skill_id"
            case version
            case reasonCode = "reason_code"
        }
    }

    struct AgentImportPromoteResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var packageSHA256: String?
        var scope: String?
        var skillId: String?
        var previousPackageSHA256: String?
        var recordPath: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case packageSHA256 = "package_sha256"
            case scope
            case skillId = "skill_id"
            case previousPackageSHA256 = "previous_package_sha256"
            case recordPath = "record_path"
            case reasonCode = "reason_code"
        }
    }

    struct SkillCatalogEntry: Codable, Equatable, Sendable, Identifiable {
        var skillID: String
        var name: String
        var version: String
        var description: String
        var publisherID: String
        var capabilitiesRequired: [String]
        var sourceID: String
        var packageSHA256: String
        var installHint: String

        var id: String { "\(skillID)::\(version)::\(sourceID)::\(packageSHA256)" }

        enum CodingKeys: String, CodingKey {
            case skillID = "skill_id"
            case name
            case version
            case description
            case publisherID = "publisher_id"
            case capabilitiesRequired = "capabilities_required"
            case sourceID = "source_id"
            case packageSHA256 = "package_sha256"
            case installHint = "install_hint"
        }
    }

    struct SkillsSearchResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var updatedAtMs: Int64
        var results: [SkillCatalogEntry]
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case results
            case reasonCode = "reason_code"
        }
    }

    struct SkillPinResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var scope: String
        var userId: String
        var projectId: String
        var skillId: String
        var packageSHA256: String
        var previousPackageSHA256: String
        var updatedAtMs: Int64
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case scope
            case userId = "user_id"
            case projectId = "project_id"
            case skillId = "skill_id"
            case packageSHA256 = "package_sha256"
            case previousPackageSHA256 = "previous_package_sha256"
            case updatedAtMs = "updated_at_ms"
            case reasonCode = "reason_code"
        }
    }

    struct ResolvedSkillEntry: Codable, Equatable, Sendable, Identifiable {
        var scope: String
        var skill: SkillCatalogEntry

        var id: String { "\(scope)::\(skill.id)" }
    }

    struct ResolvedSkillsResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var skills: [ResolvedSkillEntry]
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skills
            case reasonCode = "reason_code"
        }
    }

    struct SecretVaultItem: Codable, Equatable, Sendable, Identifiable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String
        var createdAtMs: Int64
        var updatedAtMs: Int64

        var id: String { itemId }

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case sensitivity
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct SecretVaultSnapshot: Codable, Equatable, Sendable {
        var source: String
        var updatedAtMs: Int64
        var items: [SecretVaultItem]

        enum CodingKeys: String, CodingKey {
            case source
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    struct SecretCreateRequestPayload: Codable, Equatable, Sendable {
        var scope: String
        var name: String
        var plaintext: String
        var sensitivity: String
        var projectId: String?
        var displayName: String?
        var reason: String?

        enum CodingKeys: String, CodingKey {
            case scope
            case name
            case plaintext
            case sensitivity
            case projectId = "project_id"
            case displayName = "display_name"
            case reason
        }
    }

    struct SecretCreateResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var item: SecretVaultItem?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case item
            case reasonCode = "reason_code"
        }
    }

    struct SecretVaultListRequestPayload: Codable, Equatable, Sendable {
        var scope: String?
        var namePrefix: String?
        var projectId: String?
        var limit: Int

        enum CodingKeys: String, CodingKey {
            case scope
            case namePrefix = "name_prefix"
            case projectId = "project_id"
            case limit
        }
    }

    struct SecretUseRequestPayload: Codable, Equatable, Sendable {
        var itemId: String?
        var scope: String?
        var name: String?
        var projectId: String?
        var purpose: String
        var target: String?
        var ttlMs: Int

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case projectId = "project_id"
            case purpose
            case target
            case ttlMs = "ttl_ms"
        }
    }

    struct SecretUseResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var leaseId: String?
        var useToken: String?
        var itemId: String?
        var expiresAtMs: Int64?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case useToken = "use_token"
            case itemId = "item_id"
            case expiresAtMs = "expires_at_ms"
            case reasonCode = "reason_code"
        }
    }

    struct SecretRedeemRequestPayload: Codable, Equatable, Sendable {
        var useToken: String
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case useToken = "use_token"
            case projectId = "project_id"
        }
    }

    struct SecretRedeemResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var leaseId: String?
        var itemId: String?
        var plaintext: String?
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case itemId = "item_id"
            case plaintext
            case reasonCode = "reason_code"
        }
    }

    struct ProjectSyncPayload: Codable {
        var projectId: String
        var rootPath: String
        var displayName: String
        var statusDigest: String?
        var lastSummaryAt: Double?
        var lastEventAt: Double?
        var updatedAt: Double?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case statusDigest = "status_digest"
            case lastSummaryAt = "last_summary_at"
            case lastEventAt = "last_event_at"
            case updatedAt = "updated_at"
        }
    }

    struct IPCRequest: Codable {
        var type: String
        var reqId: String
        var project: ProjectSyncPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case project
        }
    }

    struct ProjectCanonicalMemoryItemPayload: Codable {
        var key: String
        var value: String
    }

    struct ProjectCanonicalMemoryPayload: Codable {
        var projectId: String
        var projectRoot: String?
        var displayName: String?
        var updatedAt: Double?
        var items: [ProjectCanonicalMemoryItemPayload]

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case updatedAt = "updated_at"
            case items
        }
    }

    struct ProjectCanonicalMemoryIPCRequest: Codable {
        var type: String
        var reqId: String
        var projectCanonicalMemory: ProjectCanonicalMemoryPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case projectCanonicalMemory = "project_canonical_memory"
        }
    }

    struct DeviceCanonicalMemoryPayload: Codable {
        var supervisorId: String
        var displayName: String?
        var updatedAt: Double?
        var items: [ProjectCanonicalMemoryItemPayload]

        enum CodingKeys: String, CodingKey {
            case supervisorId = "supervisor_id"
            case displayName = "display_name"
            case updatedAt = "updated_at"
            case items
        }
    }

    struct DeviceCanonicalMemoryIPCRequest: Codable {
        var type: String
        var reqId: String
        var deviceCanonicalMemory: DeviceCanonicalMemoryPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case deviceCanonicalMemory = "device_canonical_memory"
        }
    }

    struct AckIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
        }
    }

    struct NetworkRequestPayload: Codable {
        var id: String
        var source: String
        var projectId: String?
        var rootPath: String?
        var displayName: String?
        var reason: String?
        var requestedSeconds: Int
        var createdAt: Double

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case projectId = "project_id"
            case rootPath = "root_path"
            case displayName = "display_name"
            case reason
            case requestedSeconds = "requested_seconds"
            case createdAt = "created_at"
        }
    }

    struct NetworkIPCRequest: Codable {
        var type: String
        var reqId: String
        var network: NetworkRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case network
        }
    }

    struct NetworkIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
        }
    }

    struct NotificationPayload: Codable {
        var id: String
        var source: String
        var title: String
        var body: String
        var createdAt: Double
        var dedupeKey: String?
        var actionURL: String?
        var unread: Bool

        enum CodingKeys: String, CodingKey {
            case id
            case source
            case title
            case body
            case createdAt = "created_at"
            case dedupeKey = "dedupe_key"
            case actionURL = "action_url"
            case unread
        }
    }

    struct NotificationIPCRequest: Codable {
        var type: String
        var reqId: String
        var notification: NotificationPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case notification
        }
    }

    struct SupervisorIncidentAuditPayload: Codable {
        var incidentId: String
        var laneId: String
        var taskId: String
        var projectId: String?
        var incidentCode: String
        var eventType: String
        var denyCode: String
        var proposedAction: String
        var severity: String
        var category: String
        var detectedAtMs: Int64
        var handledAtMs: Int64?
        var takeoverLatencyMs: Int64?
        var auditRef: String
        var detail: String?
        var status: String
        var source: String?

        enum CodingKeys: String, CodingKey {
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

    struct SupervisorIncidentAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorIncident: SupervisorIncidentAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorIncident = "supervisor_incident"
        }
    }

    struct SupervisorProjectActionAuditPayload: Codable {
        var eventId: String
        var projectId: String
        var projectName: String
        var eventType: String
        var severity: String
        var actionTitle: String
        var actionSummary: String
        var whyItMatters: String
        var nextAction: String
        var occurredAtMs: Int64
        var deliveryChannel: String
        var deliveryStatus: String
        var jurisdictionRole: String?
        var grantedScope: String?
        var auditRef: String
        var source: String?

        enum CodingKeys: String, CodingKey {
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

    struct SupervisorProjectActionAuditIPCRequest: Codable {
        var type: String
        var reqId: String
        var supervisorProjectAction: SupervisorProjectActionAuditPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case supervisorProjectAction = "supervisor_project_action"
        }
    }

    struct MemoryContextBudgets: Codable, Equatable {
        var totalTokens: Int?
        var l0Tokens: Int?
        var l1Tokens: Int?
        var l2Tokens: Int?
        var l3Tokens: Int?
        var l4Tokens: Int?

        enum CodingKeys: String, CodingKey {
            case totalTokens = "total_tokens"
            case l0Tokens = "l0_tokens"
            case l1Tokens = "l1_tokens"
            case l2Tokens = "l2_tokens"
            case l3Tokens = "l3_tokens"
            case l4Tokens = "l4_tokens"
        }
    }

    struct MemoryContextPayload: Codable {
        var mode: String?
        var projectId: String?
        var projectRoot: String?
        var displayName: String?
        var latestUser: String
        var constitutionHint: String?
        var canonicalText: String?
        var observationsText: String?
        var workingSetText: String?
        var rawEvidenceText: String?
        var servingProfile: String? = nil
        var budgets: MemoryContextBudgets?

        enum CodingKeys: String, CodingKey {
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

    struct MemoryRetrievalPayload: Codable, Equatable {
        var scope: String
        var requesterRole: String
        var projectId: String?
        var projectRoot: String?
        var displayName: String?
        var latestUser: String
        var reason: String?
        var requestedKinds: [String]
        var explicitRefs: [String]
        var maxSnippets: Int
        var maxSnippetChars: Int
        var auditRef: String

        enum CodingKeys: String, CodingKey {
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

    struct MemoryContextIPCRequest: Codable {
        var type: String
        var reqId: String
        var memoryContext: MemoryContextPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case memoryContext = "memory_context"
        }
    }

    struct MemoryRetrievalSnippet: Codable, Equatable, Sendable {
        var snippetId: String
        var sourceKind: String
        var title: String
        var ref: String
        var text: String
        var score: Int
        var truncated: Bool

        enum CodingKeys: String, CodingKey {
            case snippetId = "snippet_id"
            case sourceKind = "source_kind"
            case title
            case ref
            case text
            case score
            case truncated
        }
    }

    struct MemoryRetrievalIPCRequest: Codable {
        var type: String
        var reqId: String
        var memoryRetrieval: MemoryRetrievalPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case memoryRetrieval = "memory_retrieval"
        }
    }

    struct MemoryContextLayerUsage: Codable, Equatable {
        var layer: String
        var usedTokens: Int
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case layer
            case usedTokens = "used_tokens"
            case budgetTokens = "budget_tokens"
        }
    }

    struct MemoryContextResponsePayload: Codable, Equatable {
        var text: String
        var source: String
        var resolvedMode: String?
        var resolvedProfile: String?
        var longtermMode: String?
        var retrievalAvailable: Bool?
        var fulltextNotLoaded: Bool?
        var freshness: String?
        var cacheHit: Bool?
        var denyCode: String?
        var downgradeCode: String?
        var budgetTotalTokens: Int
        var usedTotalTokens: Int
        var layerUsage: [MemoryContextLayerUsage]
        var truncatedLayers: [String]
        var redactedItems: Int
        var privateDrops: Int

        init(
            text: String,
            source: String,
            resolvedMode: String? = nil,
            resolvedProfile: String? = nil,
            longtermMode: String? = nil,
            retrievalAvailable: Bool? = nil,
            fulltextNotLoaded: Bool? = nil,
            freshness: String? = nil,
            cacheHit: Bool? = nil,
            denyCode: String? = nil,
            downgradeCode: String? = nil,
            budgetTotalTokens: Int,
            usedTotalTokens: Int,
            layerUsage: [MemoryContextLayerUsage],
            truncatedLayers: [String],
            redactedItems: Int,
            privateDrops: Int
        ) {
            self.text = text
            self.source = source
            self.resolvedMode = resolvedMode
            self.resolvedProfile = resolvedProfile
            self.longtermMode = longtermMode
            self.retrievalAvailable = retrievalAvailable
            self.fulltextNotLoaded = fulltextNotLoaded
            self.freshness = freshness
            self.cacheHit = cacheHit
            self.denyCode = denyCode
            self.downgradeCode = downgradeCode
            self.budgetTotalTokens = budgetTotalTokens
            self.usedTotalTokens = usedTotalTokens
            self.layerUsage = layerUsage
            self.truncatedLayers = truncatedLayers
            self.redactedItems = redactedItems
            self.privateDrops = privateDrops
        }

        enum CodingKeys: String, CodingKey {
            case text
            case source
            case resolvedMode = "resolved_mode"
            case resolvedProfile = "resolved_profile"
            case longtermMode = "longterm_mode"
            case retrievalAvailable = "retrieval_available"
            case fulltextNotLoaded = "fulltext_not_loaded"
            case freshness
            case cacheHit = "cache_hit"
            case denyCode = "deny_code"
            case downgradeCode = "downgrade_code"
            case budgetTotalTokens = "budget_total_tokens"
            case usedTotalTokens = "used_total_tokens"
            case layerUsage = "layer_usage"
            case truncatedLayers = "truncated_layers"
            case redactedItems = "redacted_items"
            case privateDrops = "private_drops"
        }
    }

    struct MemoryRetrievalResponsePayload: Codable, Equatable, Sendable {
        var source: String
        var scope: String
        var auditRef: String
        var reasonCode: String?
        var denyCode: String?
        var snippets: [MemoryRetrievalSnippet]
        var truncatedItems: Int
        var redactedItems: Int

        enum CodingKeys: String, CodingKey {
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

    struct MemoryContextResolutionResult {
        var response: MemoryContextResponsePayload?
        var source: String
        var resolvedMode: XTMemoryUseMode
        var freshness: String
        var cacheHit: Bool
        var denyCode: String?
        var downgradeCode: String?
        var reasonCode: String?
    }

    struct MemoryContextIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var memoryContext: MemoryContextResponsePayload?
        var memoryRetrieval: MemoryRetrievalResponsePayload?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case memoryContext = "memory_context"
            case memoryRetrieval = "memory_retrieval"
        }
    }

    struct VoiceWakeProfileRequestPayload: Codable, Equatable {
        var desiredWakeMode: String

        enum CodingKeys: String, CodingKey {
            case desiredWakeMode = "desired_wake_mode"
        }
    }

    struct VoiceWakeProfileGetIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceWakeProfileRequest: VoiceWakeProfileRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceWakeProfileRequest = "voice_wake_profile_request"
        }
    }

    struct VoiceWakeProfileSetIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceWakeProfile: VoiceWakeProfile

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceWakeProfile = "voice_wake_profile"
        }
    }

    struct VoiceWakeProfileIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceWakeProfile: VoiceWakeProfile?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceWakeProfile = "voice_wake_profile"
        }
    }

    struct SecretVaultCreateIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultCreate: SecretCreateRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultCreate = "secret_vault_create"
        }
    }

    struct SecretVaultListIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultList: SecretVaultListRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultList = "secret_vault_list"
        }
    }

    struct SecretVaultBeginUseIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultUse: SecretUseRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultUse = "secret_vault_use"
        }
    }

    struct SecretVaultRedeemIPCRequest: Codable {
        var type: String
        var reqId: String
        var secretVaultRedeem: SecretRedeemRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case secretVaultRedeem = "secret_vault_redeem"
        }
    }

    struct SecretVaultCreateIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultItem: SecretVaultItem?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultItem = "secret_vault_item"
        }
    }

    struct SecretVaultListIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultSnapshot: SecretVaultSnapshot?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultSnapshot = "secret_vault_snapshot"
        }
    }

    struct SecretVaultUseIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultUse: SecretUseResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultUse = "secret_vault_use"
        }
    }

    struct SecretVaultRedeemIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var secretVaultRedeem: SecretRedeemResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case secretVaultRedeem = "secret_vault_redeem"
        }
    }

    struct SchedulerScopeCount: Codable, Equatable {
        var scopeKey: String
        var count: Int
    }

    struct SchedulerQueueItem: Codable, Equatable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double
        var queuedMs: Int
    }

    struct SchedulerStatusSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var inFlightTotal: Int
        var queueDepth: Int
        var oldestQueuedMs: Int
        var inFlightByScope: [SchedulerScopeCount]
        var queuedByScope: [SchedulerScopeCount]
        var queueItems: [SchedulerQueueItem]
    }

    struct PendingGrantItem: Codable, Equatable, Identifiable {
        var grantRequestId: String
        var requestId: String
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int
        var requestedTokenCap: Int
        var status: String
        var decision: String
        var createdAtMs: Double
        var decidedAtMs: Double

        var id: String { grantRequestId }
    }

    struct PendingGrantSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [PendingGrantItem]
    }

    struct ConnectorIngressReceipt: Codable, Equatable, Identifiable {
        var receiptId: String
        var requestId: String
        var projectId: String
        var connector: String
        var targetId: String
        var ingressType: String
        var channelScope: String
        var sourceId: String
        var messageId: String
        var dedupeKey: String
        var receivedAtMs: Double
        var eventSequence: Int64
        var deliveryState: String
        var runtimeState: String

        var id: String { receiptId }
    }

    struct ConnectorIngressSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [ConnectorIngressReceipt]
    }

    struct OperatorChannelXTCommandItem: Codable, Equatable, Identifiable {
        var commandId: String
        var requestId: String
        var actionName: String
        var bindingId: String
        var routeId: String
        var scopeType: String
        var scopeId: String
        var projectId: String
        var provider: String
        var accountId: String
        var conversationId: String
        var threadKey: String
        var actorRef: String
        var resolvedDeviceId: String
        var preferredDeviceId: String
        var note: String
        var createdAtMs: Double
        var auditRef: String

        var id: String { commandId }

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case bindingId = "binding_id"
            case routeId = "route_id"
            case scopeType = "scope_type"
            case scopeId = "scope_id"
            case projectId = "project_id"
            case provider
            case accountId = "account_id"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
            case actorRef = "actor_ref"
            case resolvedDeviceId = "resolved_device_id"
            case preferredDeviceId = "preferred_device_id"
            case note
            case createdAtMs = "created_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct OperatorChannelXTCommandSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [OperatorChannelXTCommandItem]
    }

    struct OperatorChannelXTCommandResultItem: Codable, Equatable, Identifiable {
        var commandId: String
        var requestId: String
        var actionName: String
        var projectId: String
        var resolvedDeviceId: String
        var status: String
        var denyCode: String
        var detail: String
        var runId: String
        var createdAtMs: Double
        var completedAtMs: Double
        var auditRef: String

        var id: String { commandId }

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case projectId = "project_id"
            case resolvedDeviceId = "resolved_device_id"
            case status
            case denyCode = "deny_code"
            case detail
            case runId = "run_id"
            case createdAtMs = "created_at_ms"
            case completedAtMs = "completed_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct OperatorChannelXTCommandResultSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [OperatorChannelXTCommandResultItem]
    }

    enum PendingGrantActionDecision: String {
        case approved
        case denied
        case failed
    }

    struct PendingGrantActionResult {
        var ok: Bool
        var decision: PendingGrantActionDecision
        var source: String
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reasonCode: String?
    }

    struct VoiceGrantChallengeRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String?
        var templateId: String
        var actionDigest: String
        var scopeDigest: String
        var amountDigest: String?
        var challengeCode: String?
        var riskLevel: String
        var boundDeviceId: String?
        var mobileTerminalId: String?
        var allowVoiceOnly: Bool
        var requiresMobileConfirm: Bool
        var ttlMs: Int

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case templateId = "template_id"
            case actionDigest = "action_digest"
            case scopeDigest = "scope_digest"
            case amountDigest = "amount_digest"
            case challengeCode = "challenge_code"
            case riskLevel = "risk_level"
            case boundDeviceId = "bound_device_id"
            case mobileTerminalId = "mobile_terminal_id"
            case allowVoiceOnly = "allow_voice_only"
            case requiresMobileConfirm = "requires_mobile_confirm"
            case ttlMs = "ttl_ms"
        }
    }

    struct VoiceGrantChallengeSnapshot: Codable, Equatable, Identifiable {
        var challengeId: String
        var templateId: String
        var actionDigest: String
        var scopeDigest: String
        var amountDigest: String
        var challengeCode: String
        var riskLevel: String
        var requiresMobileConfirm: Bool
        var allowVoiceOnly: Bool
        var boundDeviceId: String
        var mobileTerminalId: String
        var issuedAtMs: Double
        var expiresAtMs: Double

        var id: String { challengeId }

        enum CodingKeys: String, CodingKey {
            case challengeId = "challenge_id"
            case templateId = "template_id"
            case actionDigest = "action_digest"
            case scopeDigest = "scope_digest"
            case amountDigest = "amount_digest"
            case challengeCode = "challenge_code"
            case riskLevel = "risk_level"
            case requiresMobileConfirm = "requires_mobile_confirm"
            case allowVoiceOnly = "allow_voice_only"
            case boundDeviceId = "bound_device_id"
            case mobileTerminalId = "mobile_terminal_id"
            case issuedAtMs = "issued_at_ms"
            case expiresAtMs = "expires_at_ms"
        }
    }

    struct VoiceGrantChallengeResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var challenge: VoiceGrantChallengeSnapshot?
        var reasonCode: String?
    }

    struct VoiceGrantVerificationPayload: Codable, Equatable {
        var requestId: String
        var projectId: String?
        var challengeId: String
        var challengeCode: String?
        var transcript: String?
        var transcriptHash: String?
        var semanticMatchScore: Double?
        var parsedActionDigest: String?
        var parsedScopeDigest: String?
        var parsedAmountDigest: String?
        var verifyNonce: String
        var boundDeviceId: String?
        var mobileConfirmed: Bool

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case challengeId = "challenge_id"
            case challengeCode = "challenge_code"
            case transcript
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case parsedActionDigest = "parsed_action_digest"
            case parsedScopeDigest = "parsed_scope_digest"
            case parsedAmountDigest = "parsed_amount_digest"
            case verifyNonce = "verify_nonce"
            case boundDeviceId = "bound_device_id"
            case mobileConfirmed = "mobile_confirmed"
        }
    }

    enum VoiceGrantVerificationDecision: String, Codable {
        case allow
        case deny
        case failed
    }

    struct VoiceGrantVerificationResult: Codable, Equatable {
        var ok: Bool
        var verified: Bool
        var decision: VoiceGrantVerificationDecision
        var source: String
        var denyCode: String?
        var challengeId: String?
        var transcriptHash: String?
        var semanticMatchScore: Double
        var challengeMatch: Bool
        var deviceBindingOK: Bool
        var mobileConfirmed: Bool
        var reasonCode: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case verified
            case decision
            case source
            case denyCode = "deny_code"
            case challengeId = "challenge_id"
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case challengeMatch = "challenge_match"
            case deviceBindingOK = "device_binding_ok"
            case mobileConfirmed = "mobile_confirmed"
            case reasonCode = "reason_code"
        }
    }

    struct NetworkRequestTicket: Equatable {
        var reqId: String
        var baseDir: URL
    }

    private struct LocalIPCTransport {
        var mode: String
        var ipcURL: URL
        var baseDir: URL
    }

    private struct NetworkIPCDispatchResult {
        var ticket: NetworkRequestTicket
        var ack: NetworkIPCResponse?
        var source: String
    }

    enum NetworkAccessState: String {
        case enabled
        case autoApproved
        case queued
        case denied
        case failed
    }

    struct NetworkAccessResult {
        var state: NetworkAccessState
        var source: String
        var reasonCode: String?
        var remainingSeconds: Int?
        var grantRequestId: String?
    }

    private static func currentRouteDecision() async -> HubRouteDecision {
        let mode = HubAIClient.transportMode()
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        return HubRouteStateMachine.resolve(mode: mode, hasRemoteProfile: hasRemote)
    }

    private static func localIPCTransport(ttl: Double = 3.0) -> LocalIPCTransport? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: ttl) else { return nil }
        let mode = (st.ipcMode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let ipcPath = (st.ipcPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mode.isEmpty, !ipcPath.isEmpty else { return nil }

        let ipcURL: URL
        switch mode {
        case "file":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: true)
        case "socket":
            ipcURL = URL(fileURLWithPath: ipcPath, isDirectory: false)
        default:
            return nil
        }

        return LocalIPCTransport(
            mode: mode,
            ipcURL: ipcURL,
            baseDir: URL(fileURLWithPath: st.baseDir, isDirectory: true)
        )
    }

    private static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        var totalWritten = 0
        return data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return false }
            while totalWritten < data.count {
                let written = Darwin.write(fd, base.advanced(by: totalWritten), data.count - totalWritten)
                if written <= 0 { return false }
                totalWritten += written
            }
            return true
        }
    }

    private static func sendSocketRequest<Request: Encodable, Response: Decodable>(
        _ request: Request,
        socketURL: URL,
        timeoutSec: Double = 2.0
    ) -> Response? {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        let bytes = Array(socketURL.path.utf8) + [0]
        guard bytes.count <= maxLen else { return nil }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: maxLen) { buf in
                for index in 0..<bytes.count {
                    buf[index] = bytes[index]
                }
            }
        }

        var socketAddr = addr
        let connectRC = withUnsafePointer(to: &socketAddr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectRC == 0 else { return nil }

        let clampedTimeout = max(0.2, min(4.0, timeoutSec))
        var timeout = timeval(
            tv_sec: Int(clampedTimeout.rounded(.down)),
            tv_usec: __darwin_suseconds_t((clampedTimeout.truncatingRemainder(dividingBy: 1)) * 1_000_000)
        )
        withUnsafePointer(to: &timeout) { ptr in
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, ptr, socklen_t(MemoryLayout<timeval>.size))
        }

        guard let encoded = try? JSONEncoder().encode(request) else { return nil }
        var payload = encoded
        payload.append(0x0A)
        guard writeAll(payload, to: fd) else { return nil }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > 262_144 { return nil }
            if buffer.contains(0x0A) { break }
        }

        guard let lineEnd = buffer.firstIndex(of: 0x0A) else { return nil }
        let line = buffer.prefix(upTo: lineEnd)
        return try? JSONDecoder().decode(Response.self, from: line)
    }

    static func fetchVoiceWakeProfile(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                desiredWakeMode: desiredWakeMode
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile fetch requires remote route"],
                syncedAtMs: nil
            )
        }

        return await fetchVoiceWakeProfileViaLocalIPC(desiredWakeMode: desiredWakeMode)
    }

    static func setVoiceWakeProfile(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteVoiceWakeProfile(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                profile: profile
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return remote
            }
        }

        if routeDecision.requiresRemote {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                profile: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                ),
                logLines: ["voice wake profile set requires remote route"],
                syncedAtMs: nil
            )
        }

        return await setVoiceWakeProfileViaLocalIPC(profile)
    }

    static func syncProject(_ entry: AXProjectEntry) {
        let payload = ProjectSyncPayload(
            projectId: entry.projectId,
            rootPath: entry.rootPath,
            displayName: entry.displayName,
            statusDigest: entry.statusDigest,
            lastSummaryAt: entry.lastSummaryAt,
            lastEventAt: entry.lastEventAt,
            updatedAt: Date().timeIntervalSince1970
        )

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await syncProjectViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeProjectSyncViaFileIPC(payload)
        }
    }

    static func appendProjectConversationTurn(
        ctx: AXProjectContext,
        userText: String,
        assistantText: String,
        createdAt: Double,
        config: AXProjectConfig?
    ) async -> Bool {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return false }

        let mirroredMessages = XTProjectConversationMirror.messages(
            userText: userText,
            assistantText: assistantText
        )
        guard !mirroredMessages.isEmpty else { return false }

        let routeDecision = await currentRouteDecision()
        guard routeDecision.preferRemote else { return false }

        let projectId = AXProjectRegistryStore.projectId(forRoot: ctx.root)
        let payload = HubRemoteProjectConversationPayload(
            projectId: projectId,
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: projectId),
            requestId: XTProjectConversationMirror.requestID(projectId: projectId, createdAt: createdAt),
            createdAtMs: XTProjectConversationMirror.createdAtMs(createdAt),
            userText: mirroredMessages.first(where: { $0.role == "user" })?.content ?? "",
            assistantText: mirroredMessages.first(where: { $0.role == "assistant" })?.content ?? ""
        )

        let remote = await HubPairingCoordinator.shared.appendRemoteProjectConversationTurn(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            payload: payload
        )
        if remote.ok {
            await remoteMemorySnapshotCache.invalidate(projectId: projectId)
        }
        return remote.ok
    }

    static func syncProjectCanonicalMemory(
        ctx: AXProjectContext,
        memory: AXMemory,
        config: AXProjectConfig?
    ) {
        guard XTProjectMemoryGovernance.prefersHubMemory(config) else { return }

        let payload = ProjectCanonicalMemoryPayload(
            projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
            projectRoot: ctx.root.path,
            displayName: ctx.projectName(),
            updatedAt: memory.updatedAt,
            items: XTProjectCanonicalMemorySync.items(memory: memory).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            if writeProjectCanonicalMemoryViaLocalIPC(payload) {
                Task {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        }
    }

    static func syncSupervisorProjectCapsule(_ capsule: SupervisorProjectCapsule) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: capsule.projectId,
            projectRoot: nil,
            displayName: capsule.projectName,
            updatedAt: Double(capsule.updatedAtMs) / 1000.0,
            items: SupervisorProjectCapsuleCanonicalSync.items(capsule: capsule).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let wroteLocal = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let synced = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        case .auto:
            Task {
                let synced = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        case .fileIPC:
            if wroteLocal {
                Task {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        }
    }

    static func syncSupervisorProjectWorkflow(_ snapshot: SupervisorProjectWorkflowSnapshot) {
        let payload = ProjectCanonicalMemoryPayload(
            projectId: snapshot.projectId,
            projectRoot: nil,
            displayName: snapshot.projectName,
            updatedAt: Double(snapshot.updatedAtMs) / 1000.0,
            items: SupervisorProjectWorkflowCanonicalSync.items(snapshot: snapshot).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !payload.items.isEmpty else { return }

        let wroteLocal = writeProjectCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let synced = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        case .auto:
            Task {
                let synced = await syncProjectCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        case .fileIPC:
            if wroteLocal {
                Task {
                    await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                }
            }
        }
    }

    static func syncSupervisorPortfolioSnapshot(
        _ snapshot: SupervisorPortfolioSnapshot,
        supervisorId: String = defaultSupervisorCanonicalID(),
        displayName: String? = nil
    ) {
        let normalizedSupervisorId = supervisorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSupervisorId.isEmpty else { return }

        let payload = DeviceCanonicalMemoryPayload(
            supervisorId: normalizedSupervisorId,
            displayName: displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
            updatedAt: snapshot.updatedAt,
            items: SupervisorPortfolioSnapshotCanonicalSync.items(
                snapshot: snapshot,
                supervisorId: normalizedSupervisorId
            ).map { item in
                ProjectCanonicalMemoryItemPayload(key: item.key, value: item.value)
            }
        )
        guard !payload.items.isEmpty else { return }

        let wroteLocal = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                let synced = await syncDeviceCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await invalidateSupervisorMemoryCache()
                }
            }
        case .auto:
            Task {
                let synced = await syncDeviceCanonicalMemoryViaPreferredRoute(payload: payload, allowFileFallback: false)
                if synced || wroteLocal {
                    await invalidateSupervisorMemoryCache()
                }
            }
        case .fileIPC:
            if wroteLocal {
                Task {
                    await invalidateSupervisorMemoryCache()
                }
            }
        }
    }

    static func requestNetworkAccess(root: URL, seconds: Int, reason: String?) async -> NetworkAccessResult {
        let bridge = HubBridgeClient.status()
        if bridge.enabled {
            let remaining = Int(max(0, bridge.enabledUntil - Date().timeIntervalSince1970))
            return NetworkAccessResult(
                state: .enabled,
                source: "bridge",
                reasonCode: nil,
                remainingSeconds: remaining,
                grantRequestId: nil
            )
        }

        let routeDecision = await currentRouteDecision()
        let requestedSeconds = max(30, min(86_400, seconds))
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        if routeDecision.preferRemote {
            let grant = await HubPairingCoordinator.shared.requestRemoteNetworkGrant(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestedSeconds: requestedSeconds,
                reason: reason,
                projectId: projectId
            )
            let grantId = normalized(grant.grantRequestId)
            let reasonCode = normalizedReasonCode(grant.reasonCode, fallback: grant.ok ? nil : "grant_failed")

            if grant.ok {
                switch grant.decision {
                case .approved:
                    let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                    if bridgeAfterGrant.enabled {
                        let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                        return NetworkAccessResult(
                            state: .autoApproved,
                            source: "grpc",
                            reasonCode: "auto_approved",
                            remainingSeconds: remaining,
                            grantRequestId: grantId
                        )
                    }
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: "grpc",
                        reasonCode: "bridge_starting",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .queued:
                    return NetworkAccessResult(
                        state: .queued,
                        source: "grpc",
                        reasonCode: reasonCode ?? "queued",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .denied:
                    return NetworkAccessResult(
                        state: .denied,
                        source: "grpc",
                        reasonCode: reasonCode ?? "denied",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )

                case .failed:
                    if routeDecision.allowFileFallback,
                       HubRouteStateMachine.shouldFallbackToFile(afterRemoteReasonCode: reasonCode) {
                        break
                    }
                    return NetworkAccessResult(
                        state: networkFailureState(reasonCode: reasonCode),
                        source: "grpc",
                        reasonCode: reasonCode ?? "grant_failed",
                        remainingSeconds: nil,
                        grantRequestId: grantId
                    )
                }
            }

            if !routeDecision.allowFileFallback {
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: "grpc",
                    reasonCode: reasonCode ?? "grant_failed",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }
        } else if routeDecision.requiresRemote {
            return NetworkAccessResult(
                state: .failed,
                source: "grpc",
                reasonCode: routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        guard let dispatch = requestNetworkViaLocalIPC(root: root, seconds: requestedSeconds, reason: reason) else {
            return NetworkAccessResult(
                state: .failed,
                source: "local_ipc",
                reasonCode: "hub_not_connected",
                remainingSeconds: nil,
                grantRequestId: nil
            )
        }

        let ack: NetworkIPCResponse?
        if let existingAck = dispatch.ack {
            ack = existingAck
        } else {
            ack = await pollNetworkResponse(
                baseDir: dispatch.ticket.baseDir,
                reqId: dispatch.ticket.reqId,
                timeoutSec: 2.6
            )
        }
        if let ack {
            let grantId = normalized(ack.id) ?? dispatch.ticket.reqId
            if !ack.ok {
                let reasonCode = normalizedReasonCode(ack.error, fallback: "denied") ?? "denied"
                return NetworkAccessResult(
                    state: networkFailureState(reasonCode: reasonCode),
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            let reasonCode = normalizedReasonCode(ack.error, fallback: nil)
            if reasonCode == "auto_approved" {
                let bridgeAfterGrant = await waitForBridgeEnabled(timeoutSec: 4.2)
                if bridgeAfterGrant.enabled {
                    let remaining = Int(max(0, bridgeAfterGrant.enabledUntil - Date().timeIntervalSince1970))
                    return NetworkAccessResult(
                        state: .autoApproved,
                        source: dispatch.source,
                        reasonCode: "auto_approved",
                        remainingSeconds: remaining,
                        grantRequestId: grantId
                    )
                }
                return NetworkAccessResult(
                    state: .autoApproved,
                    source: dispatch.source,
                    reasonCode: "bridge_starting",
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            if reasonCode == "denied" || reasonCode == "forbidden" {
                return NetworkAccessResult(
                    state: .denied,
                    source: dispatch.source,
                    reasonCode: reasonCode,
                    remainingSeconds: nil,
                    grantRequestId: grantId
                )
            }

            return NetworkAccessResult(
                state: .queued,
                source: dispatch.source,
                reasonCode: reasonCode ?? "queued",
                remainingSeconds: nil,
                grantRequestId: grantId
            )
        }

        if dispatch.source == "file_ipc" {
            let bridgeAfterFileRequest = HubBridgeClient.status()
            if bridgeAfterFileRequest.enabled {
                let remaining = Int(max(0, bridgeAfterFileRequest.enabledUntil - Date().timeIntervalSince1970))
                return NetworkAccessResult(
                    state: .enabled,
                    source: "bridge",
                    reasonCode: nil,
                    remainingSeconds: remaining,
                    grantRequestId: dispatch.ticket.reqId
                )
            }
        }

        return NetworkAccessResult(
            state: .queued,
            source: dispatch.source,
            reasonCode: "ack_timeout",
            remainingSeconds: nil,
            grantRequestId: dispatch.ticket.reqId
        )
    }

    private static func requestNetworkViaLocalIPC(root: URL, seconds: Int, reason: String?) -> NetworkIPCDispatchResult? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }
        let reqId = UUID().uuidString
        let rootPath = AXProjectRegistryStore.normalizedRootPath(root)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let reg = AXProjectRegistryStore.load()
        let displayName = reg.projects.first(where: { $0.projectId == projectId })?.displayName

        let payload = NetworkRequestPayload(
            id: reqId,
            source: "x_terminal",
            projectId: projectId,
            rootPath: rootPath,
            displayName: displayName,
            reason: reason?.trimmingCharacters(in: .whitespacesAndNewlines),
            requestedSeconds: max(10, seconds),
            createdAt: Date().timeIntervalSince1970
        )
        let req = NetworkIPCRequest(type: "need_network", reqId: reqId, network: payload)
        let ticket = NetworkRequestTicket(reqId: reqId, baseDir: transport.baseDir)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else { return nil }
            if writeEvent(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_net",
                tmpPrefix: ".xterminal_net",
                in: transport.ipcURL
            ) {
                return NetworkIPCDispatchResult(ticket: ticket, ack: nil, source: "file_ipc")
            }
        case "socket":
            guard let ack: NetworkIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return nil
            }
            return NetworkIPCDispatchResult(ticket: ticket, ack: ack, source: "socket_ipc")
        default:
            return nil
        }

        return nil
    }

    @discardableResult
    private static func syncProjectViaPreferredRoute(
        payload: ProjectSyncPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.syncRemoteProjectSnapshot(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectSyncPayload(
                    projectId: payload.projectId,
                    rootPath: payload.rootPath,
                    displayName: payload.displayName,
                    statusDigest: payload.statusDigest,
                    lastSummaryAt: payload.lastSummaryAt,
                    lastEventAt: payload.lastEventAt,
                    updatedAt: payload.updatedAt
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeProjectSyncViaFileIPC(payload)
    }

    @discardableResult
    private static func syncProjectCanonicalMemoryViaPreferredRoute(
        payload: ProjectCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }
        let didWriteLocal = writeProjectCanonicalMemoryViaLocalIPC(payload)
        if didWriteLocal {
            await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
        }
        return didWriteLocal
    }

    private static func writeProjectSyncViaFileIPC(_ payload: ProjectSyncPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = IPCRequest(type: "project_sync", reqId: reqId, project: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal", tmpPrefix: ".xterminal", in: dir)
    }

    private static func writeProjectCanonicalMemoryViaLocalIPC(_ payload: ProjectCanonicalMemoryPayload) -> Bool {
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }

        let reqId = UUID().uuidString
        let req = ProjectCanonicalMemoryIPCRequest(
            type: "project_canonical_memory",
            reqId: reqId,
            projectCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else { return false }
            return writeEvent(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_project_memory",
                tmpPrefix: ".xterminal_project_memory",
                in: transport.ipcURL
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return false
            }
            return ack.ok
        default:
            return false
        }
    }

    @discardableResult
    private static func syncDeviceCanonicalMemoryViaPreferredRoute(
        payload: DeviceCanonicalMemoryPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.upsertRemoteDeviceCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteDeviceCanonicalMemoryPayload(
                    items: payload.items.map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await invalidateSupervisorMemoryCache()
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        let didWriteLocal = writeDeviceCanonicalMemoryViaLocalIPC(payload)
        if didWriteLocal {
            await invalidateSupervisorMemoryCache()
        }
        return didWriteLocal
    }

    private static func writeDeviceCanonicalMemoryViaLocalIPC(_ payload: DeviceCanonicalMemoryPayload) -> Bool {
        guard let transport = localIPCTransport(ttl: 3.0) else { return false }

        let reqId = UUID().uuidString
        let req = DeviceCanonicalMemoryIPCRequest(
            type: "device_canonical_memory",
            reqId: reqId,
            deviceCanonicalMemory: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else { return false }
            return writeEvent(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_device_memory",
                tmpPrefix: ".xterminal_device_memory",
                in: transport.ipcURL
            )
        case "socket":
            guard let ack: AckIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return false
            }
            return ack.ok
        default:
            return false
        }
    }

    private static func invalidateSupervisorMemoryCache() async {
        await remoteMemorySnapshotCache.invalidate(
            key: HubRemoteMemorySnapshotCache.Key(
                mode: XTMemoryUseMode.supervisorOrchestration.rawValue,
                projectId: nil
            )
        )
    }

    static func defaultSupervisorCanonicalID() -> String {
        let raw = Host.current().localizedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let scalars = raw.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        let token = String(String.UnicodeScalarView(scalars))
        return token.isEmpty ? "supervisor-main" : "supervisor-\(token)"
    }

    @discardableResult
    private static func pushNotificationViaPreferredRoute(
        payload: NotificationPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.pushRemoteNotificationMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteNotificationPayload(
                    source: payload.source,
                    title: payload.title,
                    body: payload.body,
                    dedupeKey: payload.dedupeKey,
                    actionURL: payload.actionURL,
                    unread: payload.unread
                )
            )
            if remote.ok {
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeNotificationViaFileIPC(payload)
    }

    private static func writeNotificationViaFileIPC(_ payload: NotificationPayload) -> Bool {
        guard let dir = fileIPCEventsDir() else { return false }
        let reqId = UUID().uuidString
        let req = NotificationIPCRequest(type: "push_notification", reqId: reqId, notification: payload)
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(req) else { return false }
        return writeEvent(data: data, reqId: reqId, filePrefix: "xterminal_notify", tmpPrefix: ".xterminal_notify", in: dir)
    }

    static func requestMemoryContext(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        constitutionHint: String?,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResponsePayload? {
        let result = await requestMemoryContextDetailed(
            useMode: useMode,
            requesterRole: requesterRole,
            projectId: projectId,
            projectRoot: projectRoot,
            displayName: displayName,
            latestUser: latestUser,
            constitutionHint: constitutionHint,
            canonicalText: canonicalText,
            observationsText: observationsText,
            workingSetText: workingSetText,
            rawEvidenceText: rawEvidenceText,
            servingProfile: servingProfile,
            budgets: budgets,
            timeoutSec: timeoutSec
        )
        return result.response
    }

    struct MemoryLongtermDisclosure: Equatable {
        var longtermMode: String
        var retrievalAvailable: Bool
        var fulltextNotLoaded: Bool
    }

    static func resolveMemoryLongtermDisclosure(
        useMode: XTMemoryUseMode,
        retrievalAvailable fallbackRetrievalAvailable: Bool,
        overrideLongtermMode: String? = nil,
        overrideRetrievalAvailable: Bool? = nil,
        overrideFulltextNotLoaded: Bool? = nil
    ) -> MemoryLongtermDisclosure {
        let defaultLongtermMode: String
        switch useMode {
        case .projectChat where fallbackRetrievalAvailable:
            defaultLongtermMode = "progressive_disclosure"
        case .laneHandoff:
            defaultLongtermMode = XTMemoryLongtermPolicy.denied.rawValue
        default:
            defaultLongtermMode = XTMemoryLongtermPolicy.summaryOnly.rawValue
        }

        return MemoryLongtermDisclosure(
            longtermMode: normalized(overrideLongtermMode) ?? defaultLongtermMode,
            retrievalAvailable: overrideRetrievalAvailable ?? fallbackRetrievalAvailable,
            fulltextNotLoaded: overrideFulltextNotLoaded ?? true
        )
    }

    static func ensureMemoryLongtermDisclosureText(
        _ text: String,
        disclosure: MemoryLongtermDisclosure
    ) -> String {
        guard !text.contains("[LONGTERM_MEMORY]") else { return text }
        let section = """
[LONGTERM_MEMORY]
longterm_mode=\(disclosure.longtermMode)
retrieval_available=\(disclosure.retrievalAvailable ? "true" : "false")
fulltext_not_loaded=\(disclosure.fulltextNotLoaded ? "true" : "false")
[/LONGTERM_MEMORY]
"""

        if let range = text.range(of: "[/SERVING_PROFILE]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        if let range = text.range(of: "[MEMORY_V1]\n") {
            return String(text[..<range.upperBound]) + section + "\n" + String(text[range.upperBound...])
        }
        return section + "\n" + text
    }

    static func requestMemoryContextDetailed(
        useMode: XTMemoryUseMode,
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        constitutionHint: String?,
        canonicalText: String?,
        observationsText: String?,
        workingSetText: String?,
        rawEvidenceText: String?,
        servingProfile: XTMemoryServingProfile? = nil,
        budgets: MemoryContextBudgets? = nil,
        timeoutSec: Double = 1.2
    ) async -> MemoryContextResolutionResult {
        let rawPayload = MemoryContextPayload(
            mode: useMode.rawValue,
            projectId: normalized(projectId),
            projectRoot: normalized(projectRoot),
            displayName: normalized(displayName),
            latestUser: latestUser,
            constitutionHint: normalized(constitutionHint),
            canonicalText: normalized(canonicalText),
            observationsText: normalized(observationsText),
            workingSetText: normalized(workingSetText),
            rawEvidenceText: normalized(rawEvidenceText),
            servingProfile: servingProfile?.rawValue,
            budgets: budgets
        )
        let route = XTMemoryRoleScopedRouter.route(
            role: requesterRole,
            mode: useMode,
            payload: rawPayload
        )
        if let denyCode = route.denyCode?.rawValue {
            return MemoryContextResolutionResult(
                response: nil,
                source: "memory_router",
                resolvedMode: useMode,
                freshness: "unavailable",
                cacheHit: false,
                denyCode: denyCode,
                downgradeCode: route.downgradeCode?.rawValue,
                reasonCode: denyCode
            )
        }

        let payload = route.payload
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await fetchRemoteMemorySnapshot(
                mode: useMode,
                projectId: payload.projectId,
                bypassCache: route.bypassRemoteCache
            )
            if remote.snapshot.ok {
                var response = buildMemoryContextFromRemoteSnapshot(snapshot: remote.snapshot, payload: payload)
                let disclosure = resolveMemoryLongtermDisclosure(
                    useMode: useMode,
                    retrievalAvailable: false,
                    overrideLongtermMode: response.longtermMode,
                    overrideRetrievalAvailable: response.retrievalAvailable,
                    overrideFulltextNotLoaded: response.fulltextNotLoaded
                )
                response.resolvedMode = useMode.rawValue
                response.resolvedProfile = route.servingProfile.rawValue
                response.longtermMode = disclosure.longtermMode
                response.retrievalAvailable = disclosure.retrievalAvailable
                response.fulltextNotLoaded = disclosure.fulltextNotLoaded
                response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
                response.freshness = remote.cacheHit ? "ttl_cache" : "fresh_remote"
                response.cacheHit = remote.cacheHit
                response.denyCode = nil
                response.downgradeCode = route.downgradeCode?.rawValue
                return MemoryContextResolutionResult(
                    response: response,
                    source: response.source,
                    resolvedMode: useMode,
                    freshness: response.freshness ?? "fresh_remote",
                    cacheHit: remote.cacheHit,
                    denyCode: nil,
                    downgradeCode: route.downgradeCode?.rawValue,
                    reasonCode: nil
                )
            }
            if !routeDecision.allowFileFallback {
                return MemoryContextResolutionResult(
                    response: nil,
                    source: remote.snapshot.source,
                    resolvedMode: useMode,
                    freshness: route.bypassRemoteCache ? "fresh_remote_required" : "remote_failed",
                    cacheHit: remote.cacheHit,
                    denyCode: route.bypassRemoteCache
                        ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                        : nil,
                    downgradeCode: nil,
                    reasonCode: normalizedReasonCode(remote.snapshot.reasonCode, fallback: "remote_memory_snapshot_failed")
                )
            }
        }

        if routeDecision.requiresRemote {
            return MemoryContextResolutionResult(
                response: nil,
                source: "hub_memory_v1_grpc",
                resolvedMode: useMode,
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        guard let local = await requestMemoryContextViaLocalIPC(payload: payload, timeoutSec: timeoutSec) else {
            return MemoryContextResolutionResult(
                response: nil,
                source: "local_ipc",
                resolvedMode: useMode,
                freshness: "unavailable",
                cacheHit: false,
                denyCode: route.bypassRemoteCache
                    ? XTMemoryUseDenyCode.memorySnapshotStaleForHighRiskAct.rawValue
                    : nil,
                downgradeCode: nil,
                reasonCode: "memory_context_unavailable"
            )
        }

        var response = local
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: false,
            overrideLongtermMode: response.longtermMode,
            overrideRetrievalAvailable: response.retrievalAvailable,
            overrideFulltextNotLoaded: response.fulltextNotLoaded
        )
        response.resolvedMode = useMode.rawValue
        response.resolvedProfile = route.servingProfile.rawValue
        response.longtermMode = disclosure.longtermMode
        response.retrievalAvailable = disclosure.retrievalAvailable
        response.fulltextNotLoaded = disclosure.fulltextNotLoaded
        response.text = ensureMemoryLongtermDisclosureText(response.text, disclosure: disclosure)
        response.freshness = "fresh_local_ipc"
        response.cacheHit = false
        response.denyCode = nil
        response.downgradeCode = route.downgradeCode?.rawValue
        return MemoryContextResolutionResult(
            response: response,
            source: response.source,
            resolvedMode: useMode,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: route.downgradeCode?.rawValue,
            reasonCode: nil
        )
    }

    static func requestProjectMemoryRetrieval(
        requesterRole: XTMemoryRequesterRole,
        projectId: String?,
        projectRoot: String?,
        displayName: String?,
        latestUser: String,
        reason: String?,
        requestedKinds: [String] = [],
        explicitRefs: [String] = [],
        maxSnippets: Int = 3,
        maxSnippetChars: Int = 420,
        timeoutSec: Double = 1.0
    ) async -> MemoryRetrievalResponsePayload? {
        let scope = "current_project"
        let payload = MemoryRetrievalPayload(
            scope: scope,
            requesterRole: requesterRole.rawValue,
            projectId: normalized(projectId),
            projectRoot: normalized(projectRoot),
            displayName: normalized(displayName),
            latestUser: latestUser,
            reason: normalized(reason),
            requestedKinds: HubIPCClient.orderedUniqueStringTokens(requestedKinds),
            explicitRefs: HubIPCClient.orderedUniqueStringTokens(explicitRefs),
            maxSnippets: max(1, min(6, maxSnippets)),
            maxSnippetChars: max(120, min(1_200, maxSnippetChars)),
            auditRef: "audit-xt-memory-retrieval-\(String(UUID().uuidString.lowercased().prefix(12)))"
        )
        return await requestMemoryRetrievalViaLocalIPC(payload: payload, timeoutSec: timeoutSec)
    }

    static func pushNotification(
        source: String,
        title: String,
        body: String,
        dedupeKey: String? = nil,
        actionURL: String? = nil,
        unread: Bool = true
    ) {
        let payload = NotificationPayload(
            id: "",
            source: source,
            title: title,
            body: body,
            createdAt: Date().timeIntervalSince1970,
            dedupeKey: dedupeKey,
            actionURL: actionURL,
            unread: unread
        )
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await pushNotificationViaPreferredRoute(payload: payload, allowFileFallback: true)
            }
        case .fileIPC:
            _ = writeNotificationViaFileIPC(payload)
        }
    }

    static func appendSupervisorIncidentAudit(
        incidentID: String,
        laneID: String,
        taskID: UUID,
        projectID: UUID?,
        incidentCode: String,
        eventType: String,
        denyCode: String,
        proposedAction: String,
        severity: String,
        category: String,
        detectedAtMs: Int64,
        handledAtMs: Int64?,
        takeoverLatencyMs: Int64?,
        auditRef: String,
        detail: String?,
        status: String
    ) {
        guard let dir = supervisorIncidentAuditEventsDir() else { return }

        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedIncidentCode = normalized(incidentCode) ?? ""
        let normalizedDenyCode = normalized(denyCode) ?? ""
        let normalizedLaneID = normalized(laneID) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventType.isEmpty,
              !normalizedIncidentCode.isEmpty,
              !normalizedDenyCode.isEmpty,
              !normalizedLaneID.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let reqId = UUID().uuidString
        let payload = SupervisorIncidentAuditPayload(
            incidentId: normalized(incidentID) ?? "",
            laneId: normalizedLaneID,
            taskId: taskID.uuidString.lowercased(),
            projectId: projectID?.uuidString.lowercased(),
            incidentCode: normalizedIncidentCode,
            eventType: normalizedEventType,
            denyCode: normalizedDenyCode,
            proposedAction: normalized(proposedAction) ?? "",
            severity: normalized(severity) ?? "",
            category: normalized(category) ?? "",
            detectedAtMs: max(0, detectedAtMs),
            handledAtMs: handledAtMs != nil ? max(0, handledAtMs ?? 0) : nil,
            takeoverLatencyMs: takeoverLatencyMs != nil ? max(0, takeoverLatencyMs ?? 0) : nil,
            auditRef: normalizedAuditRef,
            detail: normalized(detail),
            status: normalized(status) ?? "",
            source: "x_terminal_supervisor"
        )
        let req = SupervisorIncidentAuditIPCRequest(
            type: "supervisor_incident_audit",
            reqId: reqId,
            supervisorIncident: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return }
        _ = writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_incident_audit",
            tmpPrefix: ".xterminal_incident_audit",
            in: dir
        )
    }

    static func appendSupervisorProjectActionAudit(
        eventID: String,
        projectID: String,
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
        jurisdictionRole: String?,
        grantedScope: String?,
        auditRef: String
    ) {
        let normalizedEventID = normalized(eventID) ?? ""
        let normalizedProjectID = normalized(projectID) ?? ""
        let normalizedProjectName = normalized(projectName) ?? ""
        let normalizedEventType = normalized(eventType) ?? ""
        let normalizedSeverity = normalized(severity) ?? ""
        let normalizedActionTitle = normalized(actionTitle) ?? ""
        let normalizedActionSummary = normalized(actionSummary) ?? ""
        let normalizedWhy = normalized(whyItMatters) ?? ""
        let normalizedNextAction = normalized(nextAction) ?? ""
        let normalizedDeliveryChannel = normalized(deliveryChannel) ?? ""
        let normalizedDeliveryStatus = normalized(deliveryStatus) ?? ""
        let normalizedAuditRef = normalized(auditRef) ?? ""
        guard !normalizedEventID.isEmpty,
              !normalizedProjectID.isEmpty,
              !normalizedProjectName.isEmpty,
              !normalizedEventType.isEmpty,
              !normalizedSeverity.isEmpty,
              !normalizedActionTitle.isEmpty,
              !normalizedActionSummary.isEmpty,
              !normalizedWhy.isEmpty,
              !normalizedNextAction.isEmpty,
              !normalizedDeliveryChannel.isEmpty,
              !normalizedDeliveryStatus.isEmpty,
              !normalizedAuditRef.isEmpty else {
            return
        }

        let payload = SupervisorProjectActionAuditPayload(
            eventId: normalizedEventID,
            projectId: normalizedProjectID,
            projectName: normalizedProjectName,
            eventType: normalizedEventType,
            severity: normalizedSeverity,
            actionTitle: normalizedActionTitle,
            actionSummary: normalizedActionSummary,
            whyItMatters: normalizedWhy,
            nextAction: normalizedNextAction,
            occurredAtMs: max(0, occurredAtMs),
            deliveryChannel: normalizedDeliveryChannel,
            deliveryStatus: normalizedDeliveryStatus,
            jurisdictionRole: normalized(jurisdictionRole),
            grantedScope: normalized(grantedScope),
            auditRef: normalizedAuditRef,
            source: "x_terminal_supervisor"
        )
        let wroteLocalAudit = writeSupervisorProjectActionAuditViaLocalIPC(payload)
        let mode = HubAIClient.transportMode()
        switch mode {
        case .grpc:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .auto:
            Task {
                _ = await appendSupervisorProjectActionAuditViaPreferredRoute(payload: payload, allowFileFallback: false)
            }
        case .fileIPC:
            _ = wroteLocalAudit
        }
    }

    @discardableResult
    private static func appendSupervisorProjectActionAuditViaPreferredRoute(
        payload: SupervisorProjectActionAuditPayload,
        allowFileFallback: Bool
    ) async -> Bool {
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let record = SupervisorProjectActionCanonicalRecord(
                schemaVersion: SupervisorProjectActionCanonicalSync.schemaVersion,
                eventId: payload.eventId,
                projectId: payload.projectId,
                projectName: payload.projectName,
                eventType: payload.eventType,
                severity: payload.severity,
                actionTitle: payload.actionTitle,
                actionSummary: payload.actionSummary,
                whyItMatters: payload.whyItMatters,
                nextAction: payload.nextAction,
                occurredAtMs: payload.occurredAtMs,
                deliveryChannel: payload.deliveryChannel,
                deliveryStatus: payload.deliveryStatus,
                jurisdictionRole: payload.jurisdictionRole,
                grantedScope: payload.grantedScope,
                auditRef: payload.auditRef
            )
            let remote = await HubPairingCoordinator.shared.upsertRemoteProjectCanonicalMemory(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                payload: HubRemoteProjectCanonicalMemoryPayload(
                    projectId: payload.projectId,
                    items: SupervisorProjectActionCanonicalSync.items(record: record).map { item in
                        HubRemoteCanonicalMemoryItem(key: item.key, value: item.value)
                    }
                )
            )
            if remote.ok {
                await remoteMemorySnapshotCache.invalidate(projectId: payload.projectId)
                return true
            }
            if !allowFileFallback {
                return false
            }
        } else if !allowFileFallback {
            return false
        }

        return writeSupervisorProjectActionAuditViaLocalIPC(payload)
    }

    private static func writeSupervisorProjectActionAuditViaLocalIPC(_ payload: SupervisorProjectActionAuditPayload) -> Bool {
        guard let dir = supervisorIncidentAuditEventsDir() else { return false }

        let reqId = UUID().uuidString
        let req = SupervisorProjectActionAuditIPCRequest(
            type: "supervisor_project_action_audit",
            reqId: reqId,
            supervisorProjectAction: payload
        )
        guard let data = try? JSONEncoder().encode(req) else { return false }
        return writeEvent(
            data: data,
            reqId: reqId,
            filePrefix: "xterminal_project_action_audit",
            tmpPrefix: ".xterminal_project_action_audit",
            in: dir
        )
    }

    static func requestSchedulerStatus(
        includeQueueItems: Bool = true,
        queueItemsLimit: Int = 80
    ) async -> SchedulerStatusSnapshot? {
        let routeDecision = await currentRouteDecision()

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSchedulerStatus(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                includeQueueItems: includeQueueItems,
                queueItemsLimit: max(1, min(500, queueItemsLimit))
            )
            if remote.ok {
                return SchedulerStatusSnapshot(
                    source: remote.source,
                    updatedAtMs: max(0, remote.updatedAtMs),
                    inFlightTotal: max(0, remote.inFlightTotal),
                    queueDepth: max(0, remote.queueDepth),
                    oldestQueuedMs: max(0, remote.oldestQueuedMs),
                    inFlightByScope: remote.inFlightByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queuedByScope: remote.queuedByScope.map { row in
                        SchedulerScopeCount(
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            count: max(0, row.count)
                        )
                    },
                    queueItems: remote.queueItems.map { row in
                        SchedulerQueueItem(
                            requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scopeKey: row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                            enqueuedAtMs: max(0, row.enqueuedAtMs),
                            queuedMs: max(0, row.queuedMs)
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalSchedulerStatus(
            includeQueueItems: includeQueueItems,
            queueItemsLimit: max(1, min(500, queueItemsLimit))
        )
    }

    static func requestPendingGrantRequests(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> PendingGrantSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemotePendingGrantRequests(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    PendingGrantItem(
                        grantRequestId: row.grantRequestId,
                        requestId: row.requestId,
                        deviceId: row.deviceId,
                        userId: row.userId,
                        appId: row.appId,
                        projectId: row.projectId,
                        capability: row.capability,
                        modelId: row.modelId,
                        reason: row.reason,
                        requestedTtlSec: max(0, row.requestedTtlSec),
                        requestedTokenCap: max(0, row.requestedTokenCap),
                        status: row.status,
                        decision: row.decision,
                        createdAtMs: max(0, row.createdAtMs),
                        decidedAtMs: max(0, row.decidedAtMs)
                    )
                }
                return PendingGrantSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalPendingGrantRequests(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestSupervisorSkillRegistrySnapshot(
        projectId: String?,
        projectName: String?
    ) async -> SupervisorSkillRegistrySnapshot? {
        guard let normalizedProjectId = normalized(projectId) else { return nil }
        return AXSkillsLibrary.supervisorSkillRegistrySnapshot(
            projectId: normalizedProjectId,
            projectName: normalized(projectName),
            hubBaseDir: HubPaths.baseDir()
        )
    }

    static func searchSkills(
        query: String,
        sourceFilter: String? = nil,
        projectId: String? = nil,
        limit: Int = 20
    ) async -> SkillsSearchResult {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSourceFilter = normalized(sourceFilter)
        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(100, limit))

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.searchRemoteSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                query: normalizedQuery,
                sourceFilter: normalizedSourceFilter,
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            return SkillsSearchResult(
                ok: remote.ok,
                source: remote.source,
                updatedAtMs: remote.updatedAtMs,
                results: remote.results.map { row in
                    SkillCatalogEntry(
                        skillID: row.skillID,
                        name: row.name,
                        version: row.version,
                        description: row.description,
                        publisherID: row.publisherID,
                        capabilitiesRequired: row.capabilitiesRequired,
                        sourceID: row.sourceID,
                        packageSHA256: row.packageSHA256,
                        installHint: row.installHint
                    )
                },
                reasonCode: remote.reasonCode
            )
        }

        return SkillsSearchResult(
            ok: false,
            source: "file_ipc",
            updatedAtMs: 0,
            results: [],
            reasonCode: "skills_search_file_ipc_not_supported"
        )
    }

    static func setSkillPin(
        scope: String,
        skillId: String,
        packageSHA256: String,
        projectId: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> SkillPinResult {
        let normalizedScope = scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSkillId = skillId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedProjectId = normalized(projectId)

        guard normalizedScope == "global" || normalizedScope == "project" else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "unsupported_skill_pin_scope"
            )
        }
        if normalizedScope == "project", normalizedProjectId == nil {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: "",
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_project_id"
            )
        }
        guard !normalizedSkillId.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: "",
                packageSHA256: normalizedPackageSHA256,
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_skill_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return SkillPinResult(
                ok: false,
                source: "hub_runtime_grpc",
                scope: normalizedScope,
                userId: "",
                projectId: normalizedProjectId ?? "",
                skillId: normalizedSkillId,
                packageSHA256: "",
                previousPackageSHA256: "",
                updatedAtMs: 0,
                reasonCode: "missing_package_sha256"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.setRemoteSkillPin(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                skillId: normalizedSkillId,
                packageSHA256: normalizedPackageSHA256,
                projectId: normalizedProjectId,
                note: note,
                requestId: requestId
            )
            return SkillPinResult(
                ok: remote.ok,
                source: remote.source,
                scope: remote.scope,
                userId: remote.userId,
                projectId: remote.projectId,
                skillId: remote.skillId,
                packageSHA256: remote.packageSHA256,
                previousPackageSHA256: remote.previousPackageSHA256,
                updatedAtMs: remote.updatedAtMs,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPinResult(
            ok: false,
            source: "file_ipc",
            scope: normalizedScope,
            userId: "",
            projectId: normalizedProjectId ?? "",
            skillId: normalizedSkillId,
            packageSHA256: normalizedPackageSHA256,
            previousPackageSHA256: "",
            updatedAtMs: 0,
            reasonCode: "skills_pin_file_ipc_not_supported"
        )
    }

    static func listResolvedSkills(
        projectId: String? = nil
    ) async -> ResolvedSkillsResult {
        let normalizedProjectId = normalized(projectId)
        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteResolvedSkills(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId
            )
            return ResolvedSkillsResult(
                ok: remote.ok,
                source: remote.source,
                skills: remote.skills.map { row in
                    ResolvedSkillEntry(
                        scope: row.scope,
                        skill: SkillCatalogEntry(
                            skillID: row.skill.skillID,
                            name: row.skill.name,
                            version: row.skill.version,
                            description: row.skill.description,
                            publisherID: row.skill.publisherID,
                            capabilitiesRequired: row.skill.capabilitiesRequired,
                            sourceID: row.skill.sourceID,
                            packageSHA256: row.skill.packageSHA256,
                            installHint: row.skill.installHint
                        )
                    )
                },
                reasonCode: remote.reasonCode
            )
        }

        return ResolvedSkillsResult(
            ok: false,
            source: "file_ipc",
            skills: [],
            reasonCode: "skills_resolved_file_ipc_not_supported"
        )
    }

    static func stageAgentImport(
        importManifestJSON: String,
        findingsJSON: String? = nil,
        scanInputJSON: String? = nil,
        requestedBy: String? = nil,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportStageResult {
        let manifestText = importManifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return AgentImportStageResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                preflightStatus: nil,
                skillId: nil,
                policyScope: nil,
                findingsCount: 0,
                vetterStatus: nil,
                vetterCriticalCount: 0,
                vetterWarnCount: 0,
                vetterAuditRef: nil,
                recordPath: nil,
                reasonCode: "missing_agent_import_manifest"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.stageRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                importManifestJSON: manifestText,
                findingsJSON: findingsJSON,
                scanInputJSON: scanInputJSON,
                requestedBy: requestedBy,
                note: note,
                requestId: requestId
            )
            return AgentImportStageResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                preflightStatus: remote.preflightStatus,
                skillId: remote.skillId,
                policyScope: remote.policyScope,
                findingsCount: remote.findingsCount,
                vetterStatus: remote.vetterStatus,
                vetterCriticalCount: remote.vetterCriticalCount,
                vetterWarnCount: remote.vetterWarnCount,
                vetterAuditRef: remote.vetterAuditRef,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportStageResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            preflightStatus: nil,
            skillId: nil,
            policyScope: nil,
            findingsCount: 0,
            vetterStatus: nil,
            vetterCriticalCount: 0,
            vetterWarnCount: 0,
            vetterAuditRef: nil,
            recordPath: nil,
            reasonCode: "skills_stage_file_ipc_not_supported"
        )
    }

    static func getAgentImportRecord(
        stagingId: String
    ) async -> AgentImportRecordResult {
        let normalized = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return AgentImportRecordResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                schemaVersion: nil,
                skillId: nil,
                recordJSON: nil,
                reasonCode: "missing_agent_staging_id"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteAgentImportRecord(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                stagingId: normalized
            )
            return AgentImportRecordResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                schemaVersion: remote.schemaVersion,
                skillId: remote.skillId,
                recordJSON: remote.recordJSON,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportRecordResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            schemaVersion: nil,
            skillId: nil,
            recordJSON: nil,
            reasonCode: "skills_record_file_ipc_not_supported"
        )
    }

    static func uploadSkillPackage(
        packageFileURL: URL,
        manifestJSON: String,
        sourceId: String = "local:xt-import",
        requestId: String? = nil
    ) async -> SkillPackageUploadResult {
        let manifestText = manifestJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manifestText.isEmpty else {
            return SkillPackageUploadResult(
                ok: false,
                source: "hub_runtime_grpc",
                packageSHA256: nil,
                alreadyPresent: false,
                skillId: nil,
                version: nil,
                reasonCode: "missing_manifest_json"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.uploadRemoteSkillPackage(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                packageFileURL: packageFileURL,
                manifestJSON: manifestText,
                sourceId: sourceId,
                requestId: requestId
            )
            return SkillPackageUploadResult(
                ok: remote.ok,
                source: remote.source,
                packageSHA256: remote.packageSHA256,
                alreadyPresent: remote.alreadyPresent,
                skillId: remote.skillId,
                version: remote.version,
                reasonCode: remote.reasonCode
            )
        }

        return SkillPackageUploadResult(
            ok: false,
            source: "file_ipc",
            packageSHA256: nil,
            alreadyPresent: false,
            skillId: nil,
            version: nil,
            reasonCode: "skills_upload_file_ipc_not_supported"
        )
    }

    static func promoteAgentImport(
        stagingId: String,
        packageSHA256: String,
        note: String? = nil,
        requestId: String? = nil
    ) async -> AgentImportPromoteResult {
        let normalizedStagingId = stagingId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPackageSHA256 = packageSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedStagingId.isEmpty else {
            return AgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_agent_staging_id"
            )
        }
        guard !normalizedPackageSHA256.isEmpty else {
            return AgentImportPromoteResult(
                ok: false,
                source: "hub_runtime_grpc",
                stagingId: nil,
                status: nil,
                auditRef: nil,
                packageSHA256: nil,
                scope: nil,
                skillId: nil,
                previousPackageSHA256: nil,
                recordPath: nil,
                reasonCode: "missing_package_sha256"
            )
        }

        let hasRemote = await HubPairingCoordinator.shared.hasHubEnv(stateDir: nil)
        if hasRemote {
            let remote = await HubPairingCoordinator.shared.promoteRemoteAgentImport(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                stagingId: normalizedStagingId,
                packageSHA256: normalizedPackageSHA256,
                note: note,
                requestId: requestId
            )
            return AgentImportPromoteResult(
                ok: remote.ok,
                source: remote.source,
                stagingId: remote.stagingId,
                status: remote.status,
                auditRef: remote.auditRef,
                packageSHA256: remote.packageSHA256,
                scope: remote.scope,
                skillId: remote.skillId,
                previousPackageSHA256: remote.previousPackageSHA256,
                recordPath: remote.recordPath,
                reasonCode: remote.reasonCode
            )
        }

        return AgentImportPromoteResult(
            ok: false,
            source: "file_ipc",
            stagingId: nil,
            status: nil,
            auditRef: nil,
            packageSHA256: nil,
            scope: nil,
            skillId: nil,
            previousPackageSHA256: nil,
            recordPath: nil,
            reasonCode: "skills_promote_file_ipc_not_supported"
        )
    }

    static func requestConnectorIngressReceipts(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> ConnectorIngressSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteConnectorIngressReceipts(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let items = remote.items.map { row in
                    ConnectorIngressReceipt(
                        receiptId: row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines),
                        requestId: row.requestId.trimmingCharacters(in: .whitespacesAndNewlines),
                        projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                        connector: row.connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        targetId: row.targetId.trimmingCharacters(in: .whitespacesAndNewlines),
                        ingressType: row.ingressType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        channelScope: row.channelScope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        sourceId: row.sourceId.trimmingCharacters(in: .whitespacesAndNewlines),
                        messageId: row.messageId.trimmingCharacters(in: .whitespacesAndNewlines),
                        dedupeKey: row.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines),
                        receivedAtMs: max(0, row.receivedAtMs),
                        eventSequence: Swift.max(0, row.eventSequence),
                        deliveryState: row.deliveryState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        runtimeState: row.runtimeState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    )
                }
                return ConnectorIngressSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, remote.updatedAtMs),
                    items: items
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalConnectorIngressReceipts(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommands(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommands(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestOperatorChannelXTCommandResults(
        projectId: String? = nil,
        limit: Int = 200
    ) async -> OperatorChannelXTCommandResultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote, !routeDecision.allowFileFallback {
            return nil
        }

        if routeDecision.requiresRemote, !routeDecision.allowFileFallback {
            return nil
        }

        return readLocalOperatorChannelXTCommandResults(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    @discardableResult
    static func appendOperatorChannelXTCommandResult(
        _ result: OperatorChannelXTCommandResultItem
    ) -> Bool {
        let commandId = result.commandId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandId.isEmpty else { return false }

        let baseDir = HubPaths.baseDir()
        let url = baseDir.appendingPathComponent("operator_channel_xt_command_results_status.json")
        let existing = readLocalOperatorChannelXTCommandResults(projectId: nil, limit: 1_000)
        var deduped: [String: OperatorChannelXTCommandResultItem] = [:]
        for item in existing?.items ?? [] {
            deduped[item.commandId] = item
        }
        deduped[commandId] = result

        let merged = deduped.values.sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        let payload = OperatorChannelXTCommandResultSnapshot(
            source: "xterminal_operator_channel_result_writer",
            updatedAtMs: max(
                result.completedAtMs,
                result.createdAtMs,
                Date().timeIntervalSince1970 * 1000.0
            ),
            items: Array(merged.prefix(1_000))
        )
        return writeLocalSnapshot(payload, to: url)
    }

    static func requestAutonomyPolicyOverrides(
        projectId: String? = nil,
        limit: Int = 200,
        bypassCache: Bool = false
    ) async -> AutonomyPolicyOverridesSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let cacheKey = HubRemoteAutonomyPolicyOverrideCache.Key(
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if !bypassCache, let cached = await remoteAutonomyPolicyOverrideCache.snapshot(for: cacheKey) {
                return cached
            }

            let remote = await HubPairingCoordinator.shared.fetchRemoteAutonomyPolicyOverrides(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                projectId: normalizedProjectId,
                limit: boundedLimit
            )
            if remote.ok {
                let snapshot = AutonomyPolicyOverridesSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                    items: remote.items.map { row in
                        AutonomyPolicyOverrideItem(
                            projectId: row.projectId.trimmingCharacters(in: .whitespacesAndNewlines),
                            overrideMode: row.overrideMode,
                            updatedAtMs: max(0, Int64(row.updatedAtMs.rounded())),
                            reason: row.reason.trimmingCharacters(in: .whitespacesAndNewlines),
                            auditRef: row.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                    }
                )
                await remoteAutonomyPolicyOverrideCache.store(snapshot, for: cacheKey)
                return snapshot
            }

            await remoteAutonomyPolicyOverrideCache.invalidate(key: cacheKey)
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        return readLocalAutonomyPolicyOverrides(
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func requestSecretVaultSnapshot(
        scope: String? = nil,
        namePrefix: String? = nil,
        projectId: String? = nil,
        limit: Int = 200
    ) async -> SecretVaultSnapshot? {
        let routeDecision = await currentRouteDecision()
        let boundedLimit = max(1, min(500, limit))
        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.fetchRemoteSecretVaultItems(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: normalizedScope,
                namePrefix: normalizedNamePrefix,
                limit: boundedLimit
            )
            if remote.ok {
                return SecretVaultSnapshot(
                    source: remote.source.trimmingCharacters(in: .whitespacesAndNewlines),
                    updatedAtMs: max(0, Int64(remote.updatedAtMs.rounded())),
                    items: remote.items.map { row in
                        SecretVaultItem(
                            itemId: row.itemId.trimmingCharacters(in: .whitespacesAndNewlines),
                            scope: row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            name: row.name.trimmingCharacters(in: .whitespacesAndNewlines),
                            sensitivity: row.sensitivity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            createdAtMs: max(0, Int64(row.createdAtMs.rounded())),
                            updatedAtMs: max(0, Int64(row.updatedAtMs.rounded()))
                        )
                    }
                )
            }
            if !routeDecision.allowFileFallback {
                return nil
            }
        }

        if routeDecision.requiresRemote {
            return nil
        }

        if let snapshot = readLocalSecretVaultSnapshot(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        ) {
            return snapshot
        }

        return await requestSecretVaultSnapshotViaLocalIPC(
            scope: normalizedScope,
            namePrefix: normalizedNamePrefix,
            projectId: normalizedProjectId,
            limit: boundedLimit
        )
    }

    static func createProtectedSecret(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPlaintext = normalized(payload.plaintext)
        let normalizedSensitivity = normalized(payload.sensitivity)?.lowercased() ?? "secret"

        guard normalizedScope != nil, normalizedName != nil, normalizedPlaintext != nil else {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretCreateRequestPayload(
            scope: normalizedScope ?? "",
            name: normalizedName ?? "",
            plaintext: normalizedPlaintext ?? "",
            sensitivity: normalizedSensitivity,
            projectId: normalized(payload.projectId),
            displayName: normalized(payload.displayName),
            reason: normalized(payload.reason)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.createRemoteSecretVaultItem(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                plaintext: sanitizedPayload.plaintext,
                sensitivity: sanitizedPayload.sensitivity,
                projectId: sanitizedPayload.projectId,
                displayName: sanitizedPayload.displayName,
                reason: sanitizedPayload.reason
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultCreateResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretCreateResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                item: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await createProtectedSecretViaLocalIPC(sanitizedPayload)
    }

    static func beginSecretUse(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        testingOverrideLock.lock()
        let override = secretUseOverrideForTesting
        testingOverrideLock.unlock()
        if let override {
            return await override(payload)
        }

        let normalizedItemId = normalized(payload.itemId)
        let normalizedScope = normalized(payload.scope)?.lowercased()
        let normalizedName = normalized(payload.name)
        let normalizedPurpose = normalized(payload.purpose)

        guard normalizedPurpose != nil,
              normalizedItemId != nil || (normalizedScope != nil && normalizedName != nil) else {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: nil,
                expiresAtMs: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretUseRequestPayload(
            itemId: normalizedItemId,
            scope: normalizedScope,
            name: normalizedName,
            projectId: normalized(payload.projectId),
            purpose: normalizedPurpose ?? "",
            target: normalized(payload.target),
            ttlMs: max(1_000, min(600_000, payload.ttlMs))
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.beginRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                itemId: sanitizedPayload.itemId,
                scope: sanitizedPayload.scope,
                name: sanitizedPayload.name,
                projectId: sanitizedPayload.projectId,
                purpose: sanitizedPayload.purpose,
                target: sanitizedPayload.target,
                ttlMs: sanitizedPayload.ttlMs
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultUseResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretUseResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                useToken: nil,
                itemId: sanitizedPayload.itemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await beginSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func redeemSecretUse(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        testingOverrideLock.lock()
        let override = secretRedeemOverrideForTesting
        testingOverrideLock.unlock()
        if let override {
            return await override(payload)
        }

        let normalizedUseToken = normalized(payload.useToken)
        guard normalizedUseToken != nil else {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "invalid_request"
            )
        }

        let sanitizedPayload = SecretRedeemRequestPayload(
            useToken: normalizedUseToken ?? "",
            projectId: normalized(payload.projectId)
        )

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.redeemRemoteSecretVaultUse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                useToken: sanitizedPayload.useToken,
                projectId: sanitizedPayload.projectId
            )
            if remote.ok || !routeDecision.allowFileFallback {
                return mapSecretVaultRedeemResult(remote)
            }
        }

        if routeDecision.requiresRemote {
            return SecretRedeemResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return await redeemSecretUseViaLocalIPC(sanitizedPayload)
    }

    static func requestProjectAutonomyPolicyOverride(
        projectId: String,
        bypassCache: Bool = false
    ) async -> AXProjectAutonomyRemoteOverrideSnapshot? {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return nil }
        guard let snapshot = await requestAutonomyPolicyOverrides(
            projectId: normalizedProjectId,
            limit: 1,
            bypassCache: bypassCache
        ) else {
            return nil
        }
        guard let row = snapshot.items.first(where: { $0.projectId == normalizedProjectId }) else {
            return nil
        }
        return AXProjectAutonomyRemoteOverrideSnapshot(
            projectId: row.projectId,
            overrideMode: row.overrideMode,
            updatedAtMs: row.updatedAtMs,
            source: snapshot.source,
            reason: row.reason.isEmpty ? nil : row.reason,
            auditRef: row.auditRef.isEmpty ? nil : row.auditRef
        )
    }

    static func approvePendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        requestedTtlSec: Int? = nil,
        requestedTokenCap: Int? = nil,
        note: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.approveRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                ttlSec: requestedTtlSec,
                tokenCap: requestedTokenCap,
                note: note
            )
            return mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func denyPendingGrantRequest(
        grantRequestId: String,
        projectId: String? = nil,
        reason: String? = nil
    ) async -> PendingGrantActionResult {
        let normalizedGrantId = normalized(grantRequestId)
        guard let normalizedGrantId else {
            return PendingGrantActionResult(
                ok: false,
                decision: .failed,
                source: "hub_runtime_grpc",
                grantRequestId: nil,
                grantId: nil,
                expiresAtMs: nil,
                reasonCode: "grant_request_id_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        let normalizedProjectId = normalized(projectId)

        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.denyRemotePendingGrantRequest(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                grantRequestId: normalizedGrantId,
                projectId: normalizedProjectId,
                reason: reason
            )
            return mapPendingGrantActionResult(remote, defaultGrantRequestId: normalizedGrantId)
        }

        let fallbackReason = routeDecision.requiresRemote
            ? (routeDecision.remoteUnavailableReasonCode ?? "hub_env_missing")
            : "pending_grant_action_not_supported"
        return PendingGrantActionResult(
            ok: false,
            decision: .failed,
            source: "hub_runtime_grpc",
            grantRequestId: normalizedGrantId,
            grantId: nil,
            expiresAtMs: nil,
            reasonCode: fallbackReason
        )
    }

    static func issueVoiceGrantChallenge(
        _ payload: VoiceGrantChallengeRequestPayload
    ) async -> VoiceGrantChallengeResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedTemplateId = normalized(payload.templateId)
        let normalizedActionDigest = normalized(payload.actionDigest)
        let normalizedScopeDigest = normalized(payload.scopeDigest)
        guard normalizedTemplateId != nil, normalizedActionDigest != nil, normalizedScopeDigest != nil else {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: "invalid_request"
            )
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.issueRemoteVoiceGrantChallenge(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalized(payload.projectId),
                templateId: normalizedTemplateId ?? "",
                actionDigest: normalizedActionDigest ?? "",
                scopeDigest: normalizedScopeDigest ?? "",
                amountDigest: normalized(payload.amountDigest),
                challengeCode: normalized(payload.challengeCode),
                riskLevel: normalized(payload.riskLevel) ?? "high",
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileTerminalId: normalized(payload.mobileTerminalId),
                allowVoiceOnly: payload.allowVoiceOnly,
                requiresMobileConfirm: payload.requiresMobileConfirm,
                ttlMs: max(10_000, min(600_000, payload.ttlMs))
            )
            return mapVoiceGrantChallengeResult(remote)
        }

        if routeDecision.requiresRemote {
            return VoiceGrantChallengeResult(
                ok: false,
                source: "hub_memory_v1_grpc",
                challenge: nil,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantChallengeResult(
            ok: false,
            source: "file_ipc",
            challenge: nil,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    static func verifyVoiceGrantResponse(
        _ payload: VoiceGrantVerificationPayload
    ) async -> VoiceGrantVerificationResult {
        let normalizedRequestId = normalized(payload.requestId)
        guard let normalizedRequestId else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "request_id_empty"
            )
        }

        let normalizedChallengeId = normalized(payload.challengeId)
        guard let normalizedChallengeId else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: nil,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "challenge_id_empty"
            )
        }

        let normalizedVerifyNonce = normalized(payload.verifyNonce)
        guard let normalizedVerifyNonce else {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: "verify_nonce_empty"
            )
        }

        let routeDecision = await currentRouteDecision()
        if routeDecision.preferRemote {
            let remote = await HubPairingCoordinator.shared.verifyRemoteVoiceGrantResponse(
                options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
                requestId: normalizedRequestId,
                projectId: normalized(payload.projectId),
                challengeId: normalizedChallengeId,
                challengeCode: normalized(payload.challengeCode),
                transcript: payload.transcript,
                transcriptHash: normalized(payload.transcriptHash),
                semanticMatchScore: payload.semanticMatchScore,
                parsedActionDigest: normalized(payload.parsedActionDigest),
                parsedScopeDigest: normalized(payload.parsedScopeDigest),
                parsedAmountDigest: normalized(payload.parsedAmountDigest),
                verifyNonce: normalizedVerifyNonce,
                boundDeviceId: normalized(payload.boundDeviceId),
                mobileConfirmed: payload.mobileConfirmed
            )
            return mapVoiceGrantVerificationResult(remote)
        }

        if routeDecision.requiresRemote {
            return VoiceGrantVerificationResult(
                ok: false,
                verified: false,
                decision: .failed,
                source: "hub_memory_v1_grpc",
                denyCode: nil,
                challengeId: normalizedChallengeId,
                transcriptHash: nil,
                semanticMatchScore: payload.semanticMatchScore ?? 0,
                challengeMatch: false,
                deviceBindingOK: false,
                mobileConfirmed: payload.mobileConfirmed,
                reasonCode: normalizedReasonCode(
                    routeDecision.remoteUnavailableReasonCode,
                    fallback: "hub_env_missing"
                )
            )
        }

        return VoiceGrantVerificationResult(
            ok: false,
            verified: false,
            decision: .failed,
            source: "file_ipc",
            denyCode: nil,
            challengeId: normalizedChallengeId,
            transcriptHash: nil,
            semanticMatchScore: payload.semanticMatchScore ?? 0,
            challengeMatch: false,
            deviceBindingOK: false,
            mobileConfirmed: payload.mobileConfirmed,
            reasonCode: "voice_grant_file_ipc_not_supported"
        )
    }

    private static func requestMemoryContextViaLocalIPC(
        payload: MemoryContextPayload,
        timeoutSec: Double
    ) async -> MemoryContextResponsePayload? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = MemoryContextIPCRequest(type: "memory_context", reqId: reqId, memoryContext: payload)

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else { return nil }
            guard writeEvent(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem",
                tmpPrefix: ".xterminal_mem",
                in: transport.ipcURL
            ) else {
                return nil
            }

            guard let ack = await pollMemoryContextResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return nil
            }
            guard ack.ok else { return nil }
            return ack.memoryContext
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return nil
            }
            guard ack.ok else { return nil }
            return ack.memoryContext
        default:
            return nil
        }
    }

    private static func requestMemoryRetrievalViaLocalIPC(
        payload: MemoryRetrievalPayload,
        timeoutSec: Double
    ) async -> MemoryRetrievalResponsePayload? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = MemoryRetrievalIPCRequest(
            type: "memory_retrieval",
            reqId: reqId,
            memoryRetrieval: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            guard let data = try? encoder.encode(req) else { return nil }
            guard writeEvent(
                data: data,
                reqId: reqId,
                filePrefix: "xterminal_mem_retrieval",
                tmpPrefix: ".xterminal_mem_retrieval",
                in: transport.ipcURL
            ) else {
                return nil
            }

            guard let ack = await pollMemoryRetrievalResponse(
                baseDir: transport.baseDir,
                reqId: reqId,
                timeoutSec: timeoutSec
            ) else {
                return nil
            }
            guard ack.ok else { return nil }
            return ack.memoryRetrieval
        case "socket":
            guard let ack: MemoryContextIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: timeoutSec) else {
                return nil
            }
            guard ack.ok else { return nil }
            return ack.memoryRetrieval
        default:
            return nil
        }
    }

    private static func fetchVoiceWakeProfileViaLocalIPC(
        desiredWakeMode: VoiceWakeMode
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile fetch local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileGetIPCRequest(
            type: "voice_wake_profile_get",
            reqId: reqId,
            voiceWakeProfileRequest: VoiceWakeProfileRequestPayload(desiredWakeMode: desiredWakeMode.rawValue)
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_voicewake_get",
                    tmpPrefix: ".xterminal_voicewake_get",
                    in: transport.ipcURL
                  ) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile get request write failed"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile get ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "get")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile get socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "get")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile fetch local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func setVoiceWakeProfileViaLocalIPC(
        _ profile: VoiceWakeProfile
    ) async -> VoiceWakeProfileSyncResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "hub_not_connected",
                logLines: ["voice wake profile set local IPC unavailable"],
                syncedAtMs: nil
            )
        }

        let reqId = UUID().uuidString
        let req = VoiceWakeProfileSetIPCRequest(
            type: "voice_wake_profile_set",
            reqId: reqId,
            voiceWakeProfile: profile.sanitized()
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_voicewake_set",
                    tmpPrefix: ".xterminal_voicewake_set",
                    in: transport.ipcURL
                  ) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "voice_wake_profile_write_failed",
                    logLines: ["voice wake profile set request write failed"],
                    syncedAtMs: nil
                )
            }

            guard let ack = await pollVoiceWakeProfileResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "file_ipc",
                    profile: nil,
                    reasonCode: "ack_timeout",
                    logLines: ["voice wake profile set ack timeout"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "file_ipc", verb: "set")
        case "socket":
            guard let ack: VoiceWakeProfileIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return VoiceWakeProfileSyncResult(
                    ok: false,
                    source: "socket_ipc",
                    profile: nil,
                    reasonCode: "socket_request_failed",
                    logLines: ["voice wake profile set socket request failed"],
                    syncedAtMs: nil
                )
            }
            return mapVoiceWakeProfileAck(ack, source: "socket_ipc", verb: "set")
        default:
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: "local_ipc",
                profile: nil,
                reasonCode: "unsupported_ipc_mode",
                logLines: ["voice wake profile set local IPC mode unsupported"],
                syncedAtMs: nil
            )
        }
    }

    private static func requestSecretVaultSnapshotViaLocalIPC(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) async -> SecretVaultSnapshot? {
        guard let transport = localIPCTransport(ttl: 3.0) else { return nil }

        let reqId = UUID().uuidString
        let req = SecretVaultListIPCRequest(
            type: "secret_vault_list",
            reqId: reqId,
            secretVaultList: SecretVaultListRequestPayload(
                scope: scope,
                namePrefix: namePrefix,
                projectId: projectId,
                limit: max(1, min(500, limit))
            )
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_secret_vault_list",
                    tmpPrefix: ".xterminal_secret_vault_list",
                    in: transport.ipcURL
                  ),
                  let ack = await pollSecretVaultListResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        case "socket":
            guard let ack: SecretVaultListIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0),
                  ack.ok,
                  let snapshot = ack.secretVaultSnapshot else {
                return nil
            }
            return snapshot
        default:
            return nil
        }
    }

    private static func createProtectedSecretViaLocalIPC(
        _ payload: SecretCreateRequestPayload
    ) async -> SecretCreateResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretCreateResult(
                ok: false,
                source: "local_ipc",
                item: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        if transport.mode == "file" {
            return SecretCreateResult(
                ok: false,
                source: "file_ipc",
                item: nil,
                reasonCode: "secret_vault_secure_capture_requires_socket_ipc"
            )
        }

        let req = SecretVaultCreateIPCRequest(
            type: "secret_vault_create",
            reqId: UUID().uuidString,
            secretVaultCreate: payload
        )

        guard let ack: SecretVaultCreateIPCResponse = sendSocketRequest(
            req,
            socketURL: transport.ipcURL,
            timeoutSec: 3.0
        ) else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "socket_request_failed"
            )
        }

        guard ack.ok else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_create_failed")
            )
        }

        guard let item = ack.secretVaultItem else {
            return SecretCreateResult(
                ok: false,
                source: "socket_ipc",
                item: nil,
                reasonCode: "secret_vault_item_missing"
            )
        }

        return SecretCreateResult(
            ok: true,
            source: "socket_ipc",
            item: item,
            reasonCode: nil
        )
    }

    private static func beginSecretUseViaLocalIPC(
        _ payload: SecretUseRequestPayload
    ) async -> SecretUseResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultBeginUseIPCRequest(
            type: "secret_vault_begin_use",
            reqId: reqId,
            secretVaultUse: payload
        )

        switch transport.mode {
        case "file":
            try? FileManager.default.createDirectory(at: transport.ipcURL, withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(req),
                  writeEvent(
                    data: data,
                    reqId: reqId,
                    filePrefix: "xterminal_secret_vault_use",
                    tmpPrefix: ".xterminal_secret_vault_use",
                    in: transport.ipcURL
                  ) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "secret_vault_use_write_failed"
                )
            }
            guard let ack = await pollSecretVaultUseResponse(baseDir: transport.baseDir, reqId: reqId, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "file_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "ack_timeout"
                )
            }
            return mapSecretVaultUseAck(ack, source: "file_ipc", fallbackItemId: payload.itemId)
        case "socket":
            guard let ack: SecretVaultUseIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretUseResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    useToken: nil,
                    itemId: payload.itemId,
                    expiresAtMs: nil,
                    reasonCode: "socket_request_failed"
                )
            }
            return mapSecretVaultUseAck(ack, source: "socket_ipc", fallbackItemId: payload.itemId)
        default:
            return SecretUseResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                useToken: nil,
                itemId: payload.itemId,
                expiresAtMs: nil,
                reasonCode: "unsupported_ipc_mode"
            )
        }
    }

    private static func redeemSecretUseViaLocalIPC(
        _ payload: SecretRedeemRequestPayload
    ) async -> SecretRedeemResult {
        guard let transport = localIPCTransport(ttl: 3.0) else {
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_local_ipc_unavailable"
            )
        }

        let reqId = UUID().uuidString
        let req = SecretVaultRedeemIPCRequest(
            type: "secret_vault_redeem_use",
            reqId: reqId,
            secretVaultRedeem: payload
        )

        switch transport.mode {
        case "file":
            return SecretRedeemResult(
                ok: false,
                source: "file_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_requires_socket_ipc"
            )
        case "socket":
            guard let ack: SecretVaultRedeemIPCResponse = sendSocketRequest(req, socketURL: transport.ipcURL, timeoutSec: 2.0) else {
                return SecretRedeemResult(
                    ok: false,
                    source: "socket_ipc",
                    leaseId: nil,
                    itemId: nil,
                    plaintext: nil,
                    reasonCode: "socket_request_failed"
                )
            }
            return mapSecretVaultRedeemAck(ack, source: "socket_ipc")
        default:
            return SecretRedeemResult(
                ok: false,
                source: "local_ipc",
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "unsupported_ipc_mode"
            )
        }
    }

    private static func mapVoiceWakeProfileAck(
        _ ack: VoiceWakeProfileIPCResponse,
        source: String,
        verb: String
    ) -> VoiceWakeProfileSyncResult {
        guard ack.ok else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "voice_wake_profile_\(verb)_failed"),
                logLines: ["voice wake profile \(verb) failed: \(ack.error ?? "unknown_error")"],
                syncedAtMs: nil
            )
        }
        guard let profile = ack.voiceWakeProfile else {
            return VoiceWakeProfileSyncResult(
                ok: false,
                source: source,
                profile: nil,
                reasonCode: "voice_wake_profile_missing",
                logLines: ["voice wake profile \(verb) missing payload"],
                syncedAtMs: nil
            )
        }
        return VoiceWakeProfileSyncResult(
            ok: true,
            source: source,
            profile: profile,
            reasonCode: nil,
            logLines: ["voice wake profile \(verb) succeeded via \(source)"],
            syncedAtMs: profile.updatedAtMs
        )
    }

    private static func buildMemoryContextFromRemoteSnapshot(
        snapshot: HubRemoteMemorySnapshotResult,
        payload: MemoryContextPayload
    ) -> MemoryContextResponsePayload {
        let servingProfile = normalized(payload.servingProfile)
        let useMode = XTMemoryUseMode.parse(payload.mode) ?? .projectChat
        let disclosure = resolveMemoryLongtermDisclosure(
            useMode: useMode,
            retrievalAvailable: false
        )
        let localCanonical = XTMemorySanitizer.sanitizeText(payload.canonicalText, maxChars: 3_200, lineCap: 36) ?? ""
        let localObservations = XTMemorySanitizer.sanitizeText(payload.observationsText, maxChars: 1_800, lineCap: 24) ?? ""
        let localWorking = XTMemorySanitizer.sanitizeText(payload.workingSetText, maxChars: 2_600, lineCap: 28) ?? ""
        let rawEvidence = XTMemorySanitizer.sanitizeRawEvidenceSummary(payload.rawEvidenceText, maxChars: 1_100, lineCap: 18) ?? ""
        let constitution = XTMemorySanitizer.sanitizeText(payload.constitutionHint, maxChars: 320, lineCap: 6)
            ?? "真实透明、最小化外发；仅在高风险或不可逆动作时先解释后执行；普通编程/创作请求直接给出可执行答案。"

        let remoteCanonical = XTMemorySanitizer.sanitizeText(snapshot.canonicalEntries.joined(separator: "\n"), maxChars: 3_200, lineCap: 36) ?? ""
        let remoteWorking = XTMemorySanitizer.sanitizeText(snapshot.workingEntries.joined(separator: "\n"), maxChars: 2_400, lineCap: 24) ?? ""

        let mergedCanonical = mergedMemoryLayer(localPrimary: localCanonical, remoteSecondary: remoteCanonical)
        let mergedWorking = mergedMemoryLayer(localPrimary: localWorking, remoteSecondary: remoteWorking)
        let servingProfileSection = memoryServingProfileSection(servingProfile)

        let finalText = ensureMemoryLongtermDisclosureText(
            """
[MEMORY_V1]
\(servingProfileSection.isEmpty ? "" : "\(servingProfileSection)\n")
[L0_CONSTITUTION]
\(constitution.isEmpty ? "(none)" : constitution)
[/L0_CONSTITUTION]

[L1_CANONICAL]
\(mergedCanonical.isEmpty ? "(none)" : mergedCanonical)
[/L1_CANONICAL]

[L2_OBSERVATIONS]
\(localObservations.isEmpty ? "(none)" : localObservations)
[/L2_OBSERVATIONS]

[L3_WORKING_SET]
\(mergedWorking.isEmpty ? "(none)" : mergedWorking)
[/L3_WORKING_SET]

[L4_RAW_EVIDENCE]
\(rawEvidence.isEmpty ? "(none)" : rawEvidence)
latest_user:
\(payload.latestUser)
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
""",
            disclosure: disclosure
        )

        let l0Used = TokenEstimator.estimateTokens(constitution)
        let l1Used = TokenEstimator.estimateTokens(mergedCanonical)
        let l2Used = TokenEstimator.estimateTokens(localObservations)
        let l3Used = TokenEstimator.estimateTokens(mergedWorking)
        let l4Used = TokenEstimator.estimateTokens(rawEvidence + "\n" + payload.latestUser)
        let usedTotal = max(0, l0Used + l1Used + l2Used + l3Used + l4Used)

        let b = payload.budgets
        let configuredBudget: Int
        if let v = b?.totalTokens {
            configuredBudget = v
        } else if let v = b?.l0Tokens {
            configuredBudget = v
        } else if let v = b?.l1Tokens {
            configuredBudget = v
        } else if let v = b?.l2Tokens {
            configuredBudget = v
        } else if let v = b?.l3Tokens {
            configuredBudget = v
        } else if let v = b?.l4Tokens {
            configuredBudget = v
        } else {
            configuredBudget = 1600
        }
        let budgetTotal = max(usedTotal, configuredBudget)

        let layerUsage = [
            MemoryContextLayerUsage(layer: "l0_constitution", usedTokens: l0Used, budgetTokens: payload.budgets?.l0Tokens ?? max(80, l0Used)),
            MemoryContextLayerUsage(layer: "l1_canonical", usedTokens: l1Used, budgetTokens: payload.budgets?.l1Tokens ?? max(220, l1Used)),
            MemoryContextLayerUsage(layer: "l2_observations", usedTokens: l2Used, budgetTokens: payload.budgets?.l2Tokens ?? max(220, l2Used)),
            MemoryContextLayerUsage(layer: "l3_working_set", usedTokens: l3Used, budgetTokens: payload.budgets?.l3Tokens ?? max(300, l3Used)),
            MemoryContextLayerUsage(layer: "l4_raw_evidence", usedTokens: l4Used, budgetTokens: payload.budgets?.l4Tokens ?? max(300, l4Used)),
        ]

        return MemoryContextResponsePayload(
            text: finalText,
            source: snapshot.source,
            resolvedMode: payload.mode,
            resolvedProfile: servingProfile,
            longtermMode: disclosure.longtermMode,
            retrievalAvailable: disclosure.retrievalAvailable,
            fulltextNotLoaded: disclosure.fulltextNotLoaded,
            freshness: nil,
            cacheHit: nil,
            denyCode: nil,
            downgradeCode: nil,
            budgetTotalTokens: budgetTotal,
            usedTotalTokens: usedTotal,
            layerUsage: layerUsage,
            truncatedLayers: [],
            redactedItems: 0,
            privateDrops: 0
        )
    }

    private static func memoryServingProfileSection(_ servingProfile: String?) -> String {
        let normalizedProfile = normalized(servingProfile) ?? ""
        guard !normalizedProfile.isEmpty else { return "" }
        return """
[SERVING_PROFILE]
profile_id: \(normalizedProfile)
[/SERVING_PROFILE]
"""
    }

    private static func mergedMemoryLayer(localPrimary: String, remoteSecondary: String) -> String {
        let local = localPrimary.trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = remoteSecondary.trimmingCharacters(in: .whitespacesAndNewlines)
        if local.isEmpty { return remote }
        if remote.isEmpty { return local }
        return """
\(local)

[hub_remote]
\(remote)
"""
    }

    private struct RemoteMemorySnapshotFetchResult {
        var snapshot: HubRemoteMemorySnapshotResult
        var cacheHit: Bool
    }

    private static func fetchRemoteMemorySnapshot(
        mode: XTMemoryUseMode,
        projectId: String?,
        bypassCache: Bool
    ) async -> RemoteMemorySnapshotFetchResult {
        let cacheKey = HubRemoteMemorySnapshotCache.Key(
            mode: mode.rawValue,
            projectId: normalized(projectId)
        )
        if !bypassCache, let cached = await remoteMemorySnapshotCache.snapshot(for: cacheKey) {
            return RemoteMemorySnapshotFetchResult(snapshot: cached, cacheHit: true)
        }

        let remote = await HubPairingCoordinator.shared.fetchRemoteMemorySnapshot(
            options: HubAIClient.remoteConnectOptionsFromDefaults(stateDir: nil),
            mode: mode.rawValue,
            projectId: normalized(projectId)
        )
        if remote.ok {
            await remoteMemorySnapshotCache.store(remote, for: cacheKey)
        } else {
            await remoteMemorySnapshotCache.invalidate(key: cacheKey)
        }
        return RemoteMemorySnapshotFetchResult(snapshot: remote, cacheHit: false)
    }

    private struct LocalPaidSchedulerConfig: Codable {
        var globalConcurrency: Int?
        var perProjectConcurrency: Int?
        var queueLimit: Int?
        var queueTimeoutMs: Int?

        enum CodingKeys: String, CodingKey {
            case globalConcurrency = "global_concurrency"
            case perProjectConcurrency = "per_project_concurrency"
            case queueLimit = "queue_limit"
            case queueTimeoutMs = "queue_timeout_ms"
        }
    }

    private struct LocalPaidSchedulerState: Codable {
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
        }
    }

    private struct LocalPaidSchedulerInFlightScope: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    private struct LocalPaidSchedulerQueuedScope: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    private struct LocalPaidSchedulerQueueItem: Codable {
        var requestId: String
        var scopeKey: String
        var enqueuedAtMs: Double?
        var queuedMs: Int?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case scopeKey = "scope_key"
            case enqueuedAtMs = "enqueued_at_ms"
            case queuedMs = "queued_ms"
        }
    }

    private struct LocalPaidSchedulerSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var config: LocalPaidSchedulerConfig?
        var state: LocalPaidSchedulerState?
        var inFlightByScope: [LocalPaidSchedulerInFlightScope]?
        var queuedByScope: [LocalPaidSchedulerQueuedScope]?
        var queueItems: [LocalPaidSchedulerQueueItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case config
            case state
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
        }
    }

    private static func readLocalSchedulerStatus(
        includeQueueItems: Bool,
        queueItemsLimit: Int
    ) -> SchedulerStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("paid_ai_scheduler_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPaidSchedulerSnapshotFile.self, from: data) else {
            return nil
        }

        let inFlightByScope = (decoded.inFlightByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.inFlight ?? 0))
        }
        let queuedByScope = (decoded.queuedByScope ?? []).compactMap { row -> SchedulerScopeCount? in
            let key = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return SchedulerScopeCount(scopeKey: key, count: max(0, row.queued ?? 0))
        }
        let queueItems: [SchedulerQueueItem] = includeQueueItems
            ? (decoded.queueItems ?? []).prefix(max(1, min(500, queueItemsLimit))).compactMap { row in
                let requestId = row.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
                let scopeKey = row.scopeKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !requestId.isEmpty, !scopeKey.isEmpty else { return nil }
                return SchedulerQueueItem(
                    requestId: requestId,
                    scopeKey: scopeKey,
                    enqueuedAtMs: max(0, row.enqueuedAtMs ?? 0),
                    queuedMs: max(0, row.queuedMs ?? 0)
                )
            }
            : []

        return SchedulerStatusSnapshot(
            source: "hub_scheduler_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            inFlightTotal: max(0, decoded.state?.inFlightTotal ?? inFlightByScope.reduce(0, { $0 + max(0, $1.count) })),
            queueDepth: max(0, decoded.state?.queueDepth ?? queuedByScope.reduce(0, { $0 + max(0, $1.count) })),
            oldestQueuedMs: max(0, decoded.state?.oldestQueuedMs ?? queueItems.map(\.queuedMs).max() ?? 0),
            inFlightByScope: inFlightByScope,
            queuedByScope: queuedByScope,
            queueItems: queueItems
        )
    }

    private struct LocalPendingGrantItem: Codable {
        var grantRequestId: String
        var requestId: String?
        var client: LocalPendingGrantClient?
        var capability: String?
        var modelId: String?
        var reason: String?
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String?
        var decision: String?
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case client
            case capability
            case modelId = "model_id"
            case reason
            case requestedTtlSec = "requested_ttl_sec"
            case requestedTokenCap = "requested_token_cap"
            case status
            case decision
            case createdAtMs = "created_at_ms"
            case decidedAtMs = "decided_at_ms"
        }
    }

    private struct LocalPendingGrantClient: Codable {
        var deviceId: String?
        var userId: String?
        var appId: String?
        var projectId: String?

        enum CodingKeys: String, CodingKey {
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
        }
    }

    private struct LocalPendingGrantSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalPendingGrantItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalPendingGrantRequests(
        projectId: String?,
        limit: Int
    ) -> PendingGrantSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("pending_grant_requests_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalPendingGrantSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> PendingGrantItem? in
            let grantRequestId = row.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !grantRequestId.isEmpty else { return nil }

            let project = row.client?.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return PendingGrantItem(
                grantRequestId: grantRequestId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                deviceId: row.client?.deviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                userId: row.client?.userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                appId: row.client?.appId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                capability: row.capability?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                modelId: row.modelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                requestedTtlSec: max(0, row.requestedTtlSec ?? 0),
                requestedTokenCap: max(0, row.requestedTokenCap ?? 0),
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                decision: row.decision?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                decidedAtMs: max(0, row.decidedAtMs ?? 0)
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs < rhs.createdAtMs }
            return lhs.grantRequestId.localizedCaseInsensitiveCompare(rhs.grantRequestId) == .orderedAscending
        }

        return PendingGrantSnapshot(
            source: "hub_pending_grants_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalConnectorIngressReceipt: Codable {
        var receiptId: String
        var requestId: String?
        var projectId: String?
        var connector: String?
        var targetId: String?
        var ingressType: String?
        var channelScope: String?
        var sourceId: String?
        var messageId: String?
        var dedupeKey: String?
        var receivedAtMs: Double?
        var eventSequence: Int64?
        var deliveryState: String?
        var runtimeState: String?

        enum CodingKeys: String, CodingKey {
            case receiptId = "receipt_id"
            case requestId = "request_id"
            case projectId = "project_id"
            case connector
            case targetId = "target_id"
            case ingressType = "ingress_type"
            case channelScope = "channel_scope"
            case sourceId = "source_id"
            case messageId = "message_id"
            case dedupeKey = "dedupe_key"
            case receivedAtMs = "received_at_ms"
            case eventSequence = "event_sequence"
            case deliveryState = "delivery_state"
            case runtimeState = "runtime_state"
        }
    }

    private struct LocalConnectorIngressSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalConnectorIngressReceipt]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalConnectorIngressReceipts(
        projectId: String?,
        limit: Int
    ) -> ConnectorIngressSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("connector_ingress_receipts_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalConnectorIngressSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> ConnectorIngressReceipt? in
            let receiptId = row.receiptId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !receiptId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return ConnectorIngressReceipt(
                receiptId: receiptId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                connector: row.connector?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                targetId: row.targetId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                ingressType: row.ingressType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                channelScope: row.channelScope?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                sourceId: row.sourceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                messageId: row.messageId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                dedupeKey: row.dedupeKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                receivedAtMs: max(0, row.receivedAtMs ?? 0),
                eventSequence: Swift.max(0, row.eventSequence ?? 0),
                deliveryState: row.deliveryState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                runtimeState: row.runtimeState?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.receivedAtMs != rhs.receivedAtMs { return lhs.receivedAtMs > rhs.receivedAtMs }
            return lhs.receiptId.localizedCaseInsensitiveCompare(rhs.receiptId) == .orderedAscending
        }

        return ConnectorIngressSnapshot(
            source: "hub_connector_ingress_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var bindingId: String?
        var routeId: String?
        var scopeType: String?
        var scopeId: String?
        var projectId: String?
        var provider: String?
        var accountId: String?
        var conversationId: String?
        var threadKey: String?
        var actorRef: String?
        var resolvedDeviceId: String?
        var preferredDeviceId: String?
        var note: String?
        var createdAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case bindingId = "binding_id"
            case routeId = "route_id"
            case scopeType = "scope_type"
            case scopeId = "scope_id"
            case projectId = "project_id"
            case provider
            case accountId = "account_id"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
            case actorRef = "actor_ref"
            case resolvedDeviceId = "resolved_device_id"
            case preferredDeviceId = "preferred_device_id"
            case note
            case createdAtMs = "created_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommands(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_queue_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = (row.projectId ?? row.scopeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                bindingId: row.bindingId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                routeId: row.routeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                scopeType: row.scopeType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                scopeId: row.scopeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                projectId: project,
                provider: row.provider?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                accountId: row.accountId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                conversationId: row.conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                threadKey: row.threadKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actorRef: row.actorRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                preferredDeviceId: row.preferredDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                note: row.note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs > rhs.createdAtMs }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandSnapshot(
            source: "hub_operator_channel_xt_command_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalOperatorChannelXTCommandResultItem: Codable {
        var commandId: String?
        var requestId: String?
        var actionName: String?
        var projectId: String?
        var resolvedDeviceId: String?
        var status: String?
        var denyCode: String?
        var detail: String?
        var runId: String?
        var createdAtMs: Double?
        var completedAtMs: Double?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case commandId = "command_id"
            case requestId = "request_id"
            case actionName = "action_name"
            case projectId = "project_id"
            case resolvedDeviceId = "resolved_device_id"
            case status
            case denyCode = "deny_code"
            case detail
            case runId = "run_id"
            case createdAtMs = "created_at_ms"
            case completedAtMs = "completed_at_ms"
            case auditRef = "audit_ref"
        }
    }

    private struct LocalOperatorChannelXTCommandResultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalOperatorChannelXTCommandResultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalOperatorChannelXTCommandResults(
        projectId: String?,
        limit: Int
    ) -> OperatorChannelXTCommandResultSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("operator_channel_xt_command_results_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalOperatorChannelXTCommandResultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> OperatorChannelXTCommandResultItem? in
            let commandId = row.commandId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !commandId.isEmpty else { return nil }

            let project = row.projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let normalizedProjectId, !normalizedProjectId.isEmpty, project != normalizedProjectId {
                return nil
            }

            return OperatorChannelXTCommandResultItem(
                commandId: commandId,
                requestId: row.requestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                actionName: row.actionName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                projectId: project,
                resolvedDeviceId: row.resolvedDeviceId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                status: row.status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "",
                denyCode: row.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                detail: row.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                runId: row.runId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                createdAtMs: max(0, row.createdAtMs ?? 0),
                completedAtMs: max(0, row.completedAtMs ?? 0),
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            let leftTimestamp = max(lhs.completedAtMs, lhs.createdAtMs)
            let rightTimestamp = max(rhs.completedAtMs, rhs.createdAtMs)
            if leftTimestamp != rightTimestamp { return leftTimestamp > rightTimestamp }
            return lhs.commandId.localizedCaseInsensitiveCompare(rhs.commandId) == .orderedAscending
        }

        return OperatorChannelXTCommandResultSnapshot(
            source: "hub_operator_channel_xt_command_result_file",
            updatedAtMs: max(0, decoded.updatedAtMs ?? 0),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalAutonomyPolicyOverrideItem: Codable {
        var projectId: String
        var overrideMode: String
        var updatedAtMs: Double?
        var reason: String?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case overrideMode = "override_mode"
            case updatedAtMs = "updated_at_ms"
            case reason
            case auditRef = "audit_ref"
        }
    }

    private struct LocalAutonomyPolicyOverridesSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalAutonomyPolicyOverrideItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalAutonomyPolicyOverrides(
        projectId: String?,
        limit: Int
    ) -> AutonomyPolicyOverridesSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("autonomy_policy_overrides_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalAutonomyPolicyOverridesSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedProjectId = normalized(projectId)
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> AutonomyPolicyOverrideItem? in
            let projectId = row.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            let overrideModeRaw = row.overrideMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !projectId.isEmpty,
                  let overrideMode = AXProjectAutonomyHubOverrideMode(rawValue: overrideModeRaw) else {
                return nil
            }
            if let normalizedProjectId, !normalizedProjectId.isEmpty, projectId != normalizedProjectId {
                return nil
            }

            return AutonomyPolicyOverrideItem(
                projectId: projectId,
                overrideMode: overrideMode,
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded())),
                reason: row.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                auditRef: row.auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return lhs.projectId.localizedCaseInsensitiveCompare(rhs.projectId) == .orderedAscending
        }

        return AutonomyPolicyOverridesSnapshot(
            source: "hub_autonomy_policy_overrides_file",
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private struct LocalSecretVaultItem: Codable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String?
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case itemId = "item_id"
            case scope
            case name
            case sensitivity
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    private struct LocalSecretVaultSnapshotFile: Codable {
        var schemaVersion: String?
        var updatedAtMs: Double?
        var items: [LocalSecretVaultItem]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
        }
    }

    private static func readLocalSecretVaultSnapshot(
        scope: String?,
        namePrefix: String?,
        projectId: String?,
        limit: Int
    ) -> SecretVaultSnapshot? {
        if normalized(projectId) != nil {
            return nil
        }

        let url = HubPaths.baseDir().appendingPathComponent("secret_vault_items_status.json")
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(LocalSecretVaultSnapshotFile.self, from: data) else {
            return nil
        }

        let normalizedScope = normalized(scope)?.lowercased()
        let normalizedNamePrefix = normalized(namePrefix)?.lowercased()
        let boundedLimit = max(1, min(500, limit))

        let mapped = (decoded.items ?? []).compactMap { row -> SecretVaultItem? in
            let itemId = row.itemId.trimmingCharacters(in: .whitespacesAndNewlines)
            let scope = row.scope.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sensitivity = row.sensitivity?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "secret"
            guard !itemId.isEmpty, !scope.isEmpty, !name.isEmpty else { return nil }
            if scope == "project" {
                return nil
            }
            if let normalizedScope, scope != normalizedScope {
                return nil
            }
            if let normalizedNamePrefix, !name.lowercased().hasPrefix(normalizedNamePrefix) {
                return nil
            }
            return SecretVaultItem(
                itemId: itemId,
                scope: scope,
                name: name,
                sensitivity: sensitivity,
                createdAtMs: max(0, Int64((row.createdAtMs ?? 0).rounded())),
                updatedAtMs: max(0, Int64((row.updatedAtMs ?? 0).rounded()))
            )
        }
        .sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            let nameCompare = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameCompare != .orderedSame {
                return nameCompare == .orderedAscending
            }
            return lhs.itemId.localizedCaseInsensitiveCompare(rhs.itemId) == .orderedAscending
        }

        return SecretVaultSnapshot(
            source: "hub_secret_vault_file",
            updatedAtMs: max(0, Int64((decoded.updatedAtMs ?? 0).rounded())),
            items: Array(mapped.prefix(boundedLimit))
        )
    }

    private static func fileIPCEventsDir() -> URL? {
        guard let st = HubConnector.readHubStatusIfAny(ttl: 3.0) else { return nil }
        guard let mode = st.ipcMode, mode == "file" else { return nil }
        guard let ipcPath = st.ipcPath, !ipcPath.isEmpty else { return nil }

        let dir = URL(fileURLWithPath: ipcPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func supervisorIncidentAuditEventsDir() -> URL? {
        if let dir = fileIPCEventsDir() {
            return dir
        }
        let fallback = HubPaths.baseDir().appendingPathComponent("ipc_events", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        } catch {
            return nil
        }
    }

    private static func pollMemoryContextResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollMemoryRetrievalResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> MemoryContextIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.25, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(MemoryContextIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollVoiceWakeProfileResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> VoiceWakeProfileIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(VoiceWakeProfileIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollSecretVaultListResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultListIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultListIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollSecretVaultUseResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> SecretVaultUseIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(4.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(SecretVaultUseIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func pollNetworkResponse(
        baseDir: URL,
        reqId: String,
        timeoutSec: Double
    ) async -> NetworkIPCResponse? {
        let rid = reqId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let dir = baseDir.appendingPathComponent("ipc_responses", isDirectory: true)
        let url = dir.appendingPathComponent("resp_\(rid).json")
        let deadline = Date().addingTimeInterval(max(0.2, min(6.0, timeoutSec)))

        while Date() < deadline {
            if let data = try? Data(contentsOf: url),
               let resp = try? JSONDecoder().decode(NetworkIPCResponse.self, from: data) {
                try? FileManager.default.removeItem(at: url)
                return resp
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
        }
        return nil
    }

    private static func waitForBridgeEnabled(timeoutSec: Double) async -> HubBridgeClient.BridgeStatus {
        let deadline = Date().addingTimeInterval(max(0.2, min(8.0, timeoutSec)))
        while Date() < deadline {
            let st = HubBridgeClient.status()
            if st.enabled {
                return st
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        return HubBridgeClient.status()
    }

    private static func mapPendingGrantActionResult(
        _ remote: HubRemotePendingGrantActionResult,
        defaultGrantRequestId: String
    ) -> PendingGrantActionResult {
        let mappedDecision: PendingGrantActionDecision = {
            switch remote.decision {
            case .approved:
                return .approved
            case .denied:
                return .denied
            case .failed:
                return .failed
            }
        }()
        let reason = normalizedReasonCode(remote.reasonCode, fallback: remote.ok ? nil : "pending_grant_action_failed")
        return PendingGrantActionResult(
            ok: remote.ok,
            decision: mappedDecision,
            source: "hub_runtime_grpc",
            grantRequestId: normalized(remote.grantRequestId) ?? defaultGrantRequestId,
            grantId: normalized(remote.grantId),
            expiresAtMs: remote.expiresAtMs,
            reasonCode: reason
        )
    }

    private static func mapSecretVaultCreateResult(
        _ remote: HubRemoteSecretVaultCreateResult
    ) -> SecretCreateResult {
        let mappedItem: SecretVaultItem? = {
            guard let item = remote.item else { return nil }
            return SecretVaultItem(
                itemId: item.itemId,
                scope: item.scope,
                name: item.name,
                sensitivity: item.sensitivity,
                createdAtMs: max(0, Int64(item.createdAtMs.rounded())),
                updatedAtMs: max(0, Int64(item.updatedAtMs.rounded()))
            )
        }()
        return SecretCreateResult(
            ok: remote.ok,
            source: remote.source,
            item: mappedItem,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_create_failed"
            )
        )
    }

    private static func mapSecretVaultUseResult(
        _ remote: HubRemoteSecretVaultUseResult
    ) -> SecretUseResult {
        SecretUseResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            useToken: normalized(remote.useToken),
            itemId: normalized(remote.itemId),
            expiresAtMs: remote.expiresAtMs.map { max(0, Int64($0.rounded())) },
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_use_failed"
            )
        )
    }

    private static func mapSecretVaultUseAck(
        _ ack: SecretVaultUseIPCResponse,
        source: String,
        fallbackItemId: String?
    ) -> SecretUseResult {
        guard ack.ok else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_use_failed")
            )
        }
        guard let result = ack.secretVaultUse else {
            return SecretUseResult(
                ok: false,
                source: source,
                leaseId: nil,
                useToken: nil,
                itemId: fallbackItemId,
                expiresAtMs: nil,
                reasonCode: "secret_vault_use_missing"
            )
        }
        return SecretUseResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            useToken: normalized(result.useToken),
            itemId: normalized(result.itemId) ?? fallbackItemId,
            expiresAtMs: result.expiresAtMs.map { max(0, $0) },
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_use_failed"
            )
        )
    }

    private static func mapSecretVaultRedeemResult(
        _ remote: HubRemoteSecretVaultRedeemResult
    ) -> SecretRedeemResult {
        SecretRedeemResult(
            ok: remote.ok,
            source: remote.source,
            leaseId: normalized(remote.leaseId),
            itemId: normalized(remote.itemId),
            plaintext: remote.plaintext,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_secret_vault_redeem_failed"
            )
        )
    }

    private static func mapSecretVaultRedeemAck(
        _ ack: SecretVaultRedeemIPCResponse,
        source: String
    ) -> SecretRedeemResult {
        guard ack.ok else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: normalizedReasonCode(ack.error, fallback: "secret_vault_redeem_failed")
            )
        }
        guard let result = ack.secretVaultRedeem else {
            return SecretRedeemResult(
                ok: false,
                source: source,
                leaseId: nil,
                itemId: nil,
                plaintext: nil,
                reasonCode: "secret_vault_redeem_missing"
            )
        }
        return SecretRedeemResult(
            ok: result.ok,
            source: source,
            leaseId: normalized(result.leaseId),
            itemId: normalized(result.itemId),
            plaintext: result.plaintext,
            reasonCode: normalizedReasonCode(
                result.reasonCode,
                fallback: result.ok ? nil : "secret_vault_redeem_failed"
            )
        )
    }

    private static func mapVoiceGrantChallengeResult(
        _ remote: HubRemoteVoiceGrantChallengeResult
    ) -> VoiceGrantChallengeResult {
        let mappedChallenge: VoiceGrantChallengeSnapshot? = {
            guard let challenge = remote.challenge else { return nil }
            return VoiceGrantChallengeSnapshot(
                challengeId: challenge.challengeId,
                templateId: challenge.templateId,
                actionDigest: challenge.actionDigest,
                scopeDigest: challenge.scopeDigest,
                amountDigest: challenge.amountDigest,
                challengeCode: challenge.challengeCode,
                riskLevel: challenge.riskLevel,
                requiresMobileConfirm: challenge.requiresMobileConfirm,
                allowVoiceOnly: challenge.allowVoiceOnly,
                boundDeviceId: challenge.boundDeviceId,
                mobileTerminalId: challenge.mobileTerminalId,
                issuedAtMs: challenge.issuedAtMs,
                expiresAtMs: challenge.expiresAtMs
            )
        }()
        return VoiceGrantChallengeResult(
            ok: remote.ok,
            source: remote.source,
            challenge: mappedChallenge,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_challenge_failed"
            )
        )
    }

    private static func mapVoiceGrantVerificationResult(
        _ remote: HubRemoteVoiceGrantVerificationResult
    ) -> VoiceGrantVerificationResult {
        let mappedDecision: VoiceGrantVerificationDecision = {
            switch remote.decision {
            case .allow:
                return .allow
            case .deny:
                return .deny
            case .failed:
                return .failed
            }
        }()
        return VoiceGrantVerificationResult(
            ok: remote.ok,
            verified: remote.verified,
            decision: mappedDecision,
            source: remote.source,
            denyCode: normalized(remote.denyCode),
            challengeId: normalized(remote.challengeId),
            transcriptHash: normalized(remote.transcriptHash),
            semanticMatchScore: remote.semanticMatchScore,
            challengeMatch: remote.challengeMatch,
            deviceBindingOK: remote.deviceBindingOK,
            mobileConfirmed: remote.mobileConfirmed,
            reasonCode: normalizedReasonCode(
                remote.reasonCode,
                fallback: remote.ok ? nil : "remote_voice_grant_verify_failed"
            )
        )
    }

    static func normalizedReasonCode(_ raw: String?, fallback: String? = nil) -> String? {
        let primary = normalized(raw)
        let backup = normalized(fallback)
        let token = sanitizeReasonToken(primary ?? backup ?? "")
        guard !token.isEmpty else { return nil }

        if token.contains("grant_required") { return "grant_required" }
        if token.contains("bridge_disabled") { return "bridge_disabled" }
        if token.contains("bridge_unavailable") { return "bridge_unavailable" }
        if token.contains("permission_denied") || token.contains("forbidden") || token == "403" || token.contains("_403") {
            return "forbidden"
        }
        if token.contains("unauthenticated") || token == "401" || token.contains("_401") {
            return "unauthenticated"
        }
        if token.contains("certificate") || token.contains("tls") || token.contains("ssl") {
            return "tls_error"
        }
        if token.contains("timeout") { return "timeout" }
        if token.contains("hub_env_missing") { return "hub_env_missing" }
        if token.contains("client_kit_missing") { return "client_kit_missing" }
        if token.contains("node_missing") { return "node_missing" }
        if token.contains("hub_not_connected") || token.contains("not_connected") {
            return "hub_not_connected"
        }
        if token.contains("auto_approved") { return "auto_approved" }
        if token.contains("ack_timeout") { return "ack_timeout" }
        if token.contains("denied") { return "denied" }
        return token
    }

    static func isBridgeGrantRequiredReason(_ reasonCode: String?) -> Bool {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return false }
        return reason == "grant_required" || reason == "bridge_disabled" || reason == "bridge_unavailable"
    }

    private static func networkFailureState(reasonCode: String?) -> NetworkAccessState {
        guard let reason = normalizedReasonCode(reasonCode, fallback: nil) else { return .failed }
        if reason == "denied" || reason == "forbidden" {
            return .denied
        }
        return .failed
    }

    private static func sanitizeReasonToken(_ raw: String) -> String {
        var token = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        while token.contains("__") {
            token = token.replacingOccurrences(of: "__", with: "_")
        }
        return token.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func writeLocalSnapshot<T: Encodable>(_ payload: T, to url: URL) -> Bool {
        let directory = url.deletingLastPathComponent()
        let tmp = directory.appendingPathComponent(".\(url.lastPathComponent).tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(payload)
            try data.write(to: tmp, options: .atomic)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: tmp, to: url)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
    }

    private static func writeEvent(
        data: Data,
        reqId: String,
        filePrefix: String,
        tmpPrefix: String,
        in dir: URL
    ) -> Bool {
        let file = dir.appendingPathComponent("\(filePrefix)_\(Int(Date().timeIntervalSince1970))_\(reqId).json")
        let tmp = dir.appendingPathComponent("\(tmpPrefix)_\(reqId).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            try FileManager.default.moveItem(at: tmp, to: file)
            return true
        } catch {
            return false
        }
    }

    private static func orderedUniqueStringTokens(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        return raw.compactMap { item in
            guard let token = normalized(item)?.lowercased(), !token.isEmpty else { return nil }
            guard seen.insert(token).inserted else { return nil }
            return token
        }
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func installSecretVaultUseOverrideForTesting(
        _ override: (@Sendable (SecretUseRequestPayload) async -> SecretUseResult)?
    ) {
        testingOverrideLock.lock()
        secretUseOverrideForTesting = override
        testingOverrideLock.unlock()
    }

    static func installSecretVaultRedeemOverrideForTesting(
        _ override: (@Sendable (SecretRedeemRequestPayload) async -> SecretRedeemResult)?
    ) {
        testingOverrideLock.lock()
        secretRedeemOverrideForTesting = override
        testingOverrideLock.unlock()
    }

    static func resetSecretVaultOverridesForTesting() {
        testingOverrideLock.lock()
        secretUseOverrideForTesting = nil
        secretRedeemOverrideForTesting = nil
        testingOverrideLock.unlock()
    }
}
