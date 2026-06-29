import Foundation

extension HubPairingCoordinator {
    // MARK: - Helpers

    struct StepOutput {
        var exitCode: Int32
        var output: String
        var command: String
    }

    struct PersistedConnectionProfile: Encodable {
        var schemaVersion: String
        var updatedAtMs: Int64
        var hubEnvPath: String
        var hubHost: String?
        var grpcPort: Int
        var pairingPort: Int
        var deviceID: String?
        var pairingProfileEpoch: Int?
        var routePackVersion: String?
        var tlsMode: String?
        var tlsServerName: String?
        var caCertPath: String?
        var clientCertPath: String?
        var clientKeyPath: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case updatedAtMs = "updated_at_ms"
            case hubEnvPath = "hub_env_path"
            case hubHost = "hub_host"
            case grpcPort = "grpc_port"
            case pairingPort = "pairing_port"
            case deviceID = "device_id"
            case pairingProfileEpoch = "pairing_profile_epoch"
            case routePackVersion = "route_pack_version"
            case tlsMode = "tls_mode"
            case tlsServerName = "tls_server_name"
            case caCertPath = "ca_cert_path"
            case clientCertPath = "client_cert_path"
            case clientKeyPath = "client_key_path"
        }
    }

    struct RemoteGenerateScriptResult: Codable {
        var ok: Bool?
        var text: String?
        var modelId: String?
        var requestedModelId: String?
        var actualModelId: String?
        var runtimeProvider: String?
        var executionPath: String?
        var fallbackReasonCode: String?
        var auditRef: String?
        var denyCode: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var promptTokens: Int?
        var completionTokens: Int?
        var totalTokens: Int?
        var memoryPromptProjection: HubMemoryPromptProjectionSnapshot?

        enum CodingKeys: String, CodingKey {
            case ok
            case text
            case modelId = "model_id"
            case requestedModelId = "requested_model_id"
            case actualModelId = "actual_model_id"
            case runtimeProvider = "runtime_provider"
            case executionPath = "execution_path"
            case fallbackReasonCode = "fallback_reason_code"
            case auditRef = "audit_ref"
            case denyCode = "deny_code"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case memoryPromptProjection = "memory_prompt_projection"
        }
    }

    static func successfulRemoteGenerateResult(
        from decoded: RemoteGenerateScriptResult,
        fallbackModelId: String?,
        logLines: [String]
    ) -> HubRemoteGenerateResult? {
        func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        let text = decoded.text ?? ""
        guard !text.isEmpty else { return nil }
        return HubRemoteGenerateResult(
            ok: true,
            text: text,
            modelId: cleaned(decoded.modelId) ?? cleaned(fallbackModelId),
            requestedModelId: cleaned(decoded.requestedModelId) ?? cleaned(fallbackModelId),
            actualModelId: cleaned(decoded.actualModelId) ?? cleaned(decoded.modelId) ?? cleaned(fallbackModelId),
            runtimeProvider: cleaned(decoded.runtimeProvider),
            executionPath: cleaned(decoded.executionPath),
            fallbackReasonCode: cleaned(decoded.fallbackReasonCode),
            auditRef: cleaned(decoded.auditRef),
            denyCode: cleaned(decoded.denyCode),
            promptTokens: decoded.promptTokens,
            completionTokens: decoded.completionTokens,
            memoryPromptProjection: decoded.memoryPromptProjection,
            grantDecision: nil,
            grantRequestId: nil,
            reasonCode: nil,
            logLines: logLines
        )
    }

    struct RemoteNetworkGrantScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var expiresAtMs: Double?
        var reason: String?
        var queued: Bool?
        var autoApproved: Bool?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case queued
            case autoApproved = "auto_approved"
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteWebFetchScriptResult: Codable {
        var ok: Bool?
        var status: Int?
        var finalURL: String?
        var contentType: String?
        var truncated: Bool?
        var bytes: Int?
        var text: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case status
            case finalURL = "final_url"
            case contentType = "content_type"
            case truncated
            case bytes
            case text
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteMutationScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var auditRef: String?
        var evidenceRef: String?
        var writebackRef: String?
        var auditRefs: [String]?
        var evidenceRefs: [String]?
        var writebackRefs: [String]?
        var updatedAtMs: Int64?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case auditRef = "audit_ref"
            case evidenceRef = "evidence_ref"
            case writebackRef = "writeback_ref"
            case auditRefs = "audit_refs"
            case evidenceRefs = "evidence_refs"
            case writebackRefs = "writeback_refs"
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct RemoteSkillCatalogEntryScriptResult: Codable {
        var skillID: String?
        var name: String?
        var version: String?
        var description: String?
        var publisherID: String?
        var capabilitiesRequired: [String]?
        var sourceID: String?
        var packageSHA256: String?
        var installHint: String?
        var riskLevel: String?
        var requiresGrant: Bool?
        var sideEffectClass: String?

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
            case riskLevel = "risk_level"
            case requiresGrant = "requires_grant"
            case sideEffectClass = "side_effect_class"
        }
    }

    struct RemoteSkillsSearchScriptResult: Codable {
        struct OfficialSkillChannelStatus: Codable {
            var channelID: String?
            var status: String?
            var updatedAtMs: Int64?
            var lastAttemptAtMs: Int64?
            var lastSuccessAtMs: Int64?
            var skillCount: Int?
            var errorCode: String?
            var maintenanceEnabled: Bool?
            var maintenanceIntervalMs: Int64?
            var maintenanceLastRunAtMs: Int64?
            var maintenanceSourceKind: String?
            var lastTransitionAtMs: Int64?
            var lastTransitionKind: String?
            var lastTransitionSummary: String?

            enum CodingKeys: String, CodingKey {
                case channelID = "channel_id"
                case status
                case updatedAtMs = "updated_at_ms"
                case lastAttemptAtMs = "last_attempt_at_ms"
                case lastSuccessAtMs = "last_success_at_ms"
                case skillCount = "skill_count"
                case errorCode = "error_code"
                case maintenanceEnabled = "maintenance_enabled"
                case maintenanceIntervalMs = "maintenance_interval_ms"
                case maintenanceLastRunAtMs = "maintenance_last_run_at_ms"
                case maintenanceSourceKind = "maintenance_source_kind"
                case lastTransitionAtMs = "last_transition_at_ms"
                case lastTransitionKind = "last_transition_kind"
                case lastTransitionSummary = "last_transition_summary"
            }
        }

        var ok: Bool?
        var source: String?
        var updatedAtMs: Int64?
        var results: [RemoteSkillCatalogEntryScriptResult]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?
        var officialChannelStatus: OfficialSkillChannelStatus?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case results
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
            case officialChannelStatus = "official_channel_status"
        }
    }

    struct RemoteSkillPinScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var scope: String?
        var userId: String?
        var projectId: String?
        var skillId: String?
        var packageSHA256: String?
        var previousPackageSHA256: String?
        var updatedAtMs: Int64?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

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
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteResolvedSkillEntryScriptResult: Codable {
        var scope: String?
        var skill: RemoteSkillCatalogEntryScriptResult?
    }

    struct RemoteResolvedSkillsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var skills: [RemoteResolvedSkillEntryScriptResult]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skills
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSkillManifestScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var packageSHA256: String?
        var manifestJSON: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case manifestJSON = "manifest_json"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSkillPackageDownloadScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var packageSHA256: String?
        var packageBase64: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case packageBase64 = "package_base64"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSkillRunnerGateScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var skillId: String?
        var packageSHA256: String?
        var toolName: String?
        var decision: String?
        var toolRequestId: String?
        var grantId: String?
        var executionId: String?
        var denyCode: String?
        var resultJSON: String?
        var executedAtMs: Int64?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case skillId = "skill_id"
            case packageSHA256 = "package_sha256"
            case toolName = "tool_name"
            case decision
            case toolRequestId = "tool_request_id"
            case grantId = "grant_id"
            case executionId = "execution_id"
            case denyCode = "deny_code"
            case resultJSON = "result_json"
            case executedAtMs = "executed_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteAgentImportStageScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var preflightStatus: String?
        var skillId: String?
        var policyScope: String?
        var findingsCount: Int?
        var vetterStatus: String?
        var vetterCriticalCount: Int?
        var vetterWarnCount: Int?
        var vetterAuditRef: String?
        var recordPath: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

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
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteAgentImportRecordScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var selector: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var schemaVersion: String?
        var skillId: String?
        var projectId: String?
        var recordJSON: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case selector
            case stagingId = "staging_id"
            case status
            case auditRef = "audit_ref"
            case schemaVersion = "schema_version"
            case skillId = "skill_id"
            case projectId = "project_id"
            case recordJSON = "record_json"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSkillPackageUploadScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var packageSHA256: String?
        var alreadyPresent: Bool?
        var skillId: String?
        var version: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case packageSHA256 = "package_sha256"
            case alreadyPresent = "already_present"
            case skillId = "skill_id"
            case version
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteAgentImportPromoteScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var stagingId: String?
        var status: String?
        var auditRef: String?
        var packageSHA256: String?
        var scope: String?
        var skillId: String?
        var previousPackageSHA256: String?
        var recordPath: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

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
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteMemorySnapshotScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var canonicalEntries: [String]?
        var workingEntries: [String]?
        var roleTurnMessages: [XTProjectConversationMirrorMessage]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case canonicalEntries = "canonical_entries"
            case workingEntries = "working_entries"
            case roleTurnMessages = "role_turn_messages"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteMemoryRetrievalScriptItem: Codable {
        var ref: String?
        var sourceKind: String?
        var summary: String?
        var snippet: String?
        var score: Double?
        var redacted: Bool?

        enum CodingKeys: String, CodingKey {
            case ref
            case sourceKind = "source_kind"
            case summary
            case snippet
            case score
            case redacted
        }
    }

    struct RemoteMemoryRetrievalScriptResult: Codable {
        var ok: Bool?
        var schemaVersion: String?
        var requestId: String?
        var status: String?
        var resolvedScope: String?
        var source: String?
        var scope: String?
        var auditRef: String?
        var reasonCode: String?
        var denyCode: String?
        var results: [RemoteMemoryRetrievalScriptItem]?
        var truncated: Bool?
        var budgetUsedChars: Int?
        var truncatedItems: Int?
        var redactedItems: Int?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
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
            case truncated
            case budgetUsedChars = "budget_used_chars"
            case truncatedItems = "truncated_items"
            case redactedItems = "redacted_items"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSchedulerScopeInFlightRow: Codable {
        var scopeKey: String
        var inFlight: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case inFlight = "in_flight"
        }
    }

    struct RemoteSchedulerScopeQueuedRow: Codable {
        var scopeKey: String
        var queued: Int?

        enum CodingKeys: String, CodingKey {
            case scopeKey = "scope_key"
            case queued
        }
    }

    struct RemoteSchedulerQueueItemRow: Codable {
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

    struct RemoteSchedulerStatusScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var inFlightTotal: Int?
        var queueDepth: Int?
        var oldestQueuedMs: Int?
        var inFlightByScope: [RemoteSchedulerScopeInFlightRow]?
        var queuedByScope: [RemoteSchedulerScopeQueuedRow]?
        var queueItems: [RemoteSchedulerQueueItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case inFlightTotal = "in_flight_total"
            case queueDepth = "queue_depth"
            case oldestQueuedMs = "oldest_queued_ms"
            case inFlightByScope = "in_flight_by_scope"
            case queuedByScope = "queued_by_scope"
            case queueItems = "queue_items"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemotePendingGrantItemRow: Codable {
        var grantRequestId: String
        var requestId: String
        var deviceId: String
        var userId: String
        var appId: String
        var projectId: String
        var capability: String
        var modelId: String
        var reason: String
        var requestedTtlSec: Int?
        var requestedTokenCap: Int?
        var status: String
        var decision: String
        var createdAtMs: Double?
        var decidedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case grantRequestId = "grant_request_id"
            case requestId = "request_id"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case projectId = "project_id"
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

    struct RemotePendingGrantRequestsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemotePendingGrantItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSupervisorCandidateReviewQueueItemRow: Codable {
        var schemaVersion: String
        var reviewId: String
        var requestId: String
        var evidenceRef: String
        var reviewState: String
        var durablePromotionState: String
        var promotionBoundary: String
        var deviceId: String
        var userId: String
        var appId: String
        var threadId: String
        var threadKey: String
        var projectId: String
        var projectIds: [String]
        var scopes: [String]
        var recordTypes: [String]
        var auditRefs: [String]
        var idempotencyKeys: [String]
        var candidateCount: Int?
        var summaryLine: String
        var mirrorTarget: String
        var localStoreRole: String
        var carrierKind: String
        var carrierSchemaVersion: String
        var pendingChangeId: String
        var pendingChangeStatus: String
        var editSessionId: String
        var docId: String
        var writebackRef: String
        var stageCreatedAtMs: Double?
        var stageUpdatedAtMs: Double?
        var latestEmittedAtMs: Double?
        var createdAtMs: Double?
        var updatedAtMs: Double?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case reviewId = "review_id"
            case requestId = "request_id"
            case evidenceRef = "evidence_ref"
            case reviewState = "review_state"
            case durablePromotionState = "durable_promotion_state"
            case promotionBoundary = "promotion_boundary"
            case deviceId = "device_id"
            case userId = "user_id"
            case appId = "app_id"
            case threadId = "thread_id"
            case threadKey = "thread_key"
            case projectId = "project_id"
            case projectIds = "project_ids"
            case scopes
            case recordTypes = "record_types"
            case auditRefs = "audit_refs"
            case idempotencyKeys = "idempotency_keys"
            case candidateCount = "candidate_count"
            case summaryLine = "summary_line"
            case mirrorTarget = "mirror_target"
            case localStoreRole = "local_store_role"
            case carrierKind = "carrier_kind"
            case carrierSchemaVersion = "carrier_schema_version"
            case pendingChangeId = "pending_change_id"
            case pendingChangeStatus = "pending_change_status"
            case editSessionId = "edit_session_id"
            case docId = "doc_id"
            case writebackRef = "writeback_ref"
            case stageCreatedAtMs = "stage_created_at_ms"
            case stageUpdatedAtMs = "stage_updated_at_ms"
            case latestEmittedAtMs = "latest_emitted_at_ms"
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct RemoteSupervisorCandidateReviewQueueScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteSupervisorCandidateReviewQueueItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSupervisorBriefProjectionRow: Codable {
        var schemaVersion: String
        var projectionId: String
        var projectionKind: String
        var projectId: String
        var runId: String
        var missionId: String
        var trigger: String
        var status: String
        var criticalBlocker: String
        var topline: String
        var nextBestAction: String
        var pendingGrantCount: Int?
        var ttsScript: [String]?
        var cardSummary: String
        var evidenceRefs: [String]?
        var generatedAtMs: Double?
        var expiresAtMs: Double?
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case projectionId = "projection_id"
            case projectionKind = "projection_kind"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case trigger
            case status
            case criticalBlocker = "critical_blocker"
            case topline
            case nextBestAction = "next_best_action"
            case pendingGrantCount = "pending_grant_count"
            case ttsScript = "tts_script"
            case cardSummary = "card_summary"
            case evidenceRefs = "evidence_refs"
            case generatedAtMs = "generated_at_ms"
            case expiresAtMs = "expires_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct RemoteSupervisorBriefProjectionScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var projection: RemoteSupervisorBriefProjectionRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case projection
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSupervisorRouteDecisionRow: Codable {
        var schemaVersion: String
        var routeId: String
        var requestId: String
        var projectId: String
        var runId: String
        var missionId: String
        var decision: String
        var riskTier: String
        var preferredDeviceId: String
        var resolvedDeviceId: String
        var runnerId: String
        var xtOnline: Bool?
        var runnerRequired: Bool?
        var sameProjectScope: Bool?
        var requiresGrant: Bool?
        var grantScope: String
        var denyCode: String
        var updatedAtMs: Double?
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case routeId = "route_id"
            case requestId = "request_id"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case decision
            case riskTier = "risk_tier"
            case preferredDeviceId = "preferred_device_id"
            case resolvedDeviceId = "resolved_device_id"
            case runnerId = "runner_id"
            case xtOnline = "xt_online"
            case runnerRequired = "runner_required"
            case sameProjectScope = "same_project_scope"
            case requiresGrant = "requires_grant"
            case grantScope = "grant_scope"
            case denyCode = "deny_code"
            case updatedAtMs = "updated_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct RemoteSupervisorRouteGovernanceComponentRow: Codable {
        var key: String
        var state: String
        var denyCode: String
        var summaryLine: String
        var missingReasonCodes: [String]?

        enum CodingKeys: String, CodingKey {
            case key
            case state
            case denyCode = "deny_code"
            case summaryLine = "summary_line"
            case missingReasonCodes = "missing_reason_codes"
        }
    }

    struct RemoteSupervisorRouteGovernanceRuntimeReadinessRow: Codable {
        var schemaVersion: String
        var source: String
        var governanceSurface: String
        var context: String
        var configured: Bool?
        var state: String
        var runtimeReady: Bool?
        var projectId: String
        var blockers: [String]?
        var blockedComponentKeys: [String]?
        var missingReasonCodes: [String]?
        var summaryLine: String
        var missingSummaryLine: String
        var components: [RemoteSupervisorRouteGovernanceComponentRow]?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case source
            case governanceSurface = "governance_surface"
            case context
            case configured
            case state
            case runtimeReady = "runtime_ready"
            case projectId = "project_id"
            case blockers
            case blockedComponentKeys = "blocked_component_keys"
            case missingReasonCodes = "missing_reason_codes"
            case summaryLine = "summary_line"
            case missingSummaryLine = "missing_summary_line"
            case components
        }
    }

    struct RemoteSupervisorRouteDecisionScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var route: RemoteSupervisorRouteDecisionRow?
        var governanceRuntimeReadiness: RemoteSupervisorRouteGovernanceRuntimeReadinessRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case route
            case governanceRuntimeReadiness = "governance_runtime_readiness"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteConnectorIngressReceiptRow: Codable {
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
        var receivedAtMs: Double?
        var eventSequence: Int64?
        var deliveryState: String
        var runtimeState: String

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

    struct RemoteConnectorIngressReceiptsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteConnectorIngressReceiptRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteRuntimeSurfaceOverrideRow: Codable {
        var projectId: String
        var overrideMode: String
        var updatedAtMs: Double?
        var reason: String
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case projectId = "project_id"
            case overrideMode = "override_mode"
            case updatedAtMs = "updated_at_ms"
            case reason
            case auditRef = "audit_ref"
        }
    }

    struct RemoteRuntimeSurfaceOverridesScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteRuntimeSurfaceOverrideRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSecretVaultItemRow: Codable {
        var itemId: String
        var scope: String
        var name: String
        var sensitivity: String
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

    struct RemoteSecretVaultItemsScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var updatedAtMs: Double?
        var items: [RemoteSecretVaultItemRow]?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case updatedAtMs = "updated_at_ms"
            case items
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSecretVaultCreateScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var item: RemoteSecretVaultItemRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case item
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSecretVaultUseScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var leaseId: String?
        var useToken: String?
        var itemId: String?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case useToken = "use_token"
            case itemId = "item_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSecretVaultRedeemScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var leaseId: String?
        var itemId: String?
        var plaintextBytes: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case leaseId = "lease_id"
            case itemId = "item_id"
            case plaintextBytes = "plaintext_bytes"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemotePendingGrantActionScriptResult: Codable {
        var ok: Bool?
        var decision: String?
        var grantRequestId: String?
        var grantId: String?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case decision
            case grantRequestId = "grant_request_id"
            case grantId = "grant_id"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteSupervisorCandidateReviewStageScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var staged: Bool?
        var idempotent: Bool?
        var reviewState: String?
        var durablePromotionState: String?
        var promotionBoundary: String?
        var candidateRequestId: String?
        var evidenceRef: String?
        var editSessionId: String?
        var pendingChangeId: String?
        var docId: String?
        var baseVersion: String?
        var workingVersion: String?
        var sessionRevision: Double?
        var status: String?
        var markdown: String?
        var createdAtMs: Double?
        var updatedAtMs: Double?
        var expiresAtMs: Double?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case staged
            case idempotent
            case reviewState = "review_state"
            case durablePromotionState = "durable_promotion_state"
            case promotionBoundary = "promotion_boundary"
            case candidateRequestId = "candidate_request_id"
            case evidenceRef = "evidence_ref"
            case editSessionId = "edit_session_id"
            case pendingChangeId = "pending_change_id"
            case docId = "doc_id"
            case baseVersion = "base_version"
            case workingVersion = "working_version"
            case sessionRevision = "session_revision"
            case status
            case markdown
            case createdAtMs = "created_at_ms"
            case updatedAtMs = "updated_at_ms"
            case expiresAtMs = "expires_at_ms"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteLongtermMarkdownReviewScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var pendingChangeId: String?
        var editSessionId: String?
        var docId: String?
        var status: String?
        var reviewDecision: String?
        var policyDecision: String?
        var findingsJSON: String?
        var redactedCount: Int?
        var reviewedAtMs: Double?
        var approvedAtMs: Double?
        var markdown: String?
        var autoRejected: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case pendingChangeId = "pending_change_id"
            case editSessionId = "edit_session_id"
            case docId = "doc_id"
            case status
            case reviewDecision = "review_decision"
            case policyDecision = "policy_decision"
            case findingsJSON = "findings_json"
            case redactedCount = "redacted_count"
            case reviewedAtMs = "reviewed_at_ms"
            case approvedAtMs = "approved_at_ms"
            case markdown
            case autoRejected = "auto_rejected"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteLongtermMarkdownWritebackScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var pendingChangeId: String?
        var status: String?
        var candidateId: String?
        var queueStatus: String?
        var writtenAtMs: Double?
        var docId: String?
        var sourceVersion: String?
        var changeLogId: String?
        var evidenceRef: String?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case pendingChangeId = "pending_change_id"
            case status
            case candidateId = "candidate_id"
            case queueStatus = "queue_status"
            case writtenAtMs = "written_at_ms"
            case docId = "doc_id"
            case sourceVersion = "source_version"
            case changeLogId = "change_log_id"
            case evidenceRef = "evidence_ref"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteVoiceWakeProfileRow: Codable {
        var schemaVersion: String
        var profileID: String
        var triggerWords: [String]
        var updatedAtMs: Double?
        var wakeMode: String
        var requiresPairingReady: Bool?
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case profileID = "profile_id"
            case triggerWords = "trigger_words"
            case updatedAtMs = "updated_at_ms"
            case wakeMode = "wake_mode"
            case requiresPairingReady = "requires_pairing_ready"
            case auditRef = "audit_ref"
        }
    }

    struct RemoteVoiceWakeProfileScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var profile: RemoteVoiceWakeProfileRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case profile
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteVoiceGrantChallengeRow: Codable {
        var challengeId: String
        var templateId: String
        var actionDigest: String
        var scopeDigest: String
        var amountDigest: String
        var challengeCode: String
        var riskLevel: String
        var requiresMobileConfirm: Bool?
        var allowVoiceOnly: Bool?
        var boundDeviceId: String
        var mobileTerminalId: String
        var issuedAtMs: Double?
        var expiresAtMs: Double?

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

    struct RemoteVoiceGrantChallengeScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var challenge: RemoteVoiceGrantChallengeRow?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case challenge
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }

    struct RemoteVoiceGrantVerificationScriptResult: Codable {
        var ok: Bool?
        var source: String?
        var verified: Bool?
        var decision: String?
        var denyCode: String?
        var challengeId: String?
        var transcriptHash: String?
        var semanticMatchScore: Double?
        var challengeMatch: Bool?
        var deviceBindingOk: Bool?
        var mobileConfirmed: Bool?
        var reason: String?
        var errorCode: String?
        var errorMessage: String?

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case verified
            case decision
            case denyCode = "deny_code"
            case challengeId = "challenge_id"
            case transcriptHash = "transcript_hash"
            case semanticMatchScore = "semantic_match_score"
            case challengeMatch = "challenge_match"
            case deviceBindingOk = "device_binding_ok"
            case mobileConfirmed = "mobile_confirmed"
            case reason
            case errorCode = "error_code"
            case errorMessage = "error_message"
        }
    }
}
