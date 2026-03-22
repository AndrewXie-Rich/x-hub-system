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
                eventLoopStatusLine: supervisor.supervisorEventLoopStatusLine,
                pendingHubGrants: supervisor.pendingHubGrants,
                pendingSupervisorSkillApprovals: supervisor.pendingSupervisorSkillApprovals,
                recentEventLoopActivities: supervisor.recentSupervisorEventLoopActivities
            )
        )
    }

    static func recentSkillActivityPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorSkillActivityFeedPresentation {
        SupervisorSkillActivityFeedPresentation.map(
            items: supervisor.recentSupervisorSkillActivities
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
            eventLoopStatusLine: supervisor.supervisorEventLoopStatusLine,
            pendingHubGrants: supervisor.pendingHubGrants,
            pendingSupervisorSkillApprovals: supervisor.pendingSupervisorSkillApprovals,
            recentSupervisorSkillActivities: supervisor.recentSupervisorSkillActivities,
            recentSupervisorEventLoopActivities: supervisor.recentSupervisorEventLoopActivities
        )
    }

    static func focusRequestContext(
        supervisor: SupervisorManager
    ) -> SupervisorFocusRequestEffects.Context {
        SupervisorFocusRequestEffects.Context(
            pendingHubGrants: supervisor.pendingHubGrants,
            pendingSupervisorSkillApprovals: supervisor.pendingSupervisorSkillApprovals,
            recentSupervisorSkillActivities: supervisor.recentSupervisorSkillActivities
        )
    }

    static func eventLoopBoardPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorEventLoopBoardPresentation {
        SupervisorEventLoopFeedPresentation.board(
            items: supervisor.recentSupervisorEventLoopActivities,
            statusLine: supervisor.supervisorEventLoopStatusLine
        )
    }

    static func pendingHubGrantBoardPresentation(
        supervisor: SupervisorManager,
        hubInteractive: Bool,
        focusedRowAnchor: String?
    ) -> SupervisorPendingHubGrantBoardPresentation {
        SupervisorPendingHubGrantPresentation.board(
            grants: supervisor.pendingHubGrants,
            source: supervisor.pendingHubGrantSource,
            hasFreshSnapshot: supervisor.hasFreshPendingHubGrantSnapshot,
            updatedAt: supervisor.pendingHubGrantUpdatedAt,
            inFlightGrantIDs: supervisor.pendingHubGrantActionsInFlight,
            hubInteractive: hubInteractive,
            focusedRowAnchor: focusedRowAnchor
        )
    }

    static func pendingSkillApprovalBoardPresentation(
        supervisor: SupervisorManager,
        focusedRowAnchor: String?
    ) -> SupervisorPendingSkillApprovalBoardPresentation {
        SupervisorPendingSkillApprovalPresentation.board(
            approvals: supervisor.pendingSupervisorSkillApprovals,
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
