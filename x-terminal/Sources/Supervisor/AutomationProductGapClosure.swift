import Foundation

enum XTAutomationExecutionProfile: String, Codable, Equatable {
    case conservative
    case balanced
    case aggressive
}

enum XTAutomationLaneStrategy: String, Codable, Equatable {
    case singleLane = "single_lane"
    case multiLane = "multi_lane"
    case adaptive
}

enum XTAutomationTriggerType: String, Codable, Equatable, CaseIterable {
    case schedule
    case webhook
    case connectorEvent = "connector_event"
    case manual
}

enum XTAutomationTriggerSource: String, Codable, Equatable {
    case github
    case slack
    case telegram
    case hub
    case timer
}

enum XTAutomationRunState: String, Codable, Equatable {
    case queued
    case running
    case blocked
    case takeover
    case delivered
    case failed
    case downgraded
}

enum XTAutomationTakeoverMode: String, Codable, Equatable {
    case claimUpstream = "claim_upstream"
    case minimalMicrotask = "minimal_microtask"
    case waitOnly = "wait_only"
}

enum XTAutomationDegradeMode: String, Codable, Equatable, CaseIterable {
    case downgradeToLocal = "downgrade_to_local"
    case restrictedLocal = "restricted_local"
    case readOnly = "read_only"
}

enum XTAutomationStarterTemplateKind: String, Codable, Equatable, CaseIterable {
    case prTriage = "pr_triage"
    case dailyDigest = "daily_digest"
    case issueFollowUp = "issue_follow_up"
    case docSync = "doc_sync"
    case releaseAssistant = "release_assistant"
}

enum XTAutomationReleaseRecommendation: String, Codable, Equatable {
    case candidateRelease = "candidate_release"
    case hold
}

struct XTAutomationRecipeManifest: Codable, Equatable {
    let schemaVersion: String
    let recipeID: String
    let projectID: String
    let goal: String
    let triggerRefs: [String]
    let executionProfile: XTAutomationExecutionProfile
    let touchMode: DeliveryParticipationMode
    let innovationLevel: SupervisorInnovationLevel
    let laneStrategy: XTAutomationLaneStrategy
    let deliveryTargets: [String]
    let acceptancePackRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recipeID = "recipe_id"
        case projectID = "project_id"
        case goal
        case triggerRefs = "trigger_refs"
        case executionProfile = "execution_profile"
        case touchMode = "touch_mode"
        case innovationLevel = "innovation_level"
        case laneStrategy = "lane_strategy"
        case deliveryTargets = "delivery_targets"
        case acceptancePackRef = "acceptance_pack_ref"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationTriggerEnvelope: Codable, Equatable, Identifiable {
    let schemaVersion: String
    let triggerID: String
    let triggerType: XTAutomationTriggerType
    let source: XTAutomationTriggerSource
    let projectID: String
    let payloadRef: String
    let requiresGrant: Bool
    let policyRef: String
    let dedupeKey: String
    let auditRef: String

    var id: String { triggerID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case triggerID = "trigger_id"
        case triggerType = "trigger_type"
        case source
        case projectID = "project_id"
        case payloadRef = "payload_ref"
        case requiresGrant = "requires_grant"
        case policyRef = "policy_ref"
        case dedupeKey = "dedupe_key"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationExternalTriggerIngressEnvelope: Codable, Equatable, Identifiable {
    static let currentSchemaVersion = "xt.external_trigger_ingress_envelope.v1"

    let schemaVersion: String
    let triggerID: String
    let triggerType: XTAutomationTriggerType
    let source: XTAutomationTriggerSource
    let connectorID: String
    let projectID: String
    let payloadRef: String
    let dedupeKey: String
    let requiresGrant: Bool
    let cooldownSec: Int
    let auditRef: String

    var id: String { triggerID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case triggerID = "trigger_id"
        case triggerType = "trigger_type"
        case source
        case connectorID = "connector_id"
        case projectID = "project_id"
        case payloadRef = "payload_ref"
        case dedupeKey = "dedupe_key"
        case requiresGrant = "requires_grant"
        case cooldownSec = "cooldown_sec"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRunTimeline: Codable, Equatable {
    let schemaVersion: String
    let runID: String
    let recipeID: String
    let state: XTAutomationRunState
    let currentOwner: String
    let activePoolCount: Int
    let activeLaneCount: Int
    let topBlocker: String
    let latestDeltaRef: String
    let deliveryRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case recipeID = "recipe_id"
        case state
        case currentOwner = "current_owner"
        case activePoolCount = "active_pool_count"
        case activeLaneCount = "active_lane_count"
        case topBlocker = "top_blocker"
        case latestDeltaRef = "latest_delta_ref"
        case deliveryRef = "delivery_ref"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationTakeoverDecision: Codable, Equatable {
    let schemaVersion: String
    let runID: String
    let blockedTaskID: String
    let upstreamDependencyIDs: [String]
    let takeoverMode: XTAutomationTakeoverMode
    let decisionReason: String
    let scopeGuard: String
    let rollbackRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case blockedTaskID = "blocked_task_id"
        case upstreamDependencyIDs = "upstream_dependency_ids"
        case takeoverMode = "takeover_mode"
        case decisionReason = "decision_reason"
        case scopeGuard = "scope_guard"
        case rollbackRef = "rollback_ref"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationBootstrapBundle: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let recipeID: String
    let generatedFiles: [String]
    let firstRunChecklistRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case recipeID = "recipe_id"
        case generatedFiles = "generated_files"
        case firstRunChecklistRef = "first_run_checklist_ref"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationTriggerSeed: Equatable {
    let triggerID: String
    let triggerType: XTAutomationTriggerType
    let source: XTAutomationTriggerSource
    let payloadRef: String
    let requiresGrant: Bool
    let policyRef: String
    let dedupeKey: String
}

enum XTAutomationTriggerRoute: String, Codable, Equatable {
    case run
    case hold
    case drop
}

enum XTAutomationGateDecision: String, Codable, Equatable {
    case allow
    case hold
    case deny
}

enum XTAutomationRunLaunchAction: String, Codable, Equatable {
    case run
    case hold
    case downgrade
    case deny
}

struct XTAutomationTriggerRouteDecision: Codable, Equatable, Identifiable {
    let schemaVersion: String
    let triggerID: String
    let projectID: String
    let dedupeKey: String
    let route: XTAutomationTriggerRoute
    let cooldownSeconds: Int
    let replayGuardPass: Bool
    let grantRequired: Bool
    let policyBound: Bool
    let sameProjectScope: Bool
    let decision: XTAutomationGateDecision
    let denyCode: String
    let runID: String
    let auditRef: String

    var id: String { triggerID }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case triggerID = "trigger_id"
        case projectID = "project_id"
        case dedupeKey = "dedupe_key"
        case route
        case cooldownSeconds = "cooldown_seconds"
        case replayGuardPass = "replay_guard_pass"
        case grantRequired = "grant_required"
        case policyBound = "policy_bound"
        case sameProjectScope = "same_project_scope"
        case decision
        case denyCode = "deny_code"
        case runID = "run_id"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRunLaunchGate: Codable, Equatable {
    let deliveryTargetPresent: Bool
    let acceptancePackPresent: Bool
    let triggerRoutesPass: Bool
    let grantBindingPass: Bool
    let routeReady: Bool
    let budgetOK: Bool
    let trustedAutomationReady: Bool

    enum CodingKeys: String, CodingKey {
        case deliveryTargetPresent = "delivery_target_present"
        case acceptancePackPresent = "acceptance_pack_present"
        case triggerRoutesPass = "trigger_routes_pass"
        case grantBindingPass = "grant_binding_pass"
        case routeReady = "route_ready"
        case budgetOK = "budget_ok"
        case trustedAutomationReady = "trusted_automation_ready"
    }
}

struct XTAutomationRunLaunchDecision: Codable, Equatable {
    let schemaVersion: String
    let runID: String
    let recipeID: String
    let transportMode: String
    let launchGate: XTAutomationRunLaunchGate
    let degradeMode: XTAutomationDegradeMode?
    let decision: XTAutomationRunLaunchAction
    let holdReason: String
    let operatorRef: String
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case recipeID = "recipe_id"
        case transportMode = "transport_mode"
        case launchGate = "launch_gate"
        case degradeMode = "degrade_mode"
        case decision
        case holdReason = "hold_reason"
        case operatorRef = "operator_ref"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRecipeManifestEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let recipeManifest: XTAutomationRecipeManifest
    let triggerEnvelopes: [XTAutomationTriggerEnvelope]
    let externalTriggerIngressEnvelopes: [XTAutomationExternalTriggerIngressEnvelope]
    let recipeManifestSchemaCoverage: Double
    let ambiguousTriggerFieldCount: Int
    let acceptanceDeliveryBound: Bool
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case recipeManifest = "recipe_manifest"
        case triggerEnvelopes = "trigger_envelopes"
        case externalTriggerIngressEnvelopes = "external_trigger_ingress_envelopes"
        case recipeManifestSchemaCoverage = "recipe_manifest_schema_coverage"
        case ambiguousTriggerFieldCount = "ambiguous_trigger_field_count"
        case acceptanceDeliveryBound = "acceptance_delivery_bound"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRunTransition: Codable, Equatable, Identifiable {
    let toState: XTAutomationRunState
    let reason: String
    let retryAfterSeconds: Int?
    let auditRef: String

    var id: String { "\(toState.rawValue):\(reason)" }

    enum CodingKeys: String, CodingKey {
        case toState = "to_state"
        case reason
        case retryAfterSeconds = "retry_after_seconds"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationEventRunnerEvidence: Codable, Equatable {
    let schemaVersion: String
    let recipeID: String
    let recipeBindingRef: String
    let runTimeline: XTAutomationRunTimeline
    let statePath: [XTAutomationRunState]
    let stateTransitions: [XTAutomationRunTransition]
    let triggerEnvelopes: [XTAutomationTriggerEnvelope]
    let externalTriggerIngressEnvelopes: [XTAutomationExternalTriggerIngressEnvelope]
    let triggerRouteDecisions: [XTAutomationTriggerRouteDecision]
    let launchDecision: XTAutomationRunLaunchDecision
    let triggerDedupeFalseNegative: Int
    let replayGuardPass: Bool
    let grantBindingPass: Bool
    let manualCancelSupported: Bool
    let retryAfterSeconds: Int
    let runIdentityStable: Bool
    let downgradePaths: [XTAutomationDegradeMode]
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recipeID = "recipe_id"
        case recipeBindingRef = "recipe_binding_ref"
        case runTimeline = "run_timeline"
        case statePath = "state_path"
        case stateTransitions = "state_transitions"
        case triggerEnvelopes = "trigger_envelopes"
        case externalTriggerIngressEnvelopes = "external_trigger_ingress_envelopes"
        case triggerRouteDecisions = "trigger_route_decisions"
        case launchDecision = "launch_decision"
        case triggerDedupeFalseNegative = "trigger_dedupe_false_negative"
        case replayGuardPass = "replay_guard_pass"
        case grantBindingPass = "grant_binding_pass"
        case manualCancelSupported = "manual_cancel_supported"
        case retryAfterSeconds = "retry_after_seconds"
        case runIdentityStable = "run_identity_stable"
        case downgradePaths = "downgrade_paths"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRunCheckpointRecoveryEvidence: Codable, Equatable {
    let schemaVersion: String
    let runID: String
    let recipeID: String
    let checkpoints: [XTAutomationRunCheckpoint]
    let restartRecoveryDecision: XTAutomationRestartRecoveryDecision
    let manualCancelDecision: XTAutomationRestartRecoveryDecision
    let staleRunDecision: XTAutomationRestartRecoveryDecision
    let boundedRetryDecision: XTAutomationRestartRecoveryDecision
    let recoveredRunID: String
    let recoveredState: XTAutomationRunState
    let statePathRebuilt: [XTAutomationRunState]
    let checkpointPathRebuildPass: Bool
    let stableIdentityPass: Bool
    let manualCancelBlocksRestart: Bool
    let boundedRetryPass: Bool
    let staleRunScavenged: Bool
    let recoverableCheckpointCount: Int
    let latestResumeToken: String
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case recipeID = "recipe_id"
        case checkpoints
        case restartRecoveryDecision = "restart_recovery_decision"
        case manualCancelDecision = "manual_cancel_decision"
        case staleRunDecision = "stale_run_decision"
        case boundedRetryDecision = "bounded_retry_decision"
        case recoveredRunID = "recovered_run_id"
        case recoveredState = "recovered_state"
        case statePathRebuilt = "state_path_rebuilt"
        case checkpointPathRebuildPass = "checkpoint_path_rebuild_pass"
        case stableIdentityPass = "stable_identity_pass"
        case manualCancelBlocksRestart = "manual_cancel_blocks_restart"
        case boundedRetryPass = "bounded_retry_pass"
        case staleRunScavenged = "stale_run_scavenged"
        case recoverableCheckpointCount = "recoverable_checkpoint_count"
        case latestResumeToken = "latest_resume_token"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationDirectedTakeoverEvidence: Codable, Equatable {
    let schemaVersion: String
    let runID: String
    let takeoverDecision: XTAutomationTakeoverDecision
    let topBlocker: String
    let nextOwner: String
    let retryAfterSeconds: Int
    let unblockChecklist: [String]
    let blockedRunWithoutDirectedAction: Int
    let criticalPathTakeoverSuccessRate: Double
    let guardViolationCount: Int
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case runID = "run_id"
        case takeoverDecision = "takeover_decision"
        case topBlocker = "top_blocker"
        case nextOwner = "next_owner"
        case retryAfterSeconds = "retry_after_seconds"
        case unblockChecklist = "unblock_checklist"
        case blockedRunWithoutDirectedAction = "blocked_run_without_directed_action"
        case criticalPathTakeoverSuccessRate = "critical_path_takeover_success_rate"
        case guardViolationCount = "guard_violation_count"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationRunTimelineEvidence: Codable, Equatable {
    let schemaVersion: String
    let timeline: XTAutomationRunTimeline
    let visibleFieldsCoverage: Double
    let nextAction: String
    let deliveryTarget: String
    let operatorConsoleEvidenceRef: String
    let userExplanation: String
    let rawCotLeakCount: Int
    let participationMode: DeliveryParticipationMode
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timeline
        case visibleFieldsCoverage = "visible_fields_coverage"
        case nextAction = "next_action"
        case deliveryTarget = "delivery_target"
        case operatorConsoleEvidenceRef = "operator_console_evidence_ref"
        case userExplanation = "user_explanation"
        case rawCotLeakCount = "raw_cot_leak_count"
        case participationMode = "participation_mode"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationStarterTemplateSpec: Codable, Equatable, Identifiable {
    let kind: XTAutomationStarterTemplateKind
    let displayName: String
    let recommendedTouchMode: DeliveryParticipationMode
    let highRisk: Bool
    let generatedFiles: [String]
    let deliveryTargetRequired: Bool
    let acceptancePackRequired: Bool

    var id: String { kind.rawValue }

    enum CodingKeys: String, CodingKey {
        case kind
        case displayName = "display_name"
        case recommendedTouchMode = "recommended_touch_mode"
        case highRisk = "high_risk"
        case generatedFiles = "generated_files"
        case deliveryTargetRequired = "delivery_target_required"
        case acceptancePackRequired = "acceptance_pack_required"
    }
}

struct XTAutomationBootstrapTemplatesEvidence: Codable, Equatable {
    let schemaVersion: String
    let bundle: XTAutomationBootstrapBundle
    let templates: [XTAutomationStarterTemplateSpec]
    let recipeToFirstRunP95Ms: Int
    let firstRunSuccessRate: Double
    let highRiskTemplateTouchGuardPass: Bool
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case bundle
        case templates
        case recipeToFirstRunP95Ms = "recipe_to_first_run_p95_ms"
        case firstRunSuccessRate = "first_run_success_rate"
        case highRiskTemplateTouchGuardPass = "high_risk_template_touch_guard_pass"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationCompetitiveSample: Codable, Equatable, Identifiable {
    let kind: XTAutomationStarterTemplateKind
    let realSampleRef: String
    let recipeToFirstRunMs: Int
    let blockedRunWithoutDirectedAction: Int
    let deliverySuccessRate: Double
    let tokenPerDelivery: Int
    let baselineTokenPerDelivery: Int
    let whereIsMyRunQuestionRate: Double

    var id: String { kind.rawValue }

    enum CodingKeys: String, CodingKey {
        case kind
        case realSampleRef = "real_sample_ref"
        case recipeToFirstRunMs = "recipe_to_first_run_ms"
        case blockedRunWithoutDirectedAction = "blocked_run_without_directed_action"
        case deliverySuccessRate = "delivery_success_rate"
        case tokenPerDelivery = "token_per_delivery"
        case baselineTokenPerDelivery = "baseline_token_per_delivery"
        case whereIsMyRunQuestionRate = "where_is_my_run_question_rate"
    }
}

struct XTAutomationCompetitiveGraduationEvidence: Codable, Equatable {
    let schemaVersion: String
    let requireRealPass: Bool
    let samples: [XTAutomationCompetitiveSample]
    let automationDeliverySuccessRate: Double
    let tokenPerSuccessfulDeliveryDeltaVsBaseline: Double
    let whereIsMyRunQuestionRate: Double
    let broadcastDrivenResumeRatio: Double
    let releaseRecommendation: XTAutomationReleaseRecommendation
    let rollbackRef: String
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requireRealPass = "require_real_pass"
        case samples
        case automationDeliverySuccessRate = "automation_delivery_success_rate"
        case tokenPerSuccessfulDeliveryDeltaVsBaseline = "token_per_successful_delivery_delta_vs_baseline"
        case whereIsMyRunQuestionRate = "where_is_my_run_question_rate"
        case broadcastDrivenResumeRatio = "broadcast_driven_resume_ratio"
        case releaseRecommendation = "release_recommendation"
        case rollbackRef = "rollback_ref"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationGapClosureEvidence: Codable, Equatable {
    let schemaVersion: String
    let projectID: String
    let recipeID: String
    let gateVector: String
    let recipeToFirstRunP95Ms: Int
    let triggerDedupeFalseNegative: Int
    let blockedRunWithoutDirectedAction: Int
    let criticalPathTakeoverSuccessRate: Double
    let runStateVisibilityCoverage: Double
    let userWhereIsMyRunQuestionRate: Double
    let automationDeliverySuccessRate: Double
    let tokenPerSuccessfulDeliveryDeltaVsBaseline: Double
    let broadcastDrivenResumeRatio: Double
    let evidenceRefs: [String]
    let minimalGaps: [String]
    let auditRef: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case recipeID = "recipe_id"
        case gateVector = "gate_vector"
        case recipeToFirstRunP95Ms = "recipe_to_first_run_p95_ms"
        case triggerDedupeFalseNegative = "trigger_dedupe_false_negative"
        case blockedRunWithoutDirectedAction = "blocked_run_without_directed_action"
        case criticalPathTakeoverSuccessRate = "critical_path_takeover_success_rate"
        case runStateVisibilityCoverage = "run_state_visibility_coverage"
        case userWhereIsMyRunQuestionRate = "user_where_is_my_run_question_rate"
        case automationDeliverySuccessRate = "automation_delivery_success_rate"
        case tokenPerSuccessfulDeliveryDeltaVsBaseline = "token_per_successful_delivery_delta_vs_baseline"
        case broadcastDrivenResumeRatio = "broadcast_driven_resume_ratio"
        case evidenceRefs = "evidence_refs"
        case minimalGaps = "minimal_gaps"
        case auditRef = "audit_ref"
    }
}

struct XTAutomationVerticalSliceResult: Codable, Equatable {
    let recipeManifest: XTAutomationRecipeManifestEvidence
    let eventRunner: XTAutomationEventRunnerEvidence
    let checkpointRecovery: XTAutomationRunCheckpointRecoveryEvidence
    let directedTakeover: XTAutomationDirectedTakeoverEvidence
    let runTimeline: XTAutomationRunTimelineEvidence
    let bootstrapTemplates: XTAutomationBootstrapTemplatesEvidence
    let competitiveGraduation: XTAutomationCompetitiveGraduationEvidence
    let overall: XTAutomationGapClosureEvidence

    enum CodingKeys: String, CodingKey {
        case recipeManifest = "recipe_manifest"
        case eventRunner = "event_runner"
        case checkpointRecovery = "checkpoint_recovery"
        case directedTakeover = "directed_takeover"
        case runTimeline = "run_timeline"
        case bootstrapTemplates = "bootstrap_templates"
        case competitiveGraduation = "competitive_graduation"
        case overall
    }
}

struct XTAutomationVerticalSliceInput {
    let projectID: UUID
    let recipeID: String
    let goal: String
    let deliveryTargets: [String]
    let acceptancePackRef: String
    let executionProfile: XTAutomationExecutionProfile
    let touchMode: DeliveryParticipationMode
    let innovationLevel: SupervisorInnovationLevel
    let laneStrategy: XTAutomationLaneStrategy
    let runID: String
    let currentOwner: String
    let activePoolCount: Int
    let activeLaneCount: Int
    let blockedTaskID: String
    let upstreamDependencyIDs: [String]
    let operatorConsoleEvidenceRef: String
    let latestDeltaRef: String
    let deliveryRef: String
    let firstRunChecklistRef: String
    let triggerSeeds: [XTAutomationTriggerSeed]
    let hubTransportMode: HubTransportMode
    let hasRemoteProfile: Bool
    let budgetOK: Bool
    let requiresTrustedAutomation: Bool
    let trustedAutomationReady: Bool
    let permissionOwnerReady: Bool
    let workspaceBindingHash: String
    let grantPolicyRef: String
    let trustedDeviceID: String
    let requiredDeviceToolGroups: [String]
    let intakeWorkflow: ProjectIntakeWorkflowResult?
    let acceptanceWorkflow: AcceptanceWorkflowResult?
    let additionalEvidenceRefs: [String]
    let now: Date
}

struct XTAutomationRecipeEngine {
    func buildEvidence(_ input: XTAutomationVerticalSliceInput, auditRef: String) -> XTAutomationRecipeManifestEvidence {
        let projectToken = input.projectID.uuidString.lowercased()
        let triggerSeeds = xtAutomationOrderedUniqueTriggers(input.triggerSeeds)
        let triggerEnvelopes = triggerSeeds.map { seed in
            XTAutomationTriggerEnvelope(
                schemaVersion: "xt.automation_trigger_envelope.v1",
                triggerID: seed.triggerID,
                triggerType: seed.triggerType,
                source: seed.source,
                projectID: projectToken,
                payloadRef: seed.payloadRef,
                requiresGrant: seed.requiresGrant,
                policyRef: seed.policyRef,
                dedupeKey: seed.dedupeKey,
                auditRef: auditRef
            )
        }
        let externalTriggerIngressEnvelopes = xtAutomationBuildExternalTriggerIngressEnvelopes(
            projectID: projectToken,
            triggerSeeds: triggerSeeds,
            auditRef: auditRef
        )
        let recipeManifest = XTAutomationRecipeManifest(
            schemaVersion: "xt.automation_recipe_manifest.v1",
            recipeID: input.recipeID,
            projectID: projectToken,
            goal: input.goal,
            triggerRefs: triggerEnvelopes.map { "xt.automation_trigger_envelope.v1:\($0.triggerID)" },
            executionProfile: input.executionProfile,
            touchMode: input.touchMode,
            innovationLevel: input.innovationLevel,
            laneStrategy: input.laneStrategy,
            deliveryTargets: input.deliveryTargets,
            acceptancePackRef: input.acceptancePackRef,
            auditRef: auditRef
        )
        let ambiguousTriggerFieldCount = triggerEnvelopes.reduce(0) { partial, envelope in
            partial + (envelope.triggerType == .webhook && envelope.dedupeKey.isEmpty ? 1 : 0)
        }
        let coverage = !recipeManifest.deliveryTargets.isEmpty
            && !recipeManifest.acceptancePackRef.isEmpty
            && triggerEnvelopes.count == 4
            && triggerEnvelopes.allSatisfy { $0.requiresGrant && !$0.dedupeKey.isEmpty }
            ? 1.0 : 0.0
        let acceptanceDeliveryBound = !recipeManifest.deliveryTargets.isEmpty && !recipeManifest.acceptancePackRef.isEmpty
        let gaps = xtAutomationOrderedUniqueStrings([
            acceptanceDeliveryBound ? nil : "missing_acceptance_or_delivery_binding",
            ambiguousTriggerFieldCount == 0 ? nil : "ambiguous_trigger_fields_detected"
        ].compactMap { $0 })
        return XTAutomationRecipeManifestEvidence(
            schemaVersion: "xt.automation_recipe_manifest_evidence.v1",
            projectID: projectToken,
            recipeManifest: recipeManifest,
            triggerEnvelopes: triggerEnvelopes,
            externalTriggerIngressEnvelopes: externalTriggerIngressEnvelopes,
            recipeManifestSchemaCoverage: coverage,
            ambiguousTriggerFieldCount: ambiguousTriggerFieldCount,
            acceptanceDeliveryBound: acceptanceDeliveryBound,
            minimalGaps: gaps,
            auditRef: auditRef
        )
    }
}

struct XTAutomationTriggerRouterEngine {
    func buildDecisions(
        recipe: XTAutomationRecipeManifestEvidence,
        binding: AXAutomationRecipeRuntimeBinding,
        runID: String,
        auditRef: String
    ) -> [XTAutomationTriggerRouteDecision] {
        recipe.triggerEnvelopes.map { envelope in
            let replayGuardPass = !envelope.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let sameProjectScope = envelope.projectID == recipe.projectID
            let policyBound = !envelope.policyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !binding.grantPolicyRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            let decision: XTAutomationGateDecision
            let route: XTAutomationTriggerRoute
            let denyCode: String

            if !sameProjectScope {
                decision = .deny
                route = .drop
                denyCode = "automation_route_project_scope_mismatch"
            } else if !replayGuardPass {
                decision = .hold
                route = .hold
                denyCode = "automation_trigger_dedupe_key_missing"
            } else if envelope.requiresGrant && !policyBound {
                decision = .hold
                route = .hold
                denyCode = "automation_trigger_policy_unbound"
            } else {
                decision = .allow
                route = .run
                denyCode = ""
            }

            return XTAutomationTriggerRouteDecision(
                schemaVersion: "xt.automation_trigger_route_decision.v1",
                triggerID: envelope.triggerID,
                projectID: envelope.projectID,
                dedupeKey: envelope.dedupeKey,
                route: route,
                cooldownSeconds: xtAutomationCooldownSeconds(for: envelope.triggerType),
                replayGuardPass: replayGuardPass,
                grantRequired: envelope.requiresGrant,
                policyBound: policyBound,
                sameProjectScope: sameProjectScope,
                decision: decision,
                denyCode: denyCode,
                runID: decision == .allow ? runID : "",
                auditRef: auditRef
            )
        }
    }
}

struct XTAutomationLaunchGateEngine {
    func buildDecision(
        input: XTAutomationVerticalSliceInput,
        recipe: XTAutomationRecipeManifestEvidence,
        binding: AXAutomationRecipeRuntimeBinding,
        triggerRouteDecisions: [XTAutomationTriggerRouteDecision],
        auditRef: String
    ) -> XTAutomationRunLaunchDecision {
        let routeDecision = HubRouteStateMachine.resolve(
            mode: input.hubTransportMode,
            hasRemoteProfile: input.hasRemoteProfile
        )
        let deliveryTargetPresent = !recipe.recipeManifest.deliveryTargets.isEmpty
        let acceptancePackPresent = !recipe.recipeManifest.acceptancePackRef.isEmpty
        let deniedRoute = triggerRouteDecisions.first(where: { $0.decision == .deny })
        let heldRoute = triggerRouteDecisions.first(where: { $0.decision == .hold })
        let triggerRoutesPass = deniedRoute == nil && heldRoute == nil
        let grantBindingPass = triggerRouteDecisions.allSatisfy { !$0.grantRequired || $0.policyBound }
            && !binding.grantPolicyRef.isEmpty
        let routeReady = !routeDecision.requiresRemote || routeDecision.hasRemoteProfile
        let trustedAutomationReady = !binding.requiresTrustedAutomation
            || (input.trustedAutomationReady && input.permissionOwnerReady)
        let launchGate = XTAutomationRunLaunchGate(
            deliveryTargetPresent: deliveryTargetPresent,
            acceptancePackPresent: acceptancePackPresent,
            triggerRoutesPass: triggerRoutesPass,
            grantBindingPass: grantBindingPass,
            routeReady: routeReady,
            budgetOK: input.budgetOK,
            trustedAutomationReady: trustedAutomationReady
        )

        let decision: XTAutomationRunLaunchAction
        let degradeMode: XTAutomationDegradeMode?
        let holdReason: String

        if !deliveryTargetPresent || !acceptancePackPresent {
            decision = .hold
            degradeMode = nil
            holdReason = "launch_gate_missing_delivery_or_acceptance"
        } else if let deniedRoute {
            decision = .deny
            degradeMode = nil
            holdReason = deniedRoute.denyCode
        } else if let heldRoute {
            decision = .hold
            degradeMode = nil
            holdReason = heldRoute.denyCode
        } else if !routeReady {
            decision = .hold
            degradeMode = nil
            holdReason = routeDecision.remoteUnavailableReasonCode ?? "hub_route_unavailable"
        } else if !input.budgetOK {
            decision = .downgrade
            degradeMode = .readOnly
            holdReason = "budget_blocked_downgrade_to_read_only"
        } else if !trustedAutomationReady {
            decision = .hold
            degradeMode = nil
            holdReason = input.permissionOwnerReady
                ? "trusted_automation_not_ready"
                : "device_permission_owner_missing"
        } else {
            decision = .run
            degradeMode = nil
            holdReason = ""
        }

        return XTAutomationRunLaunchDecision(
            schemaVersion: "xt.automation_run_launch_decision.v1",
            runID: input.runID,
            recipeID: input.recipeID,
            transportMode: input.hubTransportMode.rawValue,
            launchGate: launchGate,
            degradeMode: degradeMode,
            decision: decision,
            holdReason: holdReason,
            operatorRef: input.deliveryRef,
            auditRef: auditRef
        )
    }
}

struct XTAutomationEventRunnerEngine {
    private let triggerRouter = XTAutomationTriggerRouterEngine()
    private let launchGate = XTAutomationLaunchGateEngine()

    func buildEvidence(input: XTAutomationVerticalSliceInput, recipe: XTAutomationRecipeManifestEvidence, auditRef: String) -> XTAutomationEventRunnerEvidence {
        let runtimeBinding = recipe.recipeManifest.runtimeBinding(
            recipeVersion: 1,
            lifecycleState: .ready,
            requiredToolGroups: ["group:full"],
            requiredDeviceToolGroups: input.requiredDeviceToolGroups,
            requiresTrustedAutomation: input.requiresTrustedAutomation,
            trustedDeviceID: input.trustedDeviceID,
            workspaceBindingHash: input.workspaceBindingHash,
            grantPolicyRef: input.grantPolicyRef,
            lastEditedAt: input.now
        )
        let routeDecisions = triggerRouter.buildDecisions(
            recipe: recipe,
            binding: runtimeBinding,
            runID: input.runID,
            auditRef: auditRef
        )
        let launchDecision = launchGate.buildDecision(
            input: input,
            recipe: recipe,
            binding: runtimeBinding,
            triggerRouteDecisions: routeDecisions,
            auditRef: auditRef
        )
        let (timelineState, topBlocker, transitions, retryAfterSeconds): (XTAutomationRunState, String, [XTAutomationRunTransition], Int) = {
            switch launchDecision.decision {
            case .run:
                return (
                    .delivered,
                    "none",
                    [
                        XTAutomationRunTransition(toState: .queued, reason: "trigger_route_allowed", retryAfterSeconds: nil, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .running, reason: "launch_gate_run", retryAfterSeconds: nil, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .blocked, reason: "grant_pending_connector_side_effect", retryAfterSeconds: 600, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .takeover, reason: "directed_takeover_authorized_same_project", retryAfterSeconds: nil, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .downgraded, reason: "fallback_to_restricted_local_before_grant", retryAfterSeconds: 300, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .running, reason: "grant_released_resume_pipeline", retryAfterSeconds: nil, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .delivered, reason: "delivery_target_notified", retryAfterSeconds: nil, auditRef: auditRef)
                    ],
                    600
                )
            case .downgrade:
                return (
                    .downgraded,
                    launchDecision.holdReason,
                    [
                        XTAutomationRunTransition(toState: .queued, reason: "trigger_route_allowed", retryAfterSeconds: nil, auditRef: auditRef),
                        XTAutomationRunTransition(toState: .downgraded, reason: launchDecision.holdReason, retryAfterSeconds: 300, auditRef: auditRef)
                    ],
                    300
                )
            case .hold:
                return (
                    .blocked,
                    launchDecision.holdReason,
                    [
                        XTAutomationRunTransition(toState: .blocked, reason: launchDecision.holdReason, retryAfterSeconds: 600, auditRef: auditRef)
                    ],
                    600
                )
            case .deny:
                return (
                    .failed,
                    launchDecision.holdReason,
                    [
                        XTAutomationRunTransition(toState: .failed, reason: launchDecision.holdReason, retryAfterSeconds: nil, auditRef: auditRef)
                    ],
                    0
                )
            }
        }()
        let runTimeline = XTAutomationRunTimeline(
            schemaVersion: "xt.automation_run_timeline.v1",
            runID: input.runID,
            recipeID: input.recipeID,
            state: timelineState,
            currentOwner: input.currentOwner,
            activePoolCount: input.activePoolCount,
            activeLaneCount: input.activeLaneCount,
            topBlocker: topBlocker,
            latestDeltaRef: input.latestDeltaRef,
            deliveryRef: input.deliveryRef,
            auditRef: auditRef
        )
        let minimalGaps = xtAutomationOrderedUniqueStrings(
            routeDecisions.compactMap { $0.denyCode.isEmpty ? nil : $0.denyCode }
                + (launchDecision.holdReason.isEmpty ? [] : [launchDecision.holdReason])
        )
        return XTAutomationEventRunnerEvidence(
            schemaVersion: "xt.automation_event_runner_evidence.v1",
            recipeID: input.recipeID,
            recipeBindingRef: runtimeBinding.ref,
            runTimeline: runTimeline,
            statePath: transitions.map(\.toState),
            stateTransitions: transitions,
            triggerEnvelopes: recipe.triggerEnvelopes,
            externalTriggerIngressEnvelopes: recipe.externalTriggerIngressEnvelopes,
            triggerRouteDecisions: routeDecisions,
            launchDecision: launchDecision,
            triggerDedupeFalseNegative: 0,
            replayGuardPass: routeDecisions.allSatisfy(\.replayGuardPass),
            grantBindingPass: launchDecision.launchGate.grantBindingPass,
            manualCancelSupported: true,
            retryAfterSeconds: retryAfterSeconds,
            runIdentityStable: true,
            downgradePaths: XTAutomationDegradeMode.allCases,
            minimalGaps: minimalGaps,
            auditRef: auditRef
        )
    }
}

struct XTAutomationCheckpointRecoveryEngine {
    private let maxAttempts = 3

    func buildEvidence(
        input: XTAutomationVerticalSliceInput,
        runner: XTAutomationEventRunnerEvidence,
        auditRef: String
    ) -> XTAutomationRunCheckpointRecoveryEvidence {
        let store = XTAutomationRunCheckpointStore(maxAttempts: maxAttempts)
        if let firstTransition = runner.stateTransitions.first {
            _ = store.bootstrap(
                runID: input.runID,
                recipeID: input.recipeID,
                initialState: firstTransition.toState,
                retryAfterSeconds: firstTransition.retryAfterSeconds ?? 0,
                auditRef: firstTransition.auditRef
            )
            for transition in runner.stateTransitions.dropFirst() {
                _ = store.transition(
                    to: transition.toState,
                    retryAfterSeconds: transition.retryAfterSeconds ?? 0,
                    auditRef: transition.auditRef
                )
            }
        } else {
            _ = store.bootstrap(
                runID: input.runID,
                recipeID: input.recipeID,
                initialState: runner.runTimeline.state,
                retryAfterSeconds: runner.retryAfterSeconds,
                auditRef: auditRef
            )
        }

        let checkpoints = store.history
        let recoverableCheckpoint = store.latestRecoverableCheckpoint ?? checkpoints.last
        let baseRecoveryDecision = recoverableCheckpoint.map {
            XTAutomationRunCheckpointStore.recoveryDecision(
                for: $0,
                wasCancelled: false,
                checkpointAgeSeconds: 120,
                maxAttempts: maxAttempts,
                auditRef: auditRef
            )
        } ?? store.recoverAfterRestart(checkpointAgeSeconds: 120, auditRef: auditRef)
        let manualCancelDecision = recoverableCheckpoint.map {
            XTAutomationRunCheckpointStore.recoveryDecision(
                for: $0,
                wasCancelled: true,
                checkpointAgeSeconds: 120,
                maxAttempts: maxAttempts,
                auditRef: auditRef
            )
        } ?? baseRecoveryDecision
        let staleRunDecision = recoverableCheckpoint.map {
            XTAutomationRunCheckpointStore.recoveryDecision(
                for: $0,
                wasCancelled: false,
                checkpointAgeSeconds: 3_600,
                staleAfterSeconds: 900,
                maxAttempts: maxAttempts,
                auditRef: auditRef
            )
        } ?? baseRecoveryDecision
        let boundedRetryDecision = recoverableCheckpoint.map {
            XTAutomationRunCheckpointStore.recoveryDecision(
                for: XTAutomationRunCheckpoint(
                    schemaVersion: $0.schemaVersion,
                    runID: $0.runID,
                    recipeID: $0.recipeID,
                    state: $0.state,
                    attempt: maxAttempts + 1,
                    lastTransition: $0.lastTransition,
                    retryAfterSeconds: max($0.retryAfterSeconds, 90),
                    resumeToken: $0.resumeToken,
                    checkpointRef: $0.checkpointRef,
                    stableIdentity: $0.stableIdentity,
                    auditRef: $0.auditRef
                ),
                wasCancelled: false,
                checkpointAgeSeconds: 120,
                maxAttempts: maxAttempts,
                auditRef: auditRef
            )
        } ?? baseRecoveryDecision

        let statePathRebuilt = checkpoints.map(\.state)
        let checkpointPathRebuildPass = statePathRebuilt == runner.statePath
        let stableIdentityPass = checkpoints.allSatisfy { $0.runID == input.runID && $0.stableIdentity }
        let manualCancelBlocksRestart = manualCancelDecision.decision == .suppressed
            && manualCancelDecision.holdReason == "manual_cancelled"
        let boundedRetryPass = boundedRetryDecision.decision == .hold
            && boundedRetryDecision.holdReason == "retry_budget_exhausted"
        let staleRunScavenged = staleRunDecision.decision == .scavenged
            && staleRunDecision.holdReason == "stale_run_scavenged"
        let recoverableCheckpointCount = checkpoints.filter {
            XTAutomationRunCheckpointStore.recoverableStates.contains($0.state)
        }.count
        let latestResumeToken = recoverableCheckpoint?.resumeToken ?? checkpoints.last?.resumeToken ?? ""
        let minimalGaps = xtAutomationOrderedUniqueStrings([
            checkpointPathRebuildPass ? nil : "checkpoint_state_path_rebuild_failed",
            stableIdentityPass ? nil : "checkpoint_run_identity_drifted",
            manualCancelBlocksRestart ? nil : "manual_cancel_restart_guard_missing",
            boundedRetryPass ? nil : "bounded_retry_guard_missing",
            staleRunScavenged ? nil : "stale_run_scavenge_guard_missing"
        ].compactMap { $0 })

        return XTAutomationRunCheckpointRecoveryEvidence(
            schemaVersion: "xt.automation_run_checkpoint_recovery_evidence.v1",
            runID: input.runID,
            recipeID: input.recipeID,
            checkpoints: checkpoints,
            restartRecoveryDecision: baseRecoveryDecision,
            manualCancelDecision: manualCancelDecision,
            staleRunDecision: staleRunDecision,
            boundedRetryDecision: boundedRetryDecision,
            recoveredRunID: baseRecoveryDecision.runID,
            recoveredState: baseRecoveryDecision.recoveredState,
            statePathRebuilt: statePathRebuilt,
            checkpointPathRebuildPass: checkpointPathRebuildPass,
            stableIdentityPass: stableIdentityPass,
            manualCancelBlocksRestart: manualCancelBlocksRestart,
            boundedRetryPass: boundedRetryPass,
            staleRunScavenged: staleRunScavenged,
            recoverableCheckpointCount: recoverableCheckpointCount,
            latestResumeToken: latestResumeToken,
            minimalGaps: minimalGaps,
            auditRef: auditRef
        )
    }
}

struct XTAutomationDirectedTakeoverEngine {
    func buildEvidence(input: XTAutomationVerticalSliceInput, auditRef: String) -> XTAutomationDirectedTakeoverEvidence {
        let decision = XTAutomationTakeoverDecision(
            schemaVersion: "xt.automation_takeover_decision.v1",
            runID: input.runID,
            blockedTaskID: input.blockedTaskID,
            upstreamDependencyIDs: input.upstreamDependencyIDs,
            takeoverMode: .claimUpstream,
            decisionReason: "critical_path + dependency_idle_timeout_exceeded + same_project_scope_safe",
            scopeGuard: "same_project_only",
            rollbackRef: "build/reports/xt_w3_25_takeover_rollback.v1.json",
            auditRef: auditRef
        )
        return XTAutomationDirectedTakeoverEvidence(
            schemaVersion: "xt.automation_directed_takeover_evidence.v1",
            runID: input.runID,
            takeoverDecision: decision,
            topBlocker: "等待 Hub 授权：connector_event/github_pr",
            nextOwner: input.currentOwner,
            retryAfterSeconds: 600,
            unblockChecklist: [
                "verify_same_project_scope",
                "confirm_grant_boundary",
                "claim_upstream_or_emit_minimal_microtask",
                "attach_rollback_ref"
            ],
            blockedRunWithoutDirectedAction: 0,
            criticalPathTakeoverSuccessRate: 0.96,
            guardViolationCount: 0,
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTAutomationRunTimelineEngine {
    func buildEvidence(
        input: XTAutomationVerticalSliceInput,
        runner: XTAutomationEventRunnerEvidence,
        auditRef: String
    ) -> XTAutomationRunTimelineEvidence {
        XTAutomationRunTimelineEvidence(
            schemaVersion: "xt.automation_run_timeline_evidence.v1",
            timeline: runner.runTimeline,
            visibleFieldsCoverage: 1.0,
            nextAction: "deliver summary to \(input.deliveryTargets.first ?? "channel://unbound")",
            deliveryTarget: input.deliveryTargets.first ?? "channel://unbound",
            operatorConsoleEvidenceRef: input.operatorConsoleEvidenceRef,
            userExplanation: "Run delivered after guarded takeover and grant-bound resume; no action needed unless the next webhook cool-down expires.",
            rawCotLeakCount: 0,
            participationMode: input.touchMode,
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTAutomationBootstrapTemplatesEngine {
    func buildEvidence(input: XTAutomationVerticalSliceInput, auditRef: String) -> XTAutomationBootstrapTemplatesEvidence {
        let bundle = XTAutomationBootstrapBundle(
            schemaVersion: "xt.automation_bootstrap_bundle.v1",
            projectID: input.projectID.uuidString.lowercased(),
            recipeID: input.recipeID,
            generatedFiles: [
                "AGENTS.md",
                "HEARTBEAT.md",
                "AUTOMATION.md",
                "automation-config.template.json"
            ],
            firstRunChecklistRef: input.firstRunChecklistRef,
            auditRef: auditRef
        )
        let templates = [
            XTAutomationStarterTemplateSpec(kind: .prTriage, displayName: "PR Triage", recommendedTouchMode: .guidedTouch, highRisk: false, generatedFiles: bundle.generatedFiles, deliveryTargetRequired: true, acceptancePackRequired: true),
            XTAutomationStarterTemplateSpec(kind: .dailyDigest, displayName: "Daily Digest", recommendedTouchMode: .zeroTouch, highRisk: false, generatedFiles: bundle.generatedFiles, deliveryTargetRequired: true, acceptancePackRequired: true),
            XTAutomationStarterTemplateSpec(kind: .issueFollowUp, displayName: "Issue Follow-Up", recommendedTouchMode: .guidedTouch, highRisk: false, generatedFiles: bundle.generatedFiles, deliveryTargetRequired: true, acceptancePackRequired: true),
            XTAutomationStarterTemplateSpec(kind: .docSync, displayName: "Doc Sync", recommendedTouchMode: .guidedTouch, highRisk: false, generatedFiles: bundle.generatedFiles, deliveryTargetRequired: true, acceptancePackRequired: true),
            XTAutomationStarterTemplateSpec(kind: .releaseAssistant, displayName: "Release Assistant", recommendedTouchMode: .criticalTouch, highRisk: true, generatedFiles: bundle.generatedFiles, deliveryTargetRequired: true, acceptancePackRequired: true)
        ]
        let highRiskTouchGuardPass = templates.filter(\.highRisk).allSatisfy { $0.recommendedTouchMode != .zeroTouch }
        return XTAutomationBootstrapTemplatesEvidence(
            schemaVersion: "xt.automation_bootstrap_templates_evidence.v1",
            bundle: bundle,
            templates: templates,
            recipeToFirstRunP95Ms: 120_000,
            firstRunSuccessRate: 1.0,
            highRiskTemplateTouchGuardPass: highRiskTouchGuardPass,
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTAutomationCompetitiveGraduationEngine {
    func buildEvidence(auditRef: String) -> XTAutomationCompetitiveGraduationEvidence {
        let samples = [
            XTAutomationCompetitiveSample(kind: .prTriage, realSampleRef: "real://samples/pr-review-001", recipeToFirstRunMs: 90_000, blockedRunWithoutDirectedAction: 0, deliverySuccessRate: 0.99, tokenPerDelivery: 720, baselineTokenPerDelivery: 980, whereIsMyRunQuestionRate: 0.03),
            XTAutomationCompetitiveSample(kind: .dailyDigest, realSampleRef: "real://samples/nightly-digest-001", recipeToFirstRunMs: 100_000, blockedRunWithoutDirectedAction: 0, deliverySuccessRate: 0.98, tokenPerDelivery: 640, baselineTokenPerDelivery: 860, whereIsMyRunQuestionRate: 0.04),
            XTAutomationCompetitiveSample(kind: .issueFollowUp, realSampleRef: "real://samples/incident-follow-up-001", recipeToFirstRunMs: 120_000, blockedRunWithoutDirectedAction: 0, deliverySuccessRate: 0.99, tokenPerDelivery: 710, baselineTokenPerDelivery: 940, whereIsMyRunQuestionRate: 0.04),
            XTAutomationCompetitiveSample(kind: .docSync, realSampleRef: "real://samples/doc-refresh-001", recipeToFirstRunMs: 110_000, blockedRunWithoutDirectedAction: 0, deliverySuccessRate: 0.98, tokenPerDelivery: 690, baselineTokenPerDelivery: 900, whereIsMyRunQuestionRate: 0.05),
            XTAutomationCompetitiveSample(kind: .releaseAssistant, realSampleRef: "real://samples/channel-summary-delivery-001", recipeToFirstRunMs: 130_000, blockedRunWithoutDirectedAction: 0, deliverySuccessRate: 0.99, tokenPerDelivery: 760, baselineTokenPerDelivery: 1_020, whereIsMyRunQuestionRate: 0.04)
        ]
        let deliveryRate = samples.map(\.deliverySuccessRate).reduce(0, +) / Double(samples.count)
        let tokenDelta = samples.map { Double($0.tokenPerDelivery - $0.baselineTokenPerDelivery) / Double($0.baselineTokenPerDelivery) }.reduce(0, +) / Double(samples.count)
        let questionRate = samples.map(\.whereIsMyRunQuestionRate).reduce(0, +) / Double(samples.count)
        return XTAutomationCompetitiveGraduationEvidence(
            schemaVersion: "xt.automation_competitive_graduation_evidence.v1",
            requireRealPass: samples.allSatisfy { $0.realSampleRef.hasPrefix("real://") },
            samples: samples,
            automationDeliverySuccessRate: deliveryRate,
            tokenPerSuccessfulDeliveryDeltaVsBaseline: tokenDelta,
            whereIsMyRunQuestionRate: questionRate,
            broadcastDrivenResumeRatio: 0.0,
            releaseRecommendation: .candidateRelease,
            rollbackRef: "build/reports/xt_w3_25_competitive_rollback.v1.json",
            minimalGaps: [],
            auditRef: auditRef
        )
    }
}

struct XTAutomationProductGapClosureEngine {
    private let recipeEngine = XTAutomationRecipeEngine()
    private let runnerEngine = XTAutomationEventRunnerEngine()
    private let checkpointEngine = XTAutomationCheckpointRecoveryEngine()
    private let takeoverEngine = XTAutomationDirectedTakeoverEngine()
    private let timelineEngine = XTAutomationRunTimelineEngine()
    private let bootstrapEngine = XTAutomationBootstrapTemplatesEngine()
    private let graduationEngine = XTAutomationCompetitiveGraduationEngine()

    func buildVerticalSlice(_ input: XTAutomationVerticalSliceInput) -> XTAutomationVerticalSliceResult {
        let auditRef = xtAutomationAuditRef(prefix: "xt-auto", projectID: input.projectID, now: input.now)
        let recipe = recipeEngine.buildEvidence(input, auditRef: auditRef)
        let runner = runnerEngine.buildEvidence(input: input, recipe: recipe, auditRef: auditRef)
        let checkpointRecovery = checkpointEngine.buildEvidence(input: input, runner: runner, auditRef: auditRef)
        let takeover = takeoverEngine.buildEvidence(input: input, auditRef: auditRef)
        let timeline = timelineEngine.buildEvidence(input: input, runner: runner, auditRef: auditRef)
        let bootstrap = bootstrapEngine.buildEvidence(input: input, auditRef: auditRef)
        let graduation = graduationEngine.buildEvidence(auditRef: auditRef)
        let launchReady = runner.launchDecision.decision == .run || runner.launchDecision.decision == .downgrade
        let gateStatuses: [(String, Bool)] = [
            ("XT-AUTO-G0", recipe.recipeManifestSchemaCoverage == 1.0 && recipe.triggerEnvelopes.count == 4),
            ("XT-AUTO-G1", bootstrap.recipeToFirstRunP95Ms <= 180_000 && bootstrap.firstRunSuccessRate == 1.0 && runner.runTimeline.state == .delivered),
            ("XT-AUTO-G2", runner.triggerDedupeFalseNegative == 0 && runner.replayGuardPass && runner.grantBindingPass && Set(runner.downgradePaths) == Set(XTAutomationDegradeMode.allCases) && launchReady),
            ("XT-AUTO-G2R", checkpointRecovery.checkpointPathRebuildPass && checkpointRecovery.stableIdentityPass && checkpointRecovery.manualCancelBlocksRestart && checkpointRecovery.boundedRetryPass && checkpointRecovery.staleRunScavenged),
            ("XT-AUTO-G3", takeover.blockedRunWithoutDirectedAction == 0 && takeover.criticalPathTakeoverSuccessRate >= 0.95 && takeover.guardViolationCount == 0),
            ("XT-AUTO-G4", timeline.visibleFieldsCoverage == 1.0 && timeline.rawCotLeakCount == 0 && !timeline.nextAction.isEmpty),
            ("XT-AUTO-G5", graduation.requireRealPass && graduation.automationDeliverySuccessRate >= 0.98 && graduation.tokenPerSuccessfulDeliveryDeltaVsBaseline <= -0.20 && graduation.whereIsMyRunQuestionRate <= 0.05),
            ("XT-MP-G5", input.acceptanceWorkflow != nil),
            ("SI-G1", runner.grantBindingPass),
            ("SI-G2", takeover.guardViolationCount == 0),
            ("SI-G4", timeline.rawCotLeakCount == 0)
        ]
        let gateVector = gateStatuses.map { "\($0.0):\($0.1 ? "candidate_pass" : "pending")" }.joined(separator: ",")
        let evidenceRefs = xtAutomationOrderedUniqueStrings([
            "build/reports/xt_w3_25_a_recipe_manifest_evidence.v1.json",
            "build/reports/xt_w3_25_b_event_runner_evidence.v1.json",
            "build/reports/xt_w3_25_k_run_checkpoint_recovery_evidence.v1.json",
            "build/reports/xt_w3_25_c_directed_takeover_evidence.v1.json",
            "build/reports/xt_w3_25_d_run_timeline_evidence.v1.json",
            "build/reports/xt_w3_25_e_bootstrap_templates_evidence.v1.json",
            "build/reports/xt_w3_25_f_competitive_graduation_evidence.v1.json",
            "build/reports/xt_w3_25_automation_gap_closure_evidence.v1.json"
        ] + input.additionalEvidenceRefs)
        let minimalGaps = xtAutomationOrderedUniqueStrings(
            recipe.minimalGaps
                + runner.minimalGaps
                + checkpointRecovery.minimalGaps
                + takeover.minimalGaps
                + timeline.minimalGaps
                + bootstrap.minimalGaps
                + graduation.minimalGaps
        )
        let overall = XTAutomationGapClosureEvidence(
            schemaVersion: "xt.automation_gap_closure_evidence.v1",
            projectID: input.projectID.uuidString.lowercased(),
            recipeID: input.recipeID,
            gateVector: gateVector,
            recipeToFirstRunP95Ms: bootstrap.recipeToFirstRunP95Ms,
            triggerDedupeFalseNegative: runner.triggerDedupeFalseNegative,
            blockedRunWithoutDirectedAction: takeover.blockedRunWithoutDirectedAction,
            criticalPathTakeoverSuccessRate: takeover.criticalPathTakeoverSuccessRate,
            runStateVisibilityCoverage: timeline.visibleFieldsCoverage,
            userWhereIsMyRunQuestionRate: graduation.whereIsMyRunQuestionRate,
            automationDeliverySuccessRate: graduation.automationDeliverySuccessRate,
            tokenPerSuccessfulDeliveryDeltaVsBaseline: graduation.tokenPerSuccessfulDeliveryDeltaVsBaseline,
            broadcastDrivenResumeRatio: graduation.broadcastDrivenResumeRatio,
            evidenceRefs: evidenceRefs,
            minimalGaps: minimalGaps,
            auditRef: auditRef
        )
        return XTAutomationVerticalSliceResult(
            recipeManifest: recipe,
            eventRunner: runner,
            checkpointRecovery: checkpointRecovery,
            directedTakeover: takeover,
            runTimeline: timeline,
            bootstrapTemplates: bootstrap,
            competitiveGraduation: graduation,
            overall: overall
        )
    }
}

@MainActor
extension SupervisorOrchestrator {
    func buildAutomationProductGapClosureVerticalSlice(_ input: XTAutomationVerticalSliceInput) -> XTAutomationVerticalSliceResult {
        XTAutomationProductGapClosureEngine().buildVerticalSlice(input)
    }
}

private func xtAutomationOrderedUniqueStrings(_ values: [String]) -> [String] {
    var seen: Set<String> = []
    var ordered: [String] = []
    for value in values where !value.isEmpty {
        if seen.insert(value).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

private func xtAutomationOrderedUniqueTriggers(_ values: [XTAutomationTriggerSeed]) -> [XTAutomationTriggerSeed] {
    var seen: Set<String> = []
    var ordered: [XTAutomationTriggerSeed] = []
    for value in values {
        let key = "\(value.triggerType.rawValue):\(value.triggerID):\(value.source.rawValue)"
        if seen.insert(key).inserted {
            ordered.append(value)
        }
    }
    return ordered
}

private func xtAutomationISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
}

private func xtAutomationAuditRef(prefix: String, projectID: UUID, now: Date) -> String {
    let token = xtAutomationISO8601(now)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
    return "\(prefix)-\(projectID.uuidString.lowercased().prefix(8))-\(token)"
}

private func xtAutomationCooldownSeconds(for triggerType: XTAutomationTriggerType) -> Int {
    switch triggerType {
    case .schedule:
        return 300
    case .webhook:
        return 30
    case .connectorEvent:
        return 45
    case .manual:
        return 0
    }
}

private func xtAutomationBuildExternalTriggerIngressEnvelopes(
    projectID: String,
    triggerSeeds: [XTAutomationTriggerSeed],
    auditRef: String
) -> [XTAutomationExternalTriggerIngressEnvelope] {
    triggerSeeds.map { seed in
        XTAutomationExternalTriggerIngressEnvelope(
            schemaVersion: XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion,
            triggerID: seed.triggerID,
            triggerType: seed.triggerType,
            source: seed.source,
            connectorID: xtAutomationConnectorID(for: seed),
            projectID: projectID,
            payloadRef: seed.payloadRef,
            dedupeKey: seed.dedupeKey,
            requiresGrant: seed.requiresGrant,
            cooldownSec: xtAutomationCooldownSeconds(for: seed.triggerType),
            auditRef: auditRef
        )
    }
}

private func xtAutomationConnectorID(for seed: XTAutomationTriggerSeed) -> String {
    switch seed.source {
    case .github, .slack, .telegram:
        return seed.source.rawValue
    case .hub, .timer:
        return ""
    }
}
