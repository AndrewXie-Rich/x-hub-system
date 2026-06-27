import Foundation

extension HubMemoryRetrievalBuilder {
    struct Candidate {
        var snippetId: String
        var sourceKind: String
        var title: String
        var ref: String
        var text: String
        var score: Int
        var truncated: Bool
    }

    struct SanitizeResult {
        var text: String
        var redactedItems: Int
        var truncated: Bool
    }

    enum RetrievalLayer: String {
        case l1Canonical = "l1_canonical"
        case l2Observations = "l2_observations"
    }

    struct ProjectSpecCapsuleFile: Decodable {
        var goal: String
        var mvpDefinition: String
        var nonGoals: [String]
        var approvedTechStack: [String]
        var milestoneMap: [ProjectSpecMilestoneFile]

        enum CodingKeys: String, CodingKey {
            case goal
            case mvpDefinition = "mvp_definition"
            case nonGoals = "non_goals"
            case approvedTechStack = "approved_tech_stack"
            case milestoneMap = "milestone_map"
        }
    }

    struct ProjectSpecMilestoneFile: Decodable {
        var title: String
        var status: String
    }

    struct DecisionTrackSnapshotFile: Decodable {
        var events: [DecisionTrackEventFile]
    }

    struct DecisionTrackEventFile: Decodable {
        var decisionId: String
        var category: String
        var status: String
        var statement: String
        var source: String
        var approvedBy: String
        var auditRef: String
        var updatedAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case decisionId = "decision_id"
            case category
            case status
            case statement
            case source
            case approvedBy = "approved_by"
            case auditRef = "audit_ref"
            case updatedAtMs = "updated_at_ms"
        }
    }

    struct BackgroundPreferenceSnapshotFile: Decodable {
        var notes: [BackgroundPreferenceNoteFile]
    }

    struct BackgroundPreferenceNoteFile: Decodable {
        var noteId: String
        var domain: String
        var strength: String
        var statement: String
        var createdAtMs: Int64

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case domain
            case strength
            case statement
            case createdAtMs = "created_at_ms"
        }
    }

    struct RecentContextFile: Decodable {
        var messages: [RecentContextMessageFile]
    }

    struct RecentContextMessageFile: Decodable {
        var role: String
        var content: String
        var createdAt: Double

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case createdAt = "created_at"
        }
    }

    struct AutomationCheckpointFile: Decodable {
        var runID: String
        var state: String
        var attempt: Int
        var retryAfterSeconds: Int
        var checkpointRef: String
        var stableIdentity: Bool
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case state
            case attempt
            case retryAfterSeconds = "retry_after_seconds"
            case checkpointRef = "checkpoint_ref"
            case stableIdentity = "stable_identity"
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
            case auditRef = "audit_ref"
        }
    }

    struct AutomationVerificationReportFile: Decodable {
        var required: Bool
        var executed: Bool
        var commandCount: Int
        var passedCommandCount: Int
        var holdReason: String

        enum CodingKeys: String, CodingKey {
            case required
            case executed
            case commandCount = "command_count"
            case passedCommandCount = "passed_command_count"
            case holdReason = "hold_reason"
        }
    }

    struct AutomationBlockerFile: Decodable {
        var code: String
        var summary: String
        var stage: String
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case code
            case summary
            case stage
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    struct AutomationRetryReasonDescriptorFile: Decodable {
        var code: String
        var summary: String
        var strategy: String
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case code
            case summary
            case strategy
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    struct AutomationRunHandoffFile: Decodable {
        var runID: String
        var recipeRef: String
        var deliveryRef: String?
        var finalState: String
        var holdReason: String
        var detail: String
        var verificationReport: AutomationVerificationReportFile?
        var structuredBlocker: AutomationBlockerFile?
        var suggestedNextActions: [String]
        var currentStepID: String?
        var currentStepTitle: String?
        var currentStepState: String?
        var currentStepSummary: String?

        enum CodingKeys: String, CodingKey {
            case runID = "run_id"
            case recipeRef = "recipe_ref"
            case deliveryRef = "delivery_ref"
            case finalState = "final_state"
            case holdReason = "hold_reason"
            case detail
            case verificationReport = "verification_report"
            case structuredBlocker = "structured_blocker"
            case suggestedNextActions = "suggested_next_actions"
            case currentStepID = "current_step_id"
            case currentStepTitle = "current_step_title"
            case currentStepState = "current_step_state"
            case currentStepSummary = "current_step_summary"
        }
    }

    struct AutomationRetryPackageFile: Decodable {
        var deliveryRef: String?
        var sourceRunID: String
        var sourceFinalState: String
        var sourceHoldReason: String
        var sourceBlocker: AutomationBlockerFile?
        var retryStrategy: String
        var retryReason: String
        var retryReasonDescriptor: AutomationRetryReasonDescriptorFile?
        var planningMode: String?
        var planningSummary: String?
        var retryRunID: String

        enum CodingKeys: String, CodingKey {
            case deliveryRef = "delivery_ref"
            case sourceRunID = "source_run_id"
            case sourceFinalState = "source_final_state"
            case sourceHoldReason = "source_hold_reason"
            case sourceBlocker = "source_blocker"
            case retryStrategy = "retry_strategy"
            case retryReason = "retry_reason"
            case retryReasonDescriptor = "retry_reason_descriptor"
            case planningMode = "planning_mode"
            case planningSummary = "planning_summary"
            case retryRunID = "retry_run_id"
        }
    }

    struct GuidanceInjectionSnapshotFile: Decodable {
        var items: [GuidanceInjectionRecordFile]
    }

    struct GuidanceInjectionRecordFile: Decodable {
        var injectionId: String
        var reviewId: String
        var deliveryMode: String
        var interventionMode: String
        var safePointPolicy: String
        var guidanceText: String
        var ackStatus: String
        var ackRequired: Bool
        var effectiveSupervisorTier: String?
        var workOrderRef: String?
        var injectedAtMs: Int64
        var auditRef: String

        enum CodingKeys: String, CodingKey {
            case injectionId = "injection_id"
            case reviewId = "review_id"
            case deliveryMode = "delivery_mode"
            case interventionMode = "intervention_mode"
            case safePointPolicy = "safe_point_policy"
            case guidanceText = "guidance_text"
            case ackStatus = "ack_status"
            case ackRequired = "ack_required"
            case effectiveSupervisorTier = "effective_supervisor_tier"
            case workOrderRef = "work_order_ref"
            case injectedAtMs = "injected_at_ms"
            case auditRef = "audit_ref"
        }
    }

    struct HeartbeatProjectionFile: Decodable {
        var createdAtMs: Int64
        var rawPayload: HeartbeatRawPayloadFile
        var canonicalProjection: HeartbeatCanonicalProjectionFile?

        enum CodingKeys: String, CodingKey {
            case createdAtMs = "created_at_ms"
            case rawPayload = "raw_payload"
            case canonicalProjection = "canonical_projection"
        }
    }

    struct HeartbeatCanonicalProjectionFile: Decodable {
        var auditRef: String?

        enum CodingKeys: String, CodingKey {
            case auditRef = "audit_ref"
        }
    }

    struct HeartbeatRawPayloadFile: Decodable {
        var statusDigest: String
        var currentStateSummary: String
        var nextStepSummary: String
        var blockerSummary: String
        var latestQualityBand: String?
        var latestQualityScore: Int?
        var executionStatus: String?
        var riskTier: String?
        var recoveryDecision: HeartbeatRecoveryDecisionFile?

        enum CodingKeys: String, CodingKey {
            case statusDigest = "status_digest"
            case currentStateSummary = "current_state_summary"
            case nextStepSummary = "next_step_summary"
            case blockerSummary = "blocker_summary"
            case latestQualityBand = "latest_quality_band"
            case latestQualityScore = "latest_quality_score"
            case executionStatus = "execution_status"
            case riskTier = "risk_tier"
            case recoveryDecision = "recovery_decision"
        }
    }

    struct HeartbeatRecoveryDecisionFile: Decodable {
        var action: String
        var urgency: String
        var reasonCode: String
        var summary: String
        var queuedReviewTrigger: String?
        var queuedReviewLevel: String?
        var queuedReviewRunKind: String?

        enum CodingKeys: String, CodingKey {
            case action
            case urgency
            case reasonCode = "reason_code"
            case summary
            case queuedReviewTrigger = "queued_review_trigger"
            case queuedReviewLevel = "queued_review_level"
            case queuedReviewRunKind = "queued_review_run_kind"
        }
    }

}
