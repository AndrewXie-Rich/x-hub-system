import Foundation
import Testing
@testable import XTerminal

struct SupervisorViewRuntimePresentationSupportBoardsTests {

    @Test
    @MainActor
    func portfolioBoardPresentationSurfacesPairingNotificationInReminderCenter() {
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        manager.setAppModel(appModel)
        manager.setVoiceReadinessSnapshotForTesting(
            VoiceReadinessSnapshot(
                schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
                generatedAtMs: 1,
                overallState: .inProgress,
                overallSummary: "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
                primaryReasonCode: "local_pairing_ready_remote_unverified",
                orderedFixes: [],
                checks: [
                    VoiceReadinessCheck(
                        kind: .pairingValidity,
                        state: .inProgress,
                        reasonCode: "local_pairing_ready_remote_unverified",
                        headline: "同网首配已完成，正在验证正式异网入口",
                        summary: "同网首配已经完成，系统正在核对正式异网入口是否可用。",
                        nextStep: "请先在 Hub 配对页核对正式异网入口，并完成一次切网续连验证。",
                        repairEntry: .hubPairing,
                        detailLines: []
                    )
                ],
                nodeSync: .empty
            )
        )

        let overview = SupervisorPortfolioOverviewPresentation(
            iconName: "square.stack.3d.up",
            iconTone: .neutral,
            title: "项目总览",
            statusLine: "portfolio=idle",
            countBadges: [],
            metricBadgeRows: [],
            projectNotificationLine: nil,
            infrastructureStatusLine: nil,
            infrastructureTransitionLine: nil,
            emptyStateText: "empty",
            todayQueue: nil,
            closeOutQueue: nil,
            criticalQueue: nil
        )

        let presentation = SupervisorViewRuntimePresentationSupport.portfolioBoardPresentation(
            supervisor: manager,
            appModel: appModel,
            overview: overview,
            selectedProjectID: nil
        )

        #expect(presentation.recentActionFeedTitle == "提醒中心")
        #expect(presentation.actionEventRows.count == 1)
        #expect(presentation.actionEventRows.first?.sourceLabel == "配对信息")
        #expect(presentation.actionEventRows.first?.title == "同网首配已完成，正在验证正式异网入口")
        #expect(presentation.actionEventRows.first?.detailActionLabel == "打开处理")
    }

    @Test
    func doctorSuggestionCardsPrependsHistoricalProjectBoundaryRepairSuggestion() {
        let cards = SupervisorViewRuntimePresentationSupport.doctorSuggestionCards(
            baseCards: [
                SupervisorDoctorSuggestionCard(
                    findingCode: "doctor-existing",
                    priority: .p1,
                    title: "Existing suggestion",
                    why: "Keep an eye on the baseline.",
                    actions: ["Refresh Doctor"]
                )
            ],
            historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=partial reason=load_registry scanned=4 repaired_config=1 repaired_memory=2 failed=1"
        )

        #expect(cards.count == 2)
        #expect(cards[0].findingCode == "historical_project_boundary_repair_partial")
        #expect(cards[0].priority == .p1)
        #expect(cards[0].title == "补齐历史项目边界")
        #expect(cards[0].why.contains("启动时加载项目注册表"))
        #expect(cards[0].why.contains("仍有 1 个项目"))
        #expect(cards[0].actions.first == "打开 XT Diagnostics 并重跑历史项目修复。")
        #expect(cards[0].verifyHint?.contains("repaired 或 noop") == true)
        #expect(cards[0].actionLabel == "重跑修复")
        #expect(cards[0].actionURL?.contains("section_id=diagnostics") == true)
        #expect(cards[0].actionURL?.contains("refresh_action=repair_historical_project_boundaries") == true)
        #expect(cards[0].actionURL?.contains("refresh_reason=supervisor_doctor_historical_project_boundary_repair") == true)
        #expect(cards[1].findingCode == "doctor-existing")
    }

    @Test
    func doctorSuggestionCardsIgnoresNoopHistoricalProjectBoundaryRepairState() {
        let cards = SupervisorViewRuntimePresentationSupport.doctorSuggestionCards(
            baseCards: [],
            historicalProjectBoundaryRepairStatusLine: "historical_project_boundary_repair=noop reason=load_registry scanned=4 repaired_config=0 repaired_memory=0"
        )

        #expect(cards.isEmpty)
    }

    @Test
    func doctorSuggestionCardsEnrichHiddenProjectScopedRecoverySuggestionWithDiagnosticsLink() {
        let readiness = SupervisorMemoryAssemblyReadiness(
            ready: false,
            statusLine: "underfed:memory_scoped_hidden_project_recovery_missing",
            issues: [
                SupervisorMemoryAssemblyIssue(
                    code: "memory_scoped_hidden_project_recovery_missing",
                    severity: .blocking,
                    summary: "显式 hidden project 聚焦时没有补回项目范围上下文",
                    detail: "focus=project-hidden"
                )
            ]
        )
        let snapshot = SupervisorMemoryAssemblySnapshot(
            source: "hub",
            resolutionSource: "hub",
            updatedAt: 1,
            reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
            requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
            resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
            attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
            progressiveUpgradeCount: 0,
            focusedProjectId: "project-hidden",
            selectedSections: ["l1_canonical", "l2_observations", "l3_working_set", "dialogue_window"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 1,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: 1200,
            usedTotalTokens: 640,
            truncatedLayers: [],
            freshness: "fresh_remote",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            scopedPromptRecoveryMode: "explicit_hidden_project_focus",
            scopedPromptRecoverySections: []
        )

        let cards = SupervisorViewRuntimePresentationSupport.doctorSuggestionCards(
            baseCards: [
                SupervisorDoctorSuggestionCard(
                    findingCode: "memory_scoped_hidden_project_recovery_missing",
                    priority: .p0,
                    title: "补回 hidden project 上下文",
                    why: "当前 hidden project 还没拿到项目范围上下文。",
                    actions: ["重新对该 hidden project 发起一次显式聚焦回合。"],
                    verifyHint: "snapshot.scopedPromptRecoverySections 不再为空"
                )
            ],
            historicalProjectBoundaryRepairStatusLine: "",
            memoryReadiness: readiness,
            assemblySnapshot: snapshot
        )

        #expect(cards.count == 1)
        #expect(cards[0].findingCode == "memory_scoped_hidden_project_recovery_missing")
        #expect(cards[0].actionLabel == "打开诊断")
        #expect(cards[0].actionURL?.contains("section_id=diagnostics") == true)
        #expect(cards[0].actionURL?.contains("refresh_reason=supervisor_doctor_hidden_project_scoped_recovery") == true)
        #expect(cards[0].actionURL?.contains("project-hidden") == true)
    }

    @Test
    @MainActor
    func automationRuntimePresentationUsesSelectedProjectConfigInsteadOfCurrentProjectCache() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_runtime_scope_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)
        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)
        let projectIdB = AXProjectRegistryStore.projectId(forRoot: rootB)

        var configA = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        configA = configA.settingAutomationSelfIteration(enabled: false, maxAutoRetryDepth: 2)
        try AXProjectStore.saveConfig(configA, for: ctxA)

        var configB = try AXProjectStore.loadOrCreateConfig(for: ctxB)
        configB = configB.settingAutomationSelfIteration(enabled: true, maxAutoRetryDepth: 5)
        try AXProjectStore.saveConfig(configB, for: ctxB)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let entryB = AXProjectEntry(
            projectId: projectIdB,
            rootPath: rootB.path,
            displayName: "Beta",
            lastOpenedAt: 2,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 3,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA, entryB]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = configA

        let presentation = SupervisorViewRuntimePresentationSupport.automationRuntimePresentation(
            supervisor: SupervisorManager.shared,
            appModel: appModel,
            selectedProject: entryB,
            selectedRecipe: nil,
            selectedLastLaunchRef: ""
        )

        #expect(presentation.projectLine?.text.contains("Beta") == true)
        #expect(presentation.controls?.selfIterateEnabled == true)
        #expect(presentation.controls?.maxAutoRetryDepth == 5)
    }

    @Test
    @MainActor
    func doctorBoardPresentationUsesFocusedProjectForProjectMemoryAdvisory() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_supervisor_doctor_board_focus_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let rootA = workspace.appendingPathComponent("project-a", isDirectory: true)
        let rootB = workspace.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)
        let projectIdA = AXProjectRegistryStore.projectId(forRoot: rootA)
        let projectIdB = AXProjectRegistryStore.projectId(forRoot: rootB)

        let entryA = AXProjectEntry(
            projectId: projectIdA,
            rootPath: rootA.path,
            displayName: "Alpha",
            lastOpenedAt: 1,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let entryB = AXProjectEntry(
            projectId: projectIdB,
            rootPath: rootB.path,
            displayName: "Beta",
            lastOpenedAt: 2,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 3,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectIdA,
            projects: [entryA, entryB]
        )
        appModel.selectedProjectId = projectIdA
        appModel.projectContext = ctxA
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctxA)
        _ = try AXProjectStore.loadOrCreateConfig(for: ctxB)

        let supervisor = SupervisorManager.makeForTesting()
        supervisor.setSupervisorMemoryAssemblySnapshotForTesting(
            SupervisorMemoryAssemblySnapshot(
                source: "hub",
                resolutionSource: "hub",
                updatedAt: 1,
                reviewLevelHint: SupervisorReviewLevel.r2Strategic.rawValue,
                requestedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m3DeepDive.rawValue,
                attemptedProfiles: [XTMemoryServingProfile.m3DeepDive.rawValue],
                progressiveUpgradeCount: 0,
                focusedProjectId: projectIdB,
                selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
                omittedSections: [],
                contextRefsSelected: 0,
                contextRefsOmitted: 0,
                evidenceItemsSelected: 0,
                evidenceItemsOmitted: 0,
                budgetTotalTokens: 1200,
                usedTotalTokens: 320,
                truncatedLayers: [],
                freshness: "fresh_remote",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil,
                compressionPolicy: "balanced"
            )
        )

        let presentation = SupervisorViewRuntimePresentationSupport.doctorBoardPresentation(
            supervisor: supervisor,
            appModel: appModel
        )

        #expect(presentation.projectMemoryAdvisoryLine == "Project AI memory（advisory）：Beta 当前需关注。")
        #expect(
            presentation.projectMemoryAdvisoryDetailLine?.contains("缺少最近一次真实 usage") == true
        )
    }

    @Test
    @MainActor
    func doctorBoardPresentationSurfacesUnifiedDoctorSkillTruthProjection() {
        let supervisor = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        let projection = sampleBoardsSkillDoctorTruthProjection(includeBlocked: true)
        var report = XTUnifiedDoctorReport.empty
        report.sections = [
            XTUnifiedDoctorSection(
                kind: .skillsCompatibilityReadiness,
                state: .diagnosticRequired,
                headline: "技能 doctor truth 已发现不可运行项",
                summary: "技能兼容性表面已经可读，但 typed capability/readiness 仍显示 1 个技能当前不可运行。",
                nextStep: "先处理不可运行项。",
                repairEntry: .xtDiagnostics,
                detailLines: [],
                skillDoctorTruthProjection: projection
            )
        ]
        appModel.unifiedDoctorReport = report

        let presentation = SupervisorViewRuntimePresentationSupport.doctorBoardPresentation(
            supervisor: supervisor,
            appModel: appModel
        )

        #expect(presentation.skillDoctorTruthStatusLine == "技能 doctor truth：1 个技能当前不可运行。")
        #expect(presentation.skillDoctorTruthTone == .danger)
        #expect(presentation.skillDoctorTruthDetailLine?.contains("当前阻塞：delivery-runner") == true)
    }
}

private func sampleBoardsSkillDoctorTruthProjection(
    includeBlocked: Bool
) -> XTUnifiedDoctorSkillDoctorTruthProjection {
    var effectiveProfile = XTProjectEffectiveSkillProfileSnapshot(
        schemaVersion: XTProjectEffectiveSkillProfileSnapshot.currentSchemaVersion,
        projectId: "project-alpha",
        projectName: "Alpha",
        source: "xt_project_governance+hub_skill_registry",
        executionTier: "a4_openclaw",
        runtimeSurfaceMode: "paired_hub",
        hubOverrideMode: "inherit",
        legacyToolProfile: "openclaw",
        discoverableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        installableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        requestableProfiles: ["observe_only", "browser_research", "browser_operator", "delivery"],
        runnableNowProfiles: ["observe_only"],
        grantRequiredProfiles: ["browser_research"],
        approvalRequiredProfiles: ["browser_operator"],
        blockedProfiles: includeBlocked
            ? [
                XTProjectEffectiveSkillBlockedProfile(
                    profileID: "delivery",
                    reasonCode: "policy_clamped",
                    state: XTSkillExecutionReadinessState.policyClamped.rawValue,
                    source: "project_governance",
                    unblockActions: ["raise_execution_tier"]
                )
            ]
            : [],
        ceilingCapabilityFamilies: ["skills.discover", "web.live", "browser.interact"],
        runnableCapabilityFamilies: ["skills.discover"],
        localAutoApproveEnabled: false,
        trustedAutomationReady: true,
        profileEpoch: "epoch-1",
        trustRootSetHash: "trust-root-1",
        revocationEpoch: "revocation-1",
        officialChannelSnapshotID: "channel-1",
        runtimeSurfaceHash: "surface-1",
        auditRef: "audit-xt-skill-profile-alpha"
    )
    if !includeBlocked {
        effectiveProfile.discoverableProfiles = ["observe_only", "browser_research", "browser_operator"]
        effectiveProfile.installableProfiles = ["observe_only", "browser_research", "browser_operator"]
        effectiveProfile.requestableProfiles = ["observe_only", "browser_research", "browser_operator"]
    }

    var governanceEntries = [
        sampleBoardsSkillGovernanceEntry(
            skillID: "find-skills",
            executionReadiness: XTSkillExecutionReadinessState.ready.rawValue,
            capabilityProfiles: ["observe_only"],
            capabilityFamilies: ["skills.discover"]
        ),
        sampleBoardsSkillGovernanceEntry(
            skillID: "tavily-websearch",
            executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
            whyNotRunnable: "grant floor readonly still pending",
            grantFloor: XTSkillGrantFloor.readonly.rawValue,
            approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
            capabilityProfiles: ["browser_research"],
            capabilityFamilies: ["web.live"],
            unblockActions: ["request_hub_grant"]
        ),
        sampleBoardsSkillGovernanceEntry(
            skillID: "browser-operator",
            executionReadiness: XTSkillExecutionReadinessState.localApprovalRequired.rawValue,
            whyNotRunnable: "local approval still pending",
            grantFloor: XTSkillGrantFloor.none.rawValue,
            approvalFloor: XTSkillApprovalFloor.localApproval.rawValue,
            capabilityProfiles: ["browser_operator"],
            capabilityFamilies: ["browser.interact"],
            unblockActions: ["request_local_approval"]
        )
    ]
    if includeBlocked {
        governanceEntries.append(
            sampleBoardsSkillGovernanceEntry(
                skillID: "delivery-runner",
                executionReadiness: XTSkillExecutionReadinessState.policyClamped.rawValue,
                whyNotRunnable: "project capability bundle blocks repo.delivery",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: XTSkillApprovalFloor.hubGrantPlusLocalApproval.rawValue,
                capabilityProfiles: ["delivery"],
                capabilityFamilies: ["repo.delivery"],
                unblockActions: ["raise_execution_tier"]
            )
        )
    }

    return XTUnifiedDoctorSkillDoctorTruthProjection(
        effectiveProfileSnapshot: effectiveProfile,
        governanceEntries: governanceEntries
    )
}

private func sampleBoardsSkillGovernanceEntry(
    skillID: String,
    executionReadiness: String,
    whyNotRunnable: String = "",
    grantFloor: String = XTSkillGrantFloor.none.rawValue,
    approvalFloor: String = XTSkillApprovalFloor.none.rawValue,
    capabilityProfiles: [String],
    capabilityFamilies: [String],
    unblockActions: [String] = []
) -> AXSkillGovernanceSurfaceEntry {
    let readinessState = XTSkillCapabilityProfileSupport.readinessState(from: executionReadiness)
    let tone: AXSkillGovernanceTone = {
        switch readinessState {
        case .ready:
            return .ready
        case .grantRequired, .localApprovalRequired, .degraded:
            return .warning
        default:
            return .blocked
        }
    }()

    return AXSkillGovernanceSurfaceEntry(
        skillID: skillID,
        name: skillID,
        version: "1.0.0",
        riskLevel: "medium",
        packageSHA256: "sha-\(skillID)",
        publisherID: "publisher.test",
        sourceID: "source.test",
        policyScope: "project",
        tone: tone,
        stateLabel: XTSkillCapabilityProfileSupport.readinessLabel(executionReadiness),
        intentFamilies: ["test.intent"],
        capabilityFamilies: capabilityFamilies,
        capabilityProfiles: capabilityProfiles,
        grantFloor: grantFloor,
        approvalFloor: approvalFloor,
        discoverabilityState: "discoverable",
        installabilityState: "installable",
        requestabilityState: "requestable",
        executionReadiness: executionReadiness,
        whyNotRunnable: whyNotRunnable,
        unblockActions: unblockActions,
        trustRootValue: "trusted",
        pinnedVersionValue: "1.0.0",
        runnerRequirementValue: "xt_builtin",
        compatibilityStatusValue: "compatible",
        preflightResultValue: "ready",
        note: "",
        installHint: ""
    )
}
