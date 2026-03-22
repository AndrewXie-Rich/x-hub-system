import SwiftUI

@MainActor
struct SupervisorViewInteractionCoordinator {
    let supervisor: SupervisorManager
    let ui: SupervisorViewUIState
    let appModel: AppModel
    let screenModel: SupervisorViewStateSupport.ScreenModel
    let openWindow: OpenWindowAction
    let openURL: OpenURLAction

    var contentCallbacks: SupervisorViewContent.Callbacks {
        .init(
            onHeaderAction: performSupervisorHeaderAction,
            onTriggerBigTask: triggerBigTaskFlow,
            onProcessFocusRequest: processSupervisorFocusRequest,
            onSignalCenterOverviewAction: performSignalCenterOverviewAction,
            onCockpitAction: handleCockpitAction,
            onRuntimeStageTap: handleRuntimeStageTap,
            onOpenProjectDetail: openProjectDetail,
            onOpenProjectGovernance: openProjectGovernance,
            onOpenProjectUIReview: openProjectUIReview,
            onRefreshProjectUIReview: refreshProjectUIReview,
            requestConversationFocus: requestConversationFocus,
            onCardAction: performSupervisorCardAction,
            onRetryCanonicalMemorySync: retryCanonicalMemorySyncFromSupervisorBoards,
            onOpenCanonicalMemorySyncStatusFile: openCanonicalMemorySyncStatusFile,
            onAutomationAction: performAutomationRuntimeAction,
            onLaneHealthAction: performLaneHealthRowAction
        )
    }

    var lifecycleCallbacks: SupervisorViewLifecycleAttachments.Callbacks {
        .init(
            onAppearAction: handleViewAppear,
            onSelectedProjectChange: syncSelectedAutomationRuntimeSnapshot,
            onAutomationLaunchRefChange: syncSelectedAutomationRuntimeSnapshot,
            onPortfolioSelectionChange: refreshSelectedPortfolioDrillDown,
            onPortfolioScopeChange: refreshSelectedPortfolioDrillDown,
            onPortfolioUpdatedAtChange: refreshSelectedPortfolioDrillDown,
            onAuditDrillDownRefreshFingerprintChange: refreshSelectedAuditDrillDown,
            onFocusRequestChange: { performSupervisorHeaderLifecycleEvent(.focusRequestChanged) },
            onPendingHubGrantCountChange: { performSupervisorHeaderLifecycleEvent(.pendingHubGrantsChanged) },
            onPendingSkillApprovalCountChange: { performSupervisorHeaderLifecycleEvent(.pendingSkillApprovalsChanged) },
            onRequestedWindowSheetChange: { performSupervisorHeaderLifecycleEvent(.requestedWindowSheetChanged) },
            onLatestHeartbeatChange: { performSupervisorHeaderLifecycleEvent(.latestHeartbeatChanged) },
            onSignalCenterChange: { performSupervisorHeaderLifecycleEvent(.signalCenterChanged) },
            auditSheetBuilder: { detail in
                AnyView(
                    SupervisorAuditDrillDownSheet(
                        detail: detail,
                        onAction: performSupervisorCardAction
                    )
                )
            },
            windowSheetBuilder: { sheet in
                AnyView(
                    SupervisorWindowSheetView(sheet: sheet)
                        .environmentObject(appModel)
                )
            }
        )
    }

    private func handleViewAppear() {
        SupervisorViewActionSupport.handleViewAppear(
            supervisor: supervisor,
            appModel: appModel,
            selectedAutomationProject: screenModel.selectedAutomationProject,
            performHeaderLifecycleEvent: performSupervisorHeaderLifecycleEvent,
            requestConversationFocus: requestConversationFocus
        )
    }

    private func syncSelectedAutomationRuntimeSnapshot() {
        supervisor.syncAutomationRuntimeSnapshot(
            forSelectedProject: screenModel.selectedAutomationProject
        )
    }

    private func retryCanonicalMemorySyncFromSupervisorBoards() {
        supervisor.retryCanonicalMemorySyncNow()
    }

    private func openCanonicalMemorySyncStatusFile() {
        guard screenModel.viewResources.canOpenCanonicalMemorySyncStatusFile else { return }
        openURL(screenModel.viewResources.canonicalMemorySyncStatusFileURL)
    }

    private func triggerBigTaskFlow(_ candidate: SupervisorBigTaskCandidate) {
        SupervisorViewActionSupport.triggerBigTaskFlow(
            candidate,
            setDismissedFingerprint: { ui.dismissedBigTaskFingerprint = $0 },
            setInputText: { ui.inputText = $0 },
            sendMessage: { supervisor.sendMessage($0) },
            requestConversationFocus: requestConversationFocus
        )
    }

    private func performSupervisorHeaderAction(_ action: SupervisorHeaderAction) {
        SupervisorViewActionSupport.performHeaderAction(
            action,
            context: screenModel.viewResources.headerControlContext,
            dependencies: headerEffectDependencies
        )
    }

    private func performSupervisorHeaderLifecycleEvent(
        _ event: SupervisorHeaderLifecycleEvent
    ) {
        SupervisorViewActionSupport.performHeaderLifecycleEvent(
            event,
            context: screenModel.viewResources.headerControlContext,
            dependencies: headerEffectDependencies
        )
    }

    private func performSignalCenterOverviewAction(
        _ action: SupervisorSignalCenterOverviewAction
    ) {
        switch action {
        case .scrollToBoard(let anchorID):
            appModel.requestSupervisorBoardFocus(anchorID: anchorID)
        }
    }

    private func handleCockpitAction(_ action: PrimaryActionRailAction) {
        performSupervisorCockpitAction(.primary(action))
    }

    private func handleRuntimeStageTap(_ item: SupervisorRuntimeStageItemPresentation) {
        performSupervisorCockpitAction(.runtimeStage(item))
    }

    private func performSupervisorCockpitAction(_ action: SupervisorCockpitAction) {
        SupervisorViewActionSupport.performCockpitAction(
            action,
            context: screenModel.viewResources.supervisorCockpitActionContext,
            dependencies: cockpitActionDependencies
        )
    }

    func requestConversationFocus() {
        ui.conversationFocusRequestID += 1
    }

    private func openProjectDetail(_ projectId: String) {
        focusPortfolioProject(projectId)
        if appModel.isMultiProjectViewEnabled && appModel.hubInteractive {
            appModel.requestProjectDetailFocus(
                projectId: projectId,
                section: .uiReview,
                title: "项目详情",
                detail: "最近 UI 审查"
            )
        } else {
            appModel.selectProject(projectId)
        }
    }

    private func openProjectGovernance(
        _ projectId: String,
        destination: XTProjectGovernanceDestination
    ) {
        focusPortfolioProject(projectId)
        appModel.requestProjectSettingsFocus(
            projectId: projectId,
            destination: destination
        )
    }

    private func openProjectUIReview(_ projectId: String) {
        focusPortfolioProject(projectId)
        appModel.requestProjectUIReviewFocus(
            projectId: projectId,
            title: "最近 UI 审查",
            detail: "项目 UI 审查工作台"
        )
    }

    private func refreshProjectUIReview(_ projectId: String) {
        focusPortfolioProject(projectId)
        supervisor.refreshSupervisorMemorySnapshotNow()
    }

    private func focusPortfolioProject(_ projectId: String) {
        ui.selectedPortfolioProjectID = projectId
        SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
            supervisor: supervisor,
            selectedProjectID: projectId,
            selectedScope: ui.selectedPortfolioDrillDownScope,
            setSelectedProjectID: { ui.selectedPortfolioProjectID = $0 },
            setSelectedScope: { ui.selectedPortfolioDrillDownScope = $0 }
        )
    }

    private func processSupervisorFocusRequest(using scrollProxy: ScrollViewProxy) {
        SupervisorViewActionSupport.performFocusRequest(
            request: appModel.supervisorFocusRequest,
            context: screenModel.viewResources.supervisorFocusRequestContext,
            loadRecentSkillRecord: loadSupervisorSkillFullRecord,
            loadFallbackSkillRecord: loadSupervisorFallbackSkillRecord,
            dependencies: focusRequestExecutionDependencies(using: scrollProxy)
        )
    }

    private func refreshSelectedPortfolioDrillDown() {
        SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
            supervisor: supervisor,
            selectedProjectID: ui.selectedPortfolioProjectID,
            selectedScope: ui.selectedPortfolioDrillDownScope,
            setSelectedProjectID: { selectedProjectID in
                ui.selectedPortfolioProjectID = selectedProjectID
            },
            setSelectedScope: { selectedScope in
                ui.selectedPortfolioDrillDownScope = selectedScope
            }
        )
    }

    private func refreshSelectedAuditDrillDown() {
        let currentSelection = ui.selectedSupervisorAuditDrillDown
        let refreshedSelection = SupervisorViewStateSupport.refreshedAuditDrillDownSelection(
            currentSelection: currentSelection,
            context: screenModel.viewResources.supervisorAuditDrillDownContext,
            loadFullRecord: loadSupervisorSkillFullRecord
        )
        guard refreshedSelection != currentSelection else { return }
        ui.selectedSupervisorAuditDrillDown = refreshedSelection
    }

    private func performSupervisorCardAction(_ action: SupervisorCardAction) {
        SupervisorViewActionSupport.performCardAction(
            action,
            context: supervisorCardActionContext,
            supervisor: supervisor,
            setAuditDrillDown: { ui.selectedSupervisorAuditDrillDown = $0 },
            openURL: { url in
                openURL(url)
            },
            openProjectGovernance: { projectId, destination in
                focusPortfolioProject(projectId)
                appModel.requestProjectSettingsFocus(
                    projectId: projectId,
                    destination: destination
                )
            }
        )
    }

    private func performAutomationRuntimeAction(_ action: SupervisorAutomationRuntimeAction) {
        SupervisorViewActionSupport.performAutomationRuntimeAction(
            action,
            runCommand: { command in
                _ = supervisor.performAutomationRuntimeCommand(command, emitSystemMessage: true)
            }
        )
    }

    private func performLaneHealthRowAction(_ action: SupervisorLaneHealthRowAction) {
        SupervisorViewActionSupport.performLaneHealthRowAction(
            action,
            openProject: { url in
                openURL(url)
            },
            focusLane: { laneID in
                ui.focusedSplitLaneID = laneID
            }
        )
    }
}
