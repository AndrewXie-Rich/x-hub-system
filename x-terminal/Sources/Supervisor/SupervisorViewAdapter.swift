import SwiftUI

@MainActor
struct SupervisorViewAdapter {
    let supervisor: SupervisorManager
    let ui: SupervisorViewUIState
    let appModel: AppModel
    let screenModel: SupervisorViewStateSupport.ScreenModel
    let interactionCoordinator: SupervisorViewInteractionCoordinator

    func contentProps(totalWidth: CGFloat, totalHeight: CGFloat) -> SupervisorViewContent.Props {
        let selectedAutomationTemplatePreview = screenModel.selectedAutomationProject.map {
            appModel.governanceTemplatePreview(for: $0)
        }
        return .init(
            supervisor: supervisor,
            totalWidth: totalWidth,
            totalHeight: totalHeight,
            selectedAutomationProject: screenModel.selectedAutomationProject,
            selectedAutomationTemplatePreview: selectedAutomationTemplatePreview,
            legacyRuntime: screenModel.legacyRuntime,
            dashboardPresentations: screenModel.dashboardPresentations,
            viewResources: screenModel.viewResources,
            activeWindowSheet: ui.activeWindowSheet,
            showHeartbeatFeed: ui.showHeartbeatFeed,
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
            selectedSupervisorAuditDrillDown: binding(\.selectedSupervisorAuditDrillDown)
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
            pendingHubGrantCount: supervisor.frontstagePendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.frontstagePendingSupervisorSkillApprovals.count,
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
