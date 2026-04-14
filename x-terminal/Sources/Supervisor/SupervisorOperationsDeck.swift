import SwiftUI

struct SupervisorSignalCenterDeck: View {
    let maxHeight: CGFloat
    let focusRequestNonce: Int?
    let pendingHubGrants: [SupervisorManager.SupervisorPendingGrant]
    let pendingSkillApprovals: [SupervisorManager.SupervisorPendingSkillApproval]
    let recentSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity]
    let onProcessFocusRequest: (ScrollViewProxy) -> Void
    let onOpenFocusURL: (String) -> Void
    let onPrimarySignalAction: (SupervisorSignalCenterOverviewAction) -> Void
    let runtimeActivityPresentation: SupervisorRuntimeActivityBoardPresentation
    let supervisorManager: SupervisorManager
    let cockpitOrchestrator: SupervisorOrchestrator
    let cockpitMonitor: ExecutionMonitor
    let onCockpitAction: (PrimaryActionRailAction) -> Void
    let onRuntimeStageTap: (SupervisorRuntimeStageItemPresentation) -> Void
    let onPersonalAssistantPrompt: (String) -> Void
    let onProjectCreationQuickSend: (String) -> Void
    let portfolioPresentation: SupervisorPortfolioBoardPresentation
    let activeDrillDownPresentation: SupervisorProjectDrillDownPresentation?
    @Binding var selectedDrillDownScope: SupervisorProjectDrillDownScope
    let onSelectProject: (String) -> Void
    let onOpenProjectDetail: (String) -> Void
    let onOpenProjectGovernance: (String, XTProjectGovernanceDestination) -> Void
    let onOpenProjectUIReview: (String) -> Void
    let onRefreshProjectUIReview: (String) -> Void
    let infrastructureFeedPresentation: SupervisorInfrastructureFeedBoardPresentation
    let memoryPresentation: SupervisorMemoryBoardPresentation
    let onRefreshMemory: () -> Void
    let pendingSkillApprovalPresentation: SupervisorPendingSkillApprovalBoardPresentation
    let onRefreshPendingSkillApprovals: () -> Void
    let recentSkillActivityPresentation: SupervisorRecentSkillActivityBoardPresentation
    let highlightedRecentRequestID: String?
    let onRefreshRecentSkillActivities: () -> Void
    let eventLoopPresentation: SupervisorEventLoopBoardPresentation
    let pendingHubGrantPresentation: SupervisorPendingHubGrantBoardPresentation
    let onRefreshPendingHubGrants: () -> Void
    let candidateReviewPresentation: SupervisorCandidateReviewBoardPresentation
    let onRefreshCandidateReviews: () -> Void
    let onCardAction: (SupervisorCardAction) -> Void
    let doctorPresentation: SupervisorDoctorBoardPresentation
    let doctorSuggestionCards: [SupervisorDoctorSuggestionCard]
    let canOpenCanonicalMemorySyncStatusFile: Bool
    let onRefreshDoctor: () -> Void
    let onRetryCanonicalMemorySync: () -> Void
    let onOpenCanonicalMemorySyncStatusFile: () -> Void
    let automationPresentation: SupervisorAutomationRuntimePresentation
    @Binding var automationSelfIterateEnabled: Bool
    @Binding var automationMaxAutoRetryDepth: Int
    let onAutomationAction: (SupervisorAutomationRuntimeAction) -> Void
    let splitProposalOrchestrator: SupervisorOrchestrator
    let splitProposalMonitor: ExecutionMonitor
    @Binding var draftTaskDescription: String
    @Binding var focusedLaneID: String?
    let laneHealthPresentation: SupervisorLaneHealthBoardPresentation
    @Binding var laneHealthFilter: SupervisorLaneHealthFilter
    let onLaneHealthAction: (SupervisorLaneHealthRowAction) -> Void
    let xtReadyIncidentPresentation: SupervisorXTReadyIncidentPresentation
    let onExportXTReadyReport: () -> Void
    let onOpenXTReadyReport: () -> Void

    private var projectCreationPresentation: SupervisorProjectCreationStatusPresentation? {
        supervisorManager.projectCreationStatusPresentation()
    }

    private var overviewPresentation: SupervisorSignalCenterOverviewPresentation {
        SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: pendingHubGrantPresentation,
            pendingSkillApprovalPresentation: pendingSkillApprovalPresentation,
            candidateReviewPresentation: candidateReviewPresentation,
            doctorPresentation: doctorPresentation,
            projectCreationPresentation: projectCreationPresentation,
            runtimeActivityPresentation: runtimeActivityPresentation,
            automationPresentation: automationPresentation,
            laneHealthPresentation: laneHealthPresentation
        )
    }

    private var primarySignalPresentation: SupervisorPrimarySignalPresentation? {
        SupervisorPrimarySignalPresentationMapper.map(
            overview: overviewPresentation
        )
    }

    private var reviewMemorySummary: SupervisorMemoryAssemblyCompactSummary? {
        supervisorManager.supervisorMemoryAssemblySnapshot?.compactSummary
    }

    var body: some View {
        SupervisorSignalCenterPanel(
            maxHeight: maxHeight,
            focusRequestNonce: focusRequestNonce,
            pendingHubGrants: pendingHubGrants,
            pendingSkillApprovals: pendingSkillApprovals,
            recentSkillActivities: recentSkillActivities,
            overviewPresentation: overviewPresentation,
            reviewMemorySummary: reviewMemorySummary,
            onProcessFocusRequest: onProcessFocusRequest
        ) {
            SupervisorDashboardBoards(
                includeHeartbeatBoard: false,
                heartbeatEntries: supervisorManager.heartbeatHistory,
                onOpenFocusURL: onOpenFocusURL,
                runtimeActivityPresentation: runtimeActivityPresentation,
                projectCreationPresentation: projectCreationPresentation,
                primarySignalPresentation: primarySignalPresentation,
                onPrimarySignalAction: onPrimarySignalAction,
                supervisorManager: supervisorManager,
                cockpitOrchestrator: cockpitOrchestrator,
                cockpitMonitor: cockpitMonitor,
                onCockpitAction: onCockpitAction,
                onRuntimeStageTap: onRuntimeStageTap,
                onPersonalAssistantPrompt: onPersonalAssistantPrompt,
                onProjectCreationQuickSend: onProjectCreationQuickSend,
                portfolioPresentation: portfolioPresentation,
                activeDrillDownPresentation: activeDrillDownPresentation,
                selectedDrillDownScope: $selectedDrillDownScope,
                onSelectProject: onSelectProject,
                onOpenProjectDetail: onOpenProjectDetail,
                onOpenProjectGovernance: onOpenProjectGovernance,
                onOpenProjectUIReview: onOpenProjectUIReview,
                onRefreshProjectUIReview: onRefreshProjectUIReview,
                infrastructureFeedPresentation: infrastructureFeedPresentation,
                memoryPresentation: memoryPresentation,
                onRefreshMemory: onRefreshMemory,
                pendingSkillApprovalPresentation: pendingSkillApprovalPresentation,
                onRefreshPendingSkillApprovals: onRefreshPendingSkillApprovals,
                recentSkillActivityPresentation: recentSkillActivityPresentation,
                highlightedRecentRequestID: highlightedRecentRequestID,
                onRefreshRecentSkillActivities: onRefreshRecentSkillActivities,
                eventLoopPresentation: eventLoopPresentation,
                pendingHubGrantPresentation: pendingHubGrantPresentation,
                onRefreshPendingHubGrants: onRefreshPendingHubGrants,
                candidateReviewPresentation: candidateReviewPresentation,
                onRefreshCandidateReviews: onRefreshCandidateReviews,
                onCardAction: onCardAction,
                doctorPresentation: doctorPresentation,
                doctorSuggestionCards: doctorSuggestionCards,
                canOpenCanonicalMemorySyncStatusFile: canOpenCanonicalMemorySyncStatusFile,
                onRefreshDoctor: onRefreshDoctor,
                onRetryCanonicalMemorySync: onRetryCanonicalMemorySync,
                onOpenCanonicalMemorySyncStatusFile: onOpenCanonicalMemorySyncStatusFile,
                automationPresentation: automationPresentation,
                automationSelfIterateEnabled: $automationSelfIterateEnabled,
                automationMaxAutoRetryDepth: $automationMaxAutoRetryDepth,
                onAutomationAction: onAutomationAction,
                splitProposalOrchestrator: splitProposalOrchestrator,
                splitProposalMonitor: splitProposalMonitor,
                draftTaskDescription: $draftTaskDescription,
                focusedLaneID: $focusedLaneID,
                laneHealthPresentation: laneHealthPresentation,
                laneHealthFilter: $laneHealthFilter,
                onLaneHealthAction: onLaneHealthAction,
                xtReadyIncidentPresentation: xtReadyIncidentPresentation,
                onExportXTReadyReport: onExportXTReadyReport,
                onOpenXTReadyReport: onOpenXTReadyReport
            )
        }
    }
}
