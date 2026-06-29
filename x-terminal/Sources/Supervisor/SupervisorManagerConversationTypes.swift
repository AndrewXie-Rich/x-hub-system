import Foundation

extension SupervisorManager {
    struct SupervisorBriefProjectionVoiceReply {
        var text: String
        var spokenOutcome: SupervisorSpeechSynthesizer.Outcome
    }

    struct SupervisorBriefProjectionUnavailablePresentation {
        var text: String
        var script: [String]
        var dedupeKey: String
    }

    struct SupervisorVoicePendingGrantReply {
        var text: String
        var spokenOutcome: SupervisorSpeechSynthesizer.Outcome
    }

    struct SupervisorVoiceFollowUpReply {
        var text: String
        var spokenOutcome: SupervisorSpeechSynthesizer.Outcome
        var replySource: String
    }

    struct SupervisorGeneratedReply {
        var text: String
        var replySource: String
        var lifecycle: SupervisorAfterTurnLifecycleOptions = .default
    }

    struct SupervisorVoicePendingGrantActionContext {
        var requestId: String
        var grant: SupervisorPendingGrant
        var approve: Bool
    }

    struct SupervisorVoiceAuthorizationRestartContext {
        var request: SupervisorVoiceAuthorizationRequest
        var pendingGrantAction: SupervisorVoicePendingGrantActionContext?
    }

    struct SupervisorLocalWorkflowBootstrapSpec {
        var project: AXProjectEntry
        var digest: SupervisorMemoryProjectDigest
        var jobGoal: String
        var planId: String
        var steps: [SupervisorUpsertPlanStepPayload]
    }

    struct SupervisorMemoryProjectDigest: Identifiable, Equatable {
        var projectId: String
        var displayName: String
        var runtimeState: String
        var source: String
        var goal: String
        var currentState: String
        var nextStep: String
        var blocker: String
        var updatedAt: Double
        var recentMessageCount: Int
        var missingSpecFields: [SupervisorProjectSpecField] = []
        var shadowedBackgroundNoteCount: Int = 0
        var weakOnlyBackgroundNoteCount: Int = 0
        var decisionAssist: SupervisorDecisionBlockerAssist? = nil
        var memoryCompactionRollup: SupervisorMemoryCompactionRollup? = nil

        var id: String { projectId }
    }

    struct SupervisorProjectDigestGovernanceContext {
        var specCapsule: SupervisorProjectSpecCapsule?
        var missingSpecFields: [SupervisorProjectSpecField]
        var hardDecisions: [SupervisorDecisionCategory: SupervisorDecisionTrackEvent]
        var selectedEvidencePins: [SupervisorSelectedEvidencePin]
        var backgroundShadowHint: String
        var shadowedBackgroundNoteCount: Int
        var weakOnlyBackgroundNoteCount: Int
        var decisionAssist: SupervisorDecisionBlockerAssist?
        var resolvedGovernance: AXProjectResolvedGovernanceState?
        var updatedAt: TimeInterval
        var sourceTags: [String]
    }

    struct XTReadyIncidentInjectSpec {
        var laneID: String
        var incidentCode: String
    }

    struct SupervisorIncidentFrontstagePresentation: Equatable {
        var title: String
        var eventText: String
        var systemMessageText: String
        var notificationBody: String
    }

    struct ParsedAssignCommand {
        var projectRef: String?
        var role: AXRole
        var modelId: String
        var tag: String
    }

    enum SupervisorNaturalMemoryPatchFieldKind: String {
        case goal
        case doneDefinition = "done_definition"
        case nonGoal = "non_goal"
        case approvedTechStack = "approved_tech_stack"
        case decision
        case decisionReason = "decision_reason"
        case blocker
        case attemptedAction = "attempted_action"
        case currentState = "current_state"
        case nextStep = "next_step"
        case evidence
    }

    struct SupervisorNaturalMemoryPatchIntent {
        var goal: String?
        var doneDefinition: String?
        var nonGoals: [String]
        var approvedTechStack: [String]
        var decisionStatement: String?
        var decisionReason: String?
        var blockerSummary: String?
        var attemptedActions: [String]
        var currentStateSummary: String?
        var nextStepSummary: String?
        var selectedEvidence: [String]
        var explicitRequest: Bool

        var hasFacts: Bool {
            goal?.isEmpty == false ||
            doneDefinition?.isEmpty == false ||
            !nonGoals.isEmpty ||
            !approvedTechStack.isEmpty ||
            decisionStatement?.isEmpty == false ||
            decisionReason?.isEmpty == false ||
            blockerSummary?.isEmpty == false ||
            !attemptedActions.isEmpty ||
            currentStateSummary?.isEmpty == false ||
            nextStepSummary?.isEmpty == false ||
            !selectedEvidence.isEmpty
        }
    }

    struct SupervisorNaturalMemoryPatchApplyResult {
        var replyText: String
        var appliedKinds: [String]
        var noChangeDetected: Bool
    }

    enum SupervisorMemoryFactFollowUpCategory: String, CaseIterable {
        case goalAndDone = "goal_and_done"
        case decision = "decision"
        case blocker = "blocker"
        case evidence = "evidence"

        var question: String {
            switch self {
            case .goalAndDone:
                return "这个项目的长期目标和完成标准分别是什么？"
            case .decision:
                return "我们为什么走当前这条路径？关键决策和原因是什么？"
            case .blocker:
                return "现在卡在哪里，已经试过什么，下一步准备做什么？"
            case .evidence:
                return "哪些日志、结果、回执或实验可以作为这次判断的依据？"
            }
        }

        var example: String {
            switch self {
            case .goalAndDone:
                return "目标是……，完成标准是……"
            case .decision:
                return "我们决定……，原因是……"
            case .blocker:
                return "现在卡在……，已经试过……，下一步是……"
            case .evidence:
                return "证据是…… / 把……作为依据"
            }
        }

        var tailLabel: String {
            switch self {
            case .goalAndDone:
                return "长期目标和完成标准"
            case .decision:
                return "关键决策和原因"
            case .blocker:
                return "当前卡点、已试动作和下一步"
            case .evidence:
                return "判断依据"
            }
        }
    }

    enum SupervisorMemoryFactFollowUpPromptStyle {
        case initial
        case reminder
        case next
    }

    struct SupervisorPendingMemoryFactFollowUp {
        var projectId: String?
        var projectName: String?
        var issueSummary: String?
        var remainingCategories: [SupervisorMemoryFactFollowUpCategory]
        var createdAt: TimeInterval
        var updatedAt: TimeInterval
    }

    struct SupervisorPendingExecutionIntake {
        var originalRequest: String
        var goalSummary: String
        var track: String
        var suggestedProjectName: String
        var createdAt: TimeInterval
        var updatedAt: TimeInterval
    }

    struct SupervisorPendingProjectCreationGoalRequest {
        var projectId: String?
        var projectName: String?
        var createdAt: TimeInterval
        var updatedAt: TimeInterval
    }

    struct SupervisorRecoveredProjectCreationProposal {
        var projectName: String
        var goalSummary: String
        var track: String
        var sourceMessage: String
    }

    enum SupervisorProjectCreationReadiness {
        case bootstrapInProgress
        case pendingIntake(SupervisorPendingExecutionIntake)
        case recoveredProposal(SupervisorRecoveredProjectCreationProposal)
        case awaitingGoal
        case unavailable

        var reasonCode: String {
            switch self {
            case .bootstrapInProgress:
                return "create_bootstrap_in_progress"
            case .pendingIntake:
                return "create_trigger_required_pending_intake"
            case .recoveredProposal:
                return "create_trigger_required_recovered_proposal"
            case .awaitingGoal:
                return "create_goal_missing"
            case .unavailable:
                return "create_context_missing"
            }
        }
    }

    struct SupervisorExecutionProjectBootstrapSpec {
        var goal: String
        var doneDefinition: String
        var nonGoals: [String]
        var approvedTechStack: [String]
        var milestones: [SupervisorProjectSpecMilestone]
        var requirements: [String]
        var decisions: [String]
        var currentState: String
        var nextStep: String
        var jobGoal: String
        var planId: String
        var steps: [SupervisorUpsertPlanStepPayload]
        var statusDigest: String
    }

    struct SupervisorAfterTurnLifecycleContext {
        var userMessage: String
        var responseText: String
        var triggerSource: SupervisorCommandTriggerSource
        var triggeredByVoice: Bool
        var spokenOutcome: SupervisorSpeechSynthesizer.Outcome
        var replySource: String
        var personaSlot: SupervisorPersonaSlot?
        var turnRoutingDecision: SupervisorTurnRoutingDecision? = nil
        var turnRoutingDeltaCursor: String? = nil
        var frontstageReplyScopeOverride: SupervisorAssistantReplyScope? = nil
        var allowProactiveResume: Bool = false
        var lifecycle = SupervisorAfterTurnLifecycleOptions.default
    }

    struct SupervisorAssistantReplyScope {
        var projectId: String?
        var projectName: String?
        var requiresKnownProjectMatch: Bool
    }

    struct SupervisorAfterTurnLifecycleOptions {
        var shouldRecordReviewNote: Bool = true
        var shouldSyncDerivedPersonalContext: Bool = true
        var shouldRegisterConversationTurn: Bool = true
        var shouldScheduleTalkLoopResume: Bool = true
        var shouldSyncVoiceMemoryFollowUp: Bool = true

        static let `default` = SupervisorAfterTurnLifecycleOptions()

        static let nonReviewAssistantReply = SupervisorAfterTurnLifecycleOptions(
            shouldRecordReviewNote: false,
            shouldSyncDerivedPersonalContext: true,
            shouldRegisterConversationTurn: true,
            shouldScheduleTalkLoopResume: true,
            shouldSyncVoiceMemoryFollowUp: true
        )

        static let backgroundAssistantReply = SupervisorAfterTurnLifecycleOptions(
            shouldRecordReviewNote: true,
            shouldSyncDerivedPersonalContext: true,
            shouldRegisterConversationTurn: false,
            shouldScheduleTalkLoopResume: false,
            shouldSyncVoiceMemoryFollowUp: false
        )

        static let backgroundNonReviewAssistantReply = SupervisorAfterTurnLifecycleOptions(
            shouldRecordReviewNote: false,
            shouldSyncDerivedPersonalContext: true,
            shouldRegisterConversationTurn: false,
            shouldScheduleTalkLoopResume: false,
            shouldSyncVoiceMemoryFollowUp: false
        )
    }

    struct SupervisorDerivedContextLabel: Equatable {
        var id: String
        var label: String
    }

    struct SupervisorDerivedPersonalContextState: Equatable {
        var reviewDueCount: Int
        var reviewOverdueCount: Int
        var followUpOpenCount: Int
        var followUpOverdueCount: Int
        var reviewLabels: [SupervisorDerivedContextLabel]
        var followUpLabels: [SupervisorDerivedContextLabel]
    }

    struct SupervisorMemoryFactFollowUpReminder {
        var fingerprint: String
        var notificationIdentifier: String
        var title: String
        var body: String
        var actionURL: String?
    }

    struct DirectModelAssignmentIntent {
        var appliesToAllProjects: Bool
        var projectRef: String?
        var role: AXRole
        var usedDefaultRole: Bool
        var modelId: String
        var sourceModelToken: String
    }

    enum ModelTokenResolution {
        case resolved(String)
        case auto
        case ambiguous([HubModel])
        case inventoryUnavailable
        case notFound
    }
}
