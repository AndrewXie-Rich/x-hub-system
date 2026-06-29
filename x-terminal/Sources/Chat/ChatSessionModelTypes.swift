import Foundation

let pendingToolApprovalStub =
    "有待审批的工具操作（本页处理，或从首页打开对应项目）。"

func xtCompactJSONObject<T: Encodable>(_ value: T) -> Any? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value) else { return nil }
    return try? JSONSerialization.jsonObject(with: data)
}

func xtDecodeJSONObject<T: Decodable>(_ type: T.Type, from object: Any?) -> T? {
    guard let object,
          JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object) else {
        return nil
    }
    return try? JSONDecoder().decode(type, from: data)
}

func xtCompactJSONString<T: Encodable>(_ value: T) -> String? {
    let encoder = JSONEncoder()
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8) else {
        return nil
    }
    return text
}

func xtDecodeJSONString<T: Decodable>(_ type: T.Type, from jsonString: String?) -> T? {
    guard let jsonString,
          let data = jsonString.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder().decode(T.self, from: data)
}

enum XTMessageContentBlankness {
    private static let whitespaceAndNewlines = CharacterSet.whitespacesAndNewlines

    static func isBlank(_ content: String) -> Bool {
        content.unicodeScalars.allSatisfy { whitespaceAndNewlines.contains($0) }
    }
}

extension ChatSessionModel {
    struct ToolStreamState {
        var header: String
        var display: String
        var truncated: Bool
    }

    struct ProtectedInputApprovalState {
        var sanitizedText: String
        var attachments: [AXChatAttachment]
    }

    struct TrustedAutomationApprovalRepairResult {
        var config: AXProjectConfig
        var didUpdate: Bool
        var deviceID: String
        var deviceToolGroups: [String]
    }

    struct ToolFlowState {
        var ctx: AXProjectContext
        var memory: AXMemory?
        var config: AXProjectConfig?
        var userText: String
        var userSender: AXChatMessageSender? = nil
        var currentTurnAttachments: [AXChatAttachment] = []
        var runStartedAtMs: Int64
        var step: Int
        var toolResults: [ToolResult]
        var assistantIndex: Int

        // Verification / repair control.
        var dirtySinceVerify: Bool
        var verifyRunIndex: Int
        var repairAttemptsUsed: Int
        var deferredFinal: String?
        var finalizeOnly: Bool

        var formatRetryUsed: Bool
        var executionRetryUsed: Bool
        var lastPromptVisibleGuidanceInjectionId: String? = nil
        var lastSafePointPauseInjectionId: String? = nil
    }

    struct MemoryV1BuildInfo {
        var text: String
        var source: String
        var longtermMode: String?
        var retrievalAvailable: Bool?
        var fulltextNotLoaded: Bool?
        var freshness: String? = nil
        var cacheHit: Bool? = nil
        var remoteSnapshotCacheScope: String? = nil
        var remoteSnapshotCachedAtMs: Int64? = nil
        var remoteSnapshotAgeMs: Int? = nil
        var remoteSnapshotTTLRemainingMs: Int? = nil
        var remoteSnapshotCachePosture: String? = nil
        var remoteSnapshotInvalidationReason: String? = nil
        var memoryGatewaySource: String? = nil
        var memoryGatewayPrimaryEnabled: Bool? = nil
        var memoryGatewayMode: String? = nil
        var memoryGatewaySafetyMode: String? = nil
        var memoryGatewayProductionAuthorityChange: Bool? = nil
        var memoryGatewayModelCall: Bool? = nil
        var memoryGatewayObjectCount: Int? = nil
        var memoryGatewayEffectiveLayers: [String]? = nil
        var usedTokens: Int?
        var budgetTokens: Int?
        var truncatedLayers: [String]
        var redactedItems: Int?
        var privateDrops: Int?
        var projectExplainability: ProjectPromptExplainabilityDiagnostics? = nil
        var visiblePendingGuidanceInjectionId: String? = nil
    }

    struct ProjectMemoryRetrievalPlan {
        var requestedKinds: [String]
        var explicitRefs: [String]
        var stage: String
        var reason: String
    }

    struct ProjectRecentDialogueSelection {
        var profile: AXProjectRecentDialogueProfile
        var source: String
        var selectedPairs: Int
        var floorPairs: Int
        var floorSatisfied: Bool
        var selectedMessages: [(String, String)]
        var lowSignalDroppedMessages: Int
        var messagesText: String

        var dialogueWindowText: String {
            return """
recent_project_dialogue_profile: \(profile.rawValue)
recent_project_dialogue_selected_pairs: \(selectedPairs)
recent_project_dialogue_floor_pairs: \(floorPairs)
recent_project_dialogue_floor_satisfied: \(floorSatisfied)
recent_project_dialogue_source: \(source)
recent_project_dialogue_low_signal_dropped: \(lowSignalDroppedMessages)
messages:
\(messagesText.isEmpty ? "(none)" : messagesText)
"""
        }
    }

    struct ProjectPromptExplainabilityDiagnostics {
        var roleAwareMemoryMode: String
        var projectMemoryResolutionTrigger: String
        var configuredRecentProjectDialogueProfile: String
        var recommendedRecentProjectDialogueProfile: String
        var effectiveRecentProjectDialogueProfile: String
        var recentProjectDialogueProfile: String
        var recentProjectDialogueSelectedPairs: Int
        var recentProjectDialogueFloorPairs: Int
        var recentProjectDialogueFloorSatisfied: Bool
        var recentProjectDialogueSource: String
        var recentProjectDialogueLowSignalDropped: Int
        var configuredProjectContextDepth: String
        var recommendedProjectContextDepth: String
        var effectiveProjectContextDepth: String
        var projectContextDepth: String
        var effectiveProjectServingProfile: String
        var aTierMemoryCeiling: String
        var projectMemoryCeilingHit: Bool
        var workflowPresent: Bool
        var executionEvidencePresent: Bool
        var reviewGuidancePresent: Bool
        var crossLinkHintsSelected: Int
        var personalMemoryExcludedReason: String
        var projectMemoryPolicy: XTProjectMemoryPolicySnapshot
        var policyMemoryAssemblyResolution: XTMemoryAssemblyResolution? = nil
        var memoryAssemblyResolution: XTMemoryAssemblyResolution
        var memoryAssemblyIssueCodes: [String] = []
        var memoryResolutionProjectionDriftDetail: String? = nil
        var heartbeatDigestWorkingSetPresent: Bool = false
        var heartbeatDigestVisibility: String = ""
        var heartbeatDigestReasonCodes: [String] = []
        var automationContextSource: String = ""
        var automationRunID: String? = nil
        var automationEffectiveRunID: String? = nil
        var automationRunState: String? = nil
        var automationAttempt: Int? = nil
        var automationRetryAfterSeconds: Int? = nil
        var automationDeliveryClosureSource: String? = nil
        var automationDeliveryRef: String? = nil
        var automationRecoverySelection: String? = nil
        var automationRecoveryReason: String? = nil
        var automationRecoveryDecision: String? = nil
        var automationRecoveryHoldReason: String? = nil
        var automationRecoveryRetryAfterRemainingSeconds: Int? = nil
        var automationLastRecoveryDecision: String? = nil
        var automationLastRecoveryMode: String? = nil
        var automationCurrentStepPresent: Bool = false
        var automationCurrentStepID: String? = nil
        var automationCurrentStepTitle: String? = nil
        var automationCurrentStepState: String? = nil
        var automationCurrentStepSummary: String? = nil
        var automationVerificationPresent: Bool = false
        var automationVerificationRequired: Bool? = nil
        var automationVerificationExecuted: Bool? = nil
        var automationVerificationCommandCount: Int? = nil
        var automationVerificationPassedCommandCount: Int? = nil
        var automationVerificationHoldReason: String? = nil
        var automationVerificationContract: XTAutomationVerificationContract? = nil
        var automationBlockerPresent: Bool = false
        var automationBlockerCode: String? = nil
        var automationBlockerSummary: String? = nil
        var automationBlockerStage: String? = nil
        var automationRetryReasonPresent: Bool = false
        var automationRetryReasonCode: String? = nil
        var automationRetryReasonSummary: String? = nil
        var automationRetryReasonStrategy: String? = nil
        var automationRetryVerificationContract: XTAutomationVerificationContract? = nil

        var usageFields: [String: Any] {
            var fields: [String: Any] = [
                "role_aware_memory_mode": roleAwareMemoryMode,
                "project_memory_resolution_trigger": projectMemoryResolutionTrigger,
                "project_memory_resolution_trigger_label": XTProjectMemoryTriggerPresentation.annotated(
                    projectMemoryResolutionTrigger
                ),
                "configured_recent_project_dialogue_profile": configuredRecentProjectDialogueProfile,
                "recommended_recent_project_dialogue_profile": recommendedRecentProjectDialogueProfile,
                "effective_recent_project_dialogue_profile": effectiveRecentProjectDialogueProfile,
                "recent_project_dialogue_profile": recentProjectDialogueProfile,
                "recent_project_dialogue_selected_pairs": recentProjectDialogueSelectedPairs,
                "recent_project_dialogue_floor_pairs": recentProjectDialogueFloorPairs,
                "recent_project_dialogue_floor_satisfied": recentProjectDialogueFloorSatisfied,
                "recent_project_dialogue_source": recentProjectDialogueSource,
                "recent_project_dialogue_low_signal_dropped": recentProjectDialogueLowSignalDropped,
                "configured_project_context_depth": configuredProjectContextDepth,
                "recommended_project_context_depth": recommendedProjectContextDepth,
                "effective_project_context_depth": effectiveProjectContextDepth,
                "project_context_depth": projectContextDepth,
                "effective_project_serving_profile": effectiveProjectServingProfile,
                "a_tier_memory_ceiling": aTierMemoryCeiling,
                "project_memory_ceiling_hit": projectMemoryCeilingHit,
                "workflow_present": workflowPresent,
                "execution_evidence_present": executionEvidencePresent,
                "review_guidance_present": reviewGuidancePresent,
                "cross_link_hints_selected": crossLinkHintsSelected,
                "personal_memory_excluded_reason": personalMemoryExcludedReason,
            ]
            if let policyObject = xtCompactJSONObject(projectMemoryPolicy) {
                fields["project_memory_policy"] = policyObject
            }
            if let policyResolutionObject = policyMemoryAssemblyResolution.flatMap(xtCompactJSONObject) {
                fields["project_memory_policy_resolution"] = policyResolutionObject
            }
            if let resolutionObject = xtCompactJSONObject(memoryAssemblyResolution) {
                fields["memory_assembly_resolution"] = resolutionObject
            }
            if !memoryAssemblyIssueCodes.isEmpty {
                fields["project_memory_issue_codes"] = memoryAssemblyIssueCodes
            }
            if let memoryResolutionProjectionDriftDetail,
               !memoryResolutionProjectionDriftDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["project_memory_issue_memory_resolution_projection_drift"] = memoryResolutionProjectionDriftDetail
            }
            fields["project_memory_heartbeat_digest_present"] = heartbeatDigestWorkingSetPresent
            if !heartbeatDigestVisibility.isEmpty {
                fields["project_memory_heartbeat_digest_visibility"] = heartbeatDigestVisibility
            }
            if !heartbeatDigestReasonCodes.isEmpty {
                fields["project_memory_heartbeat_digest_reason_codes"] = heartbeatDigestReasonCodes
            }
            fields["project_memory_automation_current_step_present"] = automationCurrentStepPresent
            fields["project_memory_automation_verification_present"] = automationVerificationPresent
            fields["project_memory_automation_blocker_present"] = automationBlockerPresent
            fields["project_memory_automation_retry_reason_present"] = automationRetryReasonPresent
            if !automationContextSource.isEmpty {
                fields["project_memory_automation_context_source"] = automationContextSource
            }
            if let automationRunID {
                fields["project_memory_automation_run_id"] = automationRunID
            }
            if let automationEffectiveRunID {
                fields["project_memory_automation_effective_run_id"] = automationEffectiveRunID
            }
            if let automationRunState {
                fields["project_memory_automation_run_state"] = automationRunState
            }
            if let automationAttempt {
                fields["project_memory_automation_attempt"] = automationAttempt
            }
            if let automationRetryAfterSeconds {
                fields["project_memory_automation_retry_after_seconds"] = automationRetryAfterSeconds
            }
            if let automationDeliveryClosureSource {
                fields["project_memory_automation_delivery_closure_source"] = automationDeliveryClosureSource
            }
            if let automationDeliveryRef,
               !automationDeliveryRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["project_memory_automation_delivery_ref"] = automationDeliveryRef
            }
            if let automationRecoverySelection {
                fields["project_memory_automation_recovery_selection"] = automationRecoverySelection
            }
            if let automationRecoveryReason {
                fields["project_memory_automation_recovery_reason"] = automationRecoveryReason
            }
            if let automationRecoveryDecision {
                fields["project_memory_automation_recovery_decision"] = automationRecoveryDecision
            }
            if let automationRecoveryHoldReason,
               !automationRecoveryHoldReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["project_memory_automation_recovery_hold_reason"] = automationRecoveryHoldReason
            }
            if let automationRecoveryRetryAfterRemainingSeconds {
                fields["project_memory_automation_recovery_retry_after_remaining_seconds"] = automationRecoveryRetryAfterRemainingSeconds
            }
            if let automationLastRecoveryDecision {
                fields["project_memory_automation_last_recovery_decision"] = automationLastRecoveryDecision
            }
            if let automationLastRecoveryMode {
                fields["project_memory_automation_last_recovery_mode"] = automationLastRecoveryMode
            }
            if let automationCurrentStepID {
                fields["project_memory_automation_current_step_id"] = automationCurrentStepID
            }
            if let automationCurrentStepTitle {
                fields["project_memory_automation_current_step_title"] = automationCurrentStepTitle
            }
            if let automationCurrentStepState {
                fields["project_memory_automation_current_step_state"] = automationCurrentStepState
            }
            if let automationCurrentStepSummary {
                fields["project_memory_automation_current_step_summary"] = automationCurrentStepSummary
            }
            if let automationVerificationRequired {
                fields["project_memory_automation_verification_required"] = automationVerificationRequired
            }
            if let automationVerificationExecuted {
                fields["project_memory_automation_verification_executed"] = automationVerificationExecuted
            }
            if let automationVerificationCommandCount {
                fields["project_memory_automation_verification_command_count"] = automationVerificationCommandCount
            }
            if let automationVerificationPassedCommandCount {
                fields["project_memory_automation_verification_passed_command_count"] = automationVerificationPassedCommandCount
            }
            if let automationVerificationHoldReason,
               !automationVerificationHoldReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fields["project_memory_automation_verification_hold_reason"] = automationVerificationHoldReason
            }
            if let automationVerificationContractObject = automationVerificationContract.flatMap(xtCompactJSONObject) {
                fields["project_memory_automation_verification_contract"] = automationVerificationContractObject
            }
            if let automationBlockerCode {
                fields["project_memory_automation_blocker_code"] = automationBlockerCode
            }
            if let automationBlockerSummary {
                fields["project_memory_automation_blocker_summary"] = automationBlockerSummary
            }
            if let automationBlockerStage {
                fields["project_memory_automation_blocker_stage"] = automationBlockerStage
            }
            if let automationRetryReasonCode {
                fields["project_memory_automation_retry_reason_code"] = automationRetryReasonCode
            }
            if let automationRetryReasonSummary {
                fields["project_memory_automation_retry_reason_summary"] = automationRetryReasonSummary
            }
            if let automationRetryReasonStrategy {
                fields["project_memory_automation_retry_reason_strategy"] = automationRetryReasonStrategy
            }
            if let automationRetryVerificationContractObject = automationRetryVerificationContract.flatMap(xtCompactJSONObject) {
                fields["project_memory_automation_retry_verification_contract"] = automationRetryVerificationContractObject
            }
            return fields
        }
    }

    struct ProjectHeartbeatDigestWorkingSetExplainability {
        var present: Bool
        var visibility: String
        var reasonCodes: [String]
    }

    struct ProjectAutomationMemoryContext {
        var source: String
        var runID: String?
        var effectiveRunID: String?
        var runState: XTAutomationRunState?
        var attempt: Int?
        var retryAfterSeconds: Int?
        var deliveryClosureSource: XTAutomationDeliveryClosureProjectionSource?
        var deliveryRef: String?
        var recoveryState: XTAutomationProjectRecoveryState?
        var lastRecoveryDecision: XTAutomationRestartRecoveryAction?
        var lastRecoveryMode: XTAutomationRestartRecoveryMode?
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: XTAutomationRunStepState?
        var currentStepSummary: String?
        var verificationReport: XTAutomationVerificationReport?
        var verificationContract: XTAutomationVerificationContract?
        var blocker: XTAutomationBlockerDescriptor?
        var retryReasonDescriptor: XTAutomationRetryReasonDescriptor?
        var retryVerificationContract: XTAutomationVerificationContract?

        var hasCurrentStep: Bool {
            currentStepState != nil || xtAutomationFirstNonEmpty([
                currentStepID,
                currentStepTitle,
                currentStepSummary,
            ]) != nil
        }

        var hasVerificationState: Bool {
            verificationReport != nil
        }

        var verificationNeedsAttention: Bool {
            guard let verificationReport else { return false }
            return !verificationReport.ok
        }

        var hasBlocker: Bool {
            blocker != nil
        }

        var hasRetryReason: Bool {
            retryReasonDescriptor != nil
        }
    }

    static let projectTrackedServingObjectsForExplainability: [String] = [
        "recent_project_dialogue_window",
        "focused_project_anchor_pack",
        "current_step",
        "verification_state",
        "blocker_state",
        "retry_reason",
        "active_workflow",
        "selected_cross_link_hints",
        "longterm_outline",
        "execution_evidence",
        "guidance",
    ]

    static let projectExplainabilityObservablePlaneOrder: [String] = [
        "project_dialogue_plane",
        "project_anchor_plane",
        "execution_state_plane",
        "workflow_plane",
        "cross_link_plane",
        "longterm_plane",
        "evidence_plane",
        "guidance_plane",
    ]

    struct ProjectPromptContextAssembly {
        var memoryPolicy: XTProjectMemoryPolicy
        var recentDialogueSelection: ProjectRecentDialogueSelection
        var contextDepthProfile: AXProjectContextDepthProfile
        var effectiveServingProfile: XTMemoryServingProfile?
        var observationsText: String
        var rawEvidenceText: String
        var focusedProjectAnchorPackText: String
        var longtermOutlineText: String
        var contextRefsText: String
        var evidencePackText: String
        var heartbeatWorkingSetText: String
        var diagnostics: ProjectPromptExplainabilityDiagnostics
    }

    struct ProjectCrossLinkPromptHints {
        var selectedCount: Int
        var lines: [String]
        var refs: [String]
    }

    struct ProjectRouteIncidentTrendDiagnosis {
        var summary: String
        var actionHint: String?
    }

    struct PromptBuildOutput {
        var prompt: String
        var memory: MemoryV1BuildInfo
        var visiblePendingGuidanceInjectionId: String? = nil
    }

    struct ProjectSupervisorGuidancePromptSnapshot {
        var block: String
        var visiblePendingGuidanceInjectionId: String?
    }

    struct ProjectUIReviewRepairContract {
        var summary: String
        var instruction: String
        var repairAction: String
        var repairFocus: String
        var nextSafeAction: String
        var uiReviewRef: String
        var uiReviewReviewId: String
        var uiReviewVerdict: String
        var uiReviewIssueCodes: String
        var uiReviewSummary: String
        var skillResultSummary: String
    }

    struct ProjectSupervisorReplanContract {
        var contractKind: String
        var trigger: String
        var reviewLevel: String
        var verdict: String
        var summary: String
        var primaryBlocker: String
        var currentState: String
        var nextStep: String
        var nextSafeAction: String
        var recommendedActions: [String]
        var workOrderRef: String
        var effectiveSupervisorTier: String
        var effectiveWorkOrderDepth: String
    }

    struct ProjectSupervisorGuidanceEnvelopeGateProbe: Equatable, Sendable {
        var requiresFinalOnly: Bool
        var guidanceInjectionId: String?
        var toolCallCount: Int
        var skillCallCount: Int
        var final: String?
    }

    enum ProjectSupervisorGuidanceEnvelopeGateResult {
        case allow(ToolActionEnvelope)
        case requireFinalOnly(SupervisorGuidanceInjectionRecord)
    }

    enum ToolActionEnvelopeParseResult {
        case envelope(ToolActionEnvelope)
        case invalidJSONEnvelope
        case none
    }

    struct ProjectSkillToolCallMappingError: Error, Equatable, Sendable {
        var message: String
    }

    struct ProjectSkillDispatchResolution: Equatable, Sendable {
        var dispatches: [XTProjectMappedSkillDispatch]

        var toolCalls: [ToolCall] {
            dispatches.map(\.toolCall)
        }

        var dispatchesByToolCallID: [String: XTProjectMappedSkillDispatch] {
            var out: [String: XTProjectMappedSkillDispatch] = [:]
            for dispatch in dispatches {
                out[dispatch.toolCall.id] = dispatch
            }
            return out
        }
    }

    enum VisibleLLMStreamMode {
        case none
        case finalOrPlainText
    }
}
