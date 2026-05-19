import AppKit
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
    @Environment(\.xtAppModelReference) private var appModelReference
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var hubConnectionStore: XTHubConnectionStore
    @EnvironmentObject private var navigationFocusStore: XTNavigationFocusStore
    @EnvironmentObject private var settingsSupervisorSignalStore: XTSettingsSupervisorSignalStore

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
                    hubInteractive: hubConnectionSnapshot.interactive,
                    context: props.viewResources.headerControlContext,
                    isProcessing: props.supervisor.isProcessing,
                    processingStatusText: props.supervisor.processingStatusText,
                    detectedBigTaskCandidate: props.viewResources.detectedBigTaskCandidate,
                    bigTaskSceneHint: bigTaskSceneHint,
                    heartbeatIconScale: props.heartbeatIconScale,
                    onTriggerBigTask: callbacks.onTriggerBigTask,
                    onDismissBigTask: callbacks.onDismissBigTask,
                    onVoiceCallAction: handleVoiceCallAction,
                    onAction: callbacks.onHeaderAction
                )

                if props.showHeartbeatFeed {
                    Divider()

                    SupervisorHeartbeatPanel(
                        maxHeight: SupervisorViewActionSupport.dashboardPanelMaxHeight(
                            totalHeight: props.totalHeight
                        ),
                        entries: props.supervisor.heartbeatHistory,
                        historicalProjectBoundaryRepairStatusLine: settingsSupervisorSignalSnapshot.historicalProjectBoundaryRepairStatusLine,
                        doctorPresentation: props.dashboardPresentations.doctor,
                        onOpenFocus: openFocusURL
                    )
                } else if props.showSignalCenter {
                    Divider()

                    SupervisorSignalCenterDeck(
                        maxHeight: SupervisorViewActionSupport.dashboardPanelMaxHeight(
                            totalHeight: props.totalHeight
                        ),
                        focusRequestNonce: navigationFocusSnapshot.supervisorFocusRequest?.nonce,
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
                            historicalProjectBoundaryRepairStatusLine: settingsSupervisorSignalSnapshot.historicalProjectBoundaryRepairStatusLine
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

    private func handleVoiceCallAction() {
        if props.supervisor.voiceCallModeActive {
            props.supervisor.stopHandsFreeVoiceConversation()
            return
        }
        if props.supervisor.voiceCallEntryPreflight?.blocksStart == true {
            performVoiceRepairAction()
            return
        }
        Task { @MainActor in
            let started = await props.supervisor.startHandsFreeVoiceConversation()
            if started {
                callbacks.requestConversationFocus()
                return
            }
            if props.supervisor.voiceCallEntryPreflight?.blocksStart == true {
                performVoiceRepairAction()
            }
        }
    }

    private func performVoiceRepairAction() {
        guard let preflight = props.supervisor.voiceCallEntryPreflight else { return }
        guard let destination = preflight.repairDestination else {
            openVoiceRepairURLFallback()
            return
        }

        let detail: String? = {
            let trimmed = preflight.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()
        let plan = SupervisorConversationRepairActionPlanner.plan(for: destination)

        switch plan.action {
        case .openXTSettings(let sectionId):
            appModel.requestSettingsFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .openSupervisorControlCenter(let sheet):
            if sheet == .modelSettings {
                appModel.requestModelSettingsFocus(
                    title: preflight.headline,
                    detail: detail
                )
            }
            props.supervisor.requestSupervisorWindow(
                sheet: sheet,
                reason: "voice_call_entry_repair",
                focusConversation: false,
                startConversation: false
            )
        case .openHubSetup(let sectionId):
            appModel.requestHubSetupFocus(
                sectionId: sectionId,
                title: preflight.headline,
                detail: detail
            )
            openWindow(id: "hub_setup")
        case .openHubProviderKeys:
            if !appModel.openRELFlowHubProviderKeysSettings() {
                appModel.requestHubSetupFocus(
                    sectionId: "troubleshoot",
                    title: preflight.headline,
                    detail: detail
                )
                openWindow(id: "hub_setup")
            }
        case .openSystemPrivacy(let target):
            XTSystemSettingsLinks.openPrivacy(target)
        case .focusSupervisor:
            NSApp.activate(ignoringOtherApps: true)
            callbacks.requestConversationFocus()
        }
    }

    private func openVoiceRepairURLFallback() {
        guard let raw = props.supervisor.voiceCallEntryPreflight?.actionURL,
              let url = URL(string: raw) else {
            return
        }
        openURL(url)
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

    private var hubConnectionSnapshot: XTHubConnectionSnapshot {
        hubConnectionStore.snapshot
    }

    private var navigationFocusSnapshot: XTNavigationFocusSnapshot {
        navigationFocusStore.snapshot
    }

    private var settingsSupervisorSignalSnapshot: XTSettingsSupervisorSignalSnapshot {
        settingsSupervisorSignalStore.snapshot
    }

    private var appModel: AppModel {
        guard let appModelReference else {
            preconditionFailure("SupervisorViewContent requires xtAppModelReference")
        }
        return appModelReference
    }
}
