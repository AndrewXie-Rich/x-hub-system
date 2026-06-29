import Foundation

extension HubIPCClient {
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

    struct ProjectCanonicalMemoryRustSyncOverrideResult: Equatable, Sendable {
        var ok: Bool
        var source: String = "rust_http"
        var deliveryState: String? = nil
        var reasonCode: String? = nil
        var detail: String? = nil
    }

    struct ProjectCanonicalMemoryPendingRustSyncSnapshot: Codable {
        static let schemaVersion = "xt.project_canonical_memory_pending_rust_sync.v1"

        var schemaVersion: String
        var projectId: String
        var projectRoot: String
        var displayName: String
        var recordedAtMs: Int64
        var memoryUpdatedAt: Double?
        var source: String
        var deliveryState: String
        var reasonCode: String
        var detail: String
        var itemCount: Int
        var payload: ProjectCanonicalMemoryPayload

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case projectId = "project_id"
            case projectRoot = "project_root"
            case displayName = "display_name"
            case recordedAtMs = "recorded_at_ms"
            case memoryUpdatedAt = "memory_updated_at"
            case source
            case deliveryState = "delivery_state"
            case reasonCode = "reason_code"
            case detail
            case itemCount = "item_count"
            case payload
        }
    }

    struct ProjectCanonicalMemoryPendingRustSyncRetryResult: Equatable, Sendable {
        var attempted: Bool
        var ok: Bool
        var source: String
        var deliveryState: String? = nil
        var reasonCode: String? = nil
        var detail: String? = nil
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

    struct CanonicalMemorySyncStatusItem: Codable, Equatable, Sendable, Identifiable {
        var scopeKind: String
        var scopeId: String
        var displayName: String
        var source: String
        var ok: Bool
        var updatedAtMs: Int64
        var reasonCode: String?
        var detail: String?
        var deliveryState: String?
        var auditRefs: [String]?
        var evidenceRefs: [String]?
        var writebackRefs: [String]?

        var id: String { "\(scopeKind)::\(scopeId)" }
        var primaryAuditRef: String? { auditRefs?.first }
        var primaryEvidenceRef: String? { evidenceRefs?.first }
        var primaryWritebackRef: String? { writebackRefs?.first }

        init(
            scopeKind: String,
            scopeId: String,
            displayName: String,
            source: String,
            ok: Bool,
            updatedAtMs: Int64,
            reasonCode: String? = nil,
            detail: String? = nil,
            deliveryState: String? = nil,
            auditRefs: [String]? = nil,
            evidenceRefs: [String]? = nil,
            writebackRefs: [String]? = nil
        ) {
            self.scopeKind = scopeKind
            self.scopeId = scopeId
            self.displayName = displayName
            self.source = source
            self.ok = ok
            self.updatedAtMs = updatedAtMs
            self.reasonCode = reasonCode
            self.detail = detail
            self.deliveryState = deliveryState
            self.auditRefs = auditRefs
            self.evidenceRefs = evidenceRefs
            self.writebackRefs = writebackRefs
        }

        enum CodingKeys: String, CodingKey {
            case scopeKind = "scope_kind"
            case scopeId = "scope_id"
            case displayName = "display_name"
            case source
            case ok
            case updatedAtMs = "updated_at_ms"
            case reasonCode = "reason_code"
            case detail
            case deliveryState = "delivery_state"
            case auditRefs = "audit_refs"
            case evidenceRefs = "evidence_refs"
            case writebackRefs = "writeback_refs"
        }
    }

    struct CanonicalMemorySyncStatusSnapshot: Codable, Equatable, Sendable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var items: [CanonicalMemorySyncStatusItem]

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case items
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
        var reviewLevelHint: String?
        var constitutionHint: String?
        var dialogueWindowText: String?
        var portfolioBriefText: String?
        var focusedProjectAnchorPackText: String?
        var longtermOutlineText: String?
        var deltaFeedText: String?
        var conflictSetText: String?
        var contextRefsText: String?
        var evidencePackText: String?
        var canonicalText: String?
        var observationsText: String?
        var workingSetText: String?
        var rawEvidenceText: String?
        var servingProfile: String? = nil
        var budgets: MemoryContextBudgets?

        init(
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
            budgets: MemoryContextBudgets? = nil
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

        enum CodingKeys: String, CodingKey {
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

    struct MemoryRetrievalResultItem: Codable, Equatable, Sendable {
        var ref: String
        var sourceKind: String
        var summary: String
        var snippet: String
        var score: Double
        var redacted: Bool

        enum CodingKeys: String, CodingKey {
            case ref
            case sourceKind = "source_kind"
            case summary
            case snippet
            case score
            case redacted
        }
    }

    struct MemoryRetrievalPayload: Codable, Equatable {
        var schemaVersion: String
        var requestId: String
        var scope: String
        var requesterRole: String
        var mode: String
        var projectId: String?
        var crossProjectTargetIds: [String]
        var projectRoot: String?
        var displayName: String?
        var query: String
        var latestUser: String
        var allowedLayers: [String]
        var retrievalKind: String
        var maxResults: Int
        var reason: String?
        var requireExplainability: Bool
        var requestedKinds: [String]
        var explicitRefs: [String]
        var maxSnippets: Int
        var maxSnippetChars: Int
        var auditRef: String

        init(
            schemaVersion: String = "xt.memory_retrieval_request.v1",
            requestId: String,
            scope: String,
            requesterRole: String,
            mode: String,
            projectId: String?,
            crossProjectTargetIds: [String] = [],
            projectRoot: String?,
            displayName: String?,
            query: String,
            latestUser: String,
            allowedLayers: [String],
            retrievalKind: String,
            maxResults: Int,
            reason: String?,
            requireExplainability: Bool = true,
            requestedKinds: [String],
            explicitRefs: [String],
            maxSnippets: Int,
            maxSnippetChars: Int,
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

        enum CodingKeys: String, CodingKey {
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
        var requestedProfile: String?
        var resolvedProfile: String?
        var attemptedProfiles: [String]?
        var progressiveUpgradeCount: Int?
        var longtermMode: String?
        var retrievalAvailable: Bool?
        var fulltextNotLoaded: Bool?
        var freshness: String?
        var cacheHit: Bool?
        var remoteSnapshotCacheScope: String?
        var remoteSnapshotCachedAtMs: Int64?
        var remoteSnapshotAgeMs: Int?
        var remoteSnapshotTTLRemainingMs: Int?
        var remoteSnapshotCachePosture: String?
        var remoteSnapshotInvalidationReason: String?
        var denyCode: String?
        var downgradeCode: String?
        var memoryGatewaySource: String?
        var memoryGatewayPrimaryEnabled: Bool?
        var memoryGatewayMode: String?
        var memoryGatewaySafetyMode: String?
        var memoryGatewayProductionAuthorityChange: Bool?
        var memoryGatewayModelCall: Bool?
        var memoryGatewayObjectCount: Int?
        var memoryGatewayEffectiveLayers: [String]?
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
            requestedProfile: String? = nil,
            resolvedProfile: String? = nil,
            attemptedProfiles: [String]? = nil,
            progressiveUpgradeCount: Int? = nil,
            longtermMode: String? = nil,
            retrievalAvailable: Bool? = nil,
            fulltextNotLoaded: Bool? = nil,
            freshness: String? = nil,
            cacheHit: Bool? = nil,
            remoteSnapshotCacheScope: String? = nil,
            remoteSnapshotCachedAtMs: Int64? = nil,
            remoteSnapshotAgeMs: Int? = nil,
            remoteSnapshotTTLRemainingMs: Int? = nil,
            remoteSnapshotCachePosture: String? = nil,
            remoteSnapshotInvalidationReason: String? = nil,
            denyCode: String? = nil,
            downgradeCode: String? = nil,
            memoryGatewaySource: String? = nil,
            memoryGatewayPrimaryEnabled: Bool? = nil,
            memoryGatewayMode: String? = nil,
            memoryGatewaySafetyMode: String? = nil,
            memoryGatewayProductionAuthorityChange: Bool? = nil,
            memoryGatewayModelCall: Bool? = nil,
            memoryGatewayObjectCount: Int? = nil,
            memoryGatewayEffectiveLayers: [String]? = nil,
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
            self.requestedProfile = requestedProfile
            self.resolvedProfile = resolvedProfile
            self.attemptedProfiles = attemptedProfiles
            self.progressiveUpgradeCount = progressiveUpgradeCount
            self.longtermMode = longtermMode
            self.retrievalAvailable = retrievalAvailable
            self.fulltextNotLoaded = fulltextNotLoaded
            self.freshness = freshness
            self.cacheHit = cacheHit
            self.remoteSnapshotCacheScope = remoteSnapshotCacheScope
            self.remoteSnapshotCachedAtMs = remoteSnapshotCachedAtMs
            self.remoteSnapshotAgeMs = remoteSnapshotAgeMs
            self.remoteSnapshotTTLRemainingMs = remoteSnapshotTTLRemainingMs
            self.remoteSnapshotCachePosture = remoteSnapshotCachePosture
            self.remoteSnapshotInvalidationReason = remoteSnapshotInvalidationReason
            self.denyCode = denyCode
            self.downgradeCode = downgradeCode
            self.memoryGatewaySource = memoryGatewaySource
            self.memoryGatewayPrimaryEnabled = memoryGatewayPrimaryEnabled
            self.memoryGatewayMode = memoryGatewayMode
            self.memoryGatewaySafetyMode = memoryGatewaySafetyMode
            self.memoryGatewayProductionAuthorityChange = memoryGatewayProductionAuthorityChange
            self.memoryGatewayModelCall = memoryGatewayModelCall
            self.memoryGatewayObjectCount = memoryGatewayObjectCount
            self.memoryGatewayEffectiveLayers = memoryGatewayEffectiveLayers
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
            case requestedProfile = "requested_profile"
            case resolvedProfile = "resolved_profile"
            case attemptedProfiles = "attempted_profiles"
            case progressiveUpgradeCount = "progressive_upgrade_count"
            case longtermMode = "longterm_mode"
            case retrievalAvailable = "retrieval_available"
            case fulltextNotLoaded = "fulltext_not_loaded"
            case freshness
            case cacheHit = "cache_hit"
            case remoteSnapshotCacheScope = "remote_snapshot_cache_scope"
            case remoteSnapshotCachedAtMs = "remote_snapshot_cached_at_ms"
            case remoteSnapshotAgeMs = "remote_snapshot_age_ms"
            case remoteSnapshotTTLRemainingMs = "remote_snapshot_ttl_remaining_ms"
            case remoteSnapshotCachePosture = "remote_snapshot_cache_posture"
            case remoteSnapshotInvalidationReason = "remote_snapshot_invalidation_reason"
            case denyCode = "deny_code"
            case downgradeCode = "downgrade_code"
            case memoryGatewaySource = "memory_gateway_source"
            case memoryGatewayPrimaryEnabled = "memory_gateway_primary_enabled"
            case memoryGatewayMode = "memory_gateway_mode"
            case memoryGatewaySafetyMode = "memory_gateway_safety_mode"
            case memoryGatewayProductionAuthorityChange = "memory_gateway_production_authority_change"
            case memoryGatewayModelCall = "memory_gateway_model_call"
            case memoryGatewayObjectCount = "memory_gateway_object_count"
            case memoryGatewayEffectiveLayers = "memory_gateway_effective_layers"
            case budgetTotalTokens = "budget_total_tokens"
            case usedTotalTokens = "used_total_tokens"
            case layerUsage = "layer_usage"
            case truncatedLayers = "truncated_layers"
            case redactedItems = "redacted_items"
            case privateDrops = "private_drops"
        }
    }

    struct MemoryRetrievalResponsePayload: Codable, Equatable, Sendable {
        var schemaVersion: String?
        var requestId: String?
        var status: String?
        var resolvedScope: String?
        var source: String
        var scope: String
        var auditRef: String
        var reasonCode: String?
        var detail: String?
        var denyCode: String?
        var results: [MemoryRetrievalResultItem]?
        var snippets: [MemoryRetrievalSnippet]
        var truncated: Bool?
        var budgetUsedChars: Int?
        var truncatedItems: Int
        var redactedItems: Int

        init(
            schemaVersion: String? = nil,
            requestId: String? = nil,
            status: String? = nil,
            resolvedScope: String? = nil,
            source: String,
            scope: String,
            auditRef: String,
            reasonCode: String? = nil,
            detail: String? = nil,
            denyCode: String? = nil,
            results: [MemoryRetrievalResultItem]? = nil,
            snippets: [MemoryRetrievalSnippet],
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
            self.detail = detail
            self.denyCode = denyCode
            self.results = results
            self.snippets = snippets
            self.truncated = truncated
            self.budgetUsedChars = budgetUsedChars
            self.truncatedItems = truncatedItems
            self.redactedItems = redactedItems
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case requestId = "request_id"
            case status
            case resolvedScope = "resolved_scope"
            case source
            case scope
            case auditRef = "audit_ref"
            case reasonCode = "reason_code"
            case detail
            case denyCode = "deny_code"
            case results
            case snippets
            case truncated
            case budgetUsedChars = "budget_used_chars"
            case truncatedItems = "truncated_items"
            case redactedItems = "redacted_items"
        }
    }

    struct MemoryContextResolutionResult {
        var response: MemoryContextResponsePayload?
        var source: String
        var resolvedMode: XTMemoryUseMode
        var requestedProfile: String?
        var attemptedProfiles: [String]
        var freshness: String
        var cacheHit: Bool
        var remoteSnapshotCacheScope: String? = nil
        var remoteSnapshotCachedAtMs: Int64? = nil
        var remoteSnapshotAgeMs: Int? = nil
        var remoteSnapshotTTLRemainingMs: Int? = nil
        var remoteSnapshotCachePosture: String? = nil
        var remoteSnapshotInvalidationReason: String? = nil
        var denyCode: String?
        var downgradeCode: String?
        var reasonCode: String?
        var detail: String? = nil
    }

    static func isRustMemoryGatewayRequiredFailure(_ result: MemoryContextResolutionResult) -> Bool {
        guard result.response == nil else { return false }
        if result.source == "rust_memory_gateway_cutover_gate" {
            return true
        }
        let reason = normalized(result.reasonCode) ?? ""
        return reason.hasPrefix("memory_gateway_cutover_")
            || reason.hasPrefix("rust_memory_gateway_required_")
    }

    static func rustMemoryGatewayRequiredFailureMemoryText(
        _ result: MemoryContextResolutionResult
    ) -> String {
        let reason = normalized(result.reasonCode) ?? "rust_memory_gateway_required_failed"
        let detail = rustMemoryGatewayDiagnosticLine(result.detail)
        var lines = [
            "[MEMORY_V1]",
            "[RUST_MEMORY_GATEWAY_CUTOVER]",
            "source=rust_memory_gateway_cutover_gate",
            "required=true",
            "fallback_disabled=true",
            "reason_code=\(reason)",
            "freshness=\(result.freshness)"
        ]
        if let detail {
            lines.append("detail=\(detail)")
        }
        lines.append("[/RUST_MEMORY_GATEWAY_CUTOVER]")
        lines.append("[/MEMORY_V1]")
        return lines.joined(separator: "\n")
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
}
