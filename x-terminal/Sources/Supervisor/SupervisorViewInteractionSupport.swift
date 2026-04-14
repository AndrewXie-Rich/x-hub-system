import SwiftUI

extension SupervisorViewInteractionCoordinator {
    var headerEffectDependencies: SupervisorViewHeaderEffects.Dependencies {
        SupervisorViewActionSupport.headerEffectDependencies(
            setHeartbeatFeedVisible: { ui.showHeartbeatFeed = $0 },
            setSignalCenterVisible: { ui.showSignalCenter = $0 },
            focusSignalCenterOverview: { action in
                switch action {
                case .scrollToBoard(let anchorID):
                    appModel.requestSupervisorBoardFocus(anchorID: anchorID)
                }
            },
            setWindowSheet: openDetachedSupervisorToolWindow,
            clearRequestedWindowSheet: { supervisor.clearRequestedWindowSheet() },
            clearConversation: { supervisor.clearMessages() },
            setHeartbeatScale: { ui.heartbeatIconScale = $0 }
        )
    }

    var cockpitActionDependencies: SupervisorViewCockpitActionExecution.Dependencies {
        SupervisorViewActionSupport.cockpitExecutionDependencies(
            setInputText: { ui.inputText = $0 },
            requestConversationFocus: requestConversationFocus,
            refreshPendingHubGrants: { supervisor.refreshPendingHubGrantSnapshotNow() },
            refreshSupervisorDoctorReport: { supervisor.refreshSupervisorDoctorReport() },
            setWindowSheet: openDetachedSupervisorToolWindow,
            openURL: { url in
                openURL(url)
            },
            openWindow: { windowID in
                openWindow(id: windowID)
            },
            openProjectGovernance: { projectId, destination, title, detail in
                ui.selectedPortfolioProjectID = projectId
                appModel.selectedProjectId = projectId
                SupervisorViewActionSupport.refreshSelectedPortfolioDrillDown(
                    supervisor: supervisor,
                    selectedProjectID: projectId,
                    selectedScope: ui.selectedPortfolioDrillDownScope,
                    setSelectedProjectID: { ui.selectedPortfolioProjectID = $0 },
                    setSelectedScope: { ui.selectedPortfolioDrillDownScope = $0 }
                )
                appModel.requestProjectSettingsFocus(
                    projectId: projectId,
                    destination: destination,
                    title: title,
                    detail: detail
                )
            },
            setFocusedSplitLane: { ui.focusedSplitLaneID = $0 }
        )
    }

    var supervisorCardActionContext: SupervisorViewCardActionExecution.Context {
        .init(
            auditDrillDownContext: screenModel.viewResources.supervisorAuditDrillDownContext,
            loadFullRecord: loadSupervisorSkillFullRecord
        )
    }

    func focusRequestExecutionDependencies(
        using scrollProxy: ScrollViewProxy
    ) -> SupervisorViewFocusRequestExecution.Dependencies {
        SupervisorViewActionSupport.focusRequestExecutionDependencies(
            currentSelectedProjectID: appModel.selectedProjectId,
            currentRefreshAttemptNonce: ui.supervisorFocusRefreshAttemptNonce,
            setHeartbeatFeedVisible: { ui.showHeartbeatFeed = $0 },
            setSignalCenterVisible: { ui.showSignalCenter = $0 },
            setSelectedPortfolioProjectID: { ui.selectedPortfolioProjectID = $0 },
            selectProject: { appModel.selectProject($0) },
            scrollToAnchor: { anchorID in
                withAnimation(.easeInOut(duration: 0.2)) {
                    scrollProxy.scrollTo(anchorID, anchor: .center)
                }
            },
            setHighlightedPendingHubGrantAnchor: { ui.highlightedPendingHubGrantAnchor = $0 },
            setHighlightedPendingSkillApprovalAnchor: { ui.highlightedPendingSupervisorSkillApprovalAnchor = $0 },
            setHighlightedCandidateReviewAnchor: { ui.highlightedSupervisorCandidateReviewAnchor = $0 },
            setHighlightedRecentSkillActivityRequestID: { ui.highlightedRecentSupervisorSkillActivityRequestID = $0 },
            setAuditDrillDown: { ui.selectedSupervisorAuditDrillDown = $0 },
            setRefreshAttemptNonce: { ui.supervisorFocusRefreshAttemptNonce = $0 },
            refreshPendingHubGrants: { supervisor.refreshPendingHubGrantSnapshotNow() },
            refreshPendingSkillApprovals: { supervisor.refreshPendingSupervisorSkillApprovalsNow() },
            refreshCandidateReviews: { supervisor.refreshSupervisorCandidateReviewSnapshotNow() },
            refreshRecentSkillActivities: { supervisor.refreshRecentSupervisorSkillActivitiesNow() },
            completeRequest: { request in
                ui.supervisorFocusRefreshAttemptNonce = nil
                appModel.clearSupervisorFocusRequest(request)
            }
        )
    }

    func loadSupervisorSkillFullRecord(
        _ projectId: String,
        _ projectName: String,
        _ requestId: String
    ) -> SupervisorSkillFullRecord? {
        SupervisorViewStateSupport.loadSupervisorSkillFullRecord(
            appModel: appModel,
            projectId: projectId,
            projectName: projectName,
            requestId: requestId
        )
    }

    func loadSupervisorFallbackSkillRecord(
        _ projectId: String,
        _ requestId: String
    ) -> SupervisorFocusRequestEffects.FallbackSkillRecord? {
        SupervisorViewStateSupport.loadSupervisorFallbackSkillRecord(
            appModel: appModel,
            projectId: projectId,
            requestId: requestId
        )
    }
}
