import SwiftUI

struct SupervisorDashboardBoards: View {
    let includeHeartbeatBoard: Bool
    let heartbeatEntries: [SupervisorManager.HeartbeatFeedEntry]
    let onOpenFocusURL: (String) -> Void
    let runtimeActivityPresentation: SupervisorRuntimeActivityBoardPresentation
    let projectCreationPresentation: SupervisorProjectCreationStatusPresentation?
    let primarySignalPresentation: SupervisorPrimarySignalPresentation?
    let onPrimarySignalAction: (SupervisorSignalCenterOverviewAction) -> Void
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

    var body: some View {
        VStack(spacing: 0) {
            if includeHeartbeatBoard {
                SupervisorHeartbeatBoardSection(
                    entries: heartbeatEntries,
                    doctorPresentation: doctorPresentation,
                    primarySignalPresentation: primarySignalPresentation,
                    onOpenFocus: onOpenFocusURL,
                    onPrimarySignalAction: onPrimarySignalAction
                )
                .id(SupervisorFocusPresentation.heartbeatBoardAnchorID)
                Divider()
            }
            if let projectCreationPresentation {
                SupervisorProjectCreationBoardSection(
                    presentation: projectCreationPresentation,
                    onQuickPrompt: onPersonalAssistantPrompt,
                    onQuickSend: onProjectCreationQuickSend
                )
                .id(SupervisorFocusPresentation.projectCreationBoardAnchorID)
                Divider()
            }
            SupervisorRuntimeActivityBoardSection(
                presentation: runtimeActivityPresentation,
                onAction: onCardAction
            )
            .id(SupervisorFocusPresentation.runtimeActivityBoardAnchorID)
            Divider()
            SupervisorCockpitSummarySection(
                primarySignalPresentation: primarySignalPresentation,
                supervisorManager: supervisorManager,
                orchestrator: cockpitOrchestrator,
                monitor: cockpitMonitor,
                onPrimarySignalAction: onPrimarySignalAction,
                onTap: onCockpitAction,
                onStageTap: onRuntimeStageTap
            )
            Divider()
            SupervisorPersonalAssistantSummaryBoard(onQuickPrompt: onPersonalAssistantPrompt)
            Divider()
            SupervisorPortfolioBoardSection(
                supervisorManager: supervisorManager,
                presentation: portfolioPresentation,
                activeDrillDownPresentation: activeDrillDownPresentation,
                selectedDrillDownScope: $selectedDrillDownScope,
                onSelectProject: onSelectProject,
                onOpenProjectDetail: onOpenProjectDetail,
                onOpenProjectGovernance: onOpenProjectGovernance,
                onOpenProjectUIReview: onOpenProjectUIReview,
                onRefreshProjectUIReview: onRefreshProjectUIReview
            )
            Divider()
            SupervisorInfrastructureFeedBoardSection(
                presentation: infrastructureFeedPresentation,
                onAction: onCardAction
            )
            Divider()
            SupervisorMemoryBoardSection(
                presentation: memoryPresentation,
                onRefresh: onRefreshMemory
            )
            .id(SupervisorFocusPresentation.memoryBoardAnchorID)
            Divider()
            SupervisorPendingSkillApprovalBoardSection(
                presentation: pendingSkillApprovalPresentation,
                onRefresh: onRefreshPendingSkillApprovals,
                onAction: onCardAction
            )
            .id(SupervisorFocusPresentation.pendingSupervisorSkillApprovalBoardAnchorID)
            Divider()
            SupervisorRecentSkillActivityBoardSection(
                presentation: recentSkillActivityPresentation,
                highlightedRequestID: highlightedRecentRequestID,
                onRefresh: onRefreshRecentSkillActivities,
                onAction: onCardAction
            )
            .id(SupervisorFocusPresentation.recentSupervisorSkillActivityBoardAnchorID)
            Divider()
            SupervisorEventLoopBoardSection(
                presentation: eventLoopPresentation,
                onAction: onCardAction
            )
            Divider()
            SupervisorPendingHubGrantBoardSection(
                presentation: pendingHubGrantPresentation,
                onRefresh: onRefreshPendingHubGrants,
                onAction: onCardAction
            )
            .id(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID)
            Divider()
            SupervisorCandidateReviewBoardSection(
                presentation: candidateReviewPresentation,
                onRefresh: onRefreshCandidateReviews,
                onAction: onCardAction
            )
            .id(SupervisorFocusPresentation.candidateReviewBoardAnchorID)
            Divider()
            SupervisorDoctorBoardSection(
                presentation: doctorPresentation,
                suggestionCards: doctorSuggestionCards,
                canOpenCanonicalMemorySyncStatusFile: canOpenCanonicalMemorySyncStatusFile,
                onRefreshDoctor: onRefreshDoctor,
                onRetryCanonicalMemorySync: onRetryCanonicalMemorySync,
                onOpenCanonicalMemorySyncStatusFile: onOpenCanonicalMemorySyncStatusFile
            )
            .id(SupervisorFocusPresentation.doctorBoardAnchorID)
            Divider()
            SupervisorAutomationRuntimeBoardSection(
                presentation: automationPresentation,
                selfIterateEnabled: $automationSelfIterateEnabled,
                maxAutoRetryDepth: $automationMaxAutoRetryDepth,
                onAction: onAutomationAction
            )
            .id(SupervisorFocusPresentation.automationRuntimeBoardAnchorID)
            Divider()
            SplitProposalPanel(
                orchestrator: splitProposalOrchestrator,
                monitor: splitProposalMonitor,
                draftTaskDescription: $draftTaskDescription,
                focusedLaneID: $focusedLaneID
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))
            Divider()
            SupervisorLaneHealthBoardSection(
                presentation: laneHealthPresentation,
                filter: $laneHealthFilter,
                onAction: onLaneHealthAction
            )
            .id(SupervisorFocusPresentation.laneHealthBoardAnchorID)
            Divider()
            SupervisorXTReadyIncidentBoardSection(
                presentation: xtReadyIncidentPresentation,
                canOpenCanonicalMemorySyncStatusFile: canOpenCanonicalMemorySyncStatusFile,
                onOpenFocusURL: onOpenFocusURL,
                onExportReport: onExportXTReadyReport,
                onOpenReport: onOpenXTReadyReport,
                onRetryCanonicalMemorySync: onRetryCanonicalMemorySync,
                onOpenCanonicalMemorySyncStatusFile: onOpenCanonicalMemorySyncStatusFile
            )
        }
    }
}
