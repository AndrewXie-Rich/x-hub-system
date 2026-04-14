import Foundation

@MainActor
extension SupervisorViewRuntimePresentationSupport {
    static func portfolioOverviewPresentation(
        supervisor: SupervisorManager
    ) -> SupervisorPortfolioOverviewPresentation {
        let notificationSnapshot = supervisor.frontstageSupervisorProjectNotificationSnapshot
        return SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: supervisor.supervisorPortfolioSnapshot,
            actionability: supervisor.supervisorPortfolioSnapshot.actionabilitySnapshot(),
            projectNotificationStatusLine: notificationSnapshot.userFacingStatusLine,
            hasProjectNotificationActivity: notificationSnapshot.hasActivity,
            infrastructureStatusLine: supervisor.supervisorOfficialSkillsChannelStatusLine,
            infrastructureTransitionLine: supervisor.supervisorOfficialSkillsChannelTransitionLine,
            assemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot
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
        var actionEventRows: [SupervisorPortfolioActionEventPresentation] = []
        if let pairingSignal = supervisor.frontstagePairingNotificationSignal {
            actionEventRows.append(
                SupervisorPortfolioActionEventPresentationMapper.map(pairingSignal)
            )
        }
        actionEventRows.append(
            contentsOf: supervisor.frontstageRecentProjectActionEvents.map(
                SupervisorPortfolioActionEventPresentationMapper.map
            )
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
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> SupervisorDoctorBoardPresentation {
        let suggestionCards = doctorSuggestionCards(
            baseCards: supervisor.doctorSuggestionCards,
            historicalProjectBoundaryRepairStatusLine: appModel.historicalProjectBoundaryRepairStatusLine,
            memoryReadiness: supervisor.supervisorMemoryAssemblyReadiness,
            assemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot
        )
        let projectMemoryAdvisory = projectMemoryDoctorAdvisory(
            supervisor: supervisor,
            appModel: appModel
        )
        return SupervisorDoctorBoardPresentationMapper.map(
            doctorStatusLine: supervisor.doctorStatusLine,
            doctorReport: supervisor.doctorReport,
            doctorHasBlockingFindings: supervisor.doctorHasBlockingFindings,
            releaseBlockedByDoctorWithoutReport: supervisor.releaseBlockedByDoctorWithoutReport,
            memoryReadiness: supervisor.supervisorMemoryAssemblyReadiness,
            skillDoctorTruthProjection: appModel.unifiedDoctorReport
                .section(.skillsCompatibilityReadiness)?
                .skillDoctorTruthProjection,
            projectMemoryReadiness: projectMemoryAdvisory.readiness,
            projectMemoryProjectLabel: projectMemoryAdvisory.projectLabel,
            assemblySnapshot: supervisor.supervisorMemoryAssemblySnapshot,
            turnContextAssembly: supervisor.supervisorLatestTurnContextAssembly,
            canonicalRetryFeedback: supervisor.canonicalMemoryRetryFeedback,
            suggestionCards: suggestionCards,
            doctorReportPath: supervisor.doctorReportPath
        )
    }

    nonisolated static func doctorSuggestionCards(
        baseCards: [SupervisorDoctorSuggestionCard],
        historicalProjectBoundaryRepairStatusLine: String,
        memoryReadiness: SupervisorMemoryAssemblyReadiness? = nil,
        assemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil
    ) -> [SupervisorDoctorSuggestionCard] {
        var cards = baseCards.filter { card in
            !card.findingCode.hasPrefix("historical_project_boundary_repair")
                && card.findingCode != "memory_scoped_hidden_project_recovery_missing"
        }

        if let repairCard = historicalProjectBoundaryRepairSuggestionCard(
            statusLine: historicalProjectBoundaryRepairStatusLine
        ) {
            cards.insert(repairCard, at: 0)
        }

        if let hiddenRecoveryCard = hiddenProjectScopedRecoverySuggestionCard(
            baseCards: baseCards,
            memoryReadiness: memoryReadiness,
            assemblySnapshot: assemblySnapshot
        ) {
            cards.insert(hiddenRecoveryCard, at: 0)
        }
        return cards
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
        guard let legacyRuntime = appModel.legacySupervisorRuntimeContextIfLoaded else {
            return nil
        }

        if let value = trimmedNonEmpty(legacyRuntime.monitor.taskStates[lane.taskID]?.task.metadata["split_plan_id"]) {
            return value
        }

        if let proposal = legacyRuntime.orchestrator.activeSplitProposal,
           proposal.lanes.contains(where: { $0.laneId == lane.laneID }) {
            return proposal.splitPlanId.uuidString.lowercased()
        }

        if let launch = legacyRuntime.orchestrator.lastLaneLaunchReport {
            let inLaunch = launch.launchedLaneIDs.contains(lane.laneID)
                || launch.deferredLaneIDs.contains(lane.laneID)
                || launch.blockedLaneReasons[lane.laneID] != nil
            if inLaunch {
                return trimmedNonEmpty(launch.splitPlanID)
            }
        }

        return nil
    }

    private nonisolated static func historicalProjectBoundaryRepairSuggestionCard(
        statusLine: String
    ) -> SupervisorDoctorSuggestionCard? {
        let fields = scalarFields(statusLine)
        let outcome = normalizedScalar(
            fields["historical_project_boundary_repair"] ?? fields["status"] ?? ""
        ).lowercased()
        guard outcome == "partial" || outcome == "failed" else {
            return nil
        }

        let reason = normalizedScalar(fields["reason"] ?? "")
        let scannedCount = Int(normalizedScalar(fields["scanned"] ?? "")) ?? 0
        let repairedConfigCount = Int(normalizedScalar(fields["repaired_config"] ?? "")) ?? 0
        let repairedMemoryCount = Int(normalizedScalar(fields["repaired_memory"] ?? "")) ?? 0
        let failedCount = Int(normalizedScalar(fields["failed"] ?? "")) ?? 0
        let repairedCount = repairedConfigCount + repairedMemoryCount

        let reasonLabel = historicalProjectBoundaryRepairReasonLabel(reason)
        let why: String
        if failedCount > 0 {
            let lead = reasonLabel.isEmpty
                ? "最近一次历史项目边界修复未完全通过"
                : "\(reasonLabel)时发现历史项目边界未补齐"
            why = "\(lead)。目前仍有 \(failedCount) 个项目缺失 config.json 或 project memory，这会让 Supervisor 和 Project AI 看到不完整上下文。"
        } else if repairedCount > 0 {
            let lead = reasonLabel.isEmpty
                ? "历史项目边界刚刚被补齐了一部分"
                : "\(reasonLabel)时刚补齐了一部分历史项目边界"
            why = "\(lead)。虽然已补齐 \(repairedCount) 处边界，但仍建议确认所有历史项目都恢复了 config.json 和 project memory。"
        } else if scannedCount > 0 {
            why = "已扫描 \(scannedCount) 个历史项目，但修复结果仍不完整。建议重新执行一次受治理修复，避免历史项目上下文继续失真。"
        } else {
            why = "历史项目边界修复状态异常。建议重新执行受治理修复，避免 Supervisor 和 Project AI 读取到不完整项目上下文。"
        }

        let detail = [
            reasonLabel.isEmpty ? "" : "原因=\(reasonLabel)",
            scannedCount > 0 ? "扫描=\(scannedCount)" : "",
            repairedConfigCount > 0 ? "补齐 config=\(repairedConfigCount)" : "",
            repairedMemoryCount > 0 ? "补齐 memory=\(repairedMemoryCount)" : "",
            failedCount > 0 ? "失败=\(failedCount)" : ""
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " · ")
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "历史项目修复",
            detail: detail.isEmpty
                ? "打开诊断并重跑历史项目边界修复。"
                : detail,
            refreshAction: .repairHistoricalProjectBoundaries,
            refreshReason: "supervisor_doctor_historical_project_boundary_repair"
        )?.absoluteString

        return SupervisorDoctorSuggestionCard(
            findingCode: "historical_project_boundary_repair_\(outcome)",
            priority: failedCount > 0 && repairedCount == 0 ? .p0 : .p1,
            title: "补齐历史项目边界",
            why: why,
            actions: ["打开 XT Diagnostics 并重跑历史项目修复。"],
            verifyHint: "确认修复状态变成 repaired 或 noop，并检查目标项目已重新生成 config.json 与 project memory。",
            actionLabel: actionURL == nil ? nil : "重跑修复",
            actionURL: actionURL
        )
    }

    private nonisolated static func hiddenProjectScopedRecoverySuggestionCard(
        baseCards: [SupervisorDoctorSuggestionCard],
        memoryReadiness: SupervisorMemoryAssemblyReadiness?,
        assemblySnapshot: SupervisorMemoryAssemblySnapshot?
    ) -> SupervisorDoctorSuggestionCard? {
        guard (memoryReadiness?.issueCodes.contains("memory_scoped_hidden_project_recovery_missing") ?? false)
                || baseCards.contains(where: { $0.findingCode == "memory_scoped_hidden_project_recovery_missing" }) else {
            return nil
        }
        guard var card = baseCards.first(where: { $0.findingCode == "memory_scoped_hidden_project_recovery_missing" }) else {
            return nil
        }

        let focusedProjectId = trimmedNonEmpty(assemblySnapshot?.focusedProjectId)
        let recoveredSections = assemblySnapshot?.normalizedScopedPromptRecoverySections ?? []
        let detail = [
            focusedProjectId.map { "项目=\($0)" },
            recoveredSections.isEmpty ? "恢复分区=(none)" : "恢复分区=\(recoveredSections.joined(separator: ","))"
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        let actionURL = XTDeepLinkURLBuilder.settingsURL(
            sectionId: "diagnostics",
            title: "补回 hidden project 上下文",
            detail: detail.isEmpty
                ? "打开诊断，检查 explicit hidden project focus 是否补回项目范围上下文。"
                : detail,
            refreshReason: "supervisor_doctor_hidden_project_scoped_recovery"
        )?.absoluteString

        card.actionLabel = actionURL == nil ? nil : "打开诊断"
        card.actionURL = actionURL
        return card
    }

    private static func projectMemoryDoctorAdvisory(
        supervisor: SupervisorManager,
        appModel: AppModel
    ) -> (projectLabel: String?, readiness: XTProjectMemoryAssemblyReadiness?) {
        let advisory = appModel.doctorProjectMemoryAdvisory(
            preferredProjectId: supervisor.supervisorMemoryAssemblySnapshot?.focusedProjectId
        )
        return (advisory.projectLabel, advisory.readiness)
    }

    private nonisolated static func historicalProjectBoundaryRepairReasonLabel(
        _ raw: String
    ) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "load_registry":
            return "启动时加载项目注册表"
        case "settings_diagnostics_manual":
            return "诊断页手动重跑"
        case "supervisor_historical_project_boundary_repair":
            return "Supervisor 触发重跑"
        case "supervisor_doctor_historical_project_boundary_repair":
            return "Supervisor Doctor 建议重跑"
        case "test_manual":
            return "测试手动触发"
        default:
            return normalizedScalar(raw)
        }
    }

    private nonisolated static func scalarFields(_ raw: String) -> [String: String] {
        normalizedScalar(raw)
            .split(separator: " ")
            .reduce(into: [String: String]()) { result, token in
                let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return }
                let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty, !value.isEmpty else { return }
                result[key] = value
            }
    }

    private nonisolated static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private nonisolated static func normalizedScalar(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
