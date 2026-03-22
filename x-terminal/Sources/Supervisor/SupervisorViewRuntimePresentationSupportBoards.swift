import Foundation

@MainActor
extension SupervisorViewRuntimePresentationSupport {
    static func portfolioOverviewPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorPortfolioOverviewPresentation {
        SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: supervisor.supervisorPortfolioSnapshot,
            actionability: supervisor.supervisorPortfolioSnapshot.actionabilitySnapshot(),
            projectNotificationStatusLine: supervisor.supervisorProjectNotificationSnapshot.statusLine,
            hasProjectNotificationActivity: supervisor.supervisorProjectNotificationSnapshot.hasActivity,
            infrastructureStatusLine: supervisor.supervisorOfficialSkillsChannelStatusLine,
            infrastructureTransitionLine: supervisor.supervisorOfficialSkillsChannelTransitionLine
        )
    }

    static func portfolioBoardPresentation(
        supervisor: SupervisorManager,
        appModel: AppModel,
        overview: SupervisorPortfolioOverviewPresentation,
        selectedProjectID: String?
    ) -> SupervisorPortfolioBoardPresentation {
        let snapshot = supervisor.supervisorPortfolioSnapshot
        let actionability = snapshot.actionabilitySnapshot()
        let actionabilityByProject = Dictionary(grouping: actionability.recommendedActions, by: \.projectId)
        let uiReviewScanProjectIDs = Array(
            snapshot.projects
                .prefix(SupervisorPortfolioBoardPresentationMapper.defaultMaxUIReviewScanProjects)
                .map(\.projectId)
        )
        let latestUIReviewByProjectID: [String: XTUIReviewPresentation] = .init(
            uniqueKeysWithValues: uiReviewScanProjectIDs.compactMap { projectID in
                guard let ctx = appModel.projectContext(for: projectID),
                      let review = XTUIReviewPresentation.loadLatestBrowserPage(for: ctx) else {
                    return nil
                }
                return (projectID, review)
            }
        )
        let projectRows = snapshot.projects.map { card in
            portfolioProjectRowPresentation(
                card,
                actionabilityItems: Array((actionabilityByProject[card.projectId] ?? []).prefix(2)),
                isSelected: selectedProjectID == card.projectId,
                appModel: appModel,
                latestUIReview: latestUIReviewByProjectID[card.projectId]
            )
        }
        let uiReviewActivityRows = snapshot.projects
            .prefix(SupervisorPortfolioBoardPresentationMapper.defaultMaxUIReviewScanProjects)
            .compactMap { card -> (SupervisorPortfolioProjectCard, XTUIReviewPresentation)? in
                guard let review = latestUIReviewByProjectID[card.projectId] else {
                    return nil
                }
                return (card, review)
            }
            .sorted { lhs, rhs in
                lhs.1.updatedAtMs > rhs.1.updatedAtMs
            }
            .map { card, review in
                SupervisorPortfolioUIReviewActivityPresentationMapper.map(
                    projectId: card.projectId,
                    projectName: card.displayName,
                    review: review
                )
            }
        let actionEventRows = supervisor.supervisorRecentProjectActionEvents.map(
            SupervisorPortfolioActionEventPresentationMapper.map
        )

        return SupervisorPortfolioBoardPresentationMapper.map(
            overview: overview,
            projectRows: projectRows,
            uiReviewActivityRows: uiReviewActivityRows,
            actionEventRows: actionEventRows,
            selectedProjectID: selectedProjectID,
            lastDrillDownSnapshot: supervisor.supervisorLastProjectDrillDownSnapshot
        )
    }

    static func infrastructureFeedBoardPresentation(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorInfrastructureFeedBoardPresentation {
        SupervisorInfrastructureFeedBoardPresentationMapper.map(
            feed: infrastructureFeedPresentation(
                supervisor: supervisor,
                appModel: appModel
            )
        )
    }

    static func doctorBoardPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorDoctorBoardPresentation {
        SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: supervisor.doctorStatusLine,
            doctorReport: supervisor.doctorReport,
            doctorHasBlockingFindings: supervisor.doctorHasBlockingFindings,
            releaseBlockedByDoctorWithoutReport: supervisor.releaseBlockedByDoctorWithoutReport,
            memoryReadiness: supervisor.supervisorMemoryAssemblyReadiness,
            assemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot,
            canonicalRetryFeedback: supervisor.canonicalMemoryRetryFeedback,
            suggestionCards: supervisor.doctorSuggestionCards,
            doctorReportPath: supervisor.doctorReportPath
        )
    }

    static func xtReadyIncidentPresentation(
        supervisor: SupervisorManager,
        snapshot: SupervisorManager.XTReadyIncidentExportSnapshot? = nil
    ) -> SupervisorXTReadyIncidentPresentation {
        SupervisorXTReadyIncidentPresentationMapper.map(
            snapshot: snapshot ?? supervisor.xtReadyIncidentExportSnapshot(limit: 120),
            canonicalRetryFeedback: supervisor.canonicalMemoryRetryFeedback
        )
    }

    static func projectDrillDownPresentation(
        _ snapshot: SupervisorProjectDrillDownSnapshot,
        supervisor: SupervisorManager,
        appModel: AppModel,
        selectedScope: SupervisorProjectDrillDownScope
    ) -> SupervisorProjectDrillDownPresentation {
        let allowedScopes = supervisor.supervisorJurisdictionRegistry.allowedDrillDownScopes(projectId: snapshot.projectId)
        let projectEntry = appModel.registry.project(for: snapshot.projectId)
        let governed = projectEntry.map { appModel.governedAuthorityPresentation(for: $0) }
        let templatePreview = projectEntry.map { appModel.governanceTemplatePreview(for: $0) }
        let latestUIReview = appModel.projectContext(for: snapshot.projectId).flatMap {
            XTUIReviewPresentation.loadLatestBrowserPage(for: $0)
        }
        let governanceCard = snapshot.capsule ?? SupervisorPortfolioProjectCard(
            projectId: snapshot.projectId,
            displayName: snapshot.projectName,
            projectState: .active,
            runtimeState: "",
            currentAction: "",
            topBlocker: "",
            nextStep: "",
            memoryFreshness: .fresh,
            updatedAt: snapshot.updatedAt,
            recentMessageCount: snapshot.recentMessages.count
        )
        let governanceTags = SupervisorPortfolioProjectRowPresentationMapper.governanceTags(
            card: governanceCard,
            governed: governed,
            templatePreview: templatePreview
        )
        return SupervisorProjectDrillDownPresentationMapper.map(
            snapshot: snapshot,
            allowedScopes: allowedScopes,
            selectedScope: selectedScope,
            governanceTags: governanceTags,
            runtimeSummary: templatePreview?.runtimeSummary,
            latestUIReview: latestUIReview,
            governanceNowMs: Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        )
    }

    static func laneHealthBoardPresentation(
        supervisor: SupervisorManager,
        appModel: AppModel,
        filter: SupervisorLaneHealthFilter,
        focusedLaneID: String?
    ) -> SupervisorLaneHealthBoardPresentation {
        let snapshot = supervisor.supervisorLaneHealthSnapshot
        let splitPlanTextByLaneID = Dictionary(
            uniqueKeysWithValues: (snapshot?.lanes ?? []).map { lane in
                (lane.laneID, laneSplitPlanID(for: lane, appModel: appModel) ?? "n/a")
            }
        )

        return SupervisorLaneHealthBoardPresentationMapper.map(
            snapshot: snapshot,
            statusLine: supervisor.supervisorLaneHealthStatusLine,
            filter: filter,
            focusedLaneID: focusedLaneID,
            splitPlanTextByLaneID: splitPlanTextByLaneID
        )
    }

    private static func portfolioProjectRowPresentation(
        _ card: SupervisorPortfolioProjectCard,
        actionabilityItems: [SupervisorPortfolioActionabilityItem],
        isSelected: Bool,
        appModel: AppModel,
        latestUIReview: XTUIReviewPresentation?
    ) -> SupervisorPortfolioProjectRowPresentation {
        let projectEntry = appModel.registry.project(for: card.projectId)
        let governed = projectEntry.map { appModel.governedAuthorityPresentation(for: $0) }
        let templatePreview = projectEntry.map { appModel.governanceTemplatePreview(for: $0) }
        return SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: actionabilityItems,
            isSelected: isSelected,
            governed: governed,
            templatePreview: templatePreview,
            latestUIReview: latestUIReview
        )
    }

    private static func laneSplitPlanID(
        for lane: SupervisorLaneHealthLaneState,
        appModel: AppModel
    ) -> String? {
        if let value = trimmedNonEmpty(appModel.supervisor.orchestrator.monitor.taskStates[lane.taskID]?.task.metadata["split_plan_id"]) {
            return value
        }

        if let proposal = appModel.supervisor.orchestrator.activeSplitProposal,
           proposal.lanes.contains(where: { $0.laneId == lane.laneID }) {
            return proposal.splitPlanId.uuidString.lowercased()
        }

        if let launch = appModel.supervisor.orchestrator.lastLaneLaunchReport {
            let inLaunch = launch.launchedLaneIDs.contains(lane.laneID)
                || launch.deferredLaneIDs.contains(lane.laneID)
                || launch.blockedLaneReasons[lane.laneID] != nil
            if inLaunch {
                return trimmedNonEmpty(launch.splitPlanID)
            }
        }

        return nil
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
