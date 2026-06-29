import Foundation

extension HubIPCClient {
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

    struct VoiceTTSReadinessRequestPayload: Codable, Equatable, Sendable {
        var preferredModelId: String

        enum CodingKeys: String, CodingKey {
            case preferredModelId = "preferred_model_id"
        }
    }

    struct VoiceTTSReadinessIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceTTSReadiness: VoiceTTSReadinessRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceTTSReadiness = "voice_tts_readiness"
        }
    }

    struct VoiceTTSReadinessResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var provider: String?
        var modelId: String?
        var reasonCode: String?
        var detail: String?

        init(
            ok: Bool,
            source: String,
            provider: String? = nil,
            modelId: String? = nil,
            reasonCode: String? = nil,
            detail: String? = nil
        ) {
            self.ok = ok
            self.source = source
            self.provider = provider
            self.modelId = modelId
            self.reasonCode = reasonCode
            self.detail = detail
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case provider
            case modelId = "model_id"
            case reasonCode = "reason_code"
            case detail
        }
    }

    struct VoiceTTSReadinessIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceTTSReadiness: VoiceTTSReadinessResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceTTSReadiness = "voice_tts_readiness"
        }
    }

    struct VoiceTTSRequestPayload: Codable, Equatable, Sendable {
        var preferredModelId: String
        var text: String
        var localeIdentifier: String?
        var voiceColor: String?
        var speechRate: Double?

        enum CodingKeys: String, CodingKey {
            case preferredModelId = "preferred_model_id"
            case text
            case localeIdentifier = "locale_identifier"
            case voiceColor = "voice_color"
            case speechRate = "speech_rate"
        }
    }

    struct VoiceTTSIPCRequest: Codable {
        var type: String
        var reqId: String
        var voiceTTS: VoiceTTSRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case voiceTTS = "voice_tts"
        }
    }

    struct VoiceTTSAudit: Codable, Equatable, Sendable {
        var schemaVersion: String
        var ok: Bool
        var taskKind: String
        var requestId: String
        var capability: String
        var provider: String
        var requestedModelId: String
        var modelId: String
        var resolvedModelId: String
        var routeSource: String
        var sourceKind: String
        var outputRefKind: String
        var engineName: String
        var speakerId: String
        var nativeTTSUsed: Bool?
        var fallbackUsed: Bool
        var fallbackMode: String
        var fallbackReasonCode: String
        var denyCode: String
        var rawDenyCode: String
        var locale: String
        var voiceColor: String
        var speechRate: Double

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case ok
            case taskKind = "task_kind"
            case requestId = "request_id"
            case capability
            case provider
            case requestedModelId = "requested_model_id"
            case modelId = "model_id"
            case resolvedModelId = "resolved_model_id"
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

    struct VoiceTTSResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var provider: String?
        var modelId: String?
        var taskKind: String?
        var audioFilePath: String?
        var audioFormat: String?
        var voiceName: String?
        var engineName: String?
        var speakerId: String?
        var deviceBackend: String?
        var nativeTTSUsed: Bool?
        var fallbackMode: String?
        var fallbackReasonCode: String?
        var reasonCode: String?
        var runtimeReasonCode: String?
        var error: String?
        var detail: String?
        var ttsAudit: VoiceTTSAudit?
        var ttsAuditLine: String?

        init(
            ok: Bool,
            source: String,
            provider: String? = nil,
            modelId: String? = nil,
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
            ttsAudit: VoiceTTSAudit? = nil,
            ttsAuditLine: String? = nil
        ) {
            self.ok = ok
            self.source = source
            self.provider = provider
            self.modelId = modelId
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

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case provider
            case modelId = "model_id"
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

    struct VoiceTTSIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var voiceTTS: VoiceTTSResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case voiceTTS = "voice_tts"
        }
    }

    struct LocalTaskRequestPayload: Codable, Equatable, Sendable {
        var schemaVersion: String
        var taskKind: String
        var modelId: String
        var deviceId: String?
        var timeoutSec: Double?
        var parameters: [String: JSONValue]

        init(
            schemaVersion: String = "xhub.local_task_ipc.v1",
            taskKind: String,
            modelId: String,
            deviceId: String? = nil,
            timeoutSec: Double? = nil,
            parameters: [String: JSONValue] = [:]
        ) {
            self.schemaVersion = schemaVersion
            self.taskKind = taskKind
            self.modelId = modelId
            self.deviceId = deviceId
            self.timeoutSec = timeoutSec
            self.parameters = parameters
        }

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case taskKind = "task_kind"
            case modelId = "model_id"
            case deviceId = "device_id"
            case timeoutSec = "timeout_sec"
            case parameters
        }
    }

    struct LocalTaskIPCRequest: Codable {
        var type: String
        var reqId: String
        var localTask: LocalTaskRequestPayload

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case localTask = "local_task"
        }
    }

    struct LocalTaskResult: Codable, Equatable, Sendable {
        var ok: Bool
        var source: String
        var runtimeSource: String?
        var provider: String?
        var modelId: String?
        var taskKind: String?
        var reasonCode: String?
        var runtimeReasonCode: String?
        var error: String?
        var detail: String?
        var payload: [String: JSONValue]

        init(
            ok: Bool,
            source: String,
            runtimeSource: String? = nil,
            provider: String? = nil,
            modelId: String? = nil,
            taskKind: String? = nil,
            reasonCode: String? = nil,
            runtimeReasonCode: String? = nil,
            error: String? = nil,
            detail: String? = nil,
            payload: [String: JSONValue] = [:]
        ) {
            self.ok = ok
            self.source = source
            self.runtimeSource = runtimeSource
            self.provider = provider
            self.modelId = modelId
            self.taskKind = taskKind
            self.reasonCode = reasonCode
            self.runtimeReasonCode = runtimeReasonCode
            self.error = error
            self.detail = detail
            self.payload = payload
        }

        enum CodingKeys: String, CodingKey {
            case ok
            case source
            case runtimeSource = "runtime_source"
            case provider
            case modelId = "model_id"
            case taskKind = "task_kind"
            case reasonCode = "reason_code"
            case runtimeReasonCode = "runtime_reason_code"
            case error
            case detail
            case payload
        }
    }

    struct LocalTaskIPCResponse: Codable {
        var type: String
        var reqId: String?
        var ok: Bool
        var id: String?
        var error: String?
        var localTask: LocalTaskResult?

        enum CodingKeys: String, CodingKey {
            case type
            case reqId = "req_id"
            case ok
            case id
            case error
            case localTask = "local_task"
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

    struct SupervisorCandidateReviewItem: Codable, Equatable, Identifiable {
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
        var candidateCount: Int
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
        var stageCreatedAtMs: Double
        var stageUpdatedAtMs: Double
        var latestEmittedAtMs: Double
        var createdAtMs: Double
        var updatedAtMs: Double

        var id: String { reviewId.isEmpty ? requestId : reviewId }

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

    struct SupervisorCandidateReviewSnapshot: Codable, Equatable {
        var source: String
        var updatedAtMs: Double
        var items: [SupervisorCandidateReviewItem]
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

    struct SupervisorBriefProjectionRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String
        var runId: String?
        var missionId: String?
        var projectionKind: String
        var trigger: String
        var includeTtsScript: Bool
        var includeCardSummary: Bool
        var maxEvidenceRefs: Int

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case projectionKind = "projection_kind"
            case trigger
            case includeTtsScript = "include_tts_script"
            case includeCardSummary = "include_card_summary"
            case maxEvidenceRefs = "max_evidence_refs"
        }
    }

    struct SupervisorBriefProjectionSnapshot: Codable, Equatable, Identifiable {
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
        var pendingGrantCount: Int
        var ttsScript: [String]
        var cardSummary: String
        var evidenceRefs: [String]
        var generatedAtMs: Double
        var expiresAtMs: Double
        var auditRef: String

        var id: String { projectionId }

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

    struct SupervisorBriefProjectionResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var projection: SupervisorBriefProjectionSnapshot?
        var reasonCode: String?
    }

    struct SupervisorRouteDecisionRequestPayload: Codable, Equatable {
        var requestId: String
        var projectId: String
        var runId: String?
        var missionId: String?
        var surfaceType: String
        var trustLevel: String
        var normalizedIntentType: String
        var preferredDeviceId: String?
        var requireXT: Bool
        var requireRunner: Bool
        var actorRef: String?
        var conversationId: String?
        var threadKey: String?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case projectId = "project_id"
            case runId = "run_id"
            case missionId = "mission_id"
            case surfaceType = "surface_type"
            case trustLevel = "trust_level"
            case normalizedIntentType = "normalized_intent_type"
            case preferredDeviceId = "preferred_device_id"
            case requireXT = "require_xt"
            case requireRunner = "require_runner"
            case actorRef = "actor_ref"
            case conversationId = "conversation_id"
            case threadKey = "thread_key"
        }
    }

    struct SupervisorRouteGovernanceComponentSnapshot: Codable, Equatable {
        var key: AXProjectGovernanceRuntimeReadinessComponentKey
        var state: AXProjectGovernanceRuntimeReadinessComponentState
        var denyCode: String
        var summaryLine: String
        var missingReasonCodes: [String]
    }

    struct SupervisorRouteGovernanceRuntimeReadinessSnapshot: Codable, Equatable {
        var schemaVersion: String
        var source: String
        var governanceSurface: String
        var context: String
        var configured: Bool
        var state: AXProjectGovernanceRuntimeReadinessState
        var runtimeReady: Bool
        var projectId: String
        var blockers: [String]
        var blockedComponentKeys: [AXProjectGovernanceRuntimeReadinessComponentKey]
        var missingReasonCodes: [String]
        var summaryLine: String
        var missingSummaryLine: String
        var components: [SupervisorRouteGovernanceComponentSnapshot]
    }

    struct SupervisorRouteDecisionSnapshot: Codable, Equatable {
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
        var xtOnline: Bool
        var runnerRequired: Bool
        var sameProjectScope: Bool
        var requiresGrant: Bool
        var grantScope: String
        var denyCode: String
        var updatedAtMs: Double
        var auditRef: String
    }

    struct SupervisorRouteDecisionResult: Codable, Equatable {
        var ok: Bool
        var source: String
        var route: SupervisorRouteDecisionSnapshot?
        var governanceRuntimeReadiness: SupervisorRouteGovernanceRuntimeReadinessSnapshot?
        var reasonCode: String?
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

    struct SupervisorCandidateReviewStageResult {
        var ok: Bool
        var staged: Bool
        var idempotent: Bool
        var source: String
        var reviewState: String
        var durablePromotionState: String
        var promotionBoundary: String
        var candidateRequestId: String?
        var evidenceRef: String?
        var editSessionId: String?
        var pendingChangeId: String?
        var docId: String?
        var baseVersion: String?
        var workingVersion: String?
        var sessionRevision: Int64
        var status: String?
        var markdown: String?
        var createdAtMs: Double
        var updatedAtMs: Double
        var expiresAtMs: Double
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

    struct LocalIPCTransport {
        var mode: String
        var ipcURL: URL
        var baseDir: URL
    }

    struct IPCEventWriteStatus {
        var requestQueued: Bool?
        var requestError: String
    }

    struct CanonicalMemorySyncDispatchResult {
        var ok: Bool
        var source: String
        var deliveryState: String? = nil
        var auditRefs: [String] = []
        var evidenceRefs: [String] = []
        var writebackRefs: [String] = []
        var reasonCode: String? = nil
        var detail: String? = nil
    }

    struct LocalMemoryContextIPCResult {
        var response: MemoryContextResponsePayload?
        var reasonCode: String?
        var detail: String?
    }

    struct RustProjectCanonicalMemoryListResponse: Decodable {
        var ok: Bool
        var objects: [RustProjectCanonicalMemoryObject]
    }

    struct ProjectCanonicalRustExpectedObject: Equatable {
        var key: String
        var suffix: String
        var memoryId: String
        var sourceKind: String
        var layer: String
        var title: String
        var text: String
    }

    struct NetworkIPCDispatchResult {
        var ticket: NetworkRequestTicket
        var ack: NetworkIPCResponse?
        var source: String
        var reasonCode: String? = nil
        var detail: String? = nil
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
        var detail: String? = nil
    }
}
