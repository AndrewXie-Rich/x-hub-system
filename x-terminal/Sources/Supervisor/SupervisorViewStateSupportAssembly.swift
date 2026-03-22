import Foundation
import SwiftUI

@MainActor
extension SupervisorViewStateSupport {
    static func selectedAutomationProject(
        appModel: AppModel
    ) -> AXProjectEntry? {
        guard let projectID = appModel.selectedProjectId,
              projectID != AXProjectRegistry.globalHomeId else {
            return nil
        }
        return appModel.registry.project(for: projectID)
    }

    static func selectedAutomationRecipe(
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?
    ) -> AXAutomationRecipeRuntimeBinding? {
        guard selectedAutomationProject != nil else { return nil }
        return appModel.projectConfig?.activeAutomationRecipe
    }

    static func selectedAutomationLastLaunchRef(
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?
    ) -> String {
        guard selectedAutomationProject != nil else { return "" }
        return (appModel.projectConfig?.lastAutomationLaunchRef ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cockpitActionContext(
        inputText: String,
        cockpitPresentation: SupervisorCockpitPresentation,
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorCockpitActionResolver.Context {
        SupervisorCockpitActionResolver.Context(
            inputText: inputText,
            reviewReportPath: cockpitPresentation.reviewReportPath,
            replayEvidencePath: appModel.supervisor.orchestrator.latestReplayHarnessReport?
                .evidenceRefs
                .first,
            firstPendingGrantActionURL: supervisor.pendingHubGrants.first?.actionURL,
            firstPendingSkillApprovalActionURL: supervisor.pendingSupervisorSkillApprovals.first?.actionURL,
            runtimeAccessSurfaceState: cockpitPresentation.runtimeStageRail.items
                .first(where: { $0.id == "access" })?
                .surfaceState,
            directedUnblockBaton: appModel.supervisor.orchestrator.executionMonitor
                .directedUnblockBatons
                .first
        )
    }

    static func headerControlContext(
        appModel: AppModel,
        supervisor: SupervisorManager,
        dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle,
        showSignalCenter: Bool
    ) -> SupervisorHeaderControls.Context {
        let heartbeatPresentation = SupervisorHeartbeatPresentation.map(
            entries: supervisor.heartbeatHistory
        )
        return SupervisorHeaderControls.Context(
            hasFocusRequest: appModel.supervisorFocusRequest != nil,
            pendingHubGrantCount: supervisor.pendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.pendingSupervisorSkillApprovals.count,
            hasLatestHeartbeat: supervisor.latestHeartbeat != nil,
            highestHeartbeatPriority: SupervisorHeartbeatPresentation.highestPriority(
                entries: supervisor.heartbeatHistory
            ),
            heartbeatOverview: heartbeatPresentation.overview,
            hasLatestRuntimeActivity: supervisor.latestRuntimeActivity != nil,
            signalCenterOverview: SupervisorSignalCenterOverviewPresentationMapper.map(
                pendingHubGrantPresentation: dashboardPresentations.pendingHubGrant,
                pendingSkillApprovalPresentation: dashboardPresentations.pendingSkillApproval,
                runtimeActivityPresentation: dashboardPresentations.runtimeActivity,
                automationPresentation: dashboardPresentations.automation,
                laneHealthPresentation: dashboardPresentations.laneHealth
            ),
            isSignalCenterVisible: showSignalCenter,
            requestedWindowSheet: supervisor.requestedWindowSheet
        )
    }

    static func configuredSupervisorModelId(
        appModel: AppModel
    ) -> String {
        appModel.settingsStore.settings.assignment(for: .supervisor).model?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func detectedBigTaskCandidate(
        inputText: String,
        supervisor: SupervisorManager,
        dismissedFingerprint: String?
    ) -> SupervisorBigTaskCandidate? {
        SupervisorBigTaskAssist.detect(
            inputText: inputText,
            latestUserMessage: supervisor.chatTimelineMessages.reversed()
                .first(where: { $0.role == .user })?
                .content,
            dismissedFingerprint: dismissedFingerprint
        )
    }

    static func canonicalMemorySyncStatusFileURL() -> URL {
        HubPaths.baseDir().appendingPathComponent("canonical_memory_sync_status.json")
    }

    static func canOpenCanonicalMemorySyncStatusFile(
        url: URL
    ) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func automationSelfIterateEnabledBinding(
        appModel: AppModel
    ) -> Binding<Bool> {
        Binding(
            get: { appModel.projectConfig?.automationSelfIterateEnabled ?? false },
            set: { appModel.setProjectAutomationSelfIteration(enabled: $0) }
        )
    }

    static func automationMaxAutoRetryDepthBinding(
        appModel: AppModel
    ) -> Binding<Int> {
        Binding(
            get: { appModel.projectConfig?.automationMaxAutoRetryDepth ?? 2 },
            set: { appModel.setProjectAutomationSelfIteration(maxAutoRetryDepth: $0) }
        )
    }
}
