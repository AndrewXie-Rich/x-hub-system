import Foundation

@MainActor
extension SupervisorViewRuntimePresentationSupport {
    static func infrastructureFeedPresentation(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorInfrastructureFeedPresentation {
        SupervisorInfrastructureFeedPresentation.map(
            input: SupervisorInfrastructureFeedInput(
                officialSkillsStatusLine: supervisor.supervisorOfficialSkillsChannelStatusLine,
                officialSkillsTransitionLine: supervisor.supervisorOfficialSkillsChannelTransitionLine,
                officialSkillsTopBlockersLine: supervisor.supervisorOfficialSkillsChannelTopBlockersLine,
                officialSkillsTopBlockerSummaries: supervisor.supervisorOfficialSkillsChannelTopBlockerSummaries,
                builtinGovernedSkills: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills,
                managedSkillsStatusLine: appModel.skillsCompatibilitySnapshot.statusLine,
                historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine,
                memoryReadiness: supervisor.supervisorMemoryAssemblyReadiness,
                memoryAssemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot,
                eventLoopStatusLine: supervisor.frontstageSupervisorEventLoopStatusLine,
                pendingHubGrants: supervisor.frontstagePendingHubGrants,
                pendingSupervisorSkillApprovals: supervisor.frontstagePendingSupervisorSkillApprovals,
                candidateReviews: supervisor.frontstageSupervisorCandidateReviews,
                candidateReviewProjectNamesByID: supervisor.frontstageSupervisorCandidateReviewProjectNames,
                recentEventLoopActivities: supervisor.frontstageRecentSupervisorEventLoopActivities
            )
        )
    }

    static func recentSkillActivityPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorSkillActivityFeedPresentation {
        SupervisorSkillActivityFeedPresentation.map(
            items: supervisor.frontstageRecentSupervisorSkillActivities
        )
    }

    static func recentSkillActivityBoardPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorRecentSkillActivityBoardPresentation {
        SupervisorRecentSkillActivityBoardPresentationMapper.map(
            feed: recentSkillActivityPresentation(supervisor: supervisor)
        )
    }

    static func auditDrillDownContext(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorAuditDrillDownResolver.Context {
        SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: supervisor.supervisorOfficialSkillsChannelStatusLine,
            officialSkillsTransitionLine: supervisor.supervisorOfficialSkillsChannelTransitionLine,
            officialSkillsDetailLine: supervisor.supervisorOfficialSkillsChannelDetailLine,
            officialSkillsTopBlockerSummaries: supervisor.supervisorOfficialSkillsChannelTopBlockerSummaries,
            builtinGovernedSkills: appModel.skillsCompatibilitySnapshot.builtinGovernedSkills,
            managedSkillsStatusLine: appModel.skillsCompatibilitySnapshot.statusLine,
            eventLoopStatusLine: supervisor.frontstageSupervisorEventLoopStatusLine,
            pendingHubGrants: supervisor.frontstagePendingHubGrants,
            pendingSupervisorSkillApprovals: supervisor.frontstagePendingSupervisorSkillApprovals,
            candidateReviews: supervisor.frontstageSupervisorCandidateReviews,
            candidateReviewProjectNamesByID: supervisor.frontstageSupervisorCandidateReviewProjectNames,
            recentSupervisorSkillActivities: supervisor.frontstageRecentSupervisorSkillActivities,
            recentSupervisorEventLoopActivities: supervisor.frontstageRecentSupervisorEventLoopActivities
        )
    }

    static func focusRequestContext(
        supervisor: SupervisorManager
    ) -> SupervisorFocusRequestEffects.Context {
        SupervisorFocusRequestEffects.Context(
            pendingHubGrants: supervisor.frontstagePendingHubGrants,
            pendingSupervisorSkillApprovals: supervisor.frontstagePendingSupervisorSkillApprovals,
            candidateReviews: supervisor.frontstageSupervisorCandidateReviews,
            recentSupervisorSkillActivities: supervisor.frontstageRecentSupervisorSkillActivities
        )
    }

    static func eventLoopBoardPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorEventLoopBoardPresentation {
        SupervisorEventLoopFeedPresentation.board(
            items: supervisor.frontstageRecentSupervisorEventLoopActivities,
            recentSkillActivities: supervisor.frontstageRecentSupervisorSkillActivities,
            statusLine: supervisor.frontstageSupervisorEventLoopStatusLine
        )
    }

    static func pendingHubGrantBoardPresentation(
        supervisor: SupervisorManager,
        hubInteractive: Bool,
        focusedRowAnchor: String?
    ) -> SupervisorPendingHubGrantBoardPresentation {
        SupervisorPendingHubGrantPresentation.board(
            grants: supervisor.frontstagePendingHubGrants,
            source: supervisor.pendingHubGrantSource,
            hasFreshSnapshot: supervisor.hasFreshPendingHubGrantSnapshot,
            updatedAt: supervisor.pendingHubGrantUpdatedAt,
            recentSkillActivities: supervisor.frontstageRecentSupervisorSkillActivities,
            inFlightGrantIDs: supervisor.pendingHubGrantActionsInFlight,
            hubInteractive: hubInteractive,
            focusedRowAnchor: focusedRowAnchor
        )
    }

    static func supervisorCandidateReviewBoardPresentation(
        supervisor: SupervisorManager,
        hubInteractive: Bool,
        focusedRowAnchor: String?
    ) -> SupervisorCandidateReviewBoardPresentation {
        SupervisorCandidateReviewPresentation.board(
            items: supervisor.frontstageSupervisorCandidateReviews,
            source: supervisor.supervisorCandidateReviewSource,
            hasFreshSnapshot: supervisor.hasFreshSupervisorCandidateReviewSnapshot,
            updatedAt: supervisor.supervisorCandidateReviewUpdatedAt,
            inFlightRequestIDs: supervisor.supervisorCandidateReviewActionsInFlight,
            hubInteractive: hubInteractive,
            projectNamesByID: supervisor.frontstageSupervisorCandidateReviewProjectNames,
            focusedRowAnchor: focusedRowAnchor
        )
    }

    static func pendingSkillApprovalBoardPresentation(
        supervisor: SupervisorManager,
        focusedRowAnchor: String?
    ) -> SupervisorPendingSkillApprovalBoardPresentation {
        SupervisorPendingSkillApprovalPresentation.board(
            approvals: supervisor.frontstagePendingSupervisorSkillApprovals,
            focusedRowAnchor: focusedRowAnchor
        )
    }

    static func memoryBoardPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorMemoryBoardPresentation {
        SupervisorMemoryBoardPresentationMapper.map(
            statusLine: supervisor.supervisorMemoryStatusLine,
            memorySource: supervisor.supervisorMemorySource,
            replyExecutionMode: supervisor.lastSupervisorReplyExecutionMode,
            requestedModelId: supervisor.lastSupervisorRequestedModelId,
            actualModelId: supervisor.lastSupervisorActualModelId,
            failureReasonCode: supervisor.lastSupervisorRemoteFailureReasonCode,
            readiness: supervisor.supervisorMemoryAssemblyReadiness,
            rawAssemblyStatusLine: supervisor.supervisorMemoryAssemblyStatusLine,
            afterTurnSummary: supervisor.supervisorAfterTurnDerivedSummary,
            pendingFollowUpQuestion: supervisor.supervisorPendingMemoryFactFollowUpQuestion,
            assemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot,
            skillRegistryStatusLine: supervisor.supervisorSkillRegistryStatusLine,
            skillRegistrySnapshot: supervisor.supervisorSkillRegistrySnapshot,
            turnRoutingDecision: supervisor.supervisorLatestTurnRoutingDecision,
            turnContextAssembly: supervisor.supervisorLatestTurnContextAssembly,
            writebackClassification: supervisor.supervisorAfterTurnWritebackClassification,
            modelRouteContext: supervisor.supervisorLatestModelRouteContext,
            digests: supervisor.supervisorMemoryProjectDigests,
            preview: supervisor.supervisorMemoryPreview
        )
    }
}
