import Foundation

@MainActor
enum SupervisorViewRuntimePresentationSupport {
    struct DashboardPresentationBundle: Equatable {
        let runtimeActivity: SupervisorRuntimeActivityBoardPresentation
        let portfolio: SupervisorPortfolioBoardPresentation
        let activeProjectDrillDown: SupervisorProjectDrillDownPresentation?
        let infrastructureFeed: SupervisorInfrastructureFeedBoardPresentation
        let memory: SupervisorMemoryBoardPresentation
        let pendingSkillApproval: SupervisorPendingSkillApprovalBoardPresentation
        let recentSkillActivity: SupervisorRecentSkillActivityBoardPresentation
        let eventLoop: SupervisorEventLoopBoardPresentation
        let pendingHubGrant: SupervisorPendingHubGrantBoardPresentation
        let candidateReview: SupervisorCandidateReviewBoardPresentation
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
        highlightedCandidateReviewAnchor: String?,
        laneHealthFilter: SupervisorLaneHealthFilter,
        focusedSplitLaneID: String?,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot? = nil
    ) -> DashboardPresentationBundle {
        let cacheKey = dashboardPresentationCacheKey(
            supervisor: supervisor,
            appModel: appModel,
            selectedAutomationProject: selectedAutomationProject,
            selectedAutomationRecipe: selectedAutomationRecipe,
            selectedAutomationLastLaunchRef: selectedAutomationLastLaunchRef,
            selectedPortfolioProjectID: selectedPortfolioProjectID,
            selectedPortfolioDrillDownScope: selectedPortfolioDrillDownScope,
            highlightedPendingSkillApprovalAnchor: highlightedPendingSkillApprovalAnchor,
            highlightedPendingHubGrantAnchor: highlightedPendingHubGrantAnchor,
            highlightedCandidateReviewAnchor: highlightedCandidateReviewAnchor,
            laneHealthFilter: laneHealthFilter,
            focusedSplitLaneID: focusedSplitLaneID,
            xtReadySnapshot: xtReadySnapshot
        )

        return SupervisorDashboardPresentationBundleCache.load(key: cacheKey) {
            makeDashboardPresentationBundle(
                supervisor: supervisor,
                appModel: appModel,
                selectedAutomationProject: selectedAutomationProject,
                selectedAutomationRecipe: selectedAutomationRecipe,
                selectedAutomationLastLaunchRef: selectedAutomationLastLaunchRef,
                selectedPortfolioProjectID: selectedPortfolioProjectID,
                selectedPortfolioDrillDownScope: selectedPortfolioDrillDownScope,
                highlightedPendingSkillApprovalAnchor: highlightedPendingSkillApprovalAnchor,
                highlightedPendingHubGrantAnchor: highlightedPendingHubGrantAnchor,
                highlightedCandidateReviewAnchor: highlightedCandidateReviewAnchor,
                laneHealthFilter: laneHealthFilter,
                focusedSplitLaneID: focusedSplitLaneID,
                xtReadySnapshot: xtReadySnapshot
            )
        }
    }

    private static func makeDashboardPresentationBundle(
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?,
        selectedAutomationRecipe: AXAutomationRecipeRuntimeBinding?,
        selectedAutomationLastLaunchRef: String,
        selectedPortfolioProjectID: String?,
        selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope,
        highlightedPendingSkillApprovalAnchor: String?,
        highlightedPendingHubGrantAnchor: String?,
        highlightedCandidateReviewAnchor: String?,
        laneHealthFilter: SupervisorLaneHealthFilter,
        focusedSplitLaneID: String?,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot?
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
                entries: supervisor.frontstageRuntimeActivityEntries
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
            candidateReview: supervisorCandidateReviewBoardPresentation(
                supervisor: supervisor,
                hubInteractive: appModel.hubInteractive,
                focusedRowAnchor: highlightedCandidateReviewAnchor
            ),
            doctor: doctorBoardPresentation(
                supervisor: supervisor,
                appModel: appModel
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

    private static func dashboardPresentationCacheKey(
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedAutomationProject: AXProjectEntry?,
        selectedAutomationRecipe: AXAutomationRecipeRuntimeBinding?,
        selectedAutomationLastLaunchRef: String,
        selectedPortfolioProjectID: String?,
        selectedPortfolioDrillDownScope: SupervisorProjectDrillDownScope,
        highlightedPendingSkillApprovalAnchor: String?,
        highlightedPendingHubGrantAnchor: String?,
        highlightedCandidateReviewAnchor: String?,
        laneHealthFilter: SupervisorLaneHealthFilter,
        focusedSplitLaneID: String?,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot?
    ) -> SupervisorDashboardPresentationBundleCache.Key {
        SupervisorDashboardPresentationBundleCache.Key(
            selectedAutomationProjectID: selectedAutomationProject?.projectId ?? "",
            selectedAutomationRecipeRef: selectedAutomationRecipe?.ref ?? "",
            selectedAutomationLastLaunchRef: selectedAutomationLastLaunchRef,
            selectedPortfolioProjectID: selectedPortfolioProjectID ?? "",
            selectedPortfolioDrillDownScope: selectedPortfolioDrillDownScope.rawValue,
            highlightedPendingSkillApprovalAnchor: highlightedPendingSkillApprovalAnchor ?? "",
            highlightedPendingHubGrantAnchor: highlightedPendingHubGrantAnchor ?? "",
            highlightedCandidateReviewAnchor: highlightedCandidateReviewAnchor ?? "",
            laneHealthFilter: String(describing: laneHealthFilter),
            focusedSplitLaneID: focusedSplitLaneID ?? "",
            hubInteractive: appModel.hubInteractive,
            sourceSignature: dashboardPresentationSourceSignature(
                supervisor: supervisor,
                appModel: appModel,
                xtReadySnapshot: xtReadySnapshot
            )
        )
    }

    private static func dashboardPresentationSourceSignature(
        supervisor: SupervisorManager,
        appModel: AppModel,
        xtReadySnapshot: SupervisorManager.XTReadyIncidentExportSnapshot?
    ) -> String {
        let portfolio = supervisor.supervisorPortfolioSnapshot
        let drillDown = supervisor.supervisorLastProjectDrillDownSnapshot
        let runtimeIDs = compactFingerprint(supervisor.frontstageRuntimeActivityEntries, limit: 16) {
            "\($0.id):\($0.createdAt)"
        }
        let projectActionIDs = compactFingerprint(supervisor.frontstageRecentProjectActionEvents, limit: 16) {
            "\($0.id):\($0.occurredAt)"
        }
        let pendingGrantIDs = compactFingerprint(supervisor.frontstagePendingHubGrants, limit: 16) {
            "\($0.id):\($0.createdAt ?? 0)"
        }
        let pendingSkillIDs = compactFingerprint(supervisor.frontstagePendingSupervisorSkillApprovals, limit: 16) {
            "\($0.id):\($0.createdAt ?? 0)"
        }
        let candidateReviewIDs = compactFingerprint(supervisor.frontstageSupervisorCandidateReviews, limit: 16) {
            "\($0.id):\($0.updatedAtMs)"
        }
        let recentSkillIDs = compactFingerprint(supervisor.frontstageRecentSupervisorSkillActivities, limit: 16) {
            $0.id
        }
        let eventLoopIDs = compactFingerprint(supervisor.frontstageRecentSupervisorEventLoopActivities, limit: 16) {
            "\($0.id):\($0.updatedAt)"
        }
        let projectRowIDs = compactFingerprint(portfolio.projects, limit: 24) {
            "\($0.projectId):\($0.updatedAt):\($0.projectState):\($0.memoryFreshness)"
        }
        let xtReady = xtReadySnapshot.map {
            "\($0.status):\($0.requiredIncidentEventCount):\($0.missingIncidentCodes.joined(separator: ",")):\($0.strictE2EIssues.joined(separator: ",")):\($0.reportPath)"
        } ?? "none"

        return [
            "portfolio=\(portfolio.updatedAt):\(portfolio.projects.count):\(projectRowIDs)",
            "drill=\(drillDown?.projectId ?? ""):\(drillDown?.updatedAt ?? 0)",
            "runtime=\(runtimeIDs):latest=\(supervisor.latestRuntimeActivity?.id ?? "")",
            "project_actions=\(projectActionIDs)",
            "pending_grants=\(supervisor.pendingHubGrantUpdatedAt):\(pendingGrantIDs)",
            "skill_approvals=\(pendingSkillIDs)",
            "candidate_reviews=\(supervisor.supervisorCandidateReviewUpdatedAt):\(candidateReviewIDs)",
            "recent_skills=\(recentSkillIDs)",
            "event_loop=\(supervisor.frontstageSupervisorEventLoopStatusLine):\(eventLoopIDs)",
            "memory=\(supervisor.supervisorMemoryStatusLine):\(supervisor.supervisorMemoryAssemblyStatusLine):\(supervisor.supervisorSkillRegistryStatusLine)",
            "doctor=\(supervisor.doctorStatusLine):\(supervisor.doctorHasBlockingFindings):\(supervisor.releaseBlockedByDoctorWithoutReport)",
            "automation=\(supervisor.automationStatusLine):\(supervisor.automationLatestExecutionReport?.runID ?? ""):\(supervisor.automationLatestRetryPackage?.retryRunID ?? "")",
            "lane=\(supervisor.supervisorLaneHealthStatusLine)",
            "infra=\(supervisor.supervisorOfficialSkillsChannelStatusLine):\(supervisor.supervisorOfficialSkillsChannelTransitionLine)",
            "app=\(appModel.historicalProjectBoundaryRepairStatusLine):\(appModel.skillsCompatibilitySnapshot.statusLine)",
            "xtready=\(xtReady)"
        ].joined(separator: "|")
    }

    private static func compactFingerprint<T>(
        _ values: [T],
        limit: Int,
        transform: (T) -> String
    ) -> String {
        values.prefix(limit).map(transform).joined(separator: ",")
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
            appModel.projectConfigSnapshot(for: $0.projectId)
                ?? .default(forProjectRoot: ctxRoot(for: $0))
        }
        let permissionReadiness = AXTrustedAutomationPermissionOwnerReadiness.current()
        let trustedStatus = selectedProject.flatMap { project in
            projectConfig?.trustedAutomationStatus(
                forProjectRoot: ctxRoot(for: project),
                permissionReadiness: permissionReadiness,
                requiredDeviceToolGroups: selectedRecipe?.requiredDeviceToolGroups ?? []
            )
        }
        let trustedRequiredPermissions = trustedStatus.map {
            AXTrustedAutomationPermissionOwnerReadiness.requiredPermissionKeys(
                forDeviceToolGroups: $0.deviceToolGroups
            )
        } ?? []
        let runtimeReadiness: AXProjectGovernanceRuntimeReadinessSnapshot? = {
            guard let project = selectedProject, let projectConfig else { return nil }
            let resolved = xtResolveProjectGovernance(
                projectRoot: ctxRoot(for: project),
                config: projectConfig,
                permissionReadiness: permissionReadiness
            )
            return resolved.runtimeReadinessSnapshot
        }()

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
                retryTrigger: supervisor.automationRetryTriggerForTesting(),
                runtimeReadiness: runtimeReadiness
            )
        )
    }

    private static func ctxRoot(for project: AXProjectEntry) -> URL {
        URL(fileURLWithPath: project.rootPath, isDirectory: true)
    }
}

@MainActor
private enum SupervisorDashboardPresentationBundleCache {
    struct Key: Hashable {
        var selectedAutomationProjectID: String
        var selectedAutomationRecipeRef: String
        var selectedAutomationLastLaunchRef: String
        var selectedPortfolioProjectID: String
        var selectedPortfolioDrillDownScope: String
        var highlightedPendingSkillApprovalAnchor: String
        var highlightedPendingHubGrantAnchor: String
        var highlightedCandidateReviewAnchor: String
        var laneHealthFilter: String
        var focusedSplitLaneID: String
        var hubInteractive: Bool
        var sourceSignature: String
    }

    private struct Entry {
        let loadedAt: Date
        let bundle: SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle
    }

    private static let maxAgeSeconds: TimeInterval = 0.25
    private static let maxEntries = 8
    private static var entries: [Key: Entry] = [:]

    static func load(
        key: Key,
        now: Date = Date(),
        loader: () -> SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle
    ) -> SupervisorViewRuntimePresentationSupport.DashboardPresentationBundle {
        if let entry = entries[key],
           now.timeIntervalSince(entry.loadedAt) < maxAgeSeconds {
            return entry.bundle
        }

        let bundle = loader()
        entries[key] = Entry(loadedAt: now, bundle: bundle)
        trimIfNeeded()
        return bundle
    }

    private static func trimIfNeeded() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.count - maxEntries
        let staleKeys = entries
            .sorted { $0.value.loadedAt < $1.value.loadedAt }
            .prefix(overflow)
            .map(\.key)
        for key in staleKeys {
            entries.removeValue(forKey: key)
        }
    }
}
