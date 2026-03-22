import Foundation

@MainActor
enum SupervisorViewRuntimePresentationSupport {
    struct DashboardPresentationBundle {
        let runtimeActivity: SupervisorRuntimeActivityBoardPresentation
        let portfolio: SupervisorPortfolioBoardPresentation
        let activeProjectDrillDown: SupervisorProjectDrillDownPresentation?
        let infrastructureFeed: SupervisorInfrastructureFeedBoardPresentation
        let memory: SupervisorMemoryBoardPresentation
        let pendingSkillApproval: SupervisorPendingSkillApprovalBoardPresentation
        let recentSkillActivity: SupervisorRecentSkillActivityBoardPresentation
        let eventLoop: SupervisorEventLoopBoardPresentation
        let pendingHubGrant: SupervisorPendingHubGrantBoardPresentation
        let doctor: SupervisorDoctorBoardPresentation
        let automation: SupervisorAutomationRuntimePresentation
        let laneHealth: SupervisorLaneHealthBoardPresentation
        let xtReadyIncident: SupervisorXTReadyIncidentPresentation
    }

    @MainActor
    static func dashboardPresentationBundle(
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?,
        selectedAutomationRecipe: AXAutomationRecipeRuntimeBinding?,
        selectedAutomationLastLaunchRef: String,
        selectedPortfolioProjectID: String?,
        selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope,
        highlightedPendingSkillApprovalAnchor: String?,
        highlightedPendingHubGrantAnchor: String?,
        laneHealthFilter: SupervisorLaneHealthFilter,
        focusedSplitLaneID: String?,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot? = nil
    ) -> DashboardPresentationBundle {
        let portfolioOverview = portfolioOverviewPresentation(
            supervisor: supervisor
        )
        let portfolio = portfolioBoardPresentation(
            supervisor: supervisor,
            appModel: appModel,
            overview: portfolioOverview,
            selectedProjectID: selectedPortfolioProjectID
        )
        let activeProjectDrillDown = portfolio.activeDrillDown.map {
            projectDrillDownPresentation(
                $0,
                supervisor: supervisor,
                appModel: appModel,
                selectedScope: selectedPortfolioDrillDownScope
            )
        }

        return DashboardPresentationBundle(
            runtimeActivity: SupervisorRuntimeActivityPresentation.map(
                entries: supervisor.runtimeActivityEntries
            ),
            portfolio: portfolio,
            activeProjectDrillDown: activeProjectDrillDown,
            infrastructureFeed: infrastructureFeedBoardPresentation(
                supervisor: supervisor,
                appModel: appModel
            ),
            memory: memoryBoardPresentation(
                supervisor: supervisor
            ),
            pendingSkillApproval: pendingSkillApprovalBoardPresentation(
                supervisor: supervisor,
                focusedRowAnchor: highlightedPendingSkillApprovalAnchor
            ),
            recentSkillActivity: recentSkillActivityBoardPresentation(
                supervisor: supervisor
            ),
            eventLoop: eventLoopBoardPresentation(
                supervisor: supervisor
            ),
            pendingHubGrant: pendingHubGrantBoardPresentation(
                supervisor: supervisor,
                hubInteractive: appModel.hubInteractive,
                focusedRowAnchor: highlightedPendingHubGrantAnchor
            ),
            doctor: doctorBoardPresentation(
                supervisor: supervisor
            ),
            automation: automationRuntimePresentation(
                supervisor: supervisor,
                appModel: appModel,
                selectedProject: selectedAutomationProject,
                selectedRecipe: selectedAutomationRecipe,
                selectedLastLaunchRef: selectedAutomationLastLaunchRef
            ),
            laneHealth: laneHealthBoardPresentation(
                supervisor: supervisor,
                appModel: appModel,
                filter: laneHealthFilter,
                focusedLaneID: focusedSplitLaneID
            ),
            xtReadyIncident: xtReadyIncidentPresentation(
                supervisor: supervisor,
                snapshot: xtReadySnapshot
            )
        )
    }

    @MainActor
    static func automationRuntimePresentation(
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedProject: AXProjectEntry?,
        selectedRecipe: AXAutomationRecipeRuntimeBinding?,
        selectedLastLaunchRef: String
    ) -> SupervisorAutomationRuntimePresentation {
        let projectConfig = selectedProject.map {
            appModel.projectConfig ?? .default(forProjectRoot: ctxRoot(for: $0))
        }
        let trustedStatus = selectedProject.flatMap { project in
            projectConfig?.trustedAutomationStatus(
                forProjectRoot: ctxRoot(for: project),
                permissionReadiness: AXTrustedAutomationPermissionOwnerReadiness.current(),
                requiredDeviceToolGroups: selectedRecipe?.requiredDeviceToolGroups ?? []
            )
        }
        let trustedRequiredPermissions = trustedStatus.map {
            AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
                forDeviceToolGroups: $0.deviceToolGroups
            )
        } ?? []

        return SupervisorAutomationRuntimePresentationMapper.map(
            input: .init(
                project: selectedProject,
                recipe: selectedRecipe,
                statusLine: supervisor.automationStatusLine,
                lastLaunchRef: selectedLastLaunchRef,
                selfIterateEnabled: projectConfig?.automationSelfIterateEnabled ?? false,
                maxAutoRetryDepth: projectConfig?.automationMaxAutoRetryDepth ?? 2,
                currentCheckpoint: supervisor.automationCurrentCheckpoint,
                latestExecutionReport: supervisor.automationLatestExecutionReport,
                latestRetryPackage: supervisor.automationLatestRetryPackage,
                recoveryDecision: supervisor.automationRecoveryDecision,
                trustedStatus: trustedStatus,
                trustedRequiredPermissions: trustedRequiredPermissions,
                retryTrigger: supervisor.automationRetryTriggerForTesting()
            )
        )
    }

    private static func ctxRoot(for project: AXProjectEntry) -> URL {
        URL(fileURLWithPath: project.rootPath, isDirectory: true)
    }
}
