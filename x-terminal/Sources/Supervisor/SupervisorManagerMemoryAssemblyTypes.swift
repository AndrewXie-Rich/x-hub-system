import Foundation

extension SupervisorManager {
    struct SupervisorMemoryBuildInfo {
        var text: String
        var source: String
        var updatedAt: TimeInterval
        var assemblySnapshot: SupervisorMemoryAssemblySnapshot?
        var projectDigests: [SupervisorMemoryProjectDigest]
        var skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
    }

    struct SupervisorMemoryComposition {
        var memoryPolicy: XTSupervisorMemoryPolicy
        var servingProfile: XTMemoryServingProfile
        var triggerSource: SupervisorCommandTriggerSource
        var governanceReviewTrigger: SupervisorReviewTrigger?
        var governanceReviewRunKind: SupervisorReviewRunKind?
        var reviewLevelHint: SupervisorReviewLevel
        var dominantMode: SupervisorTurnMode
        var constitution: String
        var dialogueWindow: String
        var dialogueWindowProfile: XTSupervisorRecentRawContextProfile
        var dialogueWindowFloorPairs: Int
        var dialogueWindowCeilingPairs: Int?
        var dialogueWindowSelectedPairs: Int
        var dialogueWindowEligibleMessages: Int
        var dialogueWindowLowSignalDroppedMessages: Int
        var dialogueWindowSource: String
        var continuityFloorSatisfied: Bool
        var continuityTruncationAfterFloor: Bool
        var rollingDialogueDigestPresent: Bool
        var dialogueWindowContinuityTraceLines: [String]
        var dialogueWindowLowSignalDropSampleLines: [String]
        var portfolioBrief: String
        var focusedProjectAnchorPack: String
        var crossLinkRefs: String
        var longtermOutline: String
        var deltaFeed: String
        var conflictSet: String
        var contextRefs: String
        var evidencePack: String
        var canonical: String
        var observations: String
        var workingSet: String
        var rawEvidence: String
        var localText: String
        var focusedProjectId: String?
        var profileFloor: XTMemoryServingProfile
        var minimumPack: [String]
        var servingObjectContract: [String]
        var compressionPolicy: String
        var selectedSections: [String]
        var omittedSections: [String]
        var contextRefsSelectedCount: Int
        var contextRefsOmittedCount: Int
        var evidenceItemsSelectedCount: Int
        var evidenceItemsOmittedCount: Int
        var latestReviewNoteAvailable: Bool
        var latestGuidanceAvailable: Bool
        var latestGuidanceAckStatus: String
        var latestGuidanceAckRequired: Bool?
        var latestGuidanceDeliveryMode: String
        var latestGuidanceInterventionMode: String
        var latestGuidanceSafePointPolicy: String
        var pendingAckGuidanceAvailable: Bool
        var pendingAckGuidanceAckStatus: String
        var pendingAckGuidanceAckRequired: Bool?
        var pendingAckGuidanceDeliveryMode: String
        var pendingAckGuidanceInterventionMode: String
        var pendingAckGuidanceSafePointPolicy: String
        var projectDigests: [SupervisorMemoryProjectDigest]
        var skillRegistrySnapshot: SupervisorSkillRegistrySnapshot?
        var scopedPromptRecoveryMode: String?
        var scopedPromptRecoverySections: [String]
    }

    struct SupervisorDialogueWindowSelection {
        var text: String
        var profile: XTSupervisorRecentRawContextProfile
        var floorPairs: Int
        var ceilingPairs: Int?
        var selectedPairs: Int
        var eligibleMessages: Int
        var lowSignalDroppedMessages: Int
        var source: String
        var rollingDigestPresent: Bool
        var continuityFloorSatisfied: Bool
        var truncationAfterFloor: Bool
        var continuityTraceLines: [String]
        var lowSignalDropSampleLines: [String]
    }

    struct SupervisorRemotePromptVariant {
        var label: String
        var prompt: String
        var promptMode: SupervisorSystemPromptMode
        var maxTokens: Int
        var promptTokenEstimate: Int
        var totalTokenEstimate: Int
        var selectedSections: [String]
        var omittedSections: [String]
        var contextRefsSelected: Int
        var contextRefsOmitted: Int
        var evidenceItemsSelected: Int
        var evidenceItemsOmitted: Int
    }

    struct SupervisorServingGovernorMetadata {
        var profileFloor: XTMemoryServingProfile
        var minimumPack: [String]
        var compressionPolicy: String
    }

    struct SupervisorContextRefsRenderResult {
        var text: String
        var selectedCount: Int
        var omittedCount: Int
    }

    struct SupervisorEvidencePackRenderResult {
        var text: String
        var selectedCount: Int
        var omittedCount: Int
    }

    struct SupervisorEventLoopTrigger {
        var activityId: String
        var ledgerId: String
        var userMessage: String
        var triggerSource: SupervisorCommandTriggerSource
        var dedupeKey: String
        var projectId: String
        var projectName: String
        var triggerSummary: String
        var policySummary: String
        var blockedSummary: String
        var policyReason: String
        var governanceTruth: String
        var grantRequestId: String
        var grantCapability: String
    }

    struct SupervisorWorkflowMemorySlice {
        var canonical: String
        var observation: String
        var workingSet: String
    }

    struct SupervisorFocusedProjectSelection {
        var project: AXProjectEntry
        var source: String
    }

    struct SupervisorProjectMemoryBindingDecision {
        var strength: SupervisorProjectMemoryBindingStrength
        var effectiveSelection: SupervisorFocusedProjectSelection?
        var projectMemorySuppressedForPureChat: Bool
        var suppressionReason: String?
    }

    struct SupervisorRepoInspectionIntent {
        enum Action {
            case readFiles([String])
            case listDirectory(String)
        }

        var action: Action

        var rawPaths: [String] {
            switch action {
            case .readFiles(let paths):
                return paths
            case .listDirectory(let path):
                return [path]
            }
        }
    }

    struct SupervisorFocusedProjectExecutionBrief {
        var anchorPackBody: String
        var longtermOutlineBody: String
        var decisionLineageBody: String
        var blockerLineageBody: String
        var canonical: String
        var observation: String
        var workingSet: String
    }

    struct SupervisorPersonaSelection {
        var executionPersona: SupervisorPersonaSlot
        var resolution: SupervisorPersonaResolution
    }

    struct SupervisorFocusedProjectServingContext {
        var project: AXProjectEntry
        var ctx: AXProjectContext
        var digest: SupervisorMemoryProjectDigest
        var governance: SupervisorProjectDigestGovernanceContext
        var recent: AXRecentContext
        var latestReview: SupervisorReviewNoteRecord?
        var latestGuidance: SupervisorGuidanceInjectionRecord?
        var pendingAckGuidance: SupervisorGuidanceInjectionRecord?
        var activeJob: SupervisorJobRecord?
        var activePlan: SupervisorPlanRecord?
        var activeSkillCall: SupervisorSkillCallRecord?
        var servingProfile: XTMemoryServingProfile
        var reviewLevelHint: SupervisorReviewLevel
        var doneDefinition: String
        var currentConstraints: [String]
        var longtermOutlineBody: String
        var decisionLineageDigest: String
        var blockerLineageDigest: String
        var recentMessagesDigest: String
        var nextPendingStepsDigest: String
        var attentionStepsDigest: String
    }

    struct SupervisorConflictItem {
        var conflictId: String
        var conflictKind: String
        var summary: String
        var sideA: String
        var sideB: String
        var resolutionStatus: String
        var refs: [String]
    }

    struct SupervisorContextRefItem {
        var refId: String
        var refKind: String
        var title: String
        var sourceScope: String
        var tokenCostHint: String
        var freshnessHint: String
    }

    struct SupervisorEvidenceItem {
        var refId: String
        var title: String
        var excerpt: String
        var whyIncluded: String
        var sourceScope: String
        var freshnessHint: String
    }

    struct SupervisorRecentEventRecord {
        var id: String
        var createdAt: TimeInterval
        var text: String
        var projectId: String?
        var projectName: String?
        var requiresKnownProjectMatch: Bool
    }

    struct SupervisorDeltaFeedProjection {
        var cursorFrom: String
        var cursorTo: String
        var focusProjectId: String
        var projectStateHashBefore: String
        var projectStateHashAfter: String
        var portfolioStateHashBefore: String
        var portfolioStateHashAfter: String
        var materialChangeFlags: [String]
        var deltaItems: [String]
        var recentProjectActions: [String]
        var recentActionLedger: [String]
        var recentEventLines: [String]
    }
}
