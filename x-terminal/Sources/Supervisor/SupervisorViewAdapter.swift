import SwiftUI

@MainActor
struct SupervisorViewAdapter {
    let supervisor: SupervisorManager
    let ui: SupervisorViewUIState
    let appModel: AppModel
    let screenModel: SupervisorViewStateSupport.ScreenModel
    let interactionCoordinator: SupervisorViewInteractionCoordinator

    func contentProps(totalHeight: CGFloat) -> SupervisorViewContent.Props {
        .init(
            supervisor: supervisor,
            totalHeight: totalHeight,
            dashboardPresentations: screenModel.dashboardPresentations,
            viewResources: screenModel.viewResources,
            showSignalCenter: ui.showSignalCenter,
            conversationFocusRequestID: ui.conversationFocusRequestID,
            heartbeatIconScale: ui.heartbeatIconScale,
            highlightedRecentRequestID: ui.highlightedRecentSupervisorSkillActivityRequestID
        )
    }

    var contentBindings: SupervisorViewContent.Bindings {
        .init(
            inputText: binding(\.inputText),
            autoSendVoice: binding(\.autoSendVoice),
            selectedPortfolioProjectID: binding(\.selectedPortfolioProjectID),
            selectedPortfolioDrillDownScope: binding(\.selectedPortfolioDrillDownScope),
            focusedSplitLaneID: binding(\.focusedSplitLaneID),
            laneHealthFilter: binding(\.laneHealthFilter)
        )
    }

    var contentCallbacks: SupervisorViewContent.Callbacks {
        interactionCoordinator.contentCallbacks
    }

    var lifecycleBindings: SupervisorViewLifecycleAttachments.Bindings {
        .init(
            selectedSupervisorAuditDrillDown: binding(\.selectedSupervisorAuditDrillDown),
            activeWindowSheet: binding(\.activeWindowSheet)
        )
    }

    var lifecycleProps: SupervisorViewLifecycleAttachments.Props {
        .init(
            selectedProjectID: appModel.selectedProjectId,
            selectedAutomationLastLaunchRef: screenModel.selectedAutomationLastLaunchRef,
            selectedPortfolioProjectID: ui.selectedPortfolioProjectID,
            selectedPortfolioDrillDownScope: ui.selectedPortfolioDrillDownScope,
            portfolioUpdatedAt: supervisor.supervisorPortfolioSnapshot.updatedAt,
            auditDrillDownRefreshFingerprint: SupervisorAuditDrillDownResolver.refreshFingerprint(
                context: screenModel.viewResources.supervisorAuditDrillDownContext
            ),
            focusRequestNonce: appModel.supervisorFocusRequest?.nonce,
            pendingHubGrantCount: supervisor.pendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.pendingSupervisorSkillApprovals.count,
            requestedWindowSheetID: supervisor.requestedWindowSheet?.id,
            latestHeartbeatID: supervisor.latestHeartbeat?.id,
            signalCenterFingerprint: screenModel.viewResources.headerControlContext
                .signalCenterOverview?
                .signalFingerprint
        )
    }

    var lifecycleCallbacks: SupervisorViewLifecycleAttachments.Callbacks {
        interactionCoordinator.lifecycleCallbacks
    }

    private func binding<Value>(
        _ keyPath: ReferenceWritableKeyPath<SupervisorViewUIState, Value>
    ) -> Binding<Value> {
        Binding(
            get: { ui[keyPath: keyPath] },
            set: { ui[keyPath: keyPath] = $0 }
        )
    }
}
