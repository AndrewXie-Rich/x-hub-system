import SwiftUI

struct SupervisorViewContent: View {
    struct Props {
        let supervisor: SupervisorManager
        let totalWidth: CGFloat
        let totalHeight: CGFloat
        let selectedAutomationProject: AXProjectEntry?
        let selectedAutomationTemplatePreview: AXProjectGovernanceTemplatePreview?
        let legacyRuntime: XTLegacySupervisorRuntimeContext
        let dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle
        let viewResources: SupervisorViewStateSupport.ViewResources
        let activeWindowSheet: SupervisorManager.SupervisorWindowSheet?
        let showHeartbeatFeed: Bool
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
        let onDismissBigTask: (SupervisorBigTaskCandidate) -> Void
        let onProcessFocusRequest: (ScrollViewProxy) -> Void
        let onSignalCenterOverviewAction: (SupervisorSignalCenterOverviewAction) -> Void
        let onCockpitAction: (PrimaryActionRailAction) -> Void
        let onRuntimeStageTap: (SupervisorRuntimeStageItemPresentation) -> Void
        let onOpenProjectDetail: (String) -> Void
        let onOpenProjectGovernance: (String, XTProjectGovernanceDestination) -> Void
        let onOpenProjectUIReview: (String) -> Void
        let onRefreshProjectUIReview: (String) -> Void
        let requestConversationFocus: () -> Void
        let onSubmitConversationPrompt: (String) -> Void
        let onCardAction: (SupervisorCardAction) -> Void
        let onRetryCanonicalMemorySync: () -> Void
        let onOpenCanonicalMemorySyncStatusFile: () -> Void
        let onAutomationAction: (SupervisorAutomationRuntimeAction) -> Void
        let onLaneHealthAction: (SupervisorLaneHealthRowAction) -> Void
        let onDismissWindowSheet: () -> Void
    }

    let props: Props
    let bindings: Bindings
    let callbacks: Callbacks
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        let bigTaskSceneHint = props.viewResources.detectedBigTaskCandidate.map {
            SupervisorBigTaskAssist.sceneHint(
                for: $0,
                selectedProject: props.selectedAutomationProject,
                selectedProjectTemplate: props.selectedAutomationTemplatePreview
            )
        }
        ZStack {
            VStack(spacing: 0) {
                SupervisorHeaderSection(
                    supervisor: props.supervisor,
                    configuredModelId: props.viewResources.configuredSupervisorModelId,
                    hubInteractive: appModel.hubInteractive,
                    context: props.viewResources.headerControlContext,
                    isProcessing: props.supervisor.isProcessing,
                    processingStatusText: props.supervisor.processingStatusText,
                    detectedBigTaskCandidate: props.viewResources.detectedBigTaskCandidate,
                    bigTaskSceneHint: bigTaskSceneHint,
                    heartbeatIconScale: props.heartbeatIconScale,
                    onTriggerBigTask: callbacks.onTriggerBigTask,
                    onDismissBigTask: callbacks.onDismissBigTask,
                    onAction: callbacks.onHeaderAction
                )

                if props.showHeartbeatFeed {
                    Divider()

                    SupervisorHeartbeatPanel(
                        maxHeight: SupervisorViewActionSupport.dashboardPanelMaxHeight(
                            totalHeight: props.totalHeight
                        ),
                        entries: props.supervisor.heartbeatHistory,
                        historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine,
                        doctorPresentation: props.dashboardPresentations.doctor,
                        onOpenFocus: openFocusURL
                    )
                } else if props.showSignalCenter {
                    Divider()

                    SupervisorSignalCenterDeck(
                        maxHeight: SupervisorViewActionSupport.dashboardPanelMaxHeight(
                            totalHeight: props.totalHeight
                        ),
                        focusRequestNonce: appModel.supervisorFocusRequest?.nonce,
                        pendingHubGrants: props.supervisor.frontstagePendingHubGrants,
                        pendingSkillApprovals: props.supervisor.frontstagePendingSupervisorSkillApprovals,
                        recentSkillActivities: props.supervisor.frontstageRecentSupervisorSkillActivities,
                        onProcessFocusRequest: callbacks.onProcessFocusRequest,
                        onOpenFocusURL: openFocusURL,
                        onPrimarySignalAction: callbacks.onSignalCenterOverviewAction,
                        runtimeActivityPresentation: props.dashboardPresentations.runtimeActivity,
                        supervisorManager: props.supervisor,
                        cockpitOrchestrator: props.legacyRuntime.orchestrator,
                        cockpitMonitor: props.legacyRuntime.monitor,
                        onCockpitAction: callbacks.onCockpitAction,
                        onRuntimeStageTap: callbacks.onRuntimeStageTap,
                        onPersonalAssistantPrompt: handleQuickPromptPrefill,
                        onProjectCreationQuickSend: callbacks.onSubmitConversationPrompt,
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
                        candidateReviewPresentation: props.dashboardPresentations.candidateReview,
                        onRefreshCandidateReviews: { props.supervisor.refreshSupervisorCandidateReviewSnapshotNow() },
                        onCardAction: callbacks.onCardAction,
                        doctorPresentation: props.dashboardPresentations.doctor,
                        doctorSuggestionCards: SupervisorViewRuntimePresentationSupport.doctorSuggestionCards(
                            baseCards: props.supervisor.doctorSuggestionCards,
                            historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine
                        ),
                        canOpenCanonicalMemorySyncStatusFile: props.viewResources.canOpenCanonicalMemorySyncStatusFile,
                        onRefreshDoctor: { props.supervisor.refreshSupervisorDoctorReport() },
                        onRetryCanonicalMemorySync: callbacks.onRetryCanonicalMemorySync,
                        onOpenCanonicalMemorySyncStatusFile: callbacks.onOpenCanonicalMemorySyncStatusFile,
                        automationPresentation: props.dashboardPresentations.automation,
                        automationSelfIterateEnabled: props.viewResources.automationSelfIterateEnabledBinding,
                        automationMaxAutoRetryDepth: props.viewResources.automationMaxAutoRetryDepthBinding,
                        onAutomationAction: callbacks.onAutomationAction,
                        splitProposalOrchestrator: props.legacyRuntime.orchestrator,
                        splitProposalMonitor: props.legacyRuntime.monitor,
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

            if let activeWindowSheet = props.activeWindowSheet {
                Color.black.opacity(0.14)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        callbacks.onDismissWindowSheet()
                    }

                SupervisorControlCenterView(
                    preferredTab: activeWindowSheet.controlCenterTab,
                    embedded: true,
                    onClose: callbacks.onDismissWindowSheet
                )
                .environmentObject(appModel)
                .frame(
                    maxWidth: min(980, max(680, props.totalWidth - 48)),
                    maxHeight: min(820, max(520, props.totalHeight - 56))
                )
                .background(
                    RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                        .fill(Color(NSColor.windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: UIThemeTokens.cardRadius)
                        .stroke(UIThemeTokens.subtleBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                .padding(24)
            }
        }
    }

    private func handleQuickPromptPrefill(_ prompt: String) {
        SupervisorViewActionSupport.prepareConversationPrompt(
            prompt,
            setInputText: { bindings.inputText.wrappedValue = $0 },
            requestConversationFocus: callbacks.requestConversationFocus
        )
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
