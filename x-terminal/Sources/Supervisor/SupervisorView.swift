import Foundation
import SwiftUI

struct SupervisorView: View {
    @StateObject private var supervisor = SupervisorManager.shared
    @StateObject private var ui = SupervisorViewUIState()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var appModel: AppModel

    private var screenModel: SupervisorViewStateSupport.ScreenModel {
        SupervisorViewStateSupport.screenModel(
            appModel: appModel,
            supervisor: supervisor,
            inputText: ui.inputText,
            showHeartbeatFeed: ui.showHeartbeatFeed,
            showSignalCenter: ui.showSignalCenter,
            dismissedFingerprint: ui.dismissedBigTaskFingerprint,
            selectedPortfolioProjectID: ui.selectedPortfolioProjectID,
            selectedPortfolioDrillDownScope: ui.selectedPortfolioDrillDownScope,
            highlightedPendingSkillApprovalAnchor: ui.highlightedPendingSupervisorSkillApprovalAnchor,
            highlightedPendingHubGrantAnchor: ui.highlightedPendingHubGrantAnchor,
            highlightedCandidateReviewAnchor: ui.highlightedSupervisorCandidateReviewAnchor,
            laneHealthFilter: ui.laneHealthFilter,
            focusedSplitLaneID: ui.focusedSplitLaneID
        )
    }

    private var adapter: SupervisorViewAdapter {
        let model = screenModel
        let interactionCoordinator = SupervisorViewInteractionCoordinator(
            supervisor: supervisor,
            ui: ui,
            appModel: appModel,
            screenModel: model,
            openWindow: openWindow,
            openURL: openURL
        )
        return SupervisorViewAdapter(
            supervisor: supervisor,
            ui: ui,
            appModel: appModel,
            screenModel: model,
            interactionCoordinator: interactionCoordinator
        )
    }

    var body: some View {
        let adapter = self.adapter
        GeometryReader { proxy in
            SupervisorViewContent(
                props: adapter.contentProps(
                    totalWidth: proxy.size.width,
                    totalHeight: proxy.size.height
                ),
                bindings: adapter.contentBindings,
                callbacks: adapter.contentCallbacks
            )
        }
        .frame(minWidth: 800, minHeight: 600)
        .background(
            XTSupervisorWindowAccessor { window in
                XTSupervisorWindowVisibilityRegistry.shared.track(window: window)
            }
            .frame(width: 0, height: 0)
        )
        .modifier(
            SupervisorViewLifecycleAttachments(
                bindings: adapter.lifecycleBindings,
                props: adapter.lifecycleProps,
                callbacks: adapter.lifecycleCallbacks
            )
        )
    }
}
