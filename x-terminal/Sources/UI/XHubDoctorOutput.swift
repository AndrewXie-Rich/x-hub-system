import Foundation

enum XHubDoctorBundleKind: String, Codable, CaseIterable, Sendable {
    case pairedSurfaceReadiness = "paired_surface_readiness"
    case providerRuntimeReadiness = "provider_runtime_readiness"
    case channelOnboardingReadiness = "channel_onboarding_readiness"
    case packageLifecycleReadiness = "package_lifecycle_readiness"
    case automationReadiness = "automation_readiness"
}

enum XHubDoctorSurface: String, Codable, CaseIterable, Sendable {
    case xtUI = "xt_ui"
    case xtExport = "xt_export"
    case hubUI = "hub_ui"
    case hubCLI = "hub_cli"
    case api = "api"
}

enum XHubDoctorProducer: String, Codable, CaseIterable, Sendable {
    case xTerminal = "x_terminal"
    case xHub = "x_hub"
    case xhubCLI = "xhub_cli"
}

enum XHubDoctorOverallState: String, Codable, CaseIterable, Sendable {
    case ready = "ready"
    case degraded = "degraded"
    case blocked = "blocked"
    case inProgress = "in_progress"
    case notSupported = "not_supported"
}

enum XHubDoctorCheckStatus: String, Codable, CaseIterable, Sendable {
    case pass = "pass"
    case fail = "fail"
    case warn = "warn"
    case skip = "skip"
}

enum XHubDoctorSeverity: String, Codable, CaseIterable, Sendable {
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
}

enum XHubDoctorNextStepKind: String, Codable, CaseIterable, Sendable {
    case openRepairSurface = "open_repair_surface"
    case reviewPairing = "review_pairing"
    case chooseModel = "choose_model"
    case reviewPermissions = "review_permissions"
    case repairRuntime = "repair_runtime"
    case inspectDiagnostics = "inspect_diagnostics"
    case repairSkills = "repair_skills"
    case startFirstTask = "start_first_task"
    case waitForRecovery = "wait_for_recovery"
}

enum XHubDoctorStepOwner: String, Codable, CaseIterable, Sendable {
    case user = "user"
    case humanOperator = "operator"
    case xtRuntime = "xt_runtime"
    case hubRuntime = "hub_runtime"
}

struct XHubDoctorOutputSummary: Codable, Equatable, Sendable {
    var headline: String
    var passed: Int
    var failed: Int
    var warned: Int
    var skipped: Int

    enum CodingKeys: String, CodingKey {
        case headline
        case passed
        case failed
        case warned
        case skipped
    }
}

struct XHubDoctorOutputCheckResult: Identifiable, Codable, Equatable, Sendable {
    var checkID: String
    var checkKind: String
    var status: XHubDoctorCheckStatus
    var severity: XHubDoctorSeverity
    var blocking: Bool
    var headline: String
    var message: String
    var nextStep: String
    var repairDestinationRef: String?
    var detailLines: [String]
    var projectContextSummary: XHubDoctorOutputProjectContextSummary?
    var projectGovernanceRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot?
    var projectMemoryPolicy: XTProjectMemoryPolicySnapshot?
    var projectMemoryReadiness: XTProjectMemoryAssemblyReadiness?
    var projectMemoryAssemblyResolution: XTMemoryAssemblyResolution?
    var supervisorMemoryPolicy: XTSupervisorMemoryPolicySnapshot?
    var supervisorMemoryAssemblyResolution: XTMemoryAssemblyResolution?
    var supervisorReviewTriggerSnapshot: XTUnifiedDoctorSupervisorReviewTriggerProjection?
    var supervisorGuidanceContinuitySnapshot: XTUnifiedDoctorSupervisorGuidanceContinuityProjection?
    var supervisorSafePointTimelineSnapshot: XTUnifiedDoctorSupervisorSafePointTimelineProjection?
    var projectRemoteSnapshotCacheSnapshot: XHubDoctorOutputRemoteSnapshotCacheSnapshot?
    var supervisorRemoteSnapshotCacheSnapshot: XHubDoctorOutputRemoteSnapshotCacheSnapshot?
    var projectAutomationContinuitySnapshot: XHubDoctorOutputProjectAutomationContinuitySnapshot?
    var heartbeatGovernanceSnapshot: XHubDoctorOutputHeartbeatGovernanceSnapshot?
    var hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot?
    var memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot?
    var durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot?
    var localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot?
    var skillDoctorTruthSnapshot: XTUnifiedDoctorSkillDoctorTruthProjection?
    var freshPairReconnectSmokeSnapshot: XHubDoctorOutputFreshPairReconnectSmokeSnapshot?
    var observedAtMs: Int64

    var id: String { checkID }

    init(
        checkID: String,
        checkKind: String,
        status: XHubDoctorCheckStatus,
        severity: XHubDoctorSeverity,
        blocking: Bool,
        headline: String,
        message: String,
        nextStep: String,
        repairDestinationRef: String?,
        detailLines: [String],
        projectContextSummary: XHubDoctorOutputProjectContextSummary? = nil,
        projectGovernanceRuntimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = nil,
        projectMemoryPolicy: XTProjectMemoryPolicySnapshot? = nil,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil,
        projectMemoryAssemblyResolution: XTMemoryAssemblyResolution? = nil,
        supervisorMemoryPolicy: XTSupervisorMemoryPolicySnapshot? = nil,
        supervisorMemoryAssemblyResolution: XTMemoryAssemblyResolution? = nil,
        supervisorReviewTriggerSnapshot: XTUnifiedDoctorSupervisorReviewTriggerProjection? = nil,
        supervisorGuidanceContinuitySnapshot: XTUnifiedDoctorSupervisorGuidanceContinuityProjection? = nil,
        supervisorSafePointTimelineSnapshot: XTUnifiedDoctorSupervisorSafePointTimelineProjection? = nil,
        projectRemoteSnapshotCacheSnapshot: XHubDoctorOutputRemoteSnapshotCacheSnapshot? = nil,
        supervisorRemoteSnapshotCacheSnapshot: XHubDoctorOutputRemoteSnapshotCacheSnapshot? = nil,
        projectAutomationContinuitySnapshot: XHubDoctorOutputProjectAutomationContinuitySnapshot? = nil,
        heartbeatGovernanceSnapshot: XHubDoctorOutputHeartbeatGovernanceSnapshot? = nil,
        hubMemoryPromptProjection: HubMemoryPromptProjectionSnapshot? = nil,
        observedAtMs: Int64,
        memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot? = nil,
        durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot? = nil,
        localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot? = nil,
        skillDoctorTruthSnapshot: XTUnifiedDoctorSkillDoctorTruthProjection? = nil,
        freshPairReconnectSmokeSnapshot: XHubDoctorOutputFreshPairReconnectSmokeSnapshot? = nil
    ) {
        self.checkID = checkID
        self.checkKind = checkKind
        self.status = status
        self.severity = severity
        self.blocking = blocking
        self.headline = headline
        self.message = message
        self.nextStep = nextStep
        self.repairDestinationRef = repairDestinationRef
        self.detailLines = detailLines
        self.projectContextSummary = projectContextSummary
        self.projectGovernanceRuntimeReadiness = projectGovernanceRuntimeReadiness
        self.projectMemoryPolicy = projectMemoryPolicy
        self.projectMemoryReadiness = projectMemoryReadiness
        self.projectMemoryAssemblyResolution = projectMemoryAssemblyResolution
        self.supervisorMemoryPolicy = supervisorMemoryPolicy
        self.supervisorMemoryAssemblyResolution = supervisorMemoryAssemblyResolution
        self.supervisorReviewTriggerSnapshot = supervisorReviewTriggerSnapshot
        self.supervisorGuidanceContinuitySnapshot = supervisorGuidanceContinuitySnapshot
        self.supervisorSafePointTimelineSnapshot = supervisorSafePointTimelineSnapshot
        self.projectRemoteSnapshotCacheSnapshot = projectRemoteSnapshotCacheSnapshot
        self.supervisorRemoteSnapshotCacheSnapshot = supervisorRemoteSnapshotCacheSnapshot
        self.projectAutomationContinuitySnapshot = projectAutomationContinuitySnapshot
        self.heartbeatGovernanceSnapshot = heartbeatGovernanceSnapshot
        self.hubMemoryPromptProjection = hubMemoryPromptProjection
        self.memoryRouteTruthSnapshot = memoryRouteTruthSnapshot
        self.durableCandidateMirrorSnapshot = durableCandidateMirrorSnapshot
        self.localStoreWriteSnapshot = localStoreWriteSnapshot
        self.skillDoctorTruthSnapshot = skillDoctorTruthSnapshot
        self.freshPairReconnectSmokeSnapshot = freshPairReconnectSmokeSnapshot
        self.observedAtMs = observedAtMs
    }

    enum CodingKeys: String, CodingKey {
        case checkID = "check_id"
        case checkKind = "check_kind"
        case status
        case severity
        case blocking
        case headline
        case message
        case nextStep = "next_step"
        case repairDestinationRef = "repair_destination_ref"
        case detailLines = "detail_lines"
        case projectContextSummary = "project_context_summary"
        case projectGovernanceRuntimeReadiness = "project_governance_runtime_readiness"
        case projectMemoryPolicy = "project_memory_policy"
        case projectMemoryReadiness = "project_memory_readiness"
        case projectMemoryAssemblyResolution = "project_memory_assembly_resolution"
        case supervisorMemoryPolicy = "supervisor_memory_policy"
        case supervisorMemoryAssemblyResolution = "supervisor_memory_assembly_resolution"
        case supervisorReviewTriggerSnapshot = "supervisor_review_trigger_snapshot"
        case supervisorGuidanceContinuitySnapshot = "supervisor_guidance_continuity_snapshot"
        case supervisorSafePointTimelineSnapshot = "supervisor_safe_point_timeline_snapshot"
        case projectRemoteSnapshotCacheSnapshot = "project_remote_snapshot_cache_snapshot"
        case supervisorRemoteSnapshotCacheSnapshot = "supervisor_remote_snapshot_cache_snapshot"
        case projectAutomationContinuitySnapshot = "project_automation_continuity_snapshot"
        case heartbeatGovernanceSnapshot = "heartbeat_governance_snapshot"
        case hubMemoryPromptProjection = "hub_memory_prompt_projection"
        case memoryRouteTruthSnapshot = "memory_route_truth_snapshot"
        case durableCandidateMirrorSnapshot = "durable_candidate_mirror_snapshot"
        case localStoreWriteSnapshot = "local_store_write_snapshot"
        case skillDoctorTruthSnapshot = "skill_doctor_truth_snapshot"
        case freshPairReconnectSmokeSnapshot = "fresh_pair_reconnect_smoke_snapshot"
        case observedAtMs = "observed_at_ms"
    }
}

struct XHubDoctorOutputFreshPairReconnectSmokeSnapshot: Codable, Equatable, Sendable {
    var source: String
    var status: String
    var route: String
    var triggeredAtMs: Int64
    var completedAtMs: Int64
    var reasonCode: String?
    var summary: String

    enum CodingKeys: String, CodingKey {
        case source
        case status
        case route
        case triggeredAtMs = "triggered_at_ms"
        case completedAtMs = "completed_at_ms"
        case reasonCode = "reason_code"
        case summary
    }
}

struct XHubDoctorOutputFirstPairCompletionProofSnapshot: Codable, Equatable, Sendable {
    var readiness: String
    var sameLanVerified: Bool
    var ownerLocalApprovalVerified: Bool
    var pairingMaterialIssued: Bool
    var cachedReconnectSmokePassed: Bool
    var stableRemoteRoutePresent: Bool
    var remoteShadowSmokePassed: Bool
    var remoteShadowSmokeStatus: String
    var remoteShadowSmokeSource: String? = nil
    var remoteShadowTriggeredAtMs: Int64? = nil
    var remoteShadowCompletedAtMs: Int64? = nil
    var remoteShadowRoute: String? = nil
    var remoteShadowReasonCode: String? = nil
    var remoteShadowSummary: String? = nil
    var summaryLine: String
    var generatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case readiness
        case sameLanVerified = "same_lan_verified"
        case ownerLocalApprovalVerified = "owner_local_approval_verified"
        case pairingMaterialIssued = "pairing_material_issued"
        case cachedReconnectSmokePassed = "cached_reconnect_smoke_passed"
        case stableRemoteRoutePresent = "stable_remote_route_present"
        case remoteShadowSmokePassed = "remote_shadow_smoke_passed"
        case remoteShadowSmokeStatus = "remote_shadow_smoke_status"
        case remoteShadowSmokeSource = "remote_shadow_smoke_source"
        case remoteShadowTriggeredAtMs = "remote_shadow_triggered_at_ms"
        case remoteShadowCompletedAtMs = "remote_shadow_completed_at_ms"
        case remoteShadowRoute = "remote_shadow_route"
        case remoteShadowReasonCode = "remote_shadow_reason_code"
        case remoteShadowSummary = "remote_shadow_summary"
        case summaryLine = "summary_line"
        case generatedAtMs = "generated_at_ms"
    }
}

struct XHubDoctorOutputDurableCandidateMirrorSnapshot: Codable, Equatable, Sendable {
    var status: String
    var target: String
    var attempted: Bool
    var errorCode: String?
    var localStoreRole: String

    enum CodingKeys: String, CodingKey {
        case status
        case target
        case attempted
        case errorCode = "error_code"
        case localStoreRole = "local_store_role"
    }
}

struct XHubDoctorOutputLocalStoreWriteSnapshot: Codable, Equatable, Sendable {
    var personalMemoryIntent: String?
    var crossLinkIntent: String?
    var personalReviewIntent: String?

    enum CodingKeys: String, CodingKey {
        case personalMemoryIntent = "personal_memory_intent"
        case crossLinkIntent = "cross_link_intent"
        case personalReviewIntent = "personal_review_intent"
    }
}

struct XHubDoctorOutputHeartbeatCadenceDimensionSnapshot: Codable, Equatable, Sendable {
    var dimension: String
    var dimensionDisplayText: String?
    var configuredSeconds: Int?
    var recommendedSeconds: Int?
    var effectiveSeconds: Int?
    var effectiveReasonCodes: [String]
    var effectiveReasonDisplayTexts: [String]
    var nextDueAtMs: Int64?
    var nextDueReasonCodes: [String]
    var nextDueReasonDisplayTexts: [String]
    var isDue: Bool?

    enum CodingKeys: String, CodingKey {
        case dimension
        case dimensionDisplayText = "dimension_display_text"
        case configuredSeconds = "configured_seconds"
        case recommendedSeconds = "recommended_seconds"
        case effectiveSeconds = "effective_seconds"
        case effectiveReasonCodes = "effective_reason_codes"
        case effectiveReasonDisplayTexts = "effective_reason_display_texts"
        case nextDueAtMs = "next_due_at_ms"
        case nextDueReasonCodes = "next_due_reason_codes"
        case nextDueReasonDisplayTexts = "next_due_reason_display_texts"
        case isDue = "is_due"
    }
}

struct XHubDoctorOutputHeartbeatNextReviewDueSnapshot: Codable, Equatable, Sendable {
    var kind: String?
    var kindDisplayText: String?
    var due: Bool?
    var atMs: Int64?
    var reasonCodes: [String]
    var reasonDisplayTexts: [String]

    enum CodingKeys: String, CodingKey {
        case kind
        case kindDisplayText = "kind_display_text"
        case due
        case atMs = "at_ms"
        case reasonCodes = "reason_codes"
        case reasonDisplayTexts = "reason_display_texts"
    }
}

final class XHubDoctorOutputHeartbeatRecoverySnapshot: Codable, Equatable, Sendable {
    let action: String?
    let actionDisplayText: String?
    let urgency: String?
    let urgencyDisplayText: String?
    let reasonCode: String?
    let reasonDisplayText: String?
    let systemNextStepDisplayText: String?
    let summary: String
    let doctorExplainabilityText: String?
    let sourceSignals: [String]
    let sourceSignalDisplayTexts: [String]
    let anomalyTypes: [String]
    let anomalyTypeDisplayTexts: [String]
    let blockedLaneReasons: [String]
    let blockedLaneReasonDisplayTexts: [String]
    let blockedLaneCount: Int?
    let stalledLaneCount: Int?
    let failedLaneCount: Int?
    let recoveringLaneCount: Int?
    let requiresUserAction: Bool?
    let queuedReviewTrigger: String?
    let queuedReviewTriggerDisplayText: String?
    let queuedReviewLevel: String?
    let queuedReviewLevelDisplayText: String?
    let queuedReviewRunKind: String?
    let queuedReviewRunKindDisplayText: String?

    init(
        action: String? = nil,
        actionDisplayText: String? = nil,
        urgency: String? = nil,
        urgencyDisplayText: String? = nil,
        reasonCode: String? = nil,
        reasonDisplayText: String? = nil,
        systemNextStepDisplayText: String? = nil,
        summary: String = "",
        doctorExplainabilityText: String? = nil,
        sourceSignals: [String] = [],
        sourceSignalDisplayTexts: [String] = [],
        anomalyTypes: [String] = [],
        anomalyTypeDisplayTexts: [String] = [],
        blockedLaneReasons: [String] = [],
        blockedLaneReasonDisplayTexts: [String] = [],
        blockedLaneCount: Int? = nil,
        stalledLaneCount: Int? = nil,
        failedLaneCount: Int? = nil,
        recoveringLaneCount: Int? = nil,
        requiresUserAction: Bool? = nil,
        queuedReviewTrigger: String? = nil,
        queuedReviewTriggerDisplayText: String? = nil,
        queuedReviewLevel: String? = nil,
        queuedReviewLevelDisplayText: String? = nil,
        queuedReviewRunKind: String? = nil,
        queuedReviewRunKindDisplayText: String? = nil
    ) {
        self.action = action
        self.actionDisplayText = actionDisplayText
        self.urgency = urgency
        self.urgencyDisplayText = urgencyDisplayText
        self.reasonCode = reasonCode
        self.reasonDisplayText = reasonDisplayText
        self.systemNextStepDisplayText = systemNextStepDisplayText
        self.summary = summary
        self.doctorExplainabilityText = doctorExplainabilityText
        self.sourceSignals = sourceSignals
        self.sourceSignalDisplayTexts = sourceSignalDisplayTexts
        self.anomalyTypes = anomalyTypes
        self.anomalyTypeDisplayTexts = anomalyTypeDisplayTexts
        self.blockedLaneReasons = blockedLaneReasons
        self.blockedLaneReasonDisplayTexts = blockedLaneReasonDisplayTexts
        self.blockedLaneCount = blockedLaneCount
        self.stalledLaneCount = stalledLaneCount
        self.failedLaneCount = failedLaneCount
        self.recoveringLaneCount = recoveringLaneCount
        self.requiresUserAction = requiresUserAction
        self.queuedReviewTrigger = queuedReviewTrigger
        self.queuedReviewTriggerDisplayText = queuedReviewTriggerDisplayText
        self.queuedReviewLevel = queuedReviewLevel
        self.queuedReviewLevelDisplayText = queuedReviewLevelDisplayText
        self.queuedReviewRunKind = queuedReviewRunKind
        self.queuedReviewRunKindDisplayText = queuedReviewRunKindDisplayText
    }

    enum CodingKeys: String, CodingKey {
        case action
        case actionDisplayText = "action_display_text"
        case urgency
        case urgencyDisplayText = "urgency_display_text"
        case reasonCode = "reason_code"
        case reasonDisplayText = "reason_display_text"
        case systemNextStepDisplayText = "system_next_step_display_text"
        case summary
        case doctorExplainabilityText = "doctor_explainability_text"
        case sourceSignals = "source_signals"
        case sourceSignalDisplayTexts = "source_signal_display_texts"
        case anomalyTypes = "anomaly_types"
        case anomalyTypeDisplayTexts = "anomaly_type_display_texts"
        case blockedLaneReasons = "blocked_lane_reasons"
        case blockedLaneReasonDisplayTexts = "blocked_lane_reason_display_texts"
        case blockedLaneCount = "blocked_lane_count"
        case stalledLaneCount = "stalled_lane_count"
        case failedLaneCount = "failed_lane_count"
        case recoveringLaneCount = "recovering_lane_count"
        case requiresUserAction = "requires_user_action"
        case queuedReviewTrigger = "queued_review_trigger"
        case queuedReviewTriggerDisplayText = "queued_review_trigger_display_text"
        case queuedReviewLevel = "queued_review_level"
        case queuedReviewLevelDisplayText = "queued_review_level_display_text"
        case queuedReviewRunKind = "queued_review_run_kind"
        case queuedReviewRunKindDisplayText = "queued_review_run_kind_display_text"
    }

    static func == (
        lhs: XHubDoctorOutputHeartbeatRecoverySnapshot,
        rhs: XHubDoctorOutputHeartbeatRecoverySnapshot
    ) -> Bool {
        lhs.action == rhs.action
            && lhs.actionDisplayText == rhs.actionDisplayText
            && lhs.urgency == rhs.urgency
            && lhs.urgencyDisplayText == rhs.urgencyDisplayText
            && lhs.reasonCode == rhs.reasonCode
            && lhs.reasonDisplayText == rhs.reasonDisplayText
            && lhs.systemNextStepDisplayText == rhs.systemNextStepDisplayText
            && lhs.summary == rhs.summary
            && lhs.doctorExplainabilityText == rhs.doctorExplainabilityText
            && lhs.sourceSignals == rhs.sourceSignals
            && lhs.sourceSignalDisplayTexts == rhs.sourceSignalDisplayTexts
            && lhs.anomalyTypes == rhs.anomalyTypes
            && lhs.anomalyTypeDisplayTexts == rhs.anomalyTypeDisplayTexts
            && lhs.blockedLaneReasons == rhs.blockedLaneReasons
            && lhs.blockedLaneReasonDisplayTexts == rhs.blockedLaneReasonDisplayTexts
            && lhs.blockedLaneCount == rhs.blockedLaneCount
            && lhs.stalledLaneCount == rhs.stalledLaneCount
            && lhs.failedLaneCount == rhs.failedLaneCount
            && lhs.recoveringLaneCount == rhs.recoveringLaneCount
            && lhs.requiresUserAction == rhs.requiresUserAction
            && lhs.queuedReviewTrigger == rhs.queuedReviewTrigger
            && lhs.queuedReviewTriggerDisplayText == rhs.queuedReviewTriggerDisplayText
            && lhs.queuedReviewLevel == rhs.queuedReviewLevel
            && lhs.queuedReviewLevelDisplayText == rhs.queuedReviewLevelDisplayText
            && lhs.queuedReviewRunKind == rhs.queuedReviewRunKind
            && lhs.queuedReviewRunKindDisplayText == rhs.queuedReviewRunKindDisplayText
    }
}

struct XHubDoctorOutputHeartbeatGovernanceSnapshot: Codable, Equatable, Sendable {
    var projectId: String
    var projectName: String
    var statusDigest: String
    var currentStateSummary: String
    var nextStepSummary: String
    var blockerSummary: String
    var lastHeartbeatAtMs: Int64
    var latestQualityBand: String?
    var latestQualityBandDisplayText: String?
    var latestQualityScore: Int?
    var weakReasons: [String]
    var weakReasonDisplayTexts: [String]
    var openAnomalyTypes: [String]
    var openAnomalyDisplayTexts: [String]
    var projectPhase: String?
    var projectPhaseDisplayText: String?
    var executionStatus: String?
    var executionStatusDisplayText: String?
    var riskTier: String?
    var riskTierDisplayText: String?
    var digestVisibility: String
    var digestVisibilityDisplayText: String?
    var digestReasonCodes: [String]
    var digestReasonDisplayTexts: [String]
    var digestWhatChangedText: String
    var digestWhyImportantText: String
    var digestSystemNextStepText: String
    var progressHeartbeat: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot
    var reviewPulse: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot
    var brainstormReview: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot
    var nextReviewDue: XHubDoctorOutputHeartbeatNextReviewDueSnapshot
    var recoveryDecision: XHubDoctorOutputHeartbeatRecoverySnapshot?
    var projectMemoryReady: Bool?
    var projectMemoryStatusLine: String?
    var projectMemoryIssueCodes: [String]
    var projectMemoryTopIssueSummary: String?

    enum CodingKeys: String, CodingKey {
        case projectId = "project_id"
        case projectName = "project_name"
        case statusDigest = "status_digest"
        case currentStateSummary = "current_state_summary"
        case nextStepSummary = "next_step_summary"
        case blockerSummary = "blocker_summary"
        case lastHeartbeatAtMs = "last_heartbeat_at_ms"
        case latestQualityBand = "latest_quality_band"
        case latestQualityBandDisplayText = "latest_quality_band_display_text"
        case latestQualityScore = "latest_quality_score"
        case weakReasons = "weak_reasons"
        case weakReasonDisplayTexts = "weak_reason_display_texts"
        case openAnomalyTypes = "open_anomaly_types"
        case openAnomalyDisplayTexts = "open_anomaly_display_texts"
        case projectPhase = "project_phase"
        case projectPhaseDisplayText = "project_phase_display_text"
        case executionStatus = "execution_status"
        case executionStatusDisplayText = "execution_status_display_text"
        case riskTier = "risk_tier"
        case riskTierDisplayText = "risk_tier_display_text"
        case digestVisibility = "digest_visibility"
        case digestVisibilityDisplayText = "digest_visibility_display_text"
        case digestReasonCodes = "digest_reason_codes"
        case digestReasonDisplayTexts = "digest_reason_display_texts"
        case digestWhatChangedText = "digest_what_changed_text"
        case digestWhyImportantText = "digest_why_important_text"
        case digestSystemNextStepText = "digest_system_next_step_text"
        case progressHeartbeat = "progress_heartbeat"
        case reviewPulse = "review_pulse"
        case brainstormReview = "brainstorm_review"
        case nextReviewDue = "next_review_due"
        case recoveryDecision = "recovery_decision"
        case projectMemoryReady = "project_memory_ready"
        case projectMemoryStatusLine = "project_memory_status_line"
        case projectMemoryIssueCodes = "project_memory_issue_codes"
        case projectMemoryTopIssueSummary = "project_memory_top_issue_summary"
    }
}

struct XHubDoctorOutputProjectContextSummary: Codable, Equatable, Sendable {
    var sourceKind: String
    var sourceBadge: String
    var projectLabel: String?
    var statusLine: String
    var dialogueMetric: String
    var depthMetric: String
    var coverageMetric: String?
    var boundaryMetric: String?
    var dialogueLine: String
    var depthLine: String
    var coverageLine: String?
    var boundaryLine: String?
    var planeLine: String?
    var assemblyLine: String?
    var omissionLine: String?
    var budgetLine: String?

    enum CodingKeys: String, CodingKey {
        case sourceKind = "source_kind"
        case sourceBadge = "source_badge"
        case projectLabel = "project_label"
        case statusLine = "status_line"
        case dialogueMetric = "dialogue_metric"
        case depthMetric = "depth_metric"
        case coverageMetric = "coverage_metric"
        case boundaryMetric = "boundary_metric"
        case dialogueLine = "dialogue_line"
        case depthLine = "depth_line"
        case coverageLine = "coverage_line"
        case boundaryLine = "boundary_line"
        case planeLine = "plane_line"
        case assemblyLine = "assembly_line"
        case omissionLine = "omission_line"
        case budgetLine = "budget_line"
    }
}

struct XHubDoctorOutputRemoteSnapshotCacheSnapshot: Codable, Equatable, Sendable {
    var source: String?
    var freshness: String?
    var cacheHit: Bool?
    var scope: String?
    var cachedAtMs: Int64?
    var ageMs: Int?
    var ttlRemainingMs: Int?
    var upstreamTruthClass: String?
    var cacheRole: String?
    var provenanceLabel: String?

    enum CodingKeys: String, CodingKey {
        case source
        case freshness
        case cacheHit = "cache_hit"
        case scope
        case cachedAtMs = "cached_at_ms"
        case ageMs = "age_ms"
        case ttlRemainingMs = "ttl_remaining_ms"
        case upstreamTruthClass = "upstream_truth_class"
        case cacheRole = "cache_role"
        case provenanceLabel = "provenance_label"
    }
}

struct XHubDoctorOutputProjectAutomationContinuitySnapshot: Codable, Equatable, Sendable {
    var continuitySourceClass: String?
    var automationContextSource: String?
    var memorySource: String?
    var memorySourceClass: String?
    var memoryFreshness: String?
    var memoryCacheHit: Bool?
    var remoteSnapshotProvenanceLabel: String?
    var runID: String?
    var runState: String?
    var attempt: Int?
    var retryAfterSeconds: Int?
    var recoverySelection: String?
    var recoveryReason: String?
    var recoveryDecision: String?
    var recoveryHoldReason: String?
    var recoveryRetryAfterRemainingSeconds: Int?
    var currentStepID: String?
    var currentStepTitle: String?
    var currentStepState: String?
    var verificationContract: XTAutomationVerificationContract?
    var retryVerificationContract: XTAutomationVerificationContract?
    var verificationPresent: Bool?
    var blockerPresent: Bool?
    var retryReasonPresent: Bool?

    enum CodingKeys: String, CodingKey {
        case continuitySourceClass = "continuity_source_class"
        case automationContextSource = "automation_context_source"
        case memorySource = "memory_source"
        case memorySourceClass = "memory_source_class"
        case memoryFreshness = "memory_freshness"
        case memoryCacheHit = "memory_cache_hit"
        case remoteSnapshotProvenanceLabel = "remote_snapshot_provenance_label"
        case runID = "run_id"
        case runState = "run_state"
        case attempt
        case retryAfterSeconds = "retry_after_seconds"
        case recoverySelection = "recovery_selection"
        case recoveryReason = "recovery_reason"
        case recoveryDecision = "recovery_decision"
        case recoveryHoldReason = "recovery_hold_reason"
        case recoveryRetryAfterRemainingSeconds = "recovery_retry_after_remaining_seconds"
        case currentStepID = "current_step_id"
        case currentStepTitle = "current_step_title"
        case currentStepState = "current_step_state"
        case verificationContract = "verification_contract"
        case retryVerificationContract = "retry_verification_contract"
        case verificationPresent = "verification_present"
        case blockerPresent = "blocker_present"
        case retryReasonPresent = "retry_reason_present"
    }
}

struct XHubDoctorOutputMemoryRouteTruthSnapshot: Codable, Equatable, Sendable {
    var projectionSource: String
    var completeness: String
    var requestSnapshot: XHubDoctorOutputMemoryRouteRequestSnapshot
    var resolutionChain: [XHubDoctorOutputMemoryRouteResolutionNode]
    var winningProfile: XHubDoctorOutputMemoryRouteWinningProfile
    var winningBinding: XHubDoctorOutputMemoryRouteWinningBinding
    var routeResult: XHubDoctorOutputMemoryRouteResult
    var constraintSnapshot: XHubDoctorOutputMemoryRouteConstraintSnapshot

    enum CodingKeys: String, CodingKey {
        case projectionSource = "projection_source"
        case completeness
        case requestSnapshot = "request_snapshot"
        case resolutionChain = "resolution_chain"
        case winningProfile = "winning_profile"
        case winningBinding = "winning_binding"
        case routeResult = "route_result"
        case constraintSnapshot = "constraint_snapshot"
    }
}

struct XHubDoctorOutputMemoryRouteRequestSnapshot: Codable, Equatable, Sendable {
    var jobType: String
    var mode: String
    var projectIDPresent: String
    var sensitivity: String
    var trustLevel: String
    var budgetClass: String
    var remoteAllowedByPolicy: String
    var killSwitchState: String

    enum CodingKeys: String, CodingKey {
        case jobType = "job_type"
        case mode
        case projectIDPresent = "project_id_present"
        case sensitivity
        case trustLevel = "trust_level"
        case budgetClass = "budget_class"
        case remoteAllowedByPolicy = "remote_allowed_by_policy"
        case killSwitchState = "kill_switch_state"
    }
}

struct XHubDoctorOutputMemoryRouteResolutionNode: Codable, Equatable, Sendable {
    var scopeKind: String
    var scopeRefRedacted: String
    var matched: String
    var profileID: String
    var selectionStrategy: String
    var skipReason: String

    enum CodingKeys: String, CodingKey {
        case scopeKind = "scope_kind"
        case scopeRefRedacted = "scope_ref_redacted"
        case matched
        case profileID = "profile_id"
        case selectionStrategy = "selection_strategy"
        case skipReason = "skip_reason"
    }
}

struct XHubDoctorOutputMemoryRouteWinningProfile: Codable, Equatable, Sendable {
    var resolvedProfileID: String
    var scopeKind: String
    var scopeRefRedacted: String
    var selectionStrategy: String
    var policyVersion: String
    var disabled: String

    enum CodingKeys: String, CodingKey {
        case resolvedProfileID = "resolved_profile_id"
        case scopeKind = "scope_kind"
        case scopeRefRedacted = "scope_ref_redacted"
        case selectionStrategy = "selection_strategy"
        case policyVersion = "policy_version"
        case disabled
    }
}

struct XHubDoctorOutputMemoryRouteWinningBinding: Codable, Equatable, Sendable {
    var bindingKind: String
    var bindingKey: String
    var provider: String
    var modelID: String
    var selectedByUser: String

    enum CodingKeys: String, CodingKey {
        case bindingKind = "binding_kind"
        case bindingKey = "binding_key"
        case provider
        case modelID = "model_id"
        case selectedByUser = "selected_by_user"
    }
}

struct XHubDoctorOutputMemoryRouteResult: Codable, Equatable, Sendable {
    var routeSource: String
    var routeReasonCode: String
    var fallbackApplied: String
    var fallbackReason: String
    var remoteAllowed: String
    var auditRef: String
    var denyCode: String

    enum CodingKeys: String, CodingKey {
        case routeSource = "route_source"
        case routeReasonCode = "route_reason_code"
        case fallbackApplied = "fallback_applied"
        case fallbackReason = "fallback_reason"
        case remoteAllowed = "remote_allowed"
        case auditRef = "audit_ref"
        case denyCode = "deny_code"
    }
}

struct XHubDoctorOutputMemoryRouteConstraintSnapshot: Codable, Equatable, Sendable {
    var remoteAllowedAfterUserPref: String
    var remoteAllowedAfterPolicy: String
    var budgetClass: String
    var budgetBlocked: String
    var policyBlockedRemote: String

    enum CodingKeys: String, CodingKey {
        case remoteAllowedAfterUserPref = "remote_allowed_after_user_pref"
        case remoteAllowedAfterPolicy = "remote_allowed_after_policy"
        case budgetClass = "budget_class"
        case budgetBlocked = "budget_blocked"
        case policyBlockedRemote = "policy_blocked_remote"
    }
}

struct XHubDoctorOutputNextStep: Identifiable, Codable, Equatable, Sendable {
    var stepID: String
    var kind: XHubDoctorNextStepKind
    var label: String
    var owner: XHubDoctorStepOwner
    var blocking: Bool
    var destinationRef: String
    var instruction: String

    var id: String { stepID }

    enum CodingKeys: String, CodingKey {
        case stepID = "step_id"
        case kind
        case label
        case owner
        case blocking
        case destinationRef = "destination_ref"
        case instruction
    }
}

struct XHubDoctorOutputRouteSnapshot: Codable, Equatable, Sendable {
    var transportMode: String
    var routeLabel: String
    var pairingPort: Int
    var grpcPort: Int
    var internetHost: String
    var internetHostKind: String
    var internetHostScope: String?
    var remoteEntryPosture: String

    enum CodingKeys: String, CodingKey {
        case transportMode = "transport_mode"
        case routeLabel = "route_label"
        case pairingPort = "pairing_port"
        case grpcPort = "grpc_port"
        case internetHost = "internet_host"
        case internetHostKind = "internet_host_kind"
        case internetHostScope = "internet_host_scope"
        case remoteEntryPosture = "remote_entry_posture"
    }
}

struct XHubDoctorOutputPairedRouteTargetSnapshot: Codable, Equatable, Sendable {
    var routeKind: String
    var host: String
    var pairingPort: Int
    var grpcPort: Int
    var hostKind: String
    var source: String

    enum CodingKeys: String, CodingKey {
        case routeKind = "route_kind"
        case host
        case pairingPort = "pairing_port"
        case grpcPort = "grpc_port"
        case hostKind = "host_kind"
        case source
    }
}

struct XHubDoctorOutputPairedRouteSetSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String
    var readiness: String
    var readinessReasonCode: String
    var summaryLine: String
    var hubInstanceID: String?
    var pairingProfileEpoch: Int?
    var routePackVersion: String?
    var activeRoute: XHubDoctorOutputPairedRouteTargetSnapshot?
    var lanRoute: XHubDoctorOutputPairedRouteTargetSnapshot?
    var stableRemoteRoute: XHubDoctorOutputPairedRouteTargetSnapshot?
    var lastKnownGoodRoute: XHubDoctorOutputPairedRouteTargetSnapshot?
    var cachedReconnectSmokeStatus: String?
    var cachedReconnectSmokeReasonCode: String?
    var cachedReconnectSmokeSummary: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case readiness
        case readinessReasonCode = "readiness_reason_code"
        case summaryLine = "summary_line"
        case hubInstanceID = "hub_instance_id"
        case pairingProfileEpoch = "pairing_profile_epoch"
        case routePackVersion = "route_pack_version"
        case activeRoute = "active_route"
        case lanRoute = "lan_route"
        case stableRemoteRoute = "stable_remote_route"
        case lastKnownGoodRoute = "last_known_good_route"
        case cachedReconnectSmokeStatus = "cached_reconnect_smoke_status"
        case cachedReconnectSmokeReasonCode = "cached_reconnect_smoke_reason_code"
        case cachedReconnectSmokeSummary = "cached_reconnect_smoke_summary"
    }
}

struct XHubDoctorOutputConnectivityIncidentPathSnapshot: Codable, Equatable, Sendable {
    var statusKey: String
    var usesWiFi: Bool
    var usesWiredEthernet: Bool
    var usesCellular: Bool
    var isExpensive: Bool
    var isConstrained: Bool

    enum CodingKeys: String, CodingKey {
        case statusKey = "status_key"
        case usesWiFi = "uses_wifi"
        case usesWiredEthernet = "uses_wired_ethernet"
        case usesCellular = "uses_cellular"
        case isExpensive = "is_expensive"
        case isConstrained = "is_constrained"
    }
}

struct XHubDoctorOutputConnectivityRouteStatusSnapshot: Codable, Equatable, Sendable {
    var route: String
    var healthScore: Int
    var cooldownUntilMs: Int64?
    var recentSuccessCount: Int
    var recentFailureCount: Int

    enum CodingKeys: String, CodingKey {
        case route
        case healthScore = "health_score"
        case cooldownUntilMs = "cooldown_until_ms"
        case recentSuccessCount = "recent_success_count"
        case recentFailureCount = "recent_failure_count"
    }
}

struct XHubDoctorOutputConnectivityIncidentSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: String
    var incidentState: String
    var reasonCode: String
    var summaryLine: String
    var trigger: String
    var decisionReasonCode: String
    var pairedRouteReadiness: String?
    var stableRemoteRouteHost: String?
    var currentFailureCode: String?
    var currentPath: XHubDoctorOutputConnectivityIncidentPathSnapshot?
    var lastUpdatedAtMs: Int64
    var selectedRoute: String? = nil
    var candidatesTried: [String]? = nil
    var handoffReason: String? = nil
    var cooldownApplied: Bool? = nil
    var routeStatuses: [XHubDoctorOutputConnectivityRouteStatusSnapshot]? = nil

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case incidentState = "incident_state"
        case reasonCode = "reason_code"
        case summaryLine = "summary_line"
        case trigger
        case decisionReasonCode = "decision_reason_code"
        case pairedRouteReadiness = "paired_route_readiness"
        case stableRemoteRouteHost = "stable_remote_route_host"
        case currentFailureCode = "current_failure_code"
        case currentPath = "current_path"
        case lastUpdatedAtMs = "last_updated_at_ms"
        case selectedRoute = "selected_route"
        case candidatesTried = "candidates_tried"
        case handoffReason = "handoff_reason"
        case cooldownApplied = "cooldown_applied"
        case routeStatuses = "route_statuses"
    }
}

struct XHubDoctorOutputConnectivityIncidentHistoryReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.hub_connectivity_incident_history.v1"

    var schemaVersion: String = currentSchemaVersion
    var entries: [XHubDoctorOutputConnectivityIncidentSnapshot]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case entries
    }
}

struct XHubLocalServiceSnapshotPrimaryIssue: Codable, Equatable, Sendable {
    var reasonCode: String
    var headline: String
    var message: String
    var nextStep: String

    enum CodingKeys: String, CodingKey {
        case reasonCode = "reason_code"
        case headline
        case message
        case nextStep = "next_step"
    }
}

struct XHubLocalServiceSnapshotDoctorProjection: Codable, Equatable, Sendable {
    var overallState: XHubDoctorOverallState
    var readyForFirstTask: Bool
    var currentFailureCode: String
    var currentFailureIssue: String
    var providerCheckStatus: XHubDoctorCheckStatus
    var providerCheckBlocking: Bool
    var headline: String
    var message: String
    var nextStep: String
    var repairDestinationRef: String

    enum CodingKeys: String, CodingKey {
        case overallState = "overall_state"
        case readyForFirstTask = "ready_for_first_task"
        case currentFailureCode = "current_failure_code"
        case currentFailureIssue = "current_failure_issue"
        case providerCheckStatus = "provider_check_status"
        case providerCheckBlocking = "provider_check_blocking"
        case headline
        case message
        case nextStep = "next_step"
        case repairDestinationRef = "repair_destination_ref"
    }
}

struct XHubLocalServiceProviderEvidence: Codable, Equatable, Sendable {
    var providerID: String
    var serviceState: String
    var runtimeReasonCode: String
    var serviceBaseURL: String
    var executionMode: String
    var loadedInstanceCount: Int
    var queuedTaskCount: Int
    var ready: Bool

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case serviceState = "service_state"
        case runtimeReasonCode = "runtime_reason_code"
        case serviceBaseURL = "service_base_url"
        case executionMode = "execution_mode"
        case loadedInstanceCount = "loaded_instance_count"
        case queuedTaskCount = "queued_task_count"
        case ready
    }
}

struct XHubLocalServiceSnapshotReport: Codable, Equatable, Sendable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var statusSource: String
    var runtimeAlive: Bool
    var providerCount: Int
    var readyProviderCount: Int
    var primaryIssue: XHubLocalServiceSnapshotPrimaryIssue?
    var doctorProjection: XHubLocalServiceSnapshotDoctorProjection?
    var providers: [XHubLocalServiceProviderEvidence]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case statusSource = "status_source"
        case runtimeAlive = "runtime_alive"
        case providerCount = "provider_count"
        case readyProviderCount = "ready_provider_count"
        case primaryIssue = "primary_issue"
        case doctorProjection = "doctor_projection"
        case providers
    }
}

struct XHubLocalServiceRecoveryGuidanceAction: Codable, Equatable, Sendable {
    var rank: Int
    var actionID: String
    var title: String
    var why: String
    var commandOrReference: String

    enum CodingKeys: String, CodingKey {
        case rank
        case actionID = "action_id"
        case title
        case why
        case commandOrReference = "command_or_ref"
    }
}

struct XHubLocalServiceRecoveryGuidanceFAQItem: Codable, Equatable, Sendable {
    var faqID: String
    var question: String
    var answer: String

    enum CodingKeys: String, CodingKey {
        case faqID = "faq_id"
        case question
        case answer
    }
}

struct XHubLocalServiceRecoveryGuidanceReport: Codable, Equatable, Sendable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var statusSource: String
    var runtimeAlive: Bool
    var guidancePresent: Bool
    var providerCount: Int
    var readyProviderCount: Int
    var currentFailureCode: String
    var currentFailureIssue: String
    var providerCheckStatus: String
    var providerCheckBlocking: Bool
    var actionCategory: String
    var severity: String
    var installHint: String
    var repairDestinationRef: String
    var serviceBaseURL: String
    var managedProcessState: String
    var managedStartAttemptCount: Int
    var managedLastStartError: String
    var managedLastProbeError: String
    var blockedCapabilities: [String]
    var primaryIssue: XHubLocalServiceSnapshotPrimaryIssue?
    var recommendedActions: [XHubLocalServiceRecoveryGuidanceAction]
    var supportFAQ: [XHubLocalServiceRecoveryGuidanceFAQItem]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case statusSource = "status_source"
        case runtimeAlive = "runtime_alive"
        case guidancePresent = "guidance_present"
        case providerCount = "provider_count"
        case readyProviderCount = "ready_provider_count"
        case currentFailureCode = "current_failure_code"
        case currentFailureIssue = "current_failure_issue"
        case providerCheckStatus = "provider_check_status"
        case providerCheckBlocking = "provider_check_blocking"
        case actionCategory = "action_category"
        case severity
        case installHint = "install_hint"
        case repairDestinationRef = "repair_destination_ref"
        case serviceBaseURL = "service_base_url"
        case managedProcessState = "managed_process_state"
        case managedStartAttemptCount = "managed_start_attempt_count"
        case managedLastStartError = "managed_last_start_error"
        case managedLastProbeError = "managed_last_probe_error"
        case blockedCapabilities = "blocked_capabilities"
        case primaryIssue = "primary_issue"
        case recommendedActions = "recommended_actions"
        case supportFAQ = "support_faq"
    }
}

enum XHubLocalRuntimeHostMetricsSeverity: String, Codable, CaseIterable, Sendable {
    case normal
    case elevated
    case high
    case critical
}

struct XHubLocalRuntimeHostMetricsReport: Codable, Equatable, Sendable {
    var sampledAtMs: Int64
    var sampleWindowMs: Int?
    var cpuUsagePercent: Double?
    var cpuCoreCount: Int
    var loadAverage1m: Double
    var loadAverage5m: Double
    var loadAverage15m: Double
    var normalizedLoadAverage1m: Double
    var memoryPressure: String
    var memoryUsedBytes: Int64?
    var memoryAvailableBytes: Int64?
    var memoryCompressedBytes: Int64?
    var thermalState: String
    var severity: String
    var summary: String
    var detailLines: [String]

    enum CodingKeys: String, CodingKey {
        case sampledAtMs = "sampled_at_ms"
        case sampleWindowMs = "sample_window_ms"
        case cpuUsagePercent = "cpu_usage_percent"
        case cpuCoreCount = "cpu_core_count"
        case loadAverage1m = "load_average_1m"
        case loadAverage5m = "load_average_5m"
        case loadAverage15m = "load_average_15m"
        case normalizedLoadAverage1m = "normalized_load_average_1m"
        case memoryPressure = "memory_pressure"
        case memoryUsedBytes = "memory_used_bytes"
        case memoryAvailableBytes = "memory_available_bytes"
        case memoryCompressedBytes = "memory_compressed_bytes"
        case thermalState = "thermal_state"
        case severity
        case summary
        case detailLines = "detail_lines"
    }

    var resolvedSeverity: XHubLocalRuntimeHostMetricsSeverity {
        XHubLocalRuntimeHostMetricsSeverity(rawValue: severity) ?? .normal
    }

    var machineSummaryLine: String {
        let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSummary.isEmpty {
            return trimmedSummary
        }

        let cpuText = cpuUsagePercent.map { String(format: "%.1f", $0) } ?? "unknown"
        return [
            "host_load_severity=\(resolvedSeverity.rawValue)",
            "cpu_percent=\(cpuText)",
            String(format: "load_avg=%.2f/%.2f/%.2f", loadAverage1m, loadAverage5m, loadAverage15m),
            String(format: "normalized_1m=%.2f", normalizedLoadAverage1m),
            "memory_pressure=\(memoryPressure.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : memoryPressure)",
            "thermal_state=\(thermalState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : thermalState)"
        ].joined(separator: " ")
    }
}

struct XHubLocalRuntimeMonitorCurrentTargetEvidence: Codable, Equatable, Sendable {
    var modelID: String
    var modelName: String
    var providerID: String
    var uiSummary: String
    var technicalSummary: String
    var loadSummary: String

    enum CodingKeys: String, CodingKey {
        case modelID = "model_id"
        case modelName = "model_name"
        case providerID = "provider_id"
        case uiSummary = "ui_summary"
        case technicalSummary = "technical_summary"
        case loadSummary = "load_summary"
    }
}

struct XHubLocalRuntimeMonitorLoadedInstanceEvidence: Codable, Equatable, Sendable {
    var providerID: String
    var modelID: String
    var modelName: String
    var loadSummary: String
    var detailSummary: String
    var currentTargetSummary: String

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case modelID = "model_id"
        case modelName = "model_name"
        case loadSummary = "load_summary"
        case detailSummary = "detail_summary"
        case currentTargetSummary = "current_target_summary"
    }
}

struct XHubLocalRuntimeMonitorOperationsReport: Codable, Equatable, Sendable {
    var runtimeSummary: String
    var queueSummary: String
    var loadedSummary: String
    var currentTargets: [XHubLocalRuntimeMonitorCurrentTargetEvidence]
    var loadedInstances: [XHubLocalRuntimeMonitorLoadedInstanceEvidence]

    enum CodingKeys: String, CodingKey {
        case runtimeSummary = "runtime_summary"
        case queueSummary = "queue_summary"
        case loadedSummary = "loaded_summary"
        case currentTargets = "current_targets"
        case loadedInstances = "loaded_instances"
    }
}

struct XHubLocalRuntimeMonitorSnapshotReport: Codable, Equatable, Sendable {
    var schemaVersion: String
    var generatedAtMs: Int64
    var statusSource: String
    var runtimeAlive: Bool
    var monitorSummary: String
    var hostMetrics: XHubLocalRuntimeHostMetricsReport? = nil
    var runtimeOperations: XHubLocalRuntimeMonitorOperationsReport?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case statusSource = "status_source"
        case runtimeAlive = "runtime_alive"
        case monitorSummary = "monitor_summary"
        case hostMetrics = "host_metrics"
        case runtimeOperations = "runtime_operations"
    }
}

struct XHubDoctorOutputReport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xhub.doctor_output.v1"
    static let currentContractVersion = "2026-04-01"

    var schemaVersion: String
    var contractVersion: String
    var reportID: String
    var bundleKind: XHubDoctorBundleKind
    var producer: XHubDoctorProducer
    var surface: XHubDoctorSurface
    var overallState: XHubDoctorOverallState
    var summary: XHubDoctorOutputSummary
    var readyForFirstTask: Bool
    var checks: [XHubDoctorOutputCheckResult]
    var nextSteps: [XHubDoctorOutputNextStep]
    var routeSnapshot: XHubDoctorOutputRouteSnapshot?
    var firstPairCompletionProofSnapshot: XHubDoctorOutputFirstPairCompletionProofSnapshot? = nil
    var pairedRouteSetSnapshot: XHubDoctorOutputPairedRouteSetSnapshot? = nil
    var connectivityIncidentSnapshot: XHubDoctorOutputConnectivityIncidentSnapshot? = nil
    var generatedAtMs: Int64
    var reportPath: String
    var sourceReportSchemaVersion: String
    var sourceReportPath: String
    var currentFailureCode: String
    var currentFailureIssue: String?
    var consumedContracts: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case contractVersion = "contract_version"
        case reportID = "report_id"
        case bundleKind = "bundle_kind"
        case producer
        case surface
        case overallState = "overall_state"
        case summary
        case readyForFirstTask = "ready_for_first_task"
        case checks
        case nextSteps = "next_steps"
        case routeSnapshot = "route_snapshot"
        case firstPairCompletionProofSnapshot = "first_pair_completion_proof_snapshot"
        case pairedRouteSetSnapshot = "paired_route_set_snapshot"
        case connectivityIncidentSnapshot = "connectivity_incident_snapshot"
        case generatedAtMs = "generated_at_ms"
        case reportPath = "report_path"
        case sourceReportSchemaVersion = "source_report_schema_version"
        case sourceReportPath = "source_report_path"
        case currentFailureCode = "current_failure_code"
        case currentFailureIssue = "current_failure_issue"
        case consumedContracts = "consumed_contracts"
    }

    static func xtReadinessBundle(
        from report: XTUnifiedDoctorReport,
        outputPath: String = XHubDoctorOutputStore.defaultXTReportURL().path,
        surface: XHubDoctorSurface = .xtUI
    ) -> XHubDoctorOutputReport {
        let checks = report.sections.map { XHubDoctorOutputCheckResult(section: $0, observedAtMs: report.generatedAtMs) }
        let nextSteps = report.sections.compactMap { XHubDoctorOutputNextStep(section: $0) }
        return XHubDoctorOutputReport(
            schemaVersion: currentSchemaVersion,
            contractVersion: currentContractVersion,
            reportID: "xhub-doctor-xt-\(surface.rawValue)-\(report.generatedAtMs)",
            bundleKind: .pairedSurfaceReadiness,
            producer: .xTerminal,
            surface: surface,
            overallState: XHubDoctorOverallState(surfaceState: report.overallState),
            summary: XHubDoctorOutputSummary(headline: report.overallSummary, checks: checks),
            readyForFirstTask: report.readyForFirstTask,
            checks: checks,
            nextSteps: nextSteps,
            routeSnapshot: XHubDoctorOutputRouteSnapshot(report.currentRoute),
            firstPairCompletionProofSnapshot: report.firstPairCompletionProofSnapshot.map(
                XHubDoctorOutputFirstPairCompletionProofSnapshot.init
            ),
            pairedRouteSetSnapshot: report.pairedRouteSetSnapshot.map(XHubDoctorOutputPairedRouteSetSnapshot.init),
            connectivityIncidentSnapshot: report.connectivityIncidentSnapshot.map(XHubDoctorOutputConnectivityIncidentSnapshot.init),
            generatedAtMs: report.generatedAtMs,
            reportPath: outputPath,
            sourceReportSchemaVersion: report.schemaVersion,
            sourceReportPath: report.reportPath,
            currentFailureCode: report.currentFailureCode,
            currentFailureIssue: report.currentFailureIssue?.rawValue,
            consumedContracts: report.consumedContracts
        )
    }
}

enum XHubDoctorOutputStore {
    private static let hubReportFileName = "xhub_doctor_output_hub.json"
    private static let hubLocalServiceSnapshotFileName = "xhub_local_service_snapshot.redacted.json"
    private static let hubLocalRuntimeMonitorSnapshotFileName = "local_runtime_monitor_snapshot.redacted.json"
    private static let hubLocalServiceRecoveryGuidanceFileName =
        "xhub_local_service_recovery_guidance.redacted.json"
    private static let xtConnectivityRepairLedgerFileName =
        "xt_connectivity_repair_ledger.json"
    private static let xtPairedRouteSetFileName =
        "xt_paired_route_set.v1.json"
    private static let xtFirstPairCompletionProofFileName =
        "xt_first_pair_completion_proof.v1.json"
    private static let xtConnectivityIncidentSnapshotFileName =
        "xt_hub_connectivity_incident_snapshot.json"
    private static let xtConnectivityIncidentHistoryFileName =
        "xt_hub_connectivity_incident_history.json"
    private static let xtConnectivityIncidentHistoryMaxEntries = 12

    static func defaultXTReportURL(workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("xhub_doctor_output_xt.json")
    }

    static func defaultXTConnectivityIncidentSnapshotURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(xtConnectivityIncidentSnapshotFileName)
    }

    static func defaultXTConnectivityIncidentHistoryURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(xtConnectivityIncidentHistoryFileName)
    }

    static func defaultXTConnectivityRepairLedgerURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(xtConnectivityRepairLedgerFileName)
    }

    static func defaultXTFirstPairCompletionProofURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(xtFirstPairCompletionProofFileName)
    }

    static func defaultXTPairedRouteSetURL(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> URL {
        workspaceRoot
            .appendingPathComponent(".axcoder", isDirectory: true)
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent(xtPairedRouteSetFileName)
    }

    static func xtConnectivityRepairLedgerURL(alongside reportURL: URL) -> URL {
        reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(xtConnectivityRepairLedgerFileName)
    }

    static func defaultHubReportURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubReportFileName)
    }

    static func defaultHubLocalServiceSnapshotURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceSnapshotFileName)
    }

    static func defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalRuntimeMonitorSnapshotFileName)
    }

    static func defaultHubLocalServiceRecoveryGuidanceURL(baseDir: URL = HubPaths.baseDir()) -> URL {
        baseDir.appendingPathComponent(hubLocalServiceRecoveryGuidanceFileName)
    }

    static func loadReport(from url: URL) -> XHubDoctorOutputReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubDoctorOutputReport.self, from: data)
    }

    static func loadHubReport(baseDir: URL = HubPaths.baseDir()) -> XHubDoctorOutputReport? {
        loadReport(from: defaultHubReportURL(baseDir: baseDir))
    }

    static func loadXTConnectivityIncidentSnapshot(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputConnectivityIncidentSnapshot? {
        let url = defaultXTConnectivityIncidentSnapshotURL(workspaceRoot: workspaceRoot)
        if let data = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(XHubDoctorOutputConnectivityIncidentSnapshot.self, from: data) {
            return snapshot
        }
        return loadReport(from: defaultXTReportURL(workspaceRoot: workspaceRoot))?.connectivityIncidentSnapshot
    }

    static func loadXTConnectivityIncidentHistory(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XHubDoctorOutputConnectivityIncidentHistoryReport? {
        let url = defaultXTConnectivityIncidentHistoryURL(workspaceRoot: workspaceRoot)
        if let data = try? Data(contentsOf: url),
           let history = try? JSONDecoder().decode(XHubDoctorOutputConnectivityIncidentHistoryReport.self, from: data) {
            return history
        }
        guard let snapshot = loadReport(from: defaultXTReportURL(workspaceRoot: workspaceRoot))?.connectivityIncidentSnapshot else {
            return nil
        }
        return XHubDoctorOutputConnectivityIncidentHistoryReport(entries: [snapshot])
    }

    static func loadXTConnectivityRepairLedger(
        workspaceRoot: URL = XTUnifiedDoctorStore.workspaceRootFromEnvOrCWD()
    ) -> XTConnectivityRepairLedgerSnapshot? {
        loadXTConnectivityRepairLedger(from: defaultXTConnectivityRepairLedgerURL(workspaceRoot: workspaceRoot))
    }

    static func loadXTConnectivityRepairLedger(
        alongside reportURL: URL
    ) -> XTConnectivityRepairLedgerSnapshot? {
        loadXTConnectivityRepairLedger(from: xtConnectivityRepairLedgerURL(alongside: reportURL))
    }

    static func loadHubLocalServiceSnapshot(baseDir: URL = HubPaths.baseDir()) -> XHubLocalServiceSnapshotReport? {
        let url = defaultHubLocalServiceSnapshotURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalServiceSnapshotReport.self, from: data)
    }

    static func loadHubLocalRuntimeMonitorSnapshot(
        baseDir: URL = HubPaths.baseDir()
    ) -> XHubLocalRuntimeMonitorSnapshotReport? {
        let url = defaultHubLocalRuntimeMonitorSnapshotURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalRuntimeMonitorSnapshotReport.self, from: data)
    }

    static func loadHubLocalServiceRecoveryGuidance(
        baseDir: URL = HubPaths.baseDir()
    ) -> XHubLocalServiceRecoveryGuidanceReport? {
        let url = defaultHubLocalServiceRecoveryGuidanceURL(baseDir: baseDir)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubLocalServiceRecoveryGuidanceReport.self, from: data)
    }

    static func writeReport(
        _ report: XHubDoctorOutputReport,
        to url: URL,
        xtWorkspaceRoot: URL? = nil
    ) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return }
        if existingReportMatches(data, at: url) {
            writeXTArtifactsIfNeeded(
                report,
                alongside: url,
                xtWorkspaceRoot: xtWorkspaceRoot
            )
            return
        }
        writeDataIfNeeded(data, to: url)
        writeXTArtifactsIfNeeded(
            report,
            alongside: url,
            xtWorkspaceRoot: xtWorkspaceRoot
        )
    }

    private static func existingReportMatches(_ data: Data, at url: URL) -> Bool {
        guard let existing = try? Data(contentsOf: url) else { return false }
        return existing == data
    }

    private static func writeXTArtifactsIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL,
        xtWorkspaceRoot: URL?
    ) {
        writeXTPairedRouteSetIfNeeded(report, alongside: reportURL)
        writeXTFirstPairCompletionProofIfNeeded(report, alongside: reportURL)
        writeXTConnectivityIncidentSnapshotIfNeeded(report, alongside: reportURL)
        writeXTConnectivityIncidentHistoryIfNeeded(report, alongside: reportURL)
        writeXTConnectivityRepairLedgerIfNeeded(
            report,
            alongside: reportURL,
            xtWorkspaceRoot: xtWorkspaceRoot
        )
    }

    private static func writeXTConnectivityIncidentSnapshotIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL
    ) {
        guard report.producer == .xTerminal else { return }
        let snapshotURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(xtConnectivityIncidentSnapshotFileName)
        guard let snapshot = report.connectivityIncidentSnapshot else {
            try? FileManager.default.removeItem(at: snapshotURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        writeDataIfNeeded(data, to: snapshotURL)
    }

    private static func writeXTFirstPairCompletionProofIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL
    ) {
        guard report.producer == .xTerminal else { return }
        let proofURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(xtFirstPairCompletionProofFileName)
        guard let snapshot = report.firstPairCompletionProofSnapshot else {
            try? FileManager.default.removeItem(at: proofURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        writeDataIfNeeded(data, to: proofURL)
    }

    private static func writeXTPairedRouteSetIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL
    ) {
        guard report.producer == .xTerminal else { return }
        let pairedRouteSetURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(xtPairedRouteSetFileName)
        guard let snapshot = report.pairedRouteSetSnapshot else {
            try? FileManager.default.removeItem(at: pairedRouteSetURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        writeDataIfNeeded(data, to: pairedRouteSetURL)
    }

    private static func writeXTConnectivityIncidentHistoryIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL
    ) {
        guard report.producer == .xTerminal,
              let snapshot = report.connectivityIncidentSnapshot else {
            return
        }
        let historyURL = reportURL
            .deletingLastPathComponent()
            .appendingPathComponent(xtConnectivityIncidentHistoryFileName)
        let existingEntries = loadXTConnectivityIncidentHistory(from: historyURL)?.entries ?? []
        let mergedEntries = mergedXTConnectivityIncidentHistoryEntries(existingEntries, appending: snapshot)
        let history = XHubDoctorOutputConnectivityIncidentHistoryReport(entries: mergedEntries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(history) else { return }
        writeDataIfNeeded(data, to: historyURL)
    }

    private static func loadXTConnectivityIncidentHistory(
        from url: URL
    ) -> XHubDoctorOutputConnectivityIncidentHistoryReport? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XHubDoctorOutputConnectivityIncidentHistoryReport.self, from: data)
    }

    private static func loadXTConnectivityRepairLedger(
        from url: URL
    ) -> XTConnectivityRepairLedgerSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(XTConnectivityRepairLedgerSnapshot.self, from: data)
    }

    private static func writeXTConnectivityRepairLedgerIfNeeded(
        _ report: XHubDoctorOutputReport,
        alongside reportURL: URL,
        xtWorkspaceRoot: URL?
    ) {
        guard report.producer == .xTerminal else { return }
        let outputURL = xtConnectivityRepairLedgerURL(alongside: reportURL)
        let sourceURL = resolvedXTConnectivityRepairLedgerSourceURL(
            report: report,
            xtWorkspaceRoot: xtWorkspaceRoot
        )

        guard let sourceURL else {
            try? FileManager.default.removeItem(at: outputURL)
            return
        }

        if sourceURL.standardizedFileURL == outputURL.standardizedFileURL {
            return
        }

        guard let snapshot = loadXTConnectivityRepairLedger(from: sourceURL),
              !snapshot.entries.isEmpty else {
            try? FileManager.default.removeItem(at: outputURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        writeDataIfNeeded(data, to: outputURL)
    }

    private static func resolvedXTConnectivityRepairLedgerSourceURL(
        report: XHubDoctorOutputReport,
        xtWorkspaceRoot: URL?
    ) -> URL? {
        if let xtWorkspaceRoot {
            return defaultXTConnectivityRepairLedgerURL(workspaceRoot: xtWorkspaceRoot)
        }
        if let inferredRoot = inferredXTWorkspaceRoot(from: report) {
            return defaultXTConnectivityRepairLedgerURL(workspaceRoot: inferredRoot)
        }
        return nil
    }

    private static func inferredXTWorkspaceRoot(
        from report: XHubDoctorOutputReport
    ) -> URL? {
        guard report.producer == .xTerminal else {
            return nil
        }
        let sourceURL = URL(fileURLWithPath: report.sourceReportPath)
        let reportsDir = sourceURL.deletingLastPathComponent()
        guard sourceURL.lastPathComponent == "xt_unified_doctor_report.json",
              reportsDir.lastPathComponent == "reports" else {
            return nil
        }
        let axcoderDir = reportsDir.deletingLastPathComponent()
        guard axcoderDir.lastPathComponent == ".axcoder" else {
            return nil
        }
        return axcoderDir.deletingLastPathComponent()
    }

    private static func mergedXTConnectivityIncidentHistoryEntries(
        _ existing: [XHubDoctorOutputConnectivityIncidentSnapshot],
        appending snapshot: XHubDoctorOutputConnectivityIncidentSnapshot
    ) -> [XHubDoctorOutputConnectivityIncidentSnapshot] {
        guard var last = existing.last else {
            return [snapshot]
        }

        if snapshot.lastUpdatedAtMs < last.lastUpdatedAtMs {
            return existing
        }

        var entries = existing
        if last.historyIdentityKey == snapshot.historyIdentityKey {
            if snapshot.lastUpdatedAtMs >= last.lastUpdatedAtMs {
                last = snapshot
                entries[entries.count - 1] = last
            }
            return Array(entries.suffix(xtConnectivityIncidentHistoryMaxEntries))
        }

        entries.append(snapshot)
        return Array(entries.suffix(xtConnectivityIncidentHistoryMaxEntries))
    }

    private static func writeDataIfNeeded(_ data: Data, to url: URL) {
        if existingReportMatches(data, at: url) {
            return
        }
        try? XTStoreWriteSupport.writeSnapshotData(data, to: url)
    }
}

private extension XHubDoctorOutputConnectivityIncidentSnapshot {
    var historyIdentityKey: String {
        let pathKey: String
        if let currentPath {
            pathKey = [
                currentPath.statusKey,
                currentPath.usesWiFi ? "1" : "0",
                currentPath.usesWiredEthernet ? "1" : "0",
                currentPath.usesCellular ? "1" : "0",
                currentPath.isExpensive ? "1" : "0",
                currentPath.isConstrained ? "1" : "0"
            ].joined(separator: "|")
        } else {
            pathKey = "none"
        }

        return [
            incidentState,
            reasonCode,
            decisionReasonCode,
            pairedRouteReadiness ?? "",
            stableRemoteRouteHost ?? "",
            currentFailureCode ?? "",
            pathKey
        ].joined(separator: "|")
    }
}

extension XHubLocalServiceSnapshotReport {
    func preferredDetailLines(limit: Int = 2) -> [String] {
        let readyProviders = providers
            .filter(\.ready)
            .map(\.providerID)
            .sorted()
        let providerLines = providers.map { provider in
            let runtimeReason = provider.runtimeReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let endpoint = provider.serviceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let executionMode = provider.executionMode.trimmingCharacters(in: .whitespacesAndNewlines)
            return "provider=\(provider.providerID) service_state=\(provider.serviceState) ready=\(provider.ready ? "1" : "0") runtime_reason=\(runtimeReason.isEmpty ? "none" : runtimeReason) endpoint=\(endpoint.isEmpty ? "none" : endpoint) execution_mode=\(executionMode.isEmpty ? "unknown" : executionMode) loaded_instances=\(max(0, provider.loadedInstanceCount)) queued=\(max(0, provider.queuedTaskCount))"
        }
        let summaryLines = [
            "ready_providers=\(readyProviders.isEmpty ? "none" : readyProviders.joined(separator: ","))",
            "managed_service_ready_count=\(max(0, readyProviderCount))",
            "provider_count=\(max(0, providerCount))",
            "managed_service_provider_count=\(max(0, providerCount))",
        ]
        let preferredLines = providerLines.isEmpty
            ? summaryLines
            : [summaryLines[0], providerLines[0]] + Array(summaryLines.dropFirst())
        return Array(preferredLines.prefix(max(0, limit)))
    }
}

extension XHubLocalServiceRecoveryGuidanceReport {
    var primaryFailureCode: String {
        let failureCode = currentFailureCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !failureCode.isEmpty {
            return failureCode
        }
        return primaryIssue?.reasonCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var topRecommendedActionSummary: String {
        guard let action = recommendedActions.sorted(by: { lhs, rhs in
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }).first else {
            return ""
        }

        let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let ref = action.commandOrReference.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty {
            return ref
        }
        if ref.isEmpty || title.contains(ref) {
            return title
        }
        return "\(title) | \(ref)"
    }

    var topSupportFAQSummary: String {
        guard let item = supportFAQ.first else { return "" }
        let question = item.question.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = item.answer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (question.isEmpty, answer.isEmpty) {
        case (false, false):
            return "Q: \(question) A: \(answer)"
        case (false, true):
            return "Q: \(question)"
        case (true, false):
            return "A: \(answer)"
        default:
            return ""
        }
    }

    func preferredDetailLines(limit: Int = 2) -> [String] {
        let serviceBaseLine = [
            "managed_service_ready_count=\(max(0, readyProviderCount))",
            "provider_count=\(max(0, providerCount))",
            "service_base_url=\(serviceBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none" : serviceBaseURL)",
            "managed_process_state=\(managedProcessState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "unknown" : managedProcessState)",
            "managed_start_attempt_count=\(max(0, managedStartAttemptCount))",
        ].joined(separator: " ")
        let blockedLine: String? = {
            guard !blockedCapabilities.isEmpty else { return nil }
            return "blocked_capabilities=\(blockedCapabilities.joined(separator: ","))"
        }()
        let errorLine: String? = {
            let lastStartError = managedLastStartError.trimmingCharacters(in: .whitespacesAndNewlines)
            let lastProbeError = managedLastProbeError.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lastStartError.isEmpty || !lastProbeError.isEmpty else { return nil }
            return "managed_last_start_error=\(lastStartError.isEmpty ? "none" : lastStartError) managed_last_probe_error=\(lastProbeError.isEmpty ? "none" : lastProbeError)"
        }()

        let candidates = [serviceBaseLine, blockedLine, errorLine]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(candidates.prefix(max(0, limit)))
    }
}

extension XHubLocalRuntimeMonitorSnapshotReport {
    func preferredSystemMetricsLine() -> String? {
        let trimmed = hostMetrics?.machineSummaryLine.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func preferredLoadConfigLine() -> String? {
        if let target = runtimeOperations?.currentTargets.first {
            let loadSummary = target.loadSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loadSummary.isEmpty else { return nil }
            let provider = target.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return "current_target=\(target.modelID) provider=\(provider.isEmpty ? "unknown" : provider) load_summary=\(loadSummary)"
        }
        if let instance = runtimeOperations?.loadedInstances.first {
            let loadSummary = instance.loadSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !loadSummary.isEmpty else { return nil }
            let provider = instance.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            return "loaded_instance=\(instance.modelID) provider=\(provider.isEmpty ? "unknown" : provider) load_summary=\(loadSummary)"
        }
        return nil
    }

    func preferredDetailLines(limit: Int = 2) -> [String] {
        var lines: [String] = []
        if let systemMetricsLine = preferredSystemMetricsLine() {
            lines.append(systemMetricsLine)
        }
        if let loadConfigLine = preferredLoadConfigLine() {
            lines.append(loadConfigLine)
        }
        let trimmedLoadedSummary = runtimeOperations?.loadedSummary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedLoadedSummary.isEmpty {
            lines.append("runtime_loaded_summary=\(trimmedLoadedSummary)")
        }

        if lines.isEmpty {
            let fallback = monitorSummary
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            lines.append(contentsOf: fallback.prefix(max(0, limit)))
        }

        var unique: [String] = []
        for line in lines where !unique.contains(line) {
            unique.append(line)
        }
        return Array(unique.prefix(max(0, limit)))
    }
}

private extension XHubDoctorOutputSummary {
    init(headline: String, checks: [XHubDoctorOutputCheckResult]) {
        self.init(
            headline: headline,
            passed: checks.filter { $0.status == .pass }.count,
            failed: checks.filter { $0.status == .fail }.count,
            warned: checks.filter { $0.status == .warn }.count,
            skipped: checks.filter { $0.status == .skip }.count
        )
    }
}

private func xHubDoctorOutputDetailValue(
    _ key: String,
    from detailLines: [String]
) -> String? {
    let prefix = "\(key)="
    guard let line = detailLines.first(where: { $0.hasPrefix(prefix) }) else {
        return nil
    }
    return String(line.dropFirst(prefix.count))
}

private func xHubDoctorOutputOptionalBoolValue(
    _ key: String,
    from detailLines: [String]
) -> Bool? {
    guard let raw = xHubDoctorOutputDetailValue(key, from: detailLines)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() else {
        return nil
    }
    switch raw {
    case "1", "true", "yes":
        return true
    case "0", "false", "no":
        return false
    default:
        return nil
    }
}

private func xHubDoctorOutputOptionalIntValue(
    _ key: String,
    from detailLines: [String]
) -> Int? {
    guard let raw = xHubDoctorOutputDetailValue(key, from: detailLines)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty,
        let value = Int(raw) else {
        return nil
    }
    return value
}

private func xHubDoctorOutputOptionalInt64Value(
    _ key: String,
    from detailLines: [String]
) -> Int64? {
    guard let raw = xHubDoctorOutputDetailValue(key, from: detailLines)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !raw.isEmpty,
        let value = Int64(raw) else {
        return nil
    }
    return value
}

private func xHubDoctorOutputRemoteSnapshotHasEvidence(
    freshness: String?,
    cacheHit: Bool?,
    scope: String?,
    cachedAtMs: Int64?,
    ageMs: Int?,
    ttlRemainingMs: Int?
) -> Bool {
    let freshnessText = freshness?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let scopeText = scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return !freshnessText.isEmpty
        || cacheHit != nil
        || !scopeText.isEmpty
        || cachedAtMs != nil
        || ageMs != nil
        || ttlRemainingMs != nil
}

private func xHubDoctorOutputRemoteSnapshotUpstreamTruthClass(
    source: String?,
    freshness: String?,
    cacheHit: Bool?,
    scope: String?,
    cachedAtMs: Int64?,
    ageMs: Int?,
    ttlRemainingMs: Int?
) -> String? {
    guard xHubDoctorOutputRemoteSnapshotHasEvidence(
        freshness: freshness,
        cacheHit: cacheHit,
        scope: scope,
        cachedAtMs: cachedAtMs,
        ageMs: ageMs,
        ttlRemainingMs: ttlRemainingMs
    ) else {
        return nil
    }

    switch XTMemorySourceTruthPresentation.sourceClass(source) {
    case "hub_truth", "hub_snapshot_plus_local_overlay":
        return "hub_durable_truth"
    default:
        return "unknown_upstream_truth"
    }
}

private func xHubDoctorOutputRemoteSnapshotCacheRole(
    freshness: String?,
    cacheHit: Bool?,
    scope: String?,
    cachedAtMs: Int64?,
    ageMs: Int?,
    ttlRemainingMs: Int?
) -> String? {
    guard xHubDoctorOutputRemoteSnapshotHasEvidence(
        freshness: freshness,
        cacheHit: cacheHit,
        scope: scope,
        cachedAtMs: cachedAtMs,
        ageMs: ageMs,
        ttlRemainingMs: ttlRemainingMs
    ) else {
        return nil
    }
    return "xt_remote_snapshot_ttl_cache"
}

private func xHubDoctorOutputRemoteSnapshotProvenanceLabel(
    source: String?,
    freshness: String?,
    cacheHit: Bool?,
    scope: String?,
    cachedAtMs: Int64?,
    ageMs: Int?,
    ttlRemainingMs: Int?
) -> String? {
    guard let upstreamTruthClass = xHubDoctorOutputRemoteSnapshotUpstreamTruthClass(
        source: source,
        freshness: freshness,
        cacheHit: cacheHit,
        scope: scope,
        cachedAtMs: cachedAtMs,
        ageMs: ageMs,
        ttlRemainingMs: ttlRemainingMs
    ) else {
        return nil
    }

    let normalizedFreshness = freshness?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased() ?? ""
    if upstreamTruthClass == "hub_durable_truth" {
        if normalizedFreshness == "ttl_cache" || cacheHit == true {
            return "hub_durable_truth_via_xt_ttl_cache"
        }
        if !normalizedFreshness.isEmpty || cacheHit == false {
            return "hub_durable_truth_fresh_fetch"
        }
        return "hub_durable_truth"
    }
    return "xt_ttl_cache_unknown_upstream"
}

private func xHubDoctorOutputProjectContinuitySourceClass(
    memorySource: String?,
    memoryFreshness: String?,
    memoryCacheHit: Bool?,
    automationContextSource: String?,
    remoteSnapshotProvenanceLabel: String?
) -> String? {
    let normalizedAutomationContextSource = automationContextSource?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalizedRemoteSnapshotProvenanceLabel = remoteSnapshotProvenanceLabel?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let sourceClass = XTMemorySourceTruthPresentation.sourceClass(memorySource)

    let baseClass: String? = {
        if !normalizedRemoteSnapshotProvenanceLabel.isEmpty {
            return normalizedRemoteSnapshotProvenanceLabel
        }
        switch sourceClass {
        case "hub_truth":
            return "hub_durable_truth_fresh_fetch"
        case "hub_snapshot_plus_local_overlay":
            let normalizedFreshness = memoryFreshness?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            if normalizedFreshness == "ttl_cache" || memoryCacheHit == true {
                return "hub_durable_truth_via_xt_ttl_cache"
            }
            return "hub_snapshot_plus_local_overlay"
        case "local_fallback":
            return "xt_local_fallback"
        case "local_truth":
            return "xt_local_truth"
        case "local_cache":
            return "xt_local_cache_view"
        case "disabled":
            return "disabled"
        case "unavailable":
            return "unavailable"
        default:
            return nil
        }
    }()

    guard !normalizedAutomationContextSource.isEmpty || baseClass != nil else {
        return nil
    }
    guard !normalizedAutomationContextSource.isEmpty else {
        return baseClass
    }
    guard let baseClass else {
        return "local_runtime_rehydration"
    }
    return "local_runtime_rehydration_with_\(baseClass)"
}

private func xHubDoctorOutputDecodeJSONString<T: Decodable>(
    _ type: T.Type,
    jsonString: String?
) -> T? {
    guard let jsonString,
          let data = jsonString.data(using: .utf8) else {
        return nil
    }
    return try? JSONDecoder().decode(T.self, from: data)
}

private extension XHubDoctorOutputCheckResult {
    init(section: XTUnifiedDoctorSection, observedAtMs: Int64) {
        let status = XHubDoctorCheckStatus(surfaceState: section.state)
        let projectRemoteSnapshotCacheSnapshot = section.projectRemoteSnapshotCacheProjection
            .map(XHubDoctorOutputRemoteSnapshotCacheSnapshot.init)
            ?? XHubDoctorOutputRemoteSnapshotCacheSnapshot(
                section: section,
                sourceKey: "project_memory_v1_source",
                freshnessKey: "memory_v1_freshness",
                cacheHitKey: "memory_v1_cache_hit",
                scopeKey: "memory_v1_remote_snapshot_cache_scope",
                cachedAtMsKey: "memory_v1_remote_snapshot_cached_at_ms",
                ageMsKey: "memory_v1_remote_snapshot_age_ms",
                ttlRemainingMsKey: "memory_v1_remote_snapshot_ttl_remaining_ms"
            )
        let supervisorRemoteSnapshotCacheSnapshot = section.supervisorRemoteSnapshotCacheProjection
            .map(XHubDoctorOutputRemoteSnapshotCacheSnapshot.init)
            ?? XHubDoctorOutputRemoteSnapshotCacheSnapshot(
                section: section,
                sourceKey: "memory_source",
                freshnessKey: "memory_freshness",
                cacheHitKey: "memory_cache_hit",
                scopeKey: "remote_snapshot_cache_scope",
                cachedAtMsKey: "remote_snapshot_cached_at_ms",
                ageMsKey: "remote_snapshot_age_ms",
                ttlRemainingMsKey: "remote_snapshot_ttl_remaining_ms"
            )
        self.init(
            checkID: section.kind.rawValue,
            checkKind: section.kind.rawValue,
            status: status,
            severity: XHubDoctorSeverity(surfaceState: section.state),
            blocking: status == .fail,
            headline: section.headline,
            message: section.summary,
            nextStep: section.nextStep,
            repairDestinationRef: section.repairEntry.rawValue,
            detailLines: section.detailLines,
            projectContextSummary: XHubDoctorOutputProjectContextSummary(section: section),
            projectGovernanceRuntimeReadiness: section.projectGovernanceRuntimeReadinessProjection
                ?? AXProjectGovernanceRuntimeReadinessSnapshot(detailLines: section.detailLines),
            projectMemoryPolicy: section.projectMemoryPolicyProjection ?? xHubDoctorOutputDecodeJSONString(
                XTProjectMemoryPolicySnapshot.self,
                jsonString: xHubDoctorOutputDetailValue(
                    "project_memory_policy_json",
                    from: section.detailLines
                )
            ),
            projectMemoryReadiness: section.projectMemoryReadinessProjection
                ?? XTProjectMemoryAssemblyReadiness.from(detailLines: section.detailLines),
            projectMemoryAssemblyResolution: section.projectMemoryAssemblyResolutionProjection ?? xHubDoctorOutputDecodeJSONString(
                XTMemoryAssemblyResolution.self,
                jsonString: xHubDoctorOutputDetailValue(
                    "project_memory_assembly_resolution_json",
                    from: section.detailLines
                )
            ),
            supervisorMemoryPolicy: section.supervisorMemoryPolicyProjection ?? xHubDoctorOutputDecodeJSONString(
                XTSupervisorMemoryPolicySnapshot.self,
                jsonString: xHubDoctorOutputDetailValue(
                    "supervisor_memory_policy_json",
                    from: section.detailLines
                )
            ),
            supervisorMemoryAssemblyResolution: section.supervisorMemoryAssemblyResolutionProjection ?? xHubDoctorOutputDecodeJSONString(
                XTMemoryAssemblyResolution.self,
                jsonString: xHubDoctorOutputDetailValue(
                    "supervisor_memory_assembly_resolution_json",
                    from: section.detailLines
                )
            ),
            supervisorReviewTriggerSnapshot: section.supervisorReviewTriggerProjection
                ?? XTUnifiedDoctorSupervisorReviewTriggerProjection.from(
                    detailLines: section.detailLines
                ),
            supervisorGuidanceContinuitySnapshot: section.supervisorGuidanceContinuityProjection
                ?? XTUnifiedDoctorSupervisorGuidanceContinuityProjection.from(
                    detailLines: section.detailLines
                ),
            supervisorSafePointTimelineSnapshot: section.supervisorSafePointTimelineProjection
                ?? XTUnifiedDoctorSupervisorSafePointTimelineProjection.from(
                    detailLines: section.detailLines
                ),
            projectRemoteSnapshotCacheSnapshot: projectRemoteSnapshotCacheSnapshot,
            supervisorRemoteSnapshotCacheSnapshot: supervisorRemoteSnapshotCacheSnapshot,
            projectAutomationContinuitySnapshot: XHubDoctorOutputProjectAutomationContinuitySnapshot(
                section: section,
                projectRemoteSnapshotCacheSnapshot: projectRemoteSnapshotCacheSnapshot
            ),
            heartbeatGovernanceSnapshot: XHubDoctorOutputHeartbeatGovernanceSnapshot(section: section),
            hubMemoryPromptProjection: section.hubMemoryPromptProjection
                ?? HubMemoryPromptProjectionSnapshot.fromDoctorDetailLines(section.detailLines),
            observedAtMs: observedAtMs,
            memoryRouteTruthSnapshot: XHubDoctorOutputMemoryRouteTruthSnapshot(section: section),
            durableCandidateMirrorSnapshot: XHubDoctorOutputDurableCandidateMirrorSnapshot(section: section),
            localStoreWriteSnapshot: XHubDoctorOutputLocalStoreWriteSnapshot(section: section),
            skillDoctorTruthSnapshot: section.skillDoctorTruthProjection,
            freshPairReconnectSmokeSnapshot: XHubDoctorOutputFreshPairReconnectSmokeSnapshot(section: section)
        )
    }
}

private extension XHubDoctorOutputProjectContextSummary {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let presentation = section.projectContextPresentation {
            self.init(presentation)
            return
        }
        guard let presentation = AXProjectContextAssemblyPresentation.from(detailLines: section.detailLines) else {
            return nil
        }
        self.init(presentation)
    }

    init(_ presentation: AXProjectContextAssemblyPresentation) {
        self.init(
            sourceKind: presentation.sourceKind.rawValue,
            sourceBadge: presentation.sourceBadge,
            projectLabel: presentation.projectLabel,
            statusLine: presentation.statusLine,
            dialogueMetric: presentation.dialogueMetric,
            depthMetric: presentation.depthMetric,
            coverageMetric: presentation.coverageMetric,
            boundaryMetric: presentation.boundaryMetric,
            dialogueLine: presentation.dialogueLine,
            depthLine: presentation.depthLine,
            coverageLine: presentation.coverageLine,
            boundaryLine: presentation.boundaryLine,
            planeLine: presentation.planeLine,
            assemblyLine: presentation.assemblyLine,
            omissionLine: presentation.omissionLine,
            budgetLine: presentation.budgetLine
        )
    }
}

private extension XHubDoctorOutputRemoteSnapshotCacheSnapshot {
    init(_ projection: XTUnifiedDoctorRemoteSnapshotCacheProjection) {
        let upstreamTruthClass = xHubDoctorOutputRemoteSnapshotUpstreamTruthClass(
            source: projection.source,
            freshness: projection.freshness,
            cacheHit: projection.cacheHit,
            scope: projection.scope,
            cachedAtMs: projection.cachedAtMs,
            ageMs: projection.ageMs,
            ttlRemainingMs: projection.ttlRemainingMs
        )
        let cacheRole = xHubDoctorOutputRemoteSnapshotCacheRole(
            freshness: projection.freshness,
            cacheHit: projection.cacheHit,
            scope: projection.scope,
            cachedAtMs: projection.cachedAtMs,
            ageMs: projection.ageMs,
            ttlRemainingMs: projection.ttlRemainingMs
        )
        self.init(
            source: projection.source,
            freshness: projection.freshness,
            cacheHit: projection.cacheHit,
            scope: projection.scope,
            cachedAtMs: projection.cachedAtMs,
            ageMs: projection.ageMs,
            ttlRemainingMs: projection.ttlRemainingMs,
            upstreamTruthClass: upstreamTruthClass,
            cacheRole: cacheRole,
            provenanceLabel: xHubDoctorOutputRemoteSnapshotProvenanceLabel(
                source: projection.source,
                freshness: projection.freshness,
                cacheHit: projection.cacheHit,
                scope: projection.scope,
                cachedAtMs: projection.cachedAtMs,
                ageMs: projection.ageMs,
                ttlRemainingMs: projection.ttlRemainingMs
            )
        )
    }

    init?(
        section: XTUnifiedDoctorSection,
        sourceKey: String,
        freshnessKey: String,
        cacheHitKey: String,
        scopeKey: String,
        cachedAtMsKey: String,
        ageMsKey: String,
        ttlRemainingMsKey: String
    ) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        let source = xHubDoctorOutputDetailValue(sourceKey, from: section.detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let freshness = xHubDoctorOutputDetailValue(freshnessKey, from: section.detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheHit = xHubDoctorOutputOptionalBoolValue(cacheHitKey, from: section.detailLines)
        let scope = xHubDoctorOutputDetailValue(scopeKey, from: section.detailLines)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedAtMs = xHubDoctorOutputOptionalInt64Value(cachedAtMsKey, from: section.detailLines)
        let ageMs = xHubDoctorOutputOptionalIntValue(ageMsKey, from: section.detailLines)
        let ttlRemainingMs = xHubDoctorOutputOptionalIntValue(ttlRemainingMsKey, from: section.detailLines)

        guard xHubDoctorOutputRemoteSnapshotHasEvidence(
            freshness: freshness,
            cacheHit: cacheHit,
            scope: scope,
            cachedAtMs: cachedAtMs,
            ageMs: ageMs,
            ttlRemainingMs: ttlRemainingMs
        ) else {
            return nil
        }

        let upstreamTruthClass = xHubDoctorOutputRemoteSnapshotUpstreamTruthClass(
            source: source,
            freshness: freshness,
            cacheHit: cacheHit,
            scope: scope,
            cachedAtMs: cachedAtMs,
            ageMs: ageMs,
            ttlRemainingMs: ttlRemainingMs
        )
        let cacheRole = xHubDoctorOutputRemoteSnapshotCacheRole(
            freshness: freshness,
            cacheHit: cacheHit,
            scope: scope,
            cachedAtMs: cachedAtMs,
            ageMs: ageMs,
            ttlRemainingMs: ttlRemainingMs
        )
        self.init(
            source: source?.isEmpty == true ? nil : source,
            freshness: freshness?.isEmpty == true ? nil : freshness,
            cacheHit: cacheHit,
            scope: scope?.isEmpty == true ? nil : scope,
            cachedAtMs: cachedAtMs,
            ageMs: ageMs,
            ttlRemainingMs: ttlRemainingMs,
            upstreamTruthClass: upstreamTruthClass,
            cacheRole: cacheRole,
            provenanceLabel: xHubDoctorOutputRemoteSnapshotProvenanceLabel(
                source: source,
                freshness: freshness,
                cacheHit: cacheHit,
                scope: scope,
                cachedAtMs: cachedAtMs,
                ageMs: ageMs,
                ttlRemainingMs: ttlRemainingMs
            )
        )
    }
}

private extension XHubDoctorOutputProjectAutomationContinuitySnapshot {
    init?(
        section: XTUnifiedDoctorSection,
        projectRemoteSnapshotCacheSnapshot: XHubDoctorOutputRemoteSnapshotCacheSnapshot?
    ) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }

        let automationContextSource = xHubDoctorOutputDetailValue(
            "project_memory_automation_context_source",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let memorySource = xHubDoctorOutputDetailValue(
            "project_memory_v1_source",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let memorySourceClass = xHubDoctorOutputDetailValue(
            "project_memory_v1_source_class",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? {
                let normalized = memorySource?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return normalized.isEmpty ? nil : XTMemorySourceTruthPresentation.sourceClass(normalized)
            }()
        let memoryFreshness = xHubDoctorOutputDetailValue(
            "memory_v1_freshness",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let memoryCacheHit = xHubDoctorOutputOptionalBoolValue(
            "memory_v1_cache_hit",
            from: section.detailLines
        )
        let runID = xHubDoctorOutputDetailValue(
            "project_memory_automation_run_id",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let runState = xHubDoctorOutputDetailValue(
            "project_memory_automation_run_state",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let attempt = xHubDoctorOutputOptionalIntValue(
            "project_memory_automation_attempt",
            from: section.detailLines
        )
        let retryAfterSeconds = xHubDoctorOutputOptionalIntValue(
            "project_memory_automation_retry_after_seconds",
            from: section.detailLines
        )
        let recoverySelection = xHubDoctorOutputDetailValue(
            "project_memory_automation_recovery_selection",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryReason = xHubDoctorOutputDetailValue(
            "project_memory_automation_recovery_reason",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryDecision = xHubDoctorOutputDetailValue(
            "project_memory_automation_recovery_decision",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryHoldReason = xHubDoctorOutputDetailValue(
            "project_memory_automation_recovery_hold_reason",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveryRetryAfterRemainingSeconds = xHubDoctorOutputOptionalIntValue(
            "project_memory_automation_recovery_retry_after_remaining_seconds",
            from: section.detailLines
        )
        let currentStepID = xHubDoctorOutputDetailValue(
            "project_memory_automation_current_step_id",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentStepTitle = xHubDoctorOutputDetailValue(
            "project_memory_automation_current_step_title",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentStepState = xHubDoctorOutputDetailValue(
            "project_memory_automation_current_step_state",
            from: section.detailLines
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let verificationContract = xHubDoctorOutputDecodeJSONString(
            XTAutomationVerificationContract.self,
            jsonString: xHubDoctorOutputDetailValue(
                "project_memory_automation_verification_contract_json",
                from: section.detailLines
            )
        )
        let retryVerificationContract = xHubDoctorOutputDecodeJSONString(
            XTAutomationVerificationContract.self,
            jsonString: xHubDoctorOutputDetailValue(
                "project_memory_automation_retry_verification_contract_json",
                from: section.detailLines
            )
        )
        let verificationPresent = xHubDoctorOutputOptionalBoolValue(
            "project_memory_automation_verification_present",
            from: section.detailLines
        )
        let blockerPresent = xHubDoctorOutputOptionalBoolValue(
            "project_memory_automation_blocker_present",
            from: section.detailLines
        )
        let retryReasonPresent = xHubDoctorOutputOptionalBoolValue(
            "project_memory_automation_retry_reason_present",
            from: section.detailLines
        )
        let remoteSnapshotProvenanceLabel = projectRemoteSnapshotCacheSnapshot?.provenanceLabel
        let continuitySourceClass = xHubDoctorOutputProjectContinuitySourceClass(
            memorySource: memorySource,
            memoryFreshness: memoryFreshness,
            memoryCacheHit: memoryCacheHit,
            automationContextSource: automationContextSource,
            remoteSnapshotProvenanceLabel: remoteSnapshotProvenanceLabel
        )

        guard continuitySourceClass != nil
                || !(automationContextSource ?? "").isEmpty
                || !(memorySource ?? "").isEmpty
                || !(memorySourceClass ?? "").isEmpty
                || !(memoryFreshness ?? "").isEmpty
                || memoryCacheHit != nil
                || remoteSnapshotProvenanceLabel != nil
                || !(runID ?? "").isEmpty
                || !(runState ?? "").isEmpty
                || attempt != nil
                || retryAfterSeconds != nil
                || !(recoverySelection ?? "").isEmpty
                || !(recoveryReason ?? "").isEmpty
                || !(recoveryDecision ?? "").isEmpty
                || !(recoveryHoldReason ?? "").isEmpty
                || recoveryRetryAfterRemainingSeconds != nil
                || !(currentStepID ?? "").isEmpty
                || !(currentStepTitle ?? "").isEmpty
                || !(currentStepState ?? "").isEmpty
                || verificationContract != nil
                || retryVerificationContract != nil
                || verificationPresent != nil
                || blockerPresent != nil
                || retryReasonPresent != nil else {
            return nil
        }

        self.init(
            continuitySourceClass: continuitySourceClass,
            automationContextSource: automationContextSource?.isEmpty == true ? nil : automationContextSource,
            memorySource: memorySource?.isEmpty == true ? nil : memorySource,
            memorySourceClass: memorySourceClass?.isEmpty == true ? nil : memorySourceClass,
            memoryFreshness: memoryFreshness?.isEmpty == true ? nil : memoryFreshness,
            memoryCacheHit: memoryCacheHit,
            remoteSnapshotProvenanceLabel: remoteSnapshotProvenanceLabel,
            runID: runID?.isEmpty == true ? nil : runID,
            runState: runState?.isEmpty == true ? nil : runState,
            attempt: attempt,
            retryAfterSeconds: retryAfterSeconds,
            recoverySelection: recoverySelection?.isEmpty == true ? nil : recoverySelection,
            recoveryReason: recoveryReason?.isEmpty == true ? nil : recoveryReason,
            recoveryDecision: recoveryDecision?.isEmpty == true ? nil : recoveryDecision,
            recoveryHoldReason: recoveryHoldReason?.isEmpty == true ? nil : recoveryHoldReason,
            recoveryRetryAfterRemainingSeconds: recoveryRetryAfterRemainingSeconds,
            currentStepID: currentStepID?.isEmpty == true ? nil : currentStepID,
            currentStepTitle: currentStepTitle?.isEmpty == true ? nil : currentStepTitle,
            currentStepState: currentStepState?.isEmpty == true ? nil : currentStepState,
            verificationContract: verificationContract,
            retryVerificationContract: retryVerificationContract,
            verificationPresent: verificationPresent,
            blockerPresent: blockerPresent,
            retryReasonPresent: retryReasonPresent
        )
    }
}

private extension XHubDoctorOutputHeartbeatGovernanceSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let projection = section.heartbeatGovernanceProjection {
            self.init(projection)
            return
        }
        guard let projection = XTUnifiedDoctorHeartbeatGovernanceProjection.from(
            detailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(projection)
    }

    init(_ projection: XTUnifiedDoctorHeartbeatGovernanceProjection) {
        let latestQualityBandDisplayText = xhubDoctorHeartbeatQualityBandText(
            projection.latestQualityBand
        )
        let weakReasonDisplayTexts = xhubDoctorHeartbeatWeakReasonTexts(projection.weakReasons)
        let openAnomalyDisplayTexts = xhubDoctorHeartbeatAnomalyTypeTexts(projection.openAnomalyTypes)
        let projectPhaseDisplayText = xhubDoctorHeartbeatProjectPhaseText(projection.projectPhase)
        let executionStatusDisplayText = xhubDoctorHeartbeatExecutionStatusText(
            projection.executionStatus
        )
        let riskTierDisplayText = xhubDoctorHeartbeatRiskTierText(projection.riskTier)
        let digestVisibilityDisplayText = xhubDoctorHeartbeatDigestVisibilityText(
            projection.digestVisibility
        )
        let digestReasonDisplayTexts = xhubDoctorHeartbeatDigestReasonTexts(
            projection.digestReasonCodes
        )
        let recoveryDecision: XHubDoctorOutputHeartbeatRecoverySnapshot?
        if let decision = projection.recoveryDecision {
            recoveryDecision = XHubDoctorOutputHeartbeatRecoverySnapshot(decision)
        } else {
            recoveryDecision = nil
        }
        self.init(
            projectId: projection.projectId,
            projectName: projection.projectName,
            statusDigest: projection.statusDigest,
            currentStateSummary: projection.currentStateSummary,
            nextStepSummary: projection.nextStepSummary,
            blockerSummary: projection.blockerSummary,
            lastHeartbeatAtMs: projection.lastHeartbeatAtMs,
            latestQualityBand: projection.latestQualityBand,
            latestQualityBandDisplayText: latestQualityBandDisplayText,
            latestQualityScore: projection.latestQualityScore,
            weakReasons: projection.weakReasons,
            weakReasonDisplayTexts: weakReasonDisplayTexts,
            openAnomalyTypes: projection.openAnomalyTypes,
            openAnomalyDisplayTexts: openAnomalyDisplayTexts,
            projectPhase: projection.projectPhase,
            projectPhaseDisplayText: projectPhaseDisplayText,
            executionStatus: projection.executionStatus,
            executionStatusDisplayText: executionStatusDisplayText,
            riskTier: projection.riskTier,
            riskTierDisplayText: riskTierDisplayText,
            digestVisibility: projection.digestVisibility,
            digestVisibilityDisplayText: digestVisibilityDisplayText,
            digestReasonCodes: projection.digestReasonCodes,
            digestReasonDisplayTexts: digestReasonDisplayTexts,
            digestWhatChangedText: projection.digestWhatChangedText,
            digestWhyImportantText: projection.digestWhyImportantText,
            digestSystemNextStepText: projection.digestSystemNextStepText,
            progressHeartbeat: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot(projection.progressHeartbeat),
            reviewPulse: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot(projection.reviewPulse),
            brainstormReview: XHubDoctorOutputHeartbeatCadenceDimensionSnapshot(projection.brainstormReview),
            nextReviewDue: XHubDoctorOutputHeartbeatNextReviewDueSnapshot(projection.nextReviewDue),
            recoveryDecision: recoveryDecision,
            projectMemoryReady: projection.projectMemoryReady,
            projectMemoryStatusLine: projection.projectMemoryStatusLine,
            projectMemoryIssueCodes: projection.projectMemoryIssueCodes,
            projectMemoryTopIssueSummary: projection.projectMemoryTopIssueSummary
        )
    }
}

private extension XHubDoctorOutputHeartbeatCadenceDimensionSnapshot {
    init(_ projection: XTUnifiedDoctorHeartbeatCadenceDimensionProjection) {
        let dimensionDisplayText = xhubDoctorHeartbeatCadenceDimensionText(projection.dimension)
        let effectiveReasonDisplayTexts = xhubDoctorHeartbeatCadenceReasonTexts(
            projection.effectiveReasonCodes
        )
        let nextDueReasonDisplayTexts = xhubDoctorHeartbeatCadenceReasonTexts(
            projection.nextDueReasonCodes
        )
        self.init(
            dimension: projection.dimension,
            dimensionDisplayText: dimensionDisplayText,
            configuredSeconds: projection.configuredSeconds,
            recommendedSeconds: projection.recommendedSeconds,
            effectiveSeconds: projection.effectiveSeconds,
            effectiveReasonCodes: projection.effectiveReasonCodes,
            effectiveReasonDisplayTexts: effectiveReasonDisplayTexts,
            nextDueAtMs: projection.nextDueAtMs,
            nextDueReasonCodes: projection.nextDueReasonCodes,
            nextDueReasonDisplayTexts: nextDueReasonDisplayTexts,
            isDue: projection.isDue
        )
    }
}

private extension XHubDoctorOutputHeartbeatNextReviewDueSnapshot {
    init(_ projection: XTUnifiedDoctorHeartbeatNextReviewDueProjection) {
        let kindDisplayText: String?
        if let kind = projection.kind {
            kindDisplayText = xhubDoctorHeartbeatCadenceDimensionText(kind)
        } else {
            kindDisplayText = nil
        }
        let reasonDisplayTexts = xhubDoctorHeartbeatCadenceReasonTexts(
            projection.reasonCodes
        )
        self.init(
            kind: projection.kind,
            kindDisplayText: kindDisplayText,
            due: projection.due,
            atMs: projection.atMs,
            reasonCodes: projection.reasonCodes,
            reasonDisplayTexts: reasonDisplayTexts
        )
    }
}

private func xhubDoctorHeartbeatCadenceDimensionText(_ raw: String) -> String {
    switch raw {
    case SupervisorCadenceDimension.progressHeartbeat.rawValue:
        return "进度心跳"
    case SupervisorCadenceDimension.reviewPulse.rawValue:
        return "脉冲复盘"
    case SupervisorCadenceDimension.brainstormReview.rawValue:
        return "无进展复盘"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatQualityBandText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatQualityBand.strong.rawValue:
        return "强"
    case HeartbeatQualityBand.usable.rawValue:
        return "可用"
    case HeartbeatQualityBand.weak.rawValue:
        return "偏弱"
    case HeartbeatQualityBand.hollow.rawValue:
        return "空转"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatProjectPhaseText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatProjectPhase.explore.rawValue:
        return "探索"
    case HeartbeatProjectPhase.plan.rawValue:
        return "规划"
    case HeartbeatProjectPhase.build.rawValue:
        return "构建"
    case HeartbeatProjectPhase.verify.rawValue:
        return "验证"
    case HeartbeatProjectPhase.release.rawValue:
        return "发布"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatExecutionStatusText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatExecutionStatus.active.rawValue:
        return "推进中"
    case HeartbeatExecutionStatus.blocked.rawValue:
        return "已阻塞"
    case HeartbeatExecutionStatus.stalled.rawValue:
        return "停滞"
    case HeartbeatExecutionStatus.doneCandidate.rawValue:
        return "完成候选"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatRiskTierText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatRiskTier.low.rawValue:
        return "低"
    case HeartbeatRiskTier.medium.rawValue:
        return "中"
    case HeartbeatRiskTier.high.rawValue:
        return "高"
    case HeartbeatRiskTier.critical.rawValue:
        return "极高"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatDigestVisibilityText(_ raw: String) -> String? {
    switch raw {
    case XTHeartbeatDigestVisibilityDecision.shown.rawValue:
        return "显示给用户"
    case XTHeartbeatDigestVisibilityDecision.suppressed.rawValue:
        return "当前压制"
    default:
        return raw.isEmpty ? nil : raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatWeakReasonTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatWeakReasonText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatWeakReasonText(_ raw: String) -> String {
    switch raw {
    case "freshness_low":
        return "新鲜度偏低"
    case "delta_low":
        return "变化量偏低"
    case "evidence_weak":
        return "证据偏弱"
    case "blocker_unclear":
        return "blocker 描述不清"
    case "next_action_generic":
        return "下一步过于泛化"
    case "execution_vitality_low":
        return "执行活性偏低"
    case "completion_confidence_low":
        return "完成把握偏低"
    case "project_memory_attention":
        return "Project memory 需要关注"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatAnomalyTypeTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatAnomalyTypeText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatAnomalyTypeText(_ raw: String) -> String {
    switch raw {
    case HeartbeatAnomalyType.missingHeartbeat.rawValue:
        return "缺失 heartbeat"
    case HeartbeatAnomalyType.staleRepeat.rawValue:
        return "重复心跳 / 无新进展"
    case HeartbeatAnomalyType.hollowProgress.rawValue:
        return "空转推进"
    case HeartbeatAnomalyType.queueStall.rawValue:
        return "队列停滞"
    case HeartbeatAnomalyType.weakBlocker.rawValue:
        return "弱 blocker"
    case HeartbeatAnomalyType.weakDoneClaim.rawValue:
        return "完成声明证据偏弱"
    case HeartbeatAnomalyType.routeFlaky.rawValue:
        return "route 波动"
    case HeartbeatAnomalyType.silentLane.rawValue:
        return "lane 静默"
    case HeartbeatAnomalyType.driftSuspected.rawValue:
        return "疑似偏航"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatDigestReasonTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatDigestReasonText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatDigestReasonText(_ raw: String) -> String {
    switch raw {
    case "blocker_present":
        return "当前存在 blocker"
    case HeartbeatAnomalyType.weakDoneClaim.rawValue:
        return "完成声明证据偏弱"
    case HeartbeatAnomalyType.missingHeartbeat.rawValue:
        return "最近 heartbeat 超出预期窗口"
    case "open_anomalies_present":
        return "存在未关闭异常"
    case "review_candidate_active":
        return "当前有待执行复盘候选"
    case "next_review_window_active":
        return "当前 review 窗口已到"
    case "recovery_decision_active":
        return "当前已有恢复或补救决策"
    case "risk_high":
        return "当前项目风险偏高"
    case "quality_weak":
        return "heartbeat 质量偏弱"
    case "done_candidate_status":
        return "项目已进入 done candidate"
    case "project_memory_attention":
        return "Project memory 需要关注"
    case "stable_runtime_update_suppressed":
        return "当前只是稳定运行更新，暂不打扰用户"
    case "heartbeat_truth_sparse":
        return "当前 heartbeat 真相仍偏稀疏"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatCadenceReasonTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatCadenceReasonText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatCadenceReasonText(_ raw: String) -> String {
    switch raw {
    case "preserve_current_runtime_cadence":
        return "沿用当前运行时治理值"
    case "configured_equals_recommended":
        return "当前配置已经等于协议建议值"
    case "clamped_by_fail_closed_governance":
        return "因 fail-closed 治理收束而降级"
    case "clamped_by_effective_governance_bundle":
        return "运行时有效治理先做了收束"
    case "clamped_to_protocol_recommended":
        return "按当前 A/S 与治理态收紧到协议建议值"
    case "adjusted_for_project_phase_explore":
        return "因项目处于 explore 阶段而放松到更合适的观察节奏"
    case "adjusted_for_project_phase_plan":
        return "因项目处于 plan 阶段而放松到更合适的规划节奏"
    case "adjusted_for_project_phase_build":
        return "因项目进入 build 阶段而收紧到更密的推进节奏"
    case "adjusted_for_project_phase_verify", "adjusted_for_verification_phase":
        return "因项目进入 verify 阶段而收紧到更密的验证节奏"
    case "adjusted_for_project_phase_release":
        return "因项目进入 release 阶段而收紧到更密的交付节奏"
    case "tightened_for_low_execution_confidence":
        return "因执行把握偏弱或 heartbeat 质量偏弱而进一步收紧"
    case "tightened_for_rescue_or_high_anomaly":
        return "因高严重度异常或救援态而进一步收紧"
    case "tightened_for_high_project_risk":
        return "因项目风险升高而进一步收紧"
    case "tightened_for_critical_project_risk":
        return "因项目处于 critical 风险而进一步收紧"
    case "tightened_for_blocked_execution_status":
        return "因执行已阻塞而进一步收紧"
    case "tightened_for_stalled_execution_status":
        return "因执行出现空转或停滞而进一步收紧"
    case "tightened_for_done_candidate_status":
        return "因进入 done candidate 而进一步收紧完成前复核"
    case "disabled_by_review_policy_off":
        return "当前策略已关闭这条节奏"
    case "disabled_by_review_policy_milestone_only":
        return "里程碑策略下不启用这条节奏"
    case "disabled_by_review_policy_periodic":
        return "周期策略下不启用脑暴复盘"
    case "cadence_disabled":
        return "当前未启用"
    case "awaiting_first_heartbeat":
        return "还没有首个 heartbeat 基线"
    case "awaiting_first_pulse_window":
        return "等待首个脉冲窗口走完"
    case "awaiting_progress_observation":
        return "还没有进展观察基线"
    case "waiting_for_heartbeat_window":
        return "当前 heartbeat 窗口尚未走完"
    case "waiting_for_pulse_window":
        return "当前脉冲窗口尚未走完"
    case "waiting_for_no_progress_window", "waiting_for_brainstorm_window":
        return "当前无进展窗口尚未走完"
    case "waiting_for_review_window":
        return "当前 review 窗口尚未走完"
    case "heartbeat_window_elapsed":
        return "heartbeat 窗口已到"
    case "pulse_review_window_elapsed":
        return "脉冲复盘窗口已到"
    case "no_progress_window_reached":
        return "无进展窗口已到"
    default:
        return raw.replacingOccurrences(of: "_", with: " ")
    }
}

private func xhubDoctorHeartbeatHumanizeToken(_ raw: String) -> String {
    raw.replacingOccurrences(of: "_", with: " ")
}

private extension XHubDoctorOutputHeartbeatRecoverySnapshot {
    convenience init(_ projection: XTUnifiedDoctorHeartbeatRecoveryProjection) {
        let actionDisplayText = xhubDoctorHeartbeatRecoveryActionText(projection.action)
        let urgencyDisplayText = xhubDoctorHeartbeatRecoveryUrgencyText(projection.urgency)
        let reasonDisplayText = xhubDoctorHeartbeatRecoveryReasonText(projection.reasonCode)
        let systemNextStepDisplayText = xhubDoctorHeartbeatRecoverySystemNextStepText(
            action: projection.action,
            failedLaneCount: max(0, projection.failedLaneCount ?? 0),
            blockedLaneReasons: projection.blockedLaneReasons,
            queuedReviewLevel: projection.queuedReviewLevel,
            trigger: projection.queuedReviewTrigger,
            runKind: projection.queuedReviewRunKind
        )
        let doctorExplainabilityText = xhubDoctorHeartbeatRecoveryDoctorExplainabilityText(
            action: projection.action,
            urgency: projection.urgency,
            reasonCode: projection.reasonCode,
            sourceSignals: projection.sourceSignals,
            blockedLaneReasons: projection.blockedLaneReasons,
            failedLaneCount: max(0, projection.failedLaneCount ?? 0),
            requiresUserAction: projection.requiresUserAction ?? false,
            queuedReviewLevel: projection.queuedReviewLevel,
            trigger: projection.queuedReviewTrigger,
            runKind: projection.queuedReviewRunKind
        )
        let sourceSignalDisplayTexts = xhubDoctorHeartbeatRecoverySourceSignalTexts(
            projection.sourceSignals
        )
        let anomalyTypeDisplayTexts = xhubDoctorHeartbeatAnomalyTypeTexts(projection.anomalyTypes)
        let blockedLaneReasonDisplayTexts = xhubDoctorHeartbeatRecoveryBlockedReasonTexts(
            projection.blockedLaneReasons
        )
        let queuedReviewTriggerDisplayText = xhubDoctorHeartbeatRecoveryQueuedReviewTriggerText(
            projection.queuedReviewTrigger
        )
        let queuedReviewLevelDisplayText = xhubDoctorHeartbeatRecoveryQueuedReviewLevelText(
            projection.queuedReviewLevel
        )
        let queuedReviewRunKindDisplayText = xhubDoctorHeartbeatRecoveryQueuedReviewRunKindText(
            projection.queuedReviewRunKind
        )
        self.init(
            action: projection.action,
            actionDisplayText: actionDisplayText,
            urgency: projection.urgency,
            urgencyDisplayText: urgencyDisplayText,
            reasonCode: projection.reasonCode,
            reasonDisplayText: reasonDisplayText,
            systemNextStepDisplayText: systemNextStepDisplayText,
            summary: projection.summary,
            doctorExplainabilityText: doctorExplainabilityText,
            sourceSignals: projection.sourceSignals,
            sourceSignalDisplayTexts: sourceSignalDisplayTexts,
            anomalyTypes: projection.anomalyTypes,
            anomalyTypeDisplayTexts: anomalyTypeDisplayTexts,
            blockedLaneReasons: projection.blockedLaneReasons,
            blockedLaneReasonDisplayTexts: blockedLaneReasonDisplayTexts,
            blockedLaneCount: projection.blockedLaneCount,
            stalledLaneCount: projection.stalledLaneCount,
            failedLaneCount: projection.failedLaneCount,
            recoveringLaneCount: projection.recoveringLaneCount,
            requiresUserAction: projection.requiresUserAction,
            queuedReviewTrigger: projection.queuedReviewTrigger,
            queuedReviewTriggerDisplayText: queuedReviewTriggerDisplayText,
            queuedReviewLevel: projection.queuedReviewLevel,
            queuedReviewLevelDisplayText: queuedReviewLevelDisplayText,
            queuedReviewRunKind: projection.queuedReviewRunKind,
            queuedReviewRunKindDisplayText: queuedReviewRunKindDisplayText
        )
    }
}

private func xhubDoctorHeartbeatRecoveryActionText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatRecoveryAction.resumeRun.rawValue:
        return "受控恢复执行"
    case HeartbeatRecoveryAction.replayFollowUp.rawValue:
        return "重放 follow-up / 续跑链"
    case HeartbeatRecoveryAction.requestGrantFollowUp.rawValue:
        return "grant / 授权跟进"
    case HeartbeatRecoveryAction.repairRoute.rawValue:
        return "修复 route / dispatch"
    case HeartbeatRecoveryAction.rehydrateContext.rawValue:
        return "重建项目上下文"
    case HeartbeatRecoveryAction.queueStrategicReview.rawValue:
        return "排队治理复盘"
    case HeartbeatRecoveryAction.holdForUser.rawValue:
        return "等待用户 / operator"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoveryUrgencyText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case HeartbeatRecoveryUrgency.observe.rawValue:
        return "持续观察"
    case HeartbeatRecoveryUrgency.active.rawValue:
        return "主动处理"
    case HeartbeatRecoveryUrgency.urgent.rawValue:
        return "紧急处理"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoveryReasonText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case "awaiting_user_or_operator_instruction":
        return "等待补齐用户或 operator 指令"
    case "follow_up_queue_stall_requires_replay":
        return "follow-up 队列停滞，需要先重放"
    case "restart_drain_requires_follow_up_replay":
        return "当前 drain 收口后需要重放 follow-up"
    case "grant_follow_up_required":
        return "需要先发起 grant 跟进"
    case "authorization_follow_up_required":
        return "需要先补齐授权跟进"
    case "user_authorization_or_grant_required":
        return "等待用户授权或 grant 放行"
    case "route_flaky_requires_repair":
        return "route 波动，需要先修复"
    case "route_or_dispatch_repair_required":
        return "route / dispatch 需要先修复"
    case "context_window_overflow_requires_rehydrate":
        return "上下文窗口溢出，需要先重建"
    case "heartbeat_hollow_progress_requires_context_rehydrate":
        return "heartbeat 空转，需要先重建上下文"
    case "heartbeat_or_lane_signal_requires_governance_review":
        return "heartbeat 或 lane 信号要求先做治理复盘"
    case "lane_failure_requires_controlled_resume":
        return "lane 失败后先做受控恢复"
    case "lane_vitality_degraded_resume_candidate":
        return "lane 活性下降，先尝试受控恢复"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoverySystemNextStepText(
    action: String?,
    failedLaneCount: Int,
    blockedLaneReasons: [String],
    queuedReviewLevel: String?,
    trigger: String?,
    runKind: String?
) -> String {
    switch action {
    case HeartbeatRecoveryAction.resumeRun.rawValue:
        if failedLaneCount > 0 {
            return "系统会先做一次受控恢复执行，确认失败 lane 已回到可继续状态"
        }
        return "系统会先尝试受控恢复执行，再观察 lane 活性是否恢复"
    case HeartbeatRecoveryAction.replayFollowUp.rawValue:
        if blockedLaneReasons.contains(LaneBlockedReason.restartDrain.rawValue) {
            return "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复"
        }
        return "系统会先重放挂起的 follow-up / 续跑链，再观察队列推进是否恢复"
    case HeartbeatRecoveryAction.requestGrantFollowUp.rawValue:
        if blockedLaneReasons.contains(LaneBlockedReason.authzDenied.rawValue)
            || blockedLaneReasons.contains(LaneBlockedReason.authChallengeLoop.rawValue) {
            return "系统会先发起所需授权跟进，待权限路径恢复后再继续恢复执行"
        }
        return "系统会先发起所需 grant 跟进，待放行后再继续恢复执行"
    case HeartbeatRecoveryAction.repairRoute.rawValue:
        return "系统会先修复当前 route / dispatch 健康，再尝试恢复执行"
    case HeartbeatRecoveryAction.rehydrateContext.rawValue:
        if blockedLaneReasons.contains(LaneBlockedReason.contextOverflow.rawValue) {
            return "系统会先收束并重建项目上下文，再继续下一次执行尝试"
        }
        return "系统会先重建项目上下文，再继续下一次执行尝试"
    case HeartbeatRecoveryAction.queueStrategicReview.rawValue:
        return xhubDoctorHeartbeatRecoveryQueuedReviewNextStep(
            reviewLevel: queuedReviewLevel,
            trigger: trigger,
            runKind: runKind
        )
    case HeartbeatRecoveryAction.holdForUser.rawValue:
        if blockedLaneReasons.contains(LaneBlockedReason.awaitingInstruction.rawValue) {
            return "系统会先停在当前边界，等待你或 operator 补齐缺失指令"
        }
        return "系统会先等待所需授权或 grant 放行，再继续恢复执行"
    default:
        return "系统会继续观察当前状态，并在下一次 heartbeat 再重新评估"
    }
}

private func xhubDoctorHeartbeatRecoveryDoctorExplainabilityText(
    action: String?,
    urgency: String?,
    reasonCode: String?,
    sourceSignals: [String],
    blockedLaneReasons: [String],
    failedLaneCount: Int,
    requiresUserAction: Bool,
    queuedReviewLevel: String?,
    trigger: String?,
    runKind: String?
) -> String {
    let actionText = xhubDoctorHeartbeatTrimTerminalPunctuation(
        xhubDoctorHeartbeatRecoverySystemNextStepText(
            action: action,
            failedLaneCount: failedLaneCount,
            blockedLaneReasons: blockedLaneReasons,
            queuedReviewLevel: queuedReviewLevel,
            trigger: trigger,
            runKind: runKind
        )
    )
    var details: [String] = []
    if let urgencyText = xhubDoctorHeartbeatRecoveryUrgencyText(urgency) {
        details.append("紧急度 \(urgencyText)")
    }
    if let reasonText = xhubDoctorHeartbeatRecoveryReasonText(reasonCode) {
        details.append("原因 \(reasonText)")
    }
    if requiresUserAction {
        details.append("需要用户动作")
    }
    if !sourceSignals.isEmpty {
        details.append(
            "信号 " + xhubDoctorHeartbeatRecoverySourceSignalTexts(sourceSignals).joined(separator: "、")
        )
    }
    return ([actionText] + details).joined(separator: " · ")
}

private func xhubDoctorHeartbeatRecoveryQueuedReviewLevelText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case SupervisorReviewLevel.r1Pulse.rawValue:
        return "一次脉冲复盘"
    case SupervisorReviewLevel.r2Strategic.rawValue:
        return "一次战略复盘"
    case SupervisorReviewLevel.r3Rescue.rawValue:
        return "一次救援复盘"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoveryQueuedReviewLevelFallbackText(_ raw: String?) -> String {
    xhubDoctorHeartbeatRecoveryQueuedReviewLevelText(raw) ?? "一次治理复盘"
}

private func xhubDoctorHeartbeatRecoveryQueuedReviewTriggerText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case SupervisorReviewTrigger.periodicHeartbeat.rawValue:
        return "周期心跳"
    case SupervisorReviewTrigger.periodicPulse.rawValue:
        return "周期 pulse"
    case SupervisorReviewTrigger.failureStreak.rawValue:
        return "失败累积"
    case SupervisorReviewTrigger.blockerDetected.rawValue:
        return "blocker 触发"
    case SupervisorReviewTrigger.noProgressWindow.rawValue:
        return "无进展窗口"
    case SupervisorReviewTrigger.planDrift.rawValue:
        return "计划偏航"
    case SupervisorReviewTrigger.preHighRiskAction.rawValue:
        return "高风险动作前"
    case SupervisorReviewTrigger.preDoneSummary.rawValue:
        return "pre-done 信号"
    case SupervisorReviewTrigger.manualRequest.rawValue, SupervisorReviewTrigger.userOverride.rawValue:
        return "手动请求"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoveryQueuedReviewRunKindText(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    switch raw {
    case SupervisorReviewRunKind.pulse.rawValue:
        return "周期脉冲"
    case SupervisorReviewRunKind.brainstorm.rawValue:
        return "无进展复盘"
    case SupervisorReviewRunKind.eventDriven.rawValue:
        return "事件触发"
    case SupervisorReviewRunKind.manual.rawValue:
        return "手动请求"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatRecoveryQueuedReviewNextStep(
    reviewLevel: String?,
    trigger: String?,
    runKind: String?
) -> String {
    let levelText = xhubDoctorHeartbeatRecoveryQueuedReviewLevelFallbackText(reviewLevel)
    var metadata: [String] = []
    if let runKindText = xhubDoctorHeartbeatRecoveryQueuedReviewRunKindText(runKind) {
        metadata.append(runKindText)
    }
    if let triggerText = xhubDoctorHeartbeatRecoveryQueuedReviewTriggerText(trigger) {
        metadata.append(triggerText)
    }
    if metadata.isEmpty {
        return "系统会先排队\(levelText)，并在下一个 safe point 注入 guidance"
    }
    return "系统会先基于\(metadata.joined(separator: " · "))排队\(levelText)，并在下一个 safe point 注入 guidance"
}

private func xhubDoctorHeartbeatRecoverySourceSignalTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatRecoverySourceSignalText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatRecoverySourceSignalText(_ raw: String) -> String {
    if raw.hasPrefix("anomaly:") {
        let token = String(raw.dropFirst("anomaly:".count))
        return "异常 \(xhubDoctorHeartbeatAnomalyTypeText(token))"
    }
    if raw.hasPrefix("lane_blocked_reason:") {
        let token = String(raw.dropFirst("lane_blocked_reason:".count))
        return "阻塞原因 \(xhubDoctorHeartbeatRecoveryBlockedReasonText(token))"
    }
    if raw.hasPrefix("lane_blocked_count:") {
        let count = String(raw.dropFirst("lane_blocked_count:".count))
        return "阻塞 lane \(count) 条"
    }
    if raw.hasPrefix("lane_stalled_count:") {
        let count = String(raw.dropFirst("lane_stalled_count:".count))
        return "停滞 lane \(count) 条"
    }
    if raw.hasPrefix("lane_failed_count:") {
        let count = String(raw.dropFirst("lane_failed_count:".count))
        return "失败 lane \(count) 条"
    }
    if raw.hasPrefix("lane_recovering_count:") {
        let count = String(raw.dropFirst("lane_recovering_count:".count))
        return "恢复中 lane \(count) 条"
    }
    if raw.hasPrefix("review_candidate:") {
        let payload = String(raw.dropFirst("review_candidate:".count))
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        var details: [String] = []
        if parts.indices.contains(0),
           let triggerText = xhubDoctorHeartbeatRecoveryQueuedReviewTriggerText(parts[0]) {
            details.append(triggerText)
        }
        if parts.indices.contains(1),
           let levelText = xhubDoctorHeartbeatRecoveryQueuedReviewLevelText(parts[1]) {
            details.append(levelText)
        }
        if parts.indices.contains(2),
           let runKindText = xhubDoctorHeartbeatRecoveryQueuedReviewRunKindText(parts[2]) {
            details.append(runKindText)
        }
        if details.isEmpty {
            return "复盘候选"
        }
        return "复盘候选 " + details.joined(separator: " / ")
    }
    return xhubDoctorHeartbeatHumanizeToken(raw)
}

private func xhubDoctorHeartbeatRecoveryBlockedReasonTexts(_ values: [String]) -> [String] {
    var ordered: [String] = []
    for value in values {
        let text = xhubDoctorHeartbeatRecoveryBlockedReasonText(value)
        guard !text.isEmpty, !ordered.contains(text) else { continue }
        ordered.append(text)
    }
    return ordered
}

private func xhubDoctorHeartbeatRecoveryBlockedReasonText(_ raw: String) -> String {
    switch raw {
    case LaneBlockedReason.skillGrantPending.rawValue:
        return "等待技能授权"
    case LaneBlockedReason.grantPending.rawValue:
        return "等待授权"
    case LaneBlockedReason.awaitingInstruction.rawValue:
        return "等待指令"
    case LaneBlockedReason.authzDenied.rawValue:
        return "授权被拒绝"
    case LaneBlockedReason.authChallengeLoop.rawValue:
        return "授权挑战循环"
    case LaneBlockedReason.contextOverflow.rawValue:
        return "上下文溢出"
    case LaneBlockedReason.routeOriginUnavailable.rawValue:
        return "route 源不可用"
    case LaneBlockedReason.dispatchIdleTimeout.rawValue:
        return "dispatch 空闲超时"
    case LaneBlockedReason.queueStarvation.rawValue:
        return "队列饥饿"
    case LaneBlockedReason.restartDrain.rawValue:
        return "等待 drain 恢复"
    default:
        return xhubDoctorHeartbeatHumanizeToken(raw)
    }
}

private func xhubDoctorHeartbeatTrimTerminalPunctuation(_ raw: String) -> String {
    var value = raw
    while let last = value.last, ["。", ".", "!", "！"].contains(String(last)) {
        value.removeLast()
    }
    return value
}

private extension XHubDoctorOutputMemoryRouteTruthSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .modelRouteReadiness else {
            return nil
        }
        if let projection = section.memoryRouteTruthProjection {
            self.init(projection: projection)
            return
        }
        guard let projection = AXModelRouteTruthProjection(doctorDetailLines: section.detailLines) else {
            return nil
        }
        self.init(projection: projection)
    }

    init(projection: AXModelRouteTruthProjection) {
        self.init(
            projectionSource: projection.projectionSource,
            completeness: projection.completeness,
            requestSnapshot: XHubDoctorOutputMemoryRouteRequestSnapshot(projection.requestSnapshot),
            resolutionChain: projection.resolutionChain.map(XHubDoctorOutputMemoryRouteResolutionNode.init),
            winningProfile: XHubDoctorOutputMemoryRouteWinningProfile(projection.winningProfile),
            winningBinding: XHubDoctorOutputMemoryRouteWinningBinding(projection.winningBinding),
            routeResult: XHubDoctorOutputMemoryRouteResult(projection.routeResult),
            constraintSnapshot: XHubDoctorOutputMemoryRouteConstraintSnapshot(projection.constraintSnapshot)
        )
    }
}

private extension XHubDoctorOutputDurableCandidateMirrorSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let projection = section.durableCandidateMirrorProjection {
            self.init(projection)
            return
        }
        guard let projection = XTUnifiedDoctorDurableCandidateMirrorProjection.from(
            detailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(projection)
    }

    init(_ projection: XTUnifiedDoctorDurableCandidateMirrorProjection) {
        self.init(
            status: projection.status.rawValue,
            target: projection.target,
            attempted: projection.attempted,
            errorCode: projection.errorCode,
            localStoreRole: projection.localStoreRole
        )
    }
}

private extension XHubDoctorOutputLocalStoreWriteSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .sessionRuntimeReadiness else {
            return nil
        }
        if let projection = section.localStoreWriteProjection {
            self.init(projection)
            return
        }
        guard let projection = XTUnifiedDoctorLocalStoreWriteProjection.from(
            detailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(projection)
    }

    init(_ projection: XTUnifiedDoctorLocalStoreWriteProjection) {
        self.init(
            personalMemoryIntent: projection.personalMemoryIntent,
            crossLinkIntent: projection.crossLinkIntent,
            personalReviewIntent: projection.personalReviewIntent
        )
    }
}

private extension XHubDoctorOutputFreshPairReconnectSmokeSnapshot {
    init?(section: XTUnifiedDoctorSection) {
        guard section.kind == .hubReachability else {
            return nil
        }
        guard let snapshot = XTFreshPairReconnectSmokeSnapshot.from(
            doctorDetailLines: section.detailLines
        ) else {
            return nil
        }
        self.init(snapshot)
    }

    init(_ snapshot: XTFreshPairReconnectSmokeSnapshot) {
        self.init(
            source: snapshot.source.rawValue,
            status: snapshot.status.rawValue,
            route: snapshot.route.rawValue,
            triggeredAtMs: snapshot.triggeredAtMs,
            completedAtMs: snapshot.completedAtMs,
            reasonCode: snapshot.reasonCode,
            summary: snapshot.summary
        )
    }
}

private extension XHubDoctorOutputFirstPairCompletionProofSnapshot {
    init(_ snapshot: XTFirstPairCompletionProofSnapshot) {
        self.init(
            readiness: snapshot.readiness.rawValue,
            sameLanVerified: snapshot.sameLanVerified,
            ownerLocalApprovalVerified: snapshot.ownerLocalApprovalVerified,
            pairingMaterialIssued: snapshot.pairingMaterialIssued,
            cachedReconnectSmokePassed: snapshot.cachedReconnectSmokePassed,
            stableRemoteRoutePresent: snapshot.stableRemoteRoutePresent,
            remoteShadowSmokePassed: snapshot.remoteShadowSmokePassed,
            remoteShadowSmokeStatus: snapshot.remoteShadowSmokeStatus.rawValue,
            remoteShadowSmokeSource: snapshot.remoteShadowSmokeSource?.rawValue,
            remoteShadowTriggeredAtMs: snapshot.remoteShadowTriggeredAtMs,
            remoteShadowCompletedAtMs: snapshot.remoteShadowCompletedAtMs,
            remoteShadowRoute: snapshot.remoteShadowRoute?.rawValue,
            remoteShadowReasonCode: snapshot.remoteShadowReasonCode,
            remoteShadowSummary: snapshot.remoteShadowSummary,
            summaryLine: snapshot.summaryLine,
            generatedAtMs: snapshot.generatedAtMs
        )
    }
}

private extension XHubDoctorOutputNextStep {
    init?(section: XTUnifiedDoctorSection) {
        let status = XHubDoctorCheckStatus(surfaceState: section.state)
        let instruction = section.nextStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard status != .pass, !instruction.isEmpty else { return nil }
        self.init(
            stepID: section.kind.rawValue,
            kind: xHubDoctorNextStepKind(for: section.repairEntry, state: section.state),
            label: section.repairEntry.label,
            owner: xHubDoctorStepOwner(for: section.repairEntry, state: section.state),
            blocking: status == .fail,
            destinationRef: section.repairEntry.rawValue,
            instruction: instruction
        )
    }
}

extension XHubDoctorOutputRouteSnapshot {
    init(
        transportMode: String,
        routeLabel: String,
        pairingPort: Int,
        grpcPort: Int,
        internetHost: String,
        internetHostKind: String? = nil,
        internetHostScope: String? = nil,
        remoteEntryPosture: String? = nil
    ) {
        let classification = XTHubRemoteAccessHostClassification.classify(internetHost)
        let resolvedKind = Self.resolveInternetHostKind(
            explicitKind: internetHostKind,
            classification: classification
        )
        let resolvedScope = Self.resolveInternetHostScope(
            explicitScope: internetHostScope,
            classification: classification
        )

        self.transportMode = transportMode
        self.routeLabel = routeLabel
        self.pairingPort = pairingPort
        self.grpcPort = grpcPort
        self.internetHost = internetHost
        self.internetHostKind = resolvedKind
        self.internetHostScope = resolvedScope
        self.remoteEntryPosture = Self.resolveRemoteEntryPosture(
            explicitPosture: remoteEntryPosture,
            internetHostKind: resolvedKind
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let transportMode = try container.decode(String.self, forKey: .transportMode)
        let routeLabel = try container.decode(String.self, forKey: .routeLabel)
        let pairingPort = try container.decode(Int.self, forKey: .pairingPort)
        let grpcPort = try container.decode(Int.self, forKey: .grpcPort)
        let internetHost = try container.decode(String.self, forKey: .internetHost)
        let internetHostKind = try container.decodeIfPresent(String.self, forKey: .internetHostKind)
        let internetHostScope = try container.decodeIfPresent(String.self, forKey: .internetHostScope)
        let remoteEntryPosture = try container.decodeIfPresent(String.self, forKey: .remoteEntryPosture)

        self.init(
            transportMode: transportMode,
            routeLabel: routeLabel,
            pairingPort: pairingPort,
            grpcPort: grpcPort,
            internetHost: internetHost,
            internetHostKind: internetHostKind,
            internetHostScope: internetHostScope,
            remoteEntryPosture: remoteEntryPosture
        )
    }

    var normalizedInternetHost: String? {
        let trimmed = internetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var internetHostScopeLabel: String? {
        let trimmed = internetHostScope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let scope = XTHubRemoteAccessHostClassification.IPScope(rawValue: trimmed) else {
            return nil
        }
        return scope.doctorLabel
    }

    var remoteEntryPostureLabel: String {
        switch remoteEntryPosture.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "missing_formal_remote_entry":
            return "无正式异网入口"
        case "lan_only_entry":
            return "仅同网入口"
        case "temporary_raw_ip_entry":
            return "临时 raw IP 入口"
        case "stable_named_entry":
            return "正式异网入口"
        default:
            switch internetHostKind.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "missing":
                return "无正式异网入口"
            case "lan_only":
                return "仅同网入口"
            case "raw_ip":
                return "临时 raw IP 入口"
            case "stable_named":
                return "正式异网入口"
            default:
                return "远端入口"
            }
        }
    }

    var remoteEntrySummaryLine: String {
        var parts = [remoteEntryPostureLabel]
        if let scopeLabel = internetHostScopeLabel {
            parts.append(scopeLabel)
        }
        if let host = normalizedInternetHost {
            parts.append("host=\(host)")
        }
        return parts.joined(separator: " · ")
    }

    private static func resolveInternetHostKind(
        explicitKind: String?,
        classification: XTHubRemoteAccessHostClassification
    ) -> String {
        let trimmed = explicitKind?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch trimmed {
        case "missing", "lan_only", "raw_ip", "stable_named":
            return trimmed
        default:
            return classification.kindCode
        }
    }

    private static func resolveInternetHostScope(
        explicitScope: String?,
        classification: XTHubRemoteAccessHostClassification
    ) -> String? {
        let trimmed = explicitScope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let scope = XTHubRemoteAccessHostClassification.IPScope(rawValue: trimmed) {
            return scope.rawValue
        }
        return classification.ipScope?.rawValue
    }

    private static func resolveRemoteEntryPosture(
        explicitPosture: String?,
        internetHostKind: String
    ) -> String {
        let trimmed = explicitPosture?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch trimmed {
        case "missing_formal_remote_entry",
             "lan_only_entry",
             "temporary_raw_ip_entry",
             "stable_named_entry":
            return trimmed
        default:
            switch internetHostKind {
            case "missing":
                return "missing_formal_remote_entry"
            case "lan_only":
                return "lan_only_entry"
            case "raw_ip":
                return "temporary_raw_ip_entry"
            case "stable_named":
                return "stable_named_entry"
            default:
                return "missing_formal_remote_entry"
            }
        }
    }
}

private extension XHubDoctorOutputRouteSnapshot {
    init(_ route: XTUnifiedDoctorRouteSnapshot) {
        self.init(
            transportMode: route.transportMode,
            routeLabel: route.routeLabel,
            pairingPort: route.pairingPort,
            grpcPort: route.grpcPort,
            internetHost: route.internetHost
        )
    }
}

private extension XHubDoctorOutputPairedRouteTargetSnapshot {
    init(_ snapshot: XTPairedRouteTargetSnapshot) {
        self.init(
            routeKind: snapshot.routeKind.rawValue,
            host: snapshot.host,
            pairingPort: snapshot.pairingPort,
            grpcPort: snapshot.grpcPort,
            hostKind: snapshot.hostKind,
            source: snapshot.source.rawValue
        )
    }
}

private extension XHubDoctorOutputPairedRouteSetSnapshot {
    init(_ snapshot: XTPairedRouteSetSnapshot) {
        self.init(
            schemaVersion: snapshot.schemaVersion,
            readiness: snapshot.readiness.rawValue,
            readinessReasonCode: snapshot.readinessReasonCode,
            summaryLine: snapshot.summaryLine,
            hubInstanceID: snapshot.hubInstanceID,
            pairingProfileEpoch: snapshot.pairingProfileEpoch,
            routePackVersion: snapshot.routePackVersion,
            activeRoute: snapshot.activeRoute.map(XHubDoctorOutputPairedRouteTargetSnapshot.init),
            lanRoute: snapshot.lanRoute.map(XHubDoctorOutputPairedRouteTargetSnapshot.init),
            stableRemoteRoute: snapshot.stableRemoteRoute.map(XHubDoctorOutputPairedRouteTargetSnapshot.init),
            lastKnownGoodRoute: snapshot.lastKnownGoodRoute.map(XHubDoctorOutputPairedRouteTargetSnapshot.init),
            cachedReconnectSmokeStatus: snapshot.cachedReconnectSmokeStatus,
            cachedReconnectSmokeReasonCode: snapshot.cachedReconnectSmokeReasonCode,
            cachedReconnectSmokeSummary: snapshot.cachedReconnectSmokeSummary
        )
    }
}

private extension XHubDoctorOutputConnectivityIncidentPathSnapshot {
    init(_ snapshot: XTHubConnectivityIncidentPathSnapshot) {
        self.init(
            statusKey: snapshot.statusKey,
            usesWiFi: snapshot.usesWiFi,
            usesWiredEthernet: snapshot.usesWiredEthernet,
            usesCellular: snapshot.usesCellular,
            isExpensive: snapshot.isExpensive,
            isConstrained: snapshot.isConstrained
        )
    }
}

private extension XHubDoctorOutputConnectivityRouteStatusSnapshot {
    init(_ snapshot: XTHubConnectivityRouteStatusSnapshot) {
        self.init(
            route: snapshot.route.rawValue,
            healthScore: snapshot.healthScore,
            cooldownUntilMs: snapshot.cooldownUntilMs,
            recentSuccessCount: snapshot.recentSuccessCount,
            recentFailureCount: snapshot.recentFailureCount
        )
    }
}

private extension XHubDoctorOutputConnectivityIncidentSnapshot {
    init(_ snapshot: XTHubConnectivityIncidentSnapshot) {
        self.init(
            schemaVersion: snapshot.schemaVersion,
            incidentState: snapshot.incidentState.rawValue,
            reasonCode: snapshot.reasonCode,
            summaryLine: snapshot.summaryLine,
            trigger: snapshot.trigger.rawValue,
            decisionReasonCode: snapshot.decisionReasonCode,
            pairedRouteReadiness: snapshot.pairedRouteReadiness?.rawValue,
            stableRemoteRouteHost: snapshot.stableRemoteRouteHost,
            currentFailureCode: snapshot.currentFailureCode,
            currentPath: snapshot.currentPath.map(XHubDoctorOutputConnectivityIncidentPathSnapshot.init),
            lastUpdatedAtMs: snapshot.lastUpdatedAtMs,
            selectedRoute: snapshot.selectedRoute?.rawValue,
            candidatesTried: snapshot.candidatesTried?.map(\.rawValue),
            handoffReason: snapshot.handoffReason,
            cooldownApplied: snapshot.cooldownApplied,
            routeStatuses: snapshot.routeStatuses?.map(XHubDoctorOutputConnectivityRouteStatusSnapshot.init)
        )
    }
}

private extension XHubDoctorOutputMemoryRouteRequestSnapshot {
    init(_ projection: AXModelRouteTruthRequestSnapshot) {
        self.init(
            jobType: projection.jobType,
            mode: projection.mode,
            projectIDPresent: projection.projectIDPresent,
            sensitivity: projection.sensitivity,
            trustLevel: projection.trustLevel,
            budgetClass: projection.budgetClass,
            remoteAllowedByPolicy: projection.remoteAllowedByPolicy,
            killSwitchState: projection.killSwitchState
        )
    }
}

private extension XHubDoctorOutputMemoryRouteResolutionNode {
    init(_ projection: AXModelRouteTruthResolutionNode) {
        self.init(
            scopeKind: projection.scopeKind,
            scopeRefRedacted: projection.scopeRefRedacted,
            matched: projection.matched,
            profileID: projection.profileID,
            selectionStrategy: projection.selectionStrategy,
            skipReason: projection.skipReason
        )
    }
}

private extension XHubDoctorOutputMemoryRouteWinningProfile {
    init(_ projection: AXModelRouteTruthWinningProfile) {
        self.init(
            resolvedProfileID: projection.resolvedProfileID,
            scopeKind: projection.scopeKind,
            scopeRefRedacted: projection.scopeRefRedacted,
            selectionStrategy: projection.selectionStrategy,
            policyVersion: projection.policyVersion,
            disabled: projection.disabled
        )
    }
}

private extension XHubDoctorOutputMemoryRouteWinningBinding {
    init(_ projection: AXModelRouteTruthWinningBinding) {
        self.init(
            bindingKind: projection.bindingKind,
            bindingKey: projection.bindingKey,
            provider: projection.provider,
            modelID: projection.modelID,
            selectedByUser: projection.selectedByUser
        )
    }
}

private extension XHubDoctorOutputMemoryRouteResult {
    init(_ projection: AXModelRouteTruthRouteResult) {
        self.init(
            routeSource: projection.routeSource,
            routeReasonCode: projection.routeReasonCode,
            fallbackApplied: projection.fallbackApplied,
            fallbackReason: projection.fallbackReason,
            remoteAllowed: projection.remoteAllowed,
            auditRef: projection.auditRef,
            denyCode: projection.denyCode
        )
    }
}

private extension XHubDoctorOutputMemoryRouteConstraintSnapshot {
    init(_ projection: AXModelRouteTruthConstraintSnapshot) {
        self.init(
            remoteAllowedAfterUserPref: projection.remoteAllowedAfterUserPref,
            remoteAllowedAfterPolicy: projection.remoteAllowedAfterPolicy,
            budgetClass: projection.budgetClass,
            budgetBlocked: projection.budgetBlocked,
            policyBlockedRemote: projection.policyBlockedRemote
        )
    }
}

private extension XHubDoctorOverallState {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .ready
        case .inProgress:
            self = .inProgress
        case .grantRequired, .permissionDenied, .blockedWaitingUpstream:
            self = .blocked
        case .releaseFrozen:
            self = .notSupported
        case .diagnosticRequired:
            self = .degraded
        }
    }
}

private extension XHubDoctorCheckStatus {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .pass
        case .inProgress:
            self = .warn
        case .grantRequired, .permissionDenied, .blockedWaitingUpstream, .diagnosticRequired:
            self = .fail
        case .releaseFrozen:
            self = .skip
        }
    }
}

private extension XHubDoctorSeverity {
    init(surfaceState: XTUISurfaceState) {
        switch surfaceState {
        case .ready:
            self = .info
        case .inProgress, .releaseFrozen:
            self = .warning
        case .grantRequired, .blockedWaitingUpstream, .diagnosticRequired:
            self = .error
        case .permissionDenied:
            self = .critical
        }
    }
}

private func xHubDoctorNextStepKind(
    for destination: UITroubleshootDestination,
    state: XTUISurfaceState
) -> XHubDoctorNextStepKind {
    switch state {
    case .inProgress, .blockedWaitingUpstream:
        return .waitForRecovery
    case .releaseFrozen:
        return .openRepairSurface
    case .ready, .grantRequired, .permissionDenied, .diagnosticRequired:
        break
    }

    switch destination {
    case .xtPairHub, .hubPairing, .hubLAN:
        return .reviewPairing
    case .xtChooseModel, .hubModels:
        return .chooseModel
    case .hubGrants, .hubSecurity, .systemPermissions:
        return .reviewPermissions
    case .xtDiagnostics, .hubDiagnostics:
        return .inspectDiagnostics
    case .homeSupervisor:
        return .startFirstTask
    }
}

private func xHubDoctorStepOwner(
    for destination: UITroubleshootDestination,
    state: XTUISurfaceState
) -> XHubDoctorStepOwner {
    switch state {
    case .inProgress:
        return .xtRuntime
    case .blockedWaitingUpstream:
        return .hubRuntime
    case .ready, .grantRequired, .permissionDenied, .releaseFrozen, .diagnosticRequired:
        break
    }

    switch destination {
    case .xtPairHub, .xtChooseModel, .xtDiagnostics, .hubPairing, .hubLAN, .hubModels, .hubGrants, .hubSecurity, .hubDiagnostics, .systemPermissions, .homeSupervisor:
        return .user
    }
}
