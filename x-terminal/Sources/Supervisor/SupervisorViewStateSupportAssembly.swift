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
        supervisor: SupervisorManager,
        selectedAutomationProject: AXProjectEntry?
    ) -> String {
        guard selectedAutomationProject != nil else { return "" }
        return supervisor.automationPresentationRunRef(for: selectedAutomationProject)
    }

    static func cockpitActionContext(
        inputText: String,
        cockpitPresentation: SupervisorCockpitPresentation,
        supervisor: SupervisorManager,
        legacyRuntime: XTLegacySupervisorRuntimeContext,
        appModel: AppModel
    ) -> SupervisorCockpitActionResolver.Context {
        SupervisorCockpitActionResolver.Context(
            inputText: inputText,
            reviewReportPath: cockpitPresentation.reviewReportPath,
            replayEvidencePath: legacyRuntime.orchestrator.latestReplayHarnessReport?
                .evidenceRefs
                .first,
            firstPendingGrantActionURL: supervisor.frontstagePendingHubGrants.first?.actionURL,
            firstPendingSkillApprovalActionURL: supervisor.frontstagePendingSupervisorSkillApprovals.first?.actionURL,
            selectedProjectID: appModel.selectedProjectId,
            runtimeBlockerCode: supervisor.oneShotRunState?.topBlocker,
            runtimeAccessSurfaceState: cockpitPresentation.runtimeStageRail.items
                .first(where: { $0.id == "access" })?
                .surfaceState,
            directedUnblockBaton: legacyRuntime.monitor
                .directedUnblockBatons
                .first
        )
    }

    static func headerControlContext(
        appModel: AppModel,
        supervisor: SupervisorManager,
        dashboardPresentations: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle,
        showHeartbeatFeed: Bool,
        showSignalCenter: Bool
    ) -> SupervisorHeaderControls.Context {
        let heartbeatPresentation = SupervisorHeartbeatPresentation.map(
            entries: supervisor.heartbeatHistory,
            historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine,
            doctorPresentation: dashboardPresentations.doctor
        )
        return SupervisorHeaderControls.Context(
            hasFocusRequest: appModel.supervisorFocusRequest != nil,
            pendingHubGrantCount: supervisor.frontstagePendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.frontstagePendingSupervisorSkillApprovals.count,
            hasLatestHeartbeat: supervisor.latestHeartbeat != nil,
            highestHeartbeatPriority: SupervisorHeartbeatPresentation.highestPriority(
                entries: supervisor.heartbeatHistory,
                historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine,
                doctorPresentation: dashboardPresentations.doctor
            ),
            heartbeatOverview: heartbeatPresentation.overview,
            hasLatestRuntimeActivity: supervisor.latestRuntimeActivity != nil,
            signalCenterOverview: SupervisorSignalCenterOverviewPresentationMapper.map(
                pendingHubGrantPresentation: dashboardPresentations.pendingHubGrant,
                pendingSkillApprovalPresentation: dashboardPresentations.pendingSkillApproval,
                candidateReviewPresentation: dashboardPresentations.candidateReview,
                doctorPresentation: dashboardPresentations.doctor,
                projectCreationPresentation: supervisor.projectCreationStatusPresentation(),
                runtimeActivityPresentation: dashboardPresentations.runtimeActivity,
                automationPresentation: dashboardPresentations.automation,
                laneHealthPresentation: dashboardPresentations.laneHealth
            ),
            isHeartbeatFeedVisible: showHeartbeatFeed,
            isSignalCenterVisible: showSignalCenter,
            requestedWindowSheet: supervisor.requestedWindowSheet
        )
    }

    static func lightweightHeaderControlContext(
        appModel: AppModel,
        supervisor: SupervisorManager,
        showHeartbeatFeed: Bool,
        showSignalCenter: Bool
    ) -> SupervisorHeaderControls.Context {
        let heartbeatPresentation = SupervisorHeartbeatPresentation.map(
            entries: supervisor.heartbeatHistory,
            historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine
        )
        return SupervisorHeaderControls.Context(
            hasFocusRequest: appModel.supervisorFocusRequest != nil,
            pendingHubGrantCount: supervisor.frontstagePendingHubGrants.count,
            pendingSkillApprovalCount: supervisor.frontstagePendingSupervisorSkillApprovals.count,
            hasLatestHeartbeat: supervisor.latestHeartbeat != nil,
            highestHeartbeatPriority: SupervisorHeartbeatPresentation.highestPriority(
                entries: supervisor.heartbeatHistory,
                historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine
            ),
            heartbeatOverview: heartbeatPresentation.overview,
            hasLatestRuntimeActivity: supervisor.latestRuntimeActivity != nil,
            signalCenterOverview: nil,
            isHeartbeatFeedVisible: showHeartbeatFeed,
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
        SupervisorCanonicalMemorySyncStatusFileAvailabilityCache.fileExists(at: url)
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

@MainActor
private enum SupervisorCanonicalMemorySyncStatusFileAvailabilityCache {
    private struct Entry {
        let checkedAt: Date
        let exists: Bool
    }

    private static let maxAgeSeconds: TimeInterval = 2.0
    private static var entries: [String: Entry] = [:]

    static func fileExists(
        at url: URL,
        now: Date = Date()
    ) -> Bool {
        let key = url.standardizedFileURL.path
        if let entry = entries[key],
           now.timeIntervalSince(entry.checkedAt) < maxAgeSeconds {
            return entry.exists
        }
        let exists = FileManager.default.fileExists(atPath: key)
        entries[key] = Entry(checkedAt: now, exists: exists)
        return exists
    }
}
