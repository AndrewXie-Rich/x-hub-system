import SwiftUI

struct SupervisorViewContent: View {
    struct Props {
        let supervisor: SupervisorManager
        let totalHeight: CGFloat
        let dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle
        let viewResources: SupervisorViewStateSupport.ViewResources
        let showSignalCenter: Bool
        let conversationFocusRequestID: Int
        let heartbeatIconScale: CGFloat
        let highlightedRecentRequestID: String?
    }

    struct Bindings {
        let inputText: Binding<String>
        let autoSendVoice: Binding<Bool>
        let selectedPortfolioProjectID: Binding<String?>
        let selectedPortfolioDrillDownScope: Binding<SupervisorProjectDrillDownScope>
        let focusedSplitLaneID: Binding<String?>
        let laneHealthFilter: Binding<SupervisorLaneHealthFilter>
    }

    struct Callbacks {
        let onHeaderAction: (SupervisorHeaderAction) -> Void
        let onTriggerBigTask: (SupervisorBigTaskCandidate) -> Void
        let onProcessFocusRequest: (ScrollViewProxy) -> Void
        let onSignalCenterOverviewAction: (SupervisorSignalCenterOverviewAction) -> Void
        let onCockpitAction: (PrimaryActionRailAction) -> Void
        let onRuntimeStageTap: (SupervisorRuntimeStageItemPresentation) -> Void
        let onOpenProjectDetail: (String) -> Void
        let onOpenProjectGovernance: (String, XTProjectGovernanceDestination) -> Void
        let onOpenProjectUIReview: (String) -> Void
        let onRefreshProjectUIReview: (String) -> Void
        let requestConversationFocus: () -> Void
        let onCardAction: (SupervisorCardAction) -> Void
        let onRetryCanonicalMemorySync: () -> Void
        let onOpenCanonicalMemorySyncStatusFile: () -> Void
        let onAutomationAction: (SupervisorAutomationRuntimeAction) -> Void
        let onLaneHealthAction: (SupervisorLaneHealthRowAction) -> Void
    }

    let props: Props
    let bindings: Bindings
    let callbacks: Callbacks
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            SupervisorHeaderSection(
                supervisor: props.supervisor,
                configuredModelId: props.viewResources.configuredSupervisorModelId,
                hubInteractive: appModel.hubInteractive,
                context: props.viewResources.headerControlContext,
                isProcessing: props.supervisor.isProcessing,
                detectedBigTaskCandidate: props.viewResources.detectedBigTaskCandidate,
                heartbeatIconScale: props.heartbeatIconScale,
                onTriggerBigTask: callbacks.onTriggerBigTask,
                onAction: callbacks.onHeaderAction
            )

            if props.showSignalCenter {
                Divider()

                SupervisorSignalCenterDeck(
                    maxHeight: SupervisorViewActionSupport.dashboardPanelMaxHeight(
                        totalHeight: props.totalHeight
                    ),
                    focusRequestNonce: appModel.supervisorFocusRequest?.nonce,
                    pendingHubGrants: props.supervisor.pendingHubGrants,
                    pendingSkillApprovals: props.supervisor.pendingSupervisorSkillApprovals,
                    recentSkillActivities: props.supervisor.recentSupervisorSkillActivities,
                    onProcessFocusRequest: callbacks.onProcessFocusRequest,
                    onOpenFocusURL: openFocusURL,
                    onPrimarySignalAction: callbacks.onSignalCenterOverviewAction,
                    runtimeActivityPresentation: props.dashboardPresentations.runtimeActivity,
                    supervisorManager: props.supervisor,
                    cockpitOrchestrator: appModel.supervisor.orchestrator,
                    cockpitMonitor: appModel.supervisor.orchestrator.executionMonitor,
                    onCockpitAction: callbacks.onCockpitAction,
                    onRuntimeStageTap: callbacks.onRuntimeStageTap,
                    onPersonalAssistantPrompt: handlePersonalAssistantPrompt,
                    portfolioPresentation: props.dashboardPresentations.portfolio,
                    activeDrillDownPresentation: props.dashboardPresentations.activeProjectDrillDown,
                    selectedDrillDownScope: bindings.selectedPortfolioDrillDownScope,
                    onSelectProject: selectProject,
                    onOpenProjectDetail: callbacks.onOpenProjectDetail,
                    onOpenProjectGovernance: callbacks.onOpenProjectGovernance,
                    onOpenProjectUIReview: callbacks.onOpenProjectUIReview,
                    onRefreshProjectUIReview: callbacks.onRefreshProjectUIReview,
                    infrastructureFeedPresentation: props.dashboardPresentations.infrastructureFeed,
                    memoryPresentation: props.dashboardPresentations.memory,
                    onRefreshMemory: { props.supervisor.refreshSupervisorMemorySnapshotNow() },
                    pendingSkillApprovalPresentation: props.dashboardPresentations.pendingSkillApproval,
                    onRefreshPendingSkillApprovals: { props.supervisor.refreshPendingSupervisorSkillApprovalsNow() },
                    recentSkillActivityPresentation: props.dashboardPresentations.recentSkillActivity,
                    highlightedRecentRequestID: props.highlightedRecentRequestID,
                    onRefreshRecentSkillActivities: { props.supervisor.refreshRecentSupervisorSkillActivitiesNow() },
                    eventLoopPresentation: props.dashboardPresentations.eventLoop,
                    pendingHubGrantPresentation: props.dashboardPresentations.pendingHubGrant,
                    onRefreshPendingHubGrants: { props.supervisor.refreshPendingHubGrantSnapshotNow() },
                    onCardAction: callbacks.onCardAction,
                    doctorPresentation: props.dashboardPresentations.doctor,
                    doctorSuggestionCards: props.supervisor.doctorSuggestionCards,
                    canOpenCanonicalMemorySyncStatusFile: props.viewResources.canOpenCanonicalMemorySyncStatusFile,
                    onRefreshDoctor: { props.supervisor.refreshSupervisorDoctorReport() },
                    onRetryCanonicalMemorySync: callbacks.onRetryCanonicalMemorySync,
                    onOpenCanonicalMemorySyncStatusFile: callbacks.onOpenCanonicalMemorySyncStatusFile,
                    automationPresentation: props.dashboardPresentations.automation,
                    automationSelfIterateEnabled: props.viewResources.automationSelfIterateEnabledBinding,
                    automationMaxAutoRetryDepth: props.viewResources.automationMaxAutoRetryDepthBinding,
                    onAutomationAction: callbacks.onAutomationAction,
                    splitProposalOrchestrator: appModel.supervisor.orchestrator,
                    splitProposalMonitor: appModel.supervisor.orchestrator.monitor,
                    draftTaskDescription: bindings.inputText,
                    focusedLaneID: bindings.focusedSplitLaneID,
                    laneHealthPresentation: props.dashboardPresentations.laneHealth,
                    laneHealthFilter: bindings.laneHealthFilter,
                    onLaneHealthAction: callbacks.onLaneHealthAction,
                    xtReadyIncidentPresentation: props.dashboardPresentations.xtReadyIncident,
                    onExportXTReadyReport: { _ = props.supervisor.exportXTReadyIncidentEventsReport() },
                    onOpenXTReadyReport: openXTReadyReport
                )
            }

            Divider()

            SupervisorConversationPanel(
                supervisor: props.supervisor,
                inputText: bindings.inputText,
                autoSendVoice: bindings.autoSendVoice,
                focusRequestID: props.conversationFocusRequestID
            )
            .frame(maxHeight: .infinity)
        }
    }

    private func handlePersonalAssistantPrompt(_ prompt: String) {
        bindings.inputText.wrappedValue = prompt
        callbacks.requestConversationFocus()
    }

    private func selectProject(_ projectID: String) {
        bindings.selectedPortfolioProjectID.wrappedValue = projectID
        appModel.selectedProjectId = projectID
    }

    private func openFocusURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        openURL(url)
    }

    private func openXTReadyReport() {
        let path = props.dashboardPresentations.xtReadyIncident.reportPath
        if !path.isEmpty {
            openURL(URL(fileURLWithPath: path))
        }
    }
}
