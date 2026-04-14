import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorHeartbeatVoiceTests {

    @Test
    func appModelAttachSpeaksBlockedHeartbeatWhenSummaryReportingEnabled() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Voice Runtime",
            blockerSummary: "等待 Hub grant 批准",
            nextStepSummary: "完成授权后继续运行语音回归"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(reason: "blocked_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("1 个阻塞项目"))
        #expect(spoken[0].contains("Voice Runtime"))
        #expect(spoken[0].contains("等待 Hub grant 批准"))
    }

    @Test
    func appModelAttachSuppressesStableSummaryWhenBlockersOnlyModeIsEnabled() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-stable")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Stable Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续执行联调验证"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(reason: "stable_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "suppressed:auto_report_mode_suppressed")
        #expect(spoken.isEmpty)
    }

    @Test
    func stableHeartbeatCountsOnlyActiveProjectsInVoiceSummary() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let activeRoot = try makeProjectRoot(named: "heartbeat-active-project")
        let idleRoot = try makeProjectRoot(named: "heartbeat-idle-project")
        defer {
            try? FileManager.default.removeItem(at: activeRoot)
            try? FileManager.default.removeItem(at: idleRoot)
        }

        let activeProject = makeProjectEntry(
            root: activeRoot,
            displayName: "Active Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续执行联调验证"
        )
        let idleProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: idleRoot),
            rootPath: idleRoot.path,
            displayName: "Idle Runtime",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: "runtime=paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "等待下一次指令",
            blockerSummary: nil,
            lastSummaryAt: Date().timeIntervalSince1970,
            lastEventAt: Date().timeIntervalSince1970
        )

        let appModel = AppModel()
        appModel.registry = registry(with: [activeProject, idleProject])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(reason: "stable_active_only_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("1 个项目在跑"))
        #expect(!spoken[0].contains("2 个项目在跑"))
    }

    @Test
    func heartbeatFocusActionPrefersRouteDiagnoseWhenOnlyModelRouteNoticeNeedsAttention() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-route-diagnose-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-14b-mlx",
                "runtime_provider": "Hub (Local)",
                "execution_path": "local_fallback_after_remote_error",
                "fallback_reason_code": "model_not_found",
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 200,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-14b-mlx",
                "runtime_provider": "Hub (Local)",
                "execution_path": "local_fallback_after_remote_error",
                "fallback_reason_code": "model_not_found",
            ],
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let actionURL = try #require(manager.heartbeatFocusActionURLForTesting(reason: "manual_test"))
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: .routeDiagnose,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func recentGovernanceBlockedSkillActivityUsesProjectGovernanceDeepLink() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-governance-skill-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-governance-1",
                projectId: "project-governance",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "open-index-html",
                toolName: ToolName.process_start.rawValue,
                status: .blocked,
                payload: ["name": .string("open-index-html")],
                currentOwner: "supervisor",
                resultSummary: "project governance blocks process_start under A-Tier a0_observe",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_managed_processes",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-skill-1"
            ),
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Governance Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let activity = try #require(manager.recentSupervisorSkillActivities.first)
        let actionURL = try #require(activity.actionURL)
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .executionTier
                )
            )
        )
    }

    @Test
    func heartbeatFocusActionUsesGrantFocusForRecoveryFollowUpWithoutPendingGrantSnapshot() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-recovery-grant-focus")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a2RepoAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Grant Recovery Runtime",
            blockerSummary: nil,
            nextStepSummary: "等待授权恢复执行"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .authzDenied,
                nextActionRecommendation: "request_grant_follow_up"
            )
        )

        let actionURL = try #require(
            manager.heartbeatFocusActionURLForTesting(
                reason: "timer",
                now: Date(timeIntervalSince1970: 1_773_384_220)
            )
        )
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func heartbeatNextStepSummarySurfacesRouteRepairAttentionBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let routeRoot = try makeProjectRoot(named: "heartbeat-route-repair-summary")
        let otherRoot = try makeProjectRoot(named: "heartbeat-route-repair-summary-other")
        defer {
            try? FileManager.default.removeItem(at: routeRoot)
            try? FileManager.default.removeItem(at: otherRoot)
        }

        let routeCtx = AXProjectContext(root: routeRoot)
        try routeCtx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "open_model_picker",
            outcome: "opened",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 100,
            for: routeCtx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 200,
            for: routeCtx
        )

        let routeProject = makeProjectEntry(
            root: routeRoot,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let otherProject = makeProjectEntry(
            root: otherRoot,
            displayName: "Alpha Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续 Alpha 的验证"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [routeProject, otherProject])
        manager.setAppModel(appModel)

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(maxItems: 4)
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("模型路由：Route Runtime"))
        #expect(nextStepSummary.contains("最近最常见是 目标模型未加载"))
        #expect(nextStepSummary.contains("最近一次失败停在 重连并重诊断"))
        #expect(!nextStepSummary.contains("reconnect_hub_and_diagnose"))
        #expect(nextStepSummary.contains("建议先看 /route diagnose"))
        #expect(!nextStepSummary.contains("常规推进：Route Runtime"))
        #expect(nextStepSummary.contains("常规推进：Alpha Runtime"))
    }

    @Test
    func heartbeatNextStepSummaryAddsHubSideHintForRemoteExportBlockedRouteRepair() throws {
        let manager = SupervisorManager.makeForTesting()
        let routeRoot = try makeProjectRoot(named: "heartbeat-route-repair-export-gate")
        defer { try? FileManager.default.removeItem(at: routeRoot) }

        let routeCtx = AXProjectContext(root: routeRoot)
        try routeCtx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "open_hub_recovery",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            createdAt: 100,
            for: routeCtx
        )

        let routeProject = makeProjectEntry(
            root: routeRoot,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [routeProject])
        manager.setAppModel(appModel)

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(maxItems: 3)
        #expect(nextStepSummary.contains("Hub export gate / 策略挡住远端"))
        #expect(nextStepSummary.contains("先查 Hub"))
        #expect(nextStepSummary.contains("建议先看 /route diagnose"))
    }

    @Test
    func heartbeatNextStepSummaryPrefersRecentStatusBarFollowUpForRouteRepair() throws {
        let manager = SupervisorManager.makeForTesting()
        let routeRoot = try makeProjectRoot(named: "heartbeat-route-repair-status-bar-followup")
        defer { try? FileManager.default.removeItem(at: routeRoot) }

        let routeCtx = AXProjectContext(root: routeRoot)
        try routeCtx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 100,
            for: routeCtx
        )
        AXRouteRepairLogStore.record(
            actionId: "open_choose_model",
            outcome: "opened",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            note: "source=status_bar",
            createdAt: 200,
            for: routeCtx
        )

        let routeProject = makeProjectEntry(
            root: routeRoot,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [routeProject])
        manager.setAppModel(appModel)

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(
            now: Date(timeIntervalSince1970: 210),
            maxItems: 3
        )

        #expect(nextStepSummary.contains("刚刚已从顶部状态栏打开 AI 模型"))
        #expect(nextStepSummary.contains("建议先查看 AI 模型"))
        #expect(!nextStepSummary.contains("建议先看 /route diagnose"))
    }

    @Test
    func heartbeatFocusActionPrefersRouteDiagnoseWhenRouteRepairWatchItemNeedsAttention() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-route-repair-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 100,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Repair Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let actionURL = try #require(manager.heartbeatFocusActionURLForTesting(reason: "manual_test"))
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: .routeDiagnose,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func heartbeatFocusActionUsesResumeProjectForReplayRecoveryFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-recovery-replay-focus")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a3DeliverAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Replay Recovery Runtime",
            blockerSummary: nil,
            nextStepSummary: "重放 follow-up / 续跑链"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .restartDrain,
                nextActionRecommendation: "wait_drain_recover"
            )
        )

        let actionURL = try #require(
            manager.heartbeatFocusActionURLForTesting(
                reason: "timer",
                now: Date(timeIntervalSince1970: 1_773_384_320)
            )
        )
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: true
                )
            )
        )
    }

    @Test
    func heartbeatFocusActionPrefersRecentStatusBarHubRecoveryFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-route-repair-followup-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "open_hub_recovery",
            outcome: "opened",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            note: "source=status_bar",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Repair Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let actionURL = try #require(
            manager.heartbeatFocusActionURLForTesting(
                reason: "manual_test",
                now: Date(timeIntervalSince1970: 210)
            )
        )
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "troubleshoot",
                    title: nil,
                    detail: nil,
                    refreshAction: nil,
                    refreshReason: nil,
                    pairingPrefill: nil
                )
            )
        )
    }

    @Test
    func heartbeatFocusActionPrefersGovernanceRepairWhenRecentBlockedSkillNeedsFix() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-governance-action")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-governance-2",
                projectId: "project-governance",
                jobId: "job-2",
                planId: "plan-2",
                stepId: "step-2",
                skillId: "open-index-html",
                toolName: ToolName.process_start.rawValue,
                status: .blocked,
                payload: ["name": .string("open-index-html")],
                currentOwner: "supervisor",
                resultSummary: "project governance blocks process_start under A-Tier a0_observe",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_managed_processes",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-skill-2"
            ),
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Governance Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let actionURL = try #require(manager.heartbeatFocusActionURLForTesting(reason: "manual_test"))
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: project.projectId,
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .executionTier
                )
            )
        )
    }

    @Test
    func heartbeatNextStepSummarySurfacesGovernanceRepairBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let governanceRoot = try makeProjectRoot(named: "heartbeat-governance-summary")
        let otherRoot = try makeProjectRoot(named: "heartbeat-governance-summary-other")
        defer {
            try? FileManager.default.removeItem(at: governanceRoot)
            try? FileManager.default.removeItem(at: otherRoot)
        }

        let governanceCtx = AXProjectContext(root: governanceRoot)
        try governanceCtx.ensureDirs()
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-governance-summary-1",
                projectId: "project-governance-summary",
                jobId: "job-governance-summary-1",
                planId: "plan-governance-summary-1",
                stepId: "step-governance-summary-1",
                skillId: "open-index-html",
                toolName: ToolName.process_start.rawValue,
                status: .blocked,
                payload: ["name": .string("open-index-html")],
                currentOwner: "supervisor",
                resultSummary: "project governance blocks process_start under A-Tier a0_observe",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_managed_processes",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-summary-1"
            ),
            for: governanceCtx
        )

        let governanceProject = makeProjectEntry(
            root: governanceRoot,
            displayName: "Governance Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let otherProject = makeProjectEntry(
            root: otherRoot,
            displayName: "Alpha Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续 Alpha 的验证"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [governanceProject, otherProject])
        manager.setAppModel(appModel)

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(maxItems: 4)
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("治理修复：Governance Runtime"))
        #expect(nextStepSummary.contains("A-Tier"))
        #expect(!nextStepSummary.contains("常规推进：Governance Runtime"))
        #expect(nextStepSummary.contains("常规推进：Alpha Runtime"))
    }

    @Test
    func heartbeatVoiceCallsOutGovernanceRepairWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-governance-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-governance-voice-1",
                projectId: "project-governance-voice",
                jobId: "job-governance-voice-1",
                planId: "plan-governance-voice-1",
                stepId: "step-governance-voice-1",
                skillId: "open-index-html",
                toolName: ToolName.process_start.rawValue,
                status: .blocked,
                payload: ["name": .string("open-index-html")],
                currentOwner: "supervisor",
                resultSummary: "project governance blocks process_start under A-Tier a0_observe",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_managed_processes",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-voice-1"
            ),
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Governance Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(reason: "governance_repair_voice_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("治理设置"))
        #expect(spoken[0].contains("Governance Runtime"))
        #expect(spoken[0].contains("A-Tier"))
    }

    @Test
    func heartbeatNextStepSummarySurfacesQueuedGovernedReviewBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-governed-review-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 1_800,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let staleAt: TimeInterval = 1_773_900_000
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: Int64((staleAt * 1000.0).rounded()),
            nowMs: Int64((staleAt * 1000.0).rounded())
        )

        let reviewProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Review Runtime",
            lastOpenedAt: staleAt,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: staleAt,
            lastEventAt: staleAt
        )
        let otherRoot = try makeProjectRoot(named: "heartbeat-governed-review-summary-other")
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        let otherProject = makeProjectEntry(
            root: otherRoot,
            displayName: "Alpha Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续 Alpha 的验证"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [reviewProject, otherProject])
        manager.setAppModel(appModel)

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(
            now: Date(timeIntervalSince1970: staleAt + 4_000),
            maxItems: 4
        )
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("治理审查：Review Runtime"))
        #expect(firstLine.contains("战略审查"))
        #expect(firstLine.contains("长时间无进展"))
        #expect(!nextStepSummary.contains("常规推进：Review Runtime"))
        #expect(nextStepSummary.contains("常规推进：Alpha Runtime"))
    }

    @Test
    func heartbeatVoiceUsesGovernanceRecommendationForPendingHubGrant() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-governance-grant-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "grant-voice-1",
                    dedupeKey: "grant-voice-1",
                    grantRequestId: "grant-voice-1",
                    requestId: "req-grant-voice-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "governance_pending_grant_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 待处理授权"))
        #expect(spoken[0].contains("打开授权并批准设备级权限"))
        #expect(spoken[0].contains("查看授权板"))
    }

    @Test
    func heartbeatVoiceUsesGovernanceRecommendationForPendingSkillApproval() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-governance-skill-approval-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Device Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "approval-voice-1",
                    requestId: "approval-voice-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-approval-1",
                    planId: "plan-approval-1",
                    stepId: "step-approval-1",
                    skillId: "guarded-automation",
                    requestedSkillId: "browser.open",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    tool: .deviceBrowserControl,
                    toolSummary: "打开 https://example.com/login",
                    reason: "需要确认后再执行设备级浏览器操作",
                    createdAt: 1_200,
                    actionURL: nil,
                    routingReasonCode: "preferred_builtin_selected",
                    routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open"
                )
            ]
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "governance_pending_skill_approval_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("待审批技能"))
        #expect(spoken[0].contains("受治理内建 guarded-automation"))
        #expect(spoken[0].contains("先在 X-Terminal 里批准"))
        #expect(spoken[0].contains("查看技能审批"))
    }

    @Test
    func heartbeatVoiceUsesGovernanceRecommendationForPendingSkillGrant() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-governance-skill-grant-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Device Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "approval-grant-voice-1",
                    requestId: "approval-grant-voice-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-approval-grant-1",
                    planId: "plan-approval-grant-1",
                    stepId: "step-approval-grant-1",
                    skillId: "guarded-automation",
                    requestedSkillId: "browser.open",
                    toolName: ToolName.deviceBrowserControl.rawValue,
                    tool: .deviceBrowserControl,
                    toolSummary: "打开 https://example.com/login",
                    reason: "需要确认后再执行设备级浏览器操作",
                    createdAt: 1_200,
                    actionURL: nil,
                    routingReasonCode: "preferred_builtin_selected",
                    routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
                    readiness: XTSkillExecutionReadiness(
                        schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                        projectId: project.projectId,
                        skillId: "guarded-automation",
                        packageSHA256: String(repeating: "g", count: 64),
                        publisherID: "xhub.official",
                        policyScope: "hub_governed",
                        intentFamilies: ["browser.observe", "browser.interact"],
                        capabilityFamilies: ["browser.observe", "browser.interact"],
                        capabilityProfiles: ["observe_only", "browser_operator"],
                        discoverabilityState: "discoverable",
                        installabilityState: "installable",
                        pinState: "pinned",
                        resolutionState: "resolved",
                        executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                        runnableNow: false,
                        denyCode: "grant_required",
                        reasonCode: "grant floor privileged requires hub grant",
                        grantFloor: XTSkillGrantFloor.privileged.rawValue,
                        approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                        requiredGrantCapabilities: ["browser.interact"],
                        requiredRuntimeSurfaces: ["managed_browser_runtime"],
                        stateLabel: "awaiting_hub_grant",
                        installHint: "",
                        unblockActions: ["request_hub_grant"],
                        auditRef: "audit-approval-grant-voice-1",
                        doctorAuditRef: "",
                        vetterAuditRef: "",
                        resolvedSnapshotId: "snapshot-approval-grant-voice-1",
                        grantSnapshotRef: "grant-approval-grant-voice-1"
                    )
                )
            ]
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "governance_pending_skill_grant_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("技能授权待处理"))
        #expect(spoken[0].contains("先完成 Hub grant"))
        #expect(spoken[0].contains("查看技能授权"))
    }

    @Test
    func heartbeatVoiceUsesGovernanceRecommendationForLaneHealthWhenNoGrantOrApprovalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-governance-lane-health-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Lane Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            SupervisorLaneHealthSnapshot(
                generatedAtMs: 2_000,
                summary: LaneHealthSummary(
                    total: 1,
                    running: 0,
                    blocked: 1,
                    stalled: 0,
                    failed: 0,
                    waiting: 0,
                    recovering: 0,
                    completed: 0
                ),
                lanes: [
                    laneHealthVoiceState(
                        id: "lane-approval",
                        status: .blocked,
                        heartbeatSeq: 3
                    )
                ]
            )
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "governance_lane_health_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("泳道健康需要关注"))
        #expect(spoken[0].contains("等待授权"))
        #expect(!spoken[0].contains("grant_pending"))
        #expect(spoken[0].contains("查看泳道健康"))
    }

    @Test
    func heartbeatVoiceCallsOutGrantRecoveryFollowUpWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-recovery-grant-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a2RepoAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Grant Recovery Runtime",
            blockerSummary: nil,
            nextStepSummary: "等待授权恢复执行"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .authzDenied,
                nextActionRecommendation: "request_grant_follow_up"
            )
        )

        let emission = await manager.emitHeartbeatForTesting(
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_220)
        )

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("恢复授权"))
        #expect(spoken[0].contains("Grant Recovery Runtime"))
        #expect(spoken[0].contains("grant / 授权跟进"))
        #expect(spoken[0].contains("待授权会直接卡住推进"))
        #expect(spoken[0].contains("打开授权处理"))
    }

    @Test
    func heartbeatVoiceCallsOutReplayRecoveryFollowUpWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-recovery-replay-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a3DeliverAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Replay Recovery Runtime",
            blockerSummary: nil,
            nextStepSummary: "重放 follow-up / 续跑链"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .restartDrain,
                nextActionRecommendation: "wait_drain_recover"
            )
        )

        let emission = await manager.emitHeartbeatForTesting(
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_320)
        )

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("恢复跟进"))
        #expect(spoken[0].contains("Replay Recovery Runtime"))
        #expect(spoken[0].contains("重放 follow-up / 续跑链"))
        #expect(spoken[0].contains("当前执行仍在推进，适合继续跟进"))
        #expect(spoken[0].contains("打开项目查看 resume / replan"))
    }

    @Test
    func heartbeatRecoveryVoiceSkipsProjectionFetcherAndUsesFallback() async throws {
        var spoken: [String] = []
        let capture = ProjectionRequestCapture()
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            await capture.record(projectId: payload.projectId, trigger: payload.trigger)
            return HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "recovery-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "",
                    topline: "This projection should not be used.",
                    nextBestAction: "Ignore me.",
                    pendingGrantCount: 0,
                    ttsScript: [
                        "Supervisor Hub 简报。This projection should not be used."
                    ],
                    cardSummary: "Projection should be skipped.",
                    evidenceRefs: [],
                    generatedAtMs: 1_777_100_000_000,
                    expiresAtMs: 1_777_100_060_000,
                    auditRef: "audit-hub-brief-recovery-skip"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-recovery-projection-skip")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a3DeliverAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Recovery Projection Runtime",
            blockerSummary: nil,
            nextStepSummary: "重放 follow-up / 续跑链"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .restartDrain,
                nextActionRecommendation: "wait_drain_recover"
            )
        )

        let emission = await manager.emitHeartbeatForTesting(
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_320)
        )
        let snapshot = await capture.snapshot()

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Recovery Projection Runtime"))
        #expect(snapshot.projectId == nil)
        #expect(snapshot.trigger == nil)
    }

    @Test
    func heartbeatVoiceCallsOutRouteRepairAttentionWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-route-repair-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "open_model_picker",
            outcome: "opened",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "model_not_found"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(reason: "route_repair_voice_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("模型路由值得先看一下"))
        #expect(spoken[0].contains("Route Runtime"))
        #expect(spoken[0].contains("目标模型未加载"))
        #expect(spoken[0].contains("重连并重诊断"))
        #expect(!spoken[0].contains("model_not_found"))
        #expect(!spoken[0].contains("reconnect_hub_and_diagnose"))
        #expect(!spoken[0].contains("1. 模型路由"))
    }

    @Test
    func heartbeatVoiceCallsOutHubSideHintForRemoteExportBlockedRouteRepair() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-route-repair-voice-export-gate")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "open_hub_recovery",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            createdAt: 100,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(reason: "route_repair_voice_export_gate_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("模型路由值得先看一下"))
        #expect(spoken[0].contains("Route Runtime"))
        #expect(spoken[0].contains("远端导出被拦截"))
        #expect(spoken[0].contains("方向上更像"))
        #expect(spoken[0].contains("先查 Hub"))
    }

    @Test
    func heartbeatVoiceMentionsRecentStatusBarFollowUpForRouteRepair() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-route-repair-voice-status-bar-followup")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "open_hub_recovery",
            outcome: "opened",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            note: "source=status_bar",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(
            reason: "route_repair_status_bar_followup_test",
            now: Date(timeIntervalSince1970: 210)
        )

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("我刚从顶部状态栏打开了 Hub Recovery"))
        #expect(spoken[0].contains("查看 Hub Recovery"))
        #expect(!spoken[0].contains("route diagnose"))
    }

    @Test
    func heartbeatProjectionUsesRouteRepairProjectWhenThatIsTopAttention() async throws {
        var spoken: [String] = []
        let capture = ProjectionRequestCapture()
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            await capture.record(projectId: payload.projectId, trigger: payload.trigger)
            return HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "route-repair-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "",
                    topline: "Route Runtime 的模型路由需要你先看一下。",
                    nextBestAction: "打开 route diagnose。",
                    pendingGrantCount: 0,
                    ttsScript: [
                        "Supervisor Hub 简报。Route Runtime 的模型路由需要你先看一下。",
                        "建议下一步：打开 route diagnose。"
                    ],
                    cardSummary: "Route diagnose attention required.",
                    evidenceRefs: ["route:repair-attention"],
                    generatedAtMs: 1_777_000_400_000,
                    expiresAtMs: 1_777_000_460_000,
                    auditRef: "audit-hub-brief-route-repair"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-route-repair-projection")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "remote_export_blocked"),
            repairReasonCode: "remote_export_blocked",
            createdAt: 100,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(reason: "route_repair_projection_test")
        let captured = await capture.snapshot()

        #expect(emission.path == "projection")
        #expect(emission.outcome == "spoken")
        #expect(captured.projectId == project.projectId)
        #expect(captured.trigger == "critical_path_changed")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Supervisor Hub 简报"))
        #expect(spoken[0].contains("route diagnose"))
        #expect(spoken[0].contains("方向上更像"))
        #expect(spoken[0].contains("Hub export gate"))
        #expect(spoken[0].contains("XT 模型"))
    }

    @Test
    func explicitTextStatusQueryRouteRepairProjectionAppendsHubSideHint() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "route-repair-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "",
                    topline: "Route Runtime 的模型路由需要你先看一下。",
                    nextBestAction: "打开 route diagnose。",
                    pendingGrantCount: 0,
                    ttsScript: [],
                    cardSummary: "Route diagnose attention required.",
                    evidenceRefs: ["route:repair-attention"],
                    generatedAtMs: 1_777_000_420_000,
                    expiresAtMs: 1_777_000_480_000,
                    auditRef: "audit-hub-text-route-repair"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-text-route-repair")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "downgrade_to_local"),
            repairReasonCode: "downgrade_to_local",
            createdAt: 100,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text status route repair hint emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief · \(project.displayName)") &&
                $0.content.contains("更像 Hub 执行阶段把远端降到了本地，不是 XT 自己改模型。") &&
                $0.content.contains("下一步：打开 route diagnose。")
            })
        }
    }

    @Test
    func heartbeatVoiceKeepsStableRouteRepairQuietOnTimerAfterInitialAlert() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-route-repair-timer-cooldown")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date(timeIntervalSince1970: 300)
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let firstEmission = await manager.emitHeartbeatForTesting(force: false, reason: "timer", now: now)
        let secondEmission = await manager.emitHeartbeatForTesting(force: false, reason: "timer", now: now)

        #expect(firstEmission.path == "fallback")
        #expect(firstEmission.outcome == "spoken")
        #expect(secondEmission.path == "fallback")
        #expect(secondEmission.outcome == "suppressed:empty_script")
        #expect(spoken.count == 1)
    }

    @Test
    func heartbeatVoiceTimerRouteRepairCooldownPersistsAcrossManagerRestart() async throws {
        let registryBase = try makeProjectRoot(named: "heartbeat-route-repair-runtime-state")
        let root = try makeProjectRoot(named: "heartbeat-route-repair-runtime-state-project")
        defer {
            unsetenv("XTERMINAL_PROJECT_REGISTRY_BASE_DIR")
            try? FileManager.default.removeItem(at: registryBase)
            try? FileManager.default.removeItem(at: root)
        }
        setenv("XTERMINAL_PROJECT_REGISTRY_BASE_DIR", registryBase.path, 1)

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date(timeIntervalSince1970: 300)
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        var firstSpoken: [String] = []
        let firstManager = SupervisorManager.makeForTesting(
            persistSupervisorRuntimeState: true,
            supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { firstSpoken.append($0) }
            )
        )
        firstManager.setAppModel(appModel)

        let firstEmission = await firstManager.emitHeartbeatForTesting(force: false, reason: "timer", now: now)
        let runtimeStateURL = registryBase
            .appendingPathComponent("supervisor", isDirectory: true)
            .appendingPathComponent("runtime_state.json")

        var secondSpoken: [String] = []
        let restartedManager = SupervisorManager.makeForTesting(
            persistSupervisorRuntimeState: true,
            supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { secondSpoken.append($0) }
            )
        )
        restartedManager.setAppModel(appModel)
        let secondEmission = await restartedManager.emitHeartbeatForTesting(force: false, reason: "timer", now: now)

        #expect(firstEmission.path == "fallback")
        #expect(firstEmission.outcome == "spoken")
        #expect(FileManager.default.fileExists(atPath: runtimeStateURL.path))
        #expect(secondEmission.path == "fallback")
        #expect(secondEmission.outcome == "suppressed:empty_script")
        #expect(firstSpoken.count == 1)
        #expect(secondSpoken.isEmpty)
    }

    @Test
    func routeAttentionReminderStatusTracksQuietStateAndCanBeCleared() async throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-route-repair-reminder-status")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date(timeIntervalSince1970: 300)
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
            createdAt: 200,
            for: ctx
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Route Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(force: false, reason: "timer", now: now)
        let watchItem = try #require(AXRouteRepairLogStore.watchItems(for: [project], limit: 1).first)
        let quietStatus = manager.routeAttentionReminderStatus(for: watchItem, now: now)

        #expect(emission.outcome == "spoken")
        #expect(quietStatus.lastAlertAt == now.timeIntervalSince1970)
        #expect(quietStatus.quietingCurrentIssue)
        #expect(quietStatus.cooldownRemainingSec > 0)

        manager.clearRouteAttentionReminderState(projectId: project.projectId)

        let clearedStatus = manager.routeAttentionReminderStatus(for: watchItem, now: now)
        #expect(clearedStatus.lastAlertAt == nil)
        #expect(!clearedStatus.quietingCurrentIssue)
        #expect(clearedStatus.cooldownRemainingSec == 0)
    }

    @Test
    func explicitVoiceQuerySpeaksReplyEvenWhenAutoReportModeIsBlockersOnly() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)

        manager.sendMessage("/automation", fromVoice: true)

        try await waitUntil("voice reply emitted") {
            !spoken.isEmpty &&
            manager.messages.contains(where: { $0.role == .assistant && $0.content.contains("自动化执行命令") })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("自动化执行命令"))
        #expect(spoken[0].contains("/automation status"))
    }

    @Test
    func explicitTextStatusQueryPrefersHubBriefProjectionWhenFetcherReturnsProjection() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "text-query-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "blocked",
                    criticalBlocker: "等待生产授权",
                    topline: "发布路径被一项生产授权阻塞。",
                    nextBestAction: "处理 release grant。",
                    pendingGrantCount: 1,
                    ttsScript: [
                        "Supervisor Hub 简报。发布路径被一项生产授权阻塞。",
                        "建议下一步：处理 release grant。"
                    ],
                    cardSummary: "One grant is blocking production release.",
                    evidenceRefs: ["grant:req-text"],
                    generatedAtMs: 1_777_000_220_000,
                    expiresAtMs: 1_777_000_280_000,
                    auditRef: "audit-hub-text-query-1"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-text-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text status hub brief reply emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("下一步：处理 release grant。")
            })
        }

        #expect(spoken.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("发布路径被一项生产授权阻塞。") &&
            $0.content.contains("待授权：1")
        }))
    }

    @Test
    func explicitTextStatusQueryHumanizesHubGovernedReviewProjection() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "text-governed-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "",
                    topline: "Project \(payload.projectId) has queued strategic governance review. Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
                    nextBestAction: "Open the project and inspect why the queued governance review was scheduled.",
                    pendingGrantCount: 0,
                    ttsScript: [],
                    cardSummary: "GOVERNANCE REVIEW: queued strategic governance review.",
                    evidenceRefs: ["heartbeat:\(payload.projectId):1"],
                    generatedAtMs: 1_777_000_610_000,
                    expiresAtMs: 1_777_000_670_000,
                    auditRef: "audit-hub-text-governed-review"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-text-governed-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Governance Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text status governed review reply emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("治理审查已排队")
            })
        }

        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("治理审查已排队") &&
            $0.content.contains("无进展复盘 · 长时间无进展") &&
            $0.content.contains("查看：打开项目并查看这次治理审查")
        }))
    }

    @Test
    func explicitVoiceStatusQueryPrefersHubBriefProjectionWhenFetcherReturnsProjection() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "voice-query-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "blocked",
                    criticalBlocker: "等待生产授权",
                    topline: "发布路径被一项生产授权阻塞。",
                    nextBestAction: "处理 release grant。",
                    pendingGrantCount: 1,
                    ttsScript: [
                        "Supervisor Hub 简报。发布路径被一项生产授权阻塞。",
                        "建议下一步：处理 release grant。"
                    ],
                    cardSummary: "One grant is blocking production release.",
                    evidenceRefs: ["grant:req-voice"],
                    generatedAtMs: 1_777_000_200_000,
                    expiresAtMs: 1_777_000_260_000,
                    auditRef: "audit-hub-voice-query-1"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice status hub brief reply emitted") {
            spoken.contains(where: { $0.contains("Supervisor Hub 简报") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("下一步：处理 release grant。")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Supervisor Hub 简报"))
        #expect(spoken[0].contains("处理 release grant"))
        #expect(!spoken[0].contains("等待本地 blocker 文案"))
    }

    @Test
    func explicitVoiceStatusQueryHumanizesHubRescueReviewProjection() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "voice-rescue-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "Queued rescue governance review requires prompt supervisor attention.",
                    topline: "Project \(payload.projectId) has queued rescue governance review. Supervisor heartbeat queued it via event-driven review trigger because of weak completion evidence.",
                    nextBestAction: "Open the project and prioritize the queued rescue review before autonomous execution continues.",
                    pendingGrantCount: 0,
                    ttsScript: [
                        "Project \(payload.projectId) has queued rescue governance review.",
                        "Supervisor heartbeat queued it via event-driven review trigger because of weak completion evidence.",
                        "Next best action: Open the project and prioritize the queued rescue review before autonomous execution continues."
                    ],
                    cardSummary: "GOVERNANCE REVIEW: queued rescue governance review.",
                    evidenceRefs: ["heartbeat:\(payload.projectId):2"],
                    generatedAtMs: 1_777_000_720_000,
                    expiresAtMs: 1_777_000_780_000,
                    auditRef: "audit-hub-voice-rescue-review"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-voice-rescue-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Rescue Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice status rescue review reply emitted") {
            spoken.contains(where: { $0.contains("救援审查已排队") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("救援审查已排队")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("救援审查已排队"))
        #expect(spoken[0].contains("完成声明证据偏弱"))
        #expect(spoken[0].contains("优先处理这次救援审查"))
        #expect(!spoken[0].contains("rescue governance review"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("救援审查已排队") &&
            $0.content.contains("事件触发 · 完成声明证据偏弱") &&
            $0.content.contains("查看：打开项目并优先处理这次救援审查")
        }))
    }

    @Test
    func explicitVoiceStatusQuerySurfacesHubBriefUnavailableInsteadOfLocalBrief() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { _ in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: false,
                source: "test",
                projection: nil,
                reasonCode: "projection_unavailable"
            )
        }

        let root = try makeProjectRoot(named: "status-query-local-governance-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "voice-query-grant-1",
                    dedupeKey: "voice-query-grant-1",
                    grantRequestId: "voice-query-grant-1",
                    requestId: "req-voice-query-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice status hub brief unavailable emitted") {
            spoken.contains(where: { $0.contains("Hub 简报当前不可用") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("⚠️ Hub Brief 暂不可用") &&
                $0.content.contains("Hub 没有返回这次统一简报") &&
                $0.content.contains("XT 本地信号：Hub 待处理授权") &&
                $0.content.contains("你现在可以先：查看授权板。")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 简报当前不可用"))
        #expect(spoken[0].contains("查看授权板"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。") &&
            !$0.content.contains("🧭 Supervisor Brief") &&
            !$0.content.contains("打开授权并批准设备级权限")
        }))
    }

    @Test
    func explicitVoiceStatusQuerySurfacesHubBriefUnavailableForLaneHealth() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { _ in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: false,
                source: "test",
                projection: nil,
                reasonCode: "projection_unavailable"
            )
        }

        let root = try makeProjectRoot(named: "status-query-local-lane-health-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Lane Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            SupervisorLaneHealthSnapshot(
                generatedAtMs: 2_000,
                summary: LaneHealthSummary(
                    total: 1,
                    running: 0,
                    blocked: 1,
                    stalled: 0,
                    failed: 0,
                    waiting: 0,
                    recovering: 0,
                    completed: 0
                ),
                lanes: [
                    laneHealthVoiceState(
                        id: "lane-voice-query",
                        status: .blocked,
                        heartbeatSeq: 4
                    )
                ]
            )
        )

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice status lane health hub brief unavailable emitted") {
            spoken.contains(where: { $0.contains("Hub 简报当前不可用") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("⚠️ Hub Brief 暂不可用") &&
                $0.content.contains("XT 本地信号：泳道健康需要关注") &&
                $0.content.contains("你现在可以先：查看泳道健康。")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 简报当前不可用"))
        #expect(spoken[0].contains("查看泳道健康"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            !$0.content.contains("🧭 Supervisor Brief") &&
            !$0.content.contains("grant_pending")
        }))
    }

    @Test
    func explicitTextStatusQuerySurfacesHubBriefUnavailableInsteadOfLocalBrief() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { _ in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: false,
                source: "test",
                projection: nil,
                reasonCode: "projection_unavailable"
            )
        }

        let root = try makeProjectRoot(named: "status-query-text-local-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "text-query-grant-1",
                    dedupeKey: "text-query-grant-1",
                    grantRequestId: "text-query-grant-1",
                    requestId: "req-text-query-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text status hub brief unavailable emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("⚠️ Hub Brief 暂不可用") &&
                $0.content.contains("Hub 没有返回这次统一简报") &&
                $0.content.contains("XT 本地信号：Hub 待处理授权") &&
                $0.content.contains("你现在可以先：查看授权板。")
            })
        }

        #expect(spoken.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            !$0.content.contains("🧭 Supervisor Brief") &&
            !$0.content.contains("打开授权并批准设备级权限")
        }))
    }

    @Test
    func explicitTextStatusQueryWithoutFocusedProjectRequiresProjectBinding() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )

        let rootA = try makeProjectRoot(named: "status-query-global-governance-a")
        let rootB = try makeProjectRoot(named: "status-query-global-governance-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(
            root: rootA,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let projectB = makeProjectEntry(
            root: rootB,
            displayName: "Design Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = nil
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "global-text-query-grant-1",
                    dedupeKey: "global-text-query-grant-1",
                    grantRequestId: "global-text-query-grant-1",
                    requestId: "req-global-text-query-grant-1",
                    projectId: projectA.projectId,
                    projectName: projectA.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text binding-required reply emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("⚠️ Hub Brief 需要项目绑定") &&
                $0.content.contains("Hub 统一投影现在按项目生成") &&
                $0.content.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。")
            })
        }

        #expect(spoken.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            !$0.content.contains("🧭 Supervisor Brief · 当前工作台") &&
            !$0.content.contains("Hub 待处理授权")
        }))
    }

    @Test
    func explicitVoiceStatusQueryWithoutFocusedProjectRequiresProjectBinding() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )

        let rootA = try makeProjectRoot(named: "status-query-global-voice-governance-a")
        let rootB = try makeProjectRoot(named: "status-query-global-voice-governance-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(
            root: rootA,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let projectB = makeProjectEntry(
            root: rootB,
            displayName: "Design Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = nil
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "global-voice-query-grant-1",
                    dedupeKey: "global-voice-query-grant-1",
                    grantRequestId: "global-voice-query-grant-1",
                    requestId: "req-global-voice-query-grant-1",
                    projectId: projectA.projectId,
                    projectName: projectA.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice binding-required reply emitted") {
            spoken.contains(where: { $0.contains("要给你正式的 Hub 简报") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("⚠️ Hub Brief 需要项目绑定") &&
                $0.content.contains("Hub 统一投影现在按项目生成") &&
                $0.content.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("要给你正式的 Hub 简报"))
        #expect(spoken[0].contains("先绑定项目"))
    }

    @Test
    func explicitTextStatusQueryUsesFocusPointerProjectWhenGlobalHomeIsSelected() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "focus-pointer-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "active",
                    criticalBlocker: "",
                    topline: "已按会话焦点自动绑定到当前项目。",
                    nextBestAction: "继续输出项目总结。",
                    pendingGrantCount: 0,
                    ttsScript: [],
                    cardSummary: "Focus pointer project bound.",
                    evidenceRefs: [],
                    generatedAtMs: 1_777_000_230_000,
                    expiresAtMs: 1_777_000_290_000,
                    auditRef: "audit-hub-focus-pointer-text-query"
                ),
                reasonCode: nil
            )
        }

        let rootA = try makeProjectRoot(named: "status-query-focus-pointer-a")
        let rootB = try makeProjectRoot(named: "status-query-focus-pointer-b")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }

        let projectA = makeProjectEntry(
            root: rootA,
            displayName: "Release Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let projectB = makeProjectEntry(
            root: rootB,
            displayName: "Design Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [projectA, projectB])
        appModel.selectedProjectId = AXProjectRegistry.globalHomeId
        manager.setAppModel(appModel)

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        manager.setSupervisorFocusPointerStateForTesting(
            SupervisorFocusPointerState(
                schemaVersion: SupervisorFocusPointerState.currentSchemaVersion,
                updatedAtMs: nowMs,
                currentProjectId: projectA.projectId,
                currentProjectAliases: [projectA.displayName, projectA.projectId],
                currentProjectUpdatedAtMs: nowMs,
                currentPersonName: nil,
                currentPersonUpdatedAtMs: nil,
                currentCommitmentId: nil,
                currentCommitmentUpdatedAtMs: nil,
                currentTopicDigest: "project_first: 现在状态怎么样？",
                lastTurnMode: .projectFirst,
                lastSeenDeltaCursor: "memory_build:\(nowMs)"
            )
        )

        manager.sendMessage("现在状态怎么样")

        try await waitUntil("text status uses focus pointer binding") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief · \(projectA.displayName)") &&
                $0.content.contains("下一步：继续输出项目总结。")
            })
        }

        #expect(!manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("⚠️ Hub Brief 需要项目绑定")
        }))
    }

    @Test
    func explicitVoiceStatusQueryBriefFlagsMemoryUnderfedWhenProjectionIsUsed() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "voice-query-underfed-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "blocked",
                    criticalBlocker: "等待生产授权",
                    topline: "发布路径被一项生产授权阻塞。",
                    nextBestAction: "处理 release grant。",
                    pendingGrantCount: 1,
                    ttsScript: [
                        "Supervisor Hub 简报。发布路径被一项生产授权阻塞。",
                        "建议下一步：处理 release grant。"
                    ],
                    cardSummary: "One grant is blocking production release.",
                    evidenceRefs: ["grant:req-voice-underfed"],
                    generatedAtMs: 1_777_000_210_000,
                    expiresAtMs: 1_777_000_270_000,
                    auditRef: "audit-hub-voice-query-underfed"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "status-query-brief-underfed")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .blockersOnly
        )
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                truncatedLayers: ["l1_canonical"]
            )
        )

        manager.sendMessage("现在状态怎么样", fromVoice: true)

        try await waitUntil("voice status hub brief underfed reply emitted") {
            spoken.contains(where: { $0.contains("当前项目背景记忆还没喂够") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("当前项目背景记忆还没喂够") &&
                $0.content.contains("如果要纠偏，请先补长期目标和完成标准")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("当前项目背景记忆还没喂够"))
        #expect(spoken[0].contains("Supervisor Hub 简报"))
        #expect(spoken[0].contains("处理 release grant"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("当前项目背景记忆还没喂够") &&
            $0.content.contains("如果要纠偏，请先补长期目标和完成标准")
        }))
    }

    @Test
    func heartbeatNotificationPresentationFlagsMemoryUnderfedState() {
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                projectID: "project-underfed",
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                truncatedLayers: ["l1_canonical"]
            )
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Release Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "继续收口 release 验证",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("战略记忆供给不足"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("战略纠偏状态："))
        #expect(presentation.body.contains("当前项目背景记忆还没喂够"))
        #expect(presentation.body.contains("如果要纠偏，请先补长期目标和完成标准"))
    }

    @Test
    func heartbeatNotificationPresentationStaysStableWithoutMemoryRisk() {
        let manager = SupervisorManager.makeForTesting()

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Release Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "继续收口 release 验证",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title == "Supervisor 心跳：状态稳定（静默）")
        #expect(!presentation.unread)
        #expect(!presentation.body.contains("战略纠偏状态："))
        #expect(!presentation.body.contains("当前项目背景记忆还没喂够"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsPendingProjectCreationTrigger() throws {
        let manager = SupervisorManager.makeForTesting()

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 0,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("项目创建差一句触发"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：项目创建还差一句触发"))
        #expect(presentation.body.contains("为什么重要：当前不会误把“已理解需求”当成“已真正创建项目”"))
        #expect(presentation.body.contains("系统下一步：直接说立项，或说创建一个project"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("项目创建："))
        #expect(presentation.body.contains("贪食蛇游戏"))
        #expect(!presentation.body.contains("诊断码："))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsRecoveredProjectCreationProposal() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.messages.append(
            SupervisorMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: """
现在真正的卡点不是想法，而是**系统里还没有这个项目**。
你前面要做的是**俄罗斯方块**，我这边默认理解为：
- 项目名：**俄罗斯方块**
- 形态：**完整版单机 Web 版**
- 下一步：**先建项目，再补 job + initial plan**

如果你现在是要我继续推进，你下一句只要回：
**就按这个建**
我就接着往下走。
""",
                isVoice: false,
                timestamp: Date().timeIntervalSince1970
            )
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 0,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("项目创建待确认"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：项目创建待确认"))
        #expect(presentation.body.contains("系统下一步：直接说立项，或说就按这个建"))
        #expect(presentation.body.contains("俄罗斯方块"))
        #expect(presentation.body.contains("完整版单机 Web 版"))
        #expect(!presentation.body.contains("诊断码："))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsProjectCreationGoalGap() throws {
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.directSupervisorActionIfApplicableForTesting("创建一个project")
        )
        #expect(rendered.contains("还没给项目名"))

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 0,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("项目创建缺目标"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：项目创建还缺项目名或明确交付目标"))
        #expect(presentation.body.contains("为什么重要：当前不会把一句泛化的“建项目/立项”误判成真正可推进的项目创建"))
        #expect(presentation.body.contains("系统下一步：直接给项目名，或先补一句要做什么"))
        #expect(!presentation.body.contains("诊断码："))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsCreatedProjectAwaitingGoal() async throws {
        let manager = SupervisorManager.makeForTesting()
        let workspace = try makeProjectRoot(named: "heartbeat-created-project-awaiting-goal")
        defer { try? FileManager.default.removeItem(at: workspace) }

        let appModel = AppModel()
        appModel.registry = .empty()
        manager.setAppModel(appModel)
        manager.installCreateProjectURLOverrideForTesting { projectName in
            let url = workspace.appendingPathComponent(projectName, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        _ = try #require(
            manager.directSupervisorActionIfApplicableForTesting("新建项目，名字叫 坦克大战")
        )
        await manager.waitForPendingExecutionIntakeBootstrapForTesting()

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("项目已创建待补目标"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：项目已创建，待补交付目标"))
        #expect(presentation.body.contains("为什么重要：项目已经先建好"))
        #expect(presentation.body.contains("系统下一步：直接说“我要用默认的MVP”，或说“第一版先做成最小可运行版本”"))
        #expect(presentation.body.contains("坦克大战"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsDirectRouteDiagnoseAction() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route-diagnose",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Route Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 模型路由：Route Runtime 最近已连续 2 次切到本地。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("模型路由异常"))
        #expect(presentation.title.contains("点我直接诊断"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("点开这条提醒会直接进入项目聊天"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("模型路由：Route Runtime 最近已连续 2 次切到本地。"))
        #expect(presentation.body.contains("/route diagnose"))
        let highlightRange = try #require(presentation.body.range(of: "优先建议："))
        let nextStepRange = try #require(presentation.body.range(of: "Coder 下一步建议："))
        #expect(highlightRange.lowerBound < nextStepRange.lowerBound)
    }

    @Test
    func heartbeatNotificationPresentationHighlightsRouteRepairModelSettingsFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.supervisorModelSettingsURL(
                title: "Route diagnose",
                detail: "Check real available models"
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Route Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 模型路由：Route Runtime 最近最常见是 目标模型未加载（model_not_found）（2 次）；刚刚已从顶部状态栏打开 AI 模型。建议先查看 AI 模型。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("模型路由异常"))
        #expect(presentation.title.contains("AI 模型"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("Supervisor Control Center · AI 模型"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("刚刚已从顶部状态栏打开 AI 模型"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsRouteRepairHubRecoveryFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "troubleshoot",
                title: "Route repair",
                detail: "Check Hub Recovery"
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Route Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 模型路由：Route Runtime 最近最常见是 远端导出被拦截（remote_export_blocked）（2 次）；更像 Hub export gate / 策略挡住远端；刚刚已从顶部状态栏打开 Hub Recovery。建议先查看 Hub Recovery。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("模型路由异常"))
        #expect(presentation.title.contains("Hub Recovery"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("点开这条提醒会直接进入 Hub Recovery"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("远端导出被拦截"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsGovernanceRepairAction() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governance-repair",
                pane: .chat,
                governanceDestination: .executionTier
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Governance Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            governanceRepairSummary: "• Governance Runtime：A-Tier 需要调整；Open Project Settings -> A-Tier and raise it to A2 Repo Auto or above before starting, inspecting, or stopping managed processes.",
            progressSummary: "",
            nextStepSummary: "1. 治理修复：Governance Runtime — A-Tier 需要调整；建议先打开 Project Governance -> A-Tier。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            governanceRepairCount: 1,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("治理修复"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("待治理修复项目数：1"))
        #expect(presentation.body.contains("项目治理设置"))
        #expect(presentation.body.contains("A-Tier"))
        let highlightRange = try #require(presentation.body.range(of: "优先建议："))
        let nextStepRange = try #require(presentation.body.range(of: "Coder 下一步建议："))
        #expect(highlightRange.lowerBound < nextStepRange.lowerBound)
    }

    @Test
    func heartbeatNotificationPresentationHighlightsQueuedGovernedReview() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governed-review",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Review Runtime：✅ 继续当前任务",
            queueSummary: "",
            permissionSummary: "",
            governedReviewSummary: "• Review Runtime：已排队战略审查（无进展复盘 · 长时间无进展）",
            governedReviewDetail: "• 依据：当前项目治理要求在长时间无进展时进入 brainstorm review，heartbeat 已自动排队。",
            governedReviewLevel: .r2Strategic,
            progressSummary: "",
            nextStepSummary: "1. Review Runtime：等待 Supervisor 执行已排队的 review，并在 safe point 接收 guidance。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("治理审查已排队"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("待治理审查项目数：1"))
        #expect(presentation.body.contains("治理审查："))
        #expect(presentation.body.contains("长时间无进展"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("safe point guidance"))
    }

    @Test
    func heartbeatNotificationPresentationHumanizesEnglishGovernedReviewDigest() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governed-review-en",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Review Runtime：✅ 继续当前任务",
            queueSummary: "",
            permissionSummary: "",
            governedReviewSummary: "• Project Review Runtime has queued strategic governance review. Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
            governedReviewDetail: "• Current project governance requires a brainstorm review after long no progress; heartbeat automatically queued it.",
            governedReviewLevel: .r2Strategic,
            progressSummary: "",
            nextStepSummary: "1. Open the project and inspect why the queued governance review was scheduled.",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("治理审查已排队"))
        #expect(presentation.body.contains("治理审查："))
        #expect(presentation.body.contains("已排队战略审查"))
        #expect(presentation.body.contains("无进展复盘"))
        #expect(presentation.body.contains("长时间无进展"))
        #expect(presentation.body.contains("打开项目并查看这次治理审查为何被排队。"))
        #expect(!presentation.body.contains("queued strategic governance review"))
        #expect(!presentation.body.contains("Open the project and inspect why the queued governance review was scheduled."))
    }

    @Test
    func heartbeatNotificationPresentationIncludesProjectMemoryStatusForGovernedReview() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-governed-review-memory",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Review Runtime：✅ 继续当前任务",
            queueSummary: "",
            permissionSummary: "",
            governedReviewSummary: "• Review Runtime：已排队战略审查（无进展复盘 · 长时间无进展）",
            governedReviewDetail: "• 依据：当前项目治理要求在长时间无进展时进入 brainstorm review，heartbeat 已自动排队。",
            governedReviewLevel: .r2Strategic,
            progressSummary: "",
            nextStepSummary: "1. Review Runtime：等待 Supervisor 执行已排队的 review，并在 safe point 接收 guidance。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL,
            governedReviewProjectMemoryStatusLine: "• 记忆供给：Project AI 最近一轮 memory truth 来自 latest coder usage，effective depth=deep；heartbeat digest 已在 Project AI working set 中。",
            governedReviewProjectMemoryMetadataText: "latest coder usage · depth=deep · digest已进project"
        )

        #expect(presentation.title.contains("治理审查已排队"))
        #expect(presentation.body.contains("治理审查："))
        #expect(presentation.body.contains("记忆供给：Project AI 最近一轮 memory truth 来自 latest coder usage"))
        #expect(presentation.body.contains("heartbeat digest 已在 Project AI working set 中"))
        #expect(presentation.body.contains("为什么重要：这次治理判断已对齐到 Project AI 最近一轮 latest coder usage memory truth"))
        #expect(presentation.body.contains("系统下一步：打开项目并查看这次治理审查为何被排队。"))
        #expect(presentation.body.contains("不再额外重复灌入同一份 heartbeat digest"))
    }

    @Test
    func heartbeatNotificationPresentationSanitizesAuthorizationDigestAndExplainsOpenTarget() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-auth-digest",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            reason: "project_updated",
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Auth Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: """
grant_pending
lane=lane-auth status=blocked reason=grant_pending
需要你批准 repo 写权限后，系统才会继续推进。（打开：xterminal://project?project_id=project-auth-digest)
event_loop_tick=42 dedupe_key=heartbeat:grant_pending
""",
            progressSummary: "",
            nextStepSummary: """
grant_pending
lane=lane-auth status=blocked reason=grant_pending
1. 先批准 repo 写权限，再继续执行。
event_loop_tick=42 dedupe_key=heartbeat:grant_pending
""",
            queuePendingCount: 0,
            permissionPendingCount: 1,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("权限申请待处理"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("原因：项目更新"))
        #expect(presentation.body.contains("发生了什么：需要你批准 repo 写权限后，系统才会继续推进。"))
        #expect(presentation.body.contains("为什么重要：当前推进被授权或审批挡住"))
        #expect(presentation.body.contains("系统下一步：先批准 repo 写权限，再继续执行。"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("点开这条提醒会直接进入项目授权处理"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("需要你批准 repo 写权限后，系统才会继续推进。"))
        #expect(presentation.body.contains("先批准 repo 写权限，再继续执行。"))
        #expect(!presentation.body.contains("grant_pending"))
        #expect(!presentation.body.contains("lane="))
        #expect(!presentation.body.contains("event_loop_tick"))
        #expect(!presentation.body.contains("dedupe_key"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsGrantRecoveryFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-grant",
                pane: .chat,
                focusTarget: .grant
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            reason: "timer",
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Grant Recovery Runtime：⏸️ 等待授权恢复",
            queueSummary: "",
            permissionSummary: "需要你批准 repo 写权限后，系统才会继续推进。",
            recoveryAction: .requestGrantFollowUp,
            recoveryProjectId: "project-recovery-grant",
            recoveryProjectName: "Grant Recovery Runtime",
            recoverySummary: "Grant Recovery Runtime 需要 grant / 授权跟进",
            recoveryDetail: "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。",
            recoveryPriorityReason: "为什么先跟进：待授权会直接卡住推进（优先级：紧急 · score=8）",
            progressSummary: "",
            nextStepSummary: "1. Recovery 跟进：Grant Recovery Runtime — 建议先批准 repo 写权限，再继续恢复执行。",
            queuePendingCount: 0,
            permissionPendingCount: 1,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("授权恢复跟进"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：Grant Recovery Runtime 需要 grant / 授权跟进"))
        #expect(presentation.body.contains("为什么重要：系统已判断当前需要先补齐 grant / 授权跟进"))
        #expect(presentation.body.contains("系统下一步：系统会先发起所需 grant 跟进"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("点开这条提醒会直接进入项目授权处理"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("批准 repo 写权限"))
        #expect(presentation.body.contains("Recovery 跟进："))
        #expect(presentation.body.contains("Grant Recovery Runtime 需要 grant / 授权跟进"))
        #expect(presentation.body.contains("为什么先跟进：待授权会直接卡住推进"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsReplayRecoveryFollowUp() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-recovery-replay",
                pane: .chat,
                resumeRequested: true
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            reason: "timer",
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Replay Recovery Runtime：⏸️ drain 收口后继续续跑",
            queueSummary: "",
            permissionSummary: "",
            recoveryAction: .replayFollowUp,
            recoveryProjectId: "project-recovery-replay",
            recoveryProjectName: "Replay Recovery Runtime",
            recoverySummary: "Replay Recovery Runtime 需要重放 follow-up / 续跑链",
            recoveryDetail: "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。",
            recoveryPriorityReason: "为什么先跟进：存在明确 blocker，需要优先解阻（优先级：高 · score=6）",
            progressSummary: "",
            nextStepSummary: "1. Recovery 跟进：Replay Recovery Runtime — 建议先打开项目查看 resume / replan。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("续跑恢复跟进"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：Replay Recovery Runtime 需要重放 follow-up / 续跑链"))
        #expect(presentation.body.contains("为什么重要：系统已判断当前要先修复挂起的 follow-up / 续跑链"))
        #expect(presentation.body.contains("系统下一步：系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("点开这条提醒会直接进入项目聊天"))
        #expect(presentation.body.contains("resume / replan"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("follow-up 续跑链"))
        #expect(presentation.body.contains("Recovery 跟进："))
        #expect(presentation.body.contains("Replay Recovery Runtime 需要重放 follow-up / 续跑链"))
        #expect(presentation.body.contains("为什么先跟进：存在明确 blocker，需要优先解阻"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsBlockedSkillDoctorTruth() {
        let manager = SupervisorManager.makeForTesting()

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Delivery Runtime：✅ 继续当前任务",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            doctorPresentation: heartbeatDoctorTruthPresentation(
                statusLine: "技能 doctor truth：1 个技能当前不可运行。",
                tone: .danger,
                detailLine: "当前可直接运行：2 个；当前阻塞：1 个（delivery-runner）；技能计数：3 个。"
            )
        )

        #expect(presentation.title.contains("技能能力阻塞"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：技能 doctor truth：1 个技能当前不可运行。"))
        #expect(presentation.body.contains("为什么重要：这说明 typed capability / readiness 与真实可运行事实还没对齐"))
        #expect(presentation.body.contains("系统下一步：打开 Supervisor 体检，优先处理技能 doctor truth 里的阻塞项"))
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("进入 Supervisor 体检"))
        #expect(presentation.body.contains("优先建议："))
        #expect(presentation.body.contains("技能 Doctor Truth："))
        #expect(presentation.body.contains("当前阻塞：1 个"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsPendingSkillDoctorTruth() {
        let manager = SupervisorManager.makeForTesting()

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Browser Runtime：✅ 继续当前任务",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            doctorPresentation: heartbeatDoctorTruthPresentation(
                statusLine: "技能 doctor truth：1 个待 Hub grant，1 个待本地确认。",
                tone: .warning,
                detailLine: "当前可直接运行：4 个；待 Hub grant：1 个；待本地确认：1 个；技能计数：6 个。"
            )
        )

        #expect(presentation.title.contains("技能授权待补齐"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("发生了什么：技能 doctor truth：1 个待 Hub grant，1 个待本地确认。"))
        #expect(presentation.body.contains("为什么重要：这说明部分技能虽然已被纳入治理"))
        #expect(presentation.body.contains("系统下一步：打开 Supervisor 体检，优先补齐技能 doctor truth 里的 Hub grant / 本地确认项"))
        #expect(presentation.body.contains("技能 Doctor Truth："))
        #expect(presentation.body.contains("待 Hub grant：1 个"))
        #expect(presentation.body.contains("待本地确认：1 个"))
    }

    @Test
    func heartbeatFocusActionURLPrefersSupervisorWhenSkillDoctorTruthNeedsAttention() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-doctor-truth-focus")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Doctor Truth Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)

        let actionURL = try #require(
            manager.heartbeatFocusActionURLForTesting(
                reason: "manual_test",
                doctorPresentation: heartbeatDoctorTruthPresentation(
                    statusLine: "技能 doctor truth：1 个技能当前不可运行。",
                    tone: .danger,
                    detailLine: "当前可直接运行：2 个；当前阻塞：1 个（delivery-runner）；技能计数：3 个。"
                )
            )
        )
        let url = try #require(URL(string: actionURL))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil
                )
            )
        )
    }

    @Test
    func heartbeatConciseNextStepExtractsActionOrientedFollowUps() {
        let manager = SupervisorManager.makeForTesting()

        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 模型路由：Route Runtime 最近最常见是 目标模型未加载（model_not_found）（2 次）；刚刚已从顶部状态栏打开 AI 模型。建议先查看 AI 模型。"
            ) == "查看 AI 模型"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 模型路由：Route Runtime 最近最常见是 远端导出被拦截（remote_export_blocked）（2 次）；更像 Hub export gate / 策略挡住远端；刚刚已从顶部状态栏打开 Hub Recovery。建议先查看 Hub Recovery。"
            ) == "查看 Hub Recovery"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. Hub 负载：Hub 主机负载偏高 · CPU 92% · load 7.20 / 6.30 / 5.90 · 内存 high · 热状态 serious；建议先查看 Hub 诊断（打开：xterminal://hub-setup/troubleshoot）"
            ) == "查看 Hub 诊断"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 治理修复：Governance Runtime — A-Tier 需要调整；建议先打开 Project Governance -> A-Tier。"
            ) == "打开 Project Governance -> A-Tier"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. Recovery 跟进：Replay Recovery Runtime — 建议先打开项目查看 resume / replan。"
            ) == "打开项目查看 resume / replan"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 泳道健康：Lane Runtime 当前等待授权；建议先查看泳道健康。"
            ) == "查看泳道健康"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 关注排队：Queue Runtime — 已排队 4 分钟，建议先清队列"
            ) == "清队列"
        )
        #expect(
            manager.conciseHeartbeatNextStepForTesting(
                "1. 模型路由：Route Runtime 最近最常见是 grpc_route_unavailable；建议先看 /route diagnose。"
            ) == "看 route diagnose"
        )
    }

    @Test
    func heartbeatNotificationPresentationKeepsStableRouteDiagnoseQuietWhenAlertNotNeeded() throws {
        let manager = SupervisorManager.makeForTesting()
        let focusActionURL = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-route-diagnose",
                pane: .chat,
                focusTarget: .routeDiagnose
            )?.absoluteString
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Route Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 模型路由：Route Runtime 最近最常见是 grpc_route_unavailable。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            focusActionURL: focusActionURL,
            routeDiagnoseShouldAlert: false
        )

        #expect(presentation.title.contains("仍需关注"))
        #expect(!presentation.unread)
        #expect(presentation.body.contains("操作提示："))
        #expect(presentation.body.contains("优先建议："))
    }

    @Test
    func heartbeatNextStepSummarySurfacesVoiceReadinessRepairBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-voice-readiness-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Voice Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .permissionDenied,
                overallSummary: "首个任务已可启动，但唤醒配置就绪仍需修复：唤醒配置被语音识别权限阻塞",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .wakeProfileReadiness,
                        state: .permissionDenied,
                        reasonCode: "speech_authorization_denied",
                        headline: "唤醒配置被语音识别权限阻塞",
                        summary: "在 macOS 系统设置里恢复语音识别权限之前，唤醒词仍然不可用。",
                        nextStep: "请先在 macOS 系统设置中授予语音识别权限，然后刷新语音运行时。",
                        repairEntry: .systemPermissions
                    ),
                    makeVoiceReadinessCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            )
        )

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(maxItems: 4)
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("语音修复"))
        #expect(firstLine.contains("首个任务已可启动，但唤醒配置就绪仍需修复"))
        #expect(nextStepSummary.contains("常规推进：Voice Runtime"))
    }

    @Test
    func heartbeatNextStepSummarySurfacesPairingContinuityBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-pairing-readiness-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Pairing Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        manager.setAppModel(appModel)
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .inProgress,
                overallSummary: "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .pairingValidity,
                        state: .inProgress,
                        reasonCode: "local_pairing_ready_remote_unverified",
                        headline: "同网首配已完成，正在验证正式异网入口",
                        summary: "同网首配已经完成，系统正在核对正式异网入口（host=hub.tailnet.example）是否可用。",
                        nextStep: "请先在 Hub 配对页核对正式异网入口，并完成一次切网续连验证。",
                        repairEntry: .hubPairing
                    ),
                    makeVoiceReadinessCheck(
                        kind: .talkLoopReadiness,
                        state: .ready,
                        reasonCode: "talk_loop_ready",
                        headline: "Talk loop foundation is ready",
                        summary: "The live voice route is healthy enough.",
                        nextStep: "Use wake or push-to-talk to start a new Supervisor voice turn."
                    )
                ]
            )
        )

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(maxItems: 4)
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("配对续连"))
        #expect(firstLine.contains("正在验证正式异网入口"))
        #expect(!firstLine.contains("语音修复"))
        #expect(nextStepSummary.contains("常规推进：Pairing Runtime"))
    }

    @Test
    func heartbeatNextStepSummarySurfacesReplayRecoveryFollowUpBeforeGenericProgress() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "heartbeat-recovery-replay-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try configureHeartbeatRecoveryGovernance(
            ctx: ctx,
            executionTier: .a3DeliverAuto,
            supervisorTier: .s3StrategicCoach
        )

        let project = makeProjectEntry(
            root: root,
            displayName: "Replay Recovery Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .restartDrain,
                nextActionRecommendation: "wait_drain_recover"
            )
        )

        let nextStepSummary = manager.buildHeartbeatNextStepSummaryForTesting(
            now: Date(timeIntervalSince1970: 1_773_384_320),
            reason: "timer",
            maxItems: 4
        )
        let firstLine = try #require(nextStepSummary.split(separator: "\n").first.map(String.init))

        #expect(firstLine.contains("Recovery 跟进：Replay Recovery Runtime"))
        #expect(firstLine.contains("drain 收口后"))
        #expect(firstLine.contains("为什么先跟进"))
        #expect(firstLine.contains("建议先打开项目查看 resume / replan"))
        #expect(!nextStepSummary.contains("常规推进：Replay Recovery Runtime"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsVoiceReadinessRepair() {
        let manager = SupervisorManager.makeForTesting()
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .diagnosticRequired,
                overallSummary: "fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .bridgeToolReadiness,
                        state: .diagnosticRequired,
                        reasonCode: "bridge_heartbeat_missing",
                        headline: "Model route ok, but bridge / tool route is unavailable",
                        summary: "Hub is reachable, but the bridge heartbeat is missing.",
                        nextStep: "Open Hub Diagnostics & Recovery, relaunch the bridge if needed, then rerun Verify.",
                        repairEntry: .hubDiagnostics
                    )
                ]
            )
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: false,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Voice Runtime：✅ 正常运行",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 语音 fail-closed：fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("语音链路待修复"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("语音就绪："))
        #expect(presentation.body.contains("fail-closed on bridge / tool readiness"))
        #expect(presentation.body.contains("点开这条提醒会直接进入 Hub Recovery"))
        #expect(presentation.body.contains("Open Hub Diagnostics & Recovery"))
    }

    @Test
    func heartbeatNotificationPresentationHighlightsPairingContinuityRepair() {
        let manager = SupervisorManager.makeForTesting()
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .inProgress,
                overallSummary: "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .pairingValidity,
                        state: .inProgress,
                        reasonCode: "local_pairing_ready_remote_unverified",
                        headline: "同网首配已完成，正在验证正式异网入口",
                        summary: "正式异网入口还在验证中，切网后续连能力暂未最终确认。",
                        nextStep: "请先在 Hub 配对页核对正式异网入口，并完成一次切网续连验证。",
                        repairEntry: .hubPairing
                    )
                ]
            )
        )

        let presentation = manager.buildHeartbeatNotificationPresentationForTesting(
            projectCount: 1,
            changed: true,
            blockerCount: 0,
            blockerStreak: 0,
            blockerEscalated: false,
            topSummary: "• Hub Pairing：🔗 首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
            queueSummary: "",
            permissionSummary: "",
            progressSummary: "",
            nextStepSummary: "1. 配对续连：首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口；建议先查看 Hub 配对",
            queuePendingCount: 0,
            permissionPendingCount: 0
        )

        #expect(presentation.title.contains("配对续连仍需确认"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("配对续连："))
        #expect(!presentation.body.contains("语音就绪："))
        #expect(presentation.body.contains("切网或换环境后可能断开"))
        #expect(presentation.body.contains("点开这条提醒会直接进入 Hub 配对"))
        #expect(presentation.body.contains("正式异网入口"))
    }

    @Test
    func heartbeatVoiceCallsOutVoiceReadinessRepairWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-voice-readiness-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Voice Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .diagnosticRequired,
                overallSummary: "fail-closed on bridge / tool readiness: Model route ok, but bridge / tool route is unavailable",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .bridgeToolReadiness,
                        state: .diagnosticRequired,
                        reasonCode: "bridge_heartbeat_missing",
                        headline: "Model route ok, but bridge / tool route is unavailable",
                        summary: "Hub is reachable, but the bridge heartbeat is missing.",
                        nextStep: "Open Hub Diagnostics & Recovery, relaunch the bridge if needed, then rerun Verify.",
                        repairEntry: .hubDiagnostics
                    )
                ]
            )
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "voice_readiness_voice_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Supervisor 语音链路现在还是失败闭锁"))
        #expect(spoken[0].contains("Model route ok"))
        #expect(spoken[0].contains("bridge / tool route"))
        #expect(spoken[0].contains("查看 Hub Recovery"))
    }

    @Test
    func heartbeatVoiceCallsOutPairingContinuityAdvisoryWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-pairing-readiness-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Pairing Runtime",
            blockerSummary: nil,
            nextStepSummary: "继续当前任务"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setVoiceReadinessSnapshotForTesting(
            makeVoiceReadinessSnapshot(
                overallState: .inProgress,
                overallSummary: "首个任务已可启动，但配对有效性仍需修复：同网首配已完成，正在验证正式异网入口",
                checks: [
                    makeVoiceReadinessCheck(
                        kind: .pairingValidity,
                        state: .inProgress,
                        reasonCode: "local_pairing_ready_remote_unverified",
                        headline: "同网首配已完成，正在验证正式异网入口",
                        summary: "正式异网入口还在验证中，切网后续连能力暂未最终确认。",
                        nextStep: "请先在 Hub 配对页核对正式异网入口，并完成一次切网续连验证。",
                        repairEntry: .hubPairing
                    )
                ]
            )
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "pairing_readiness_voice_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("配对续连还需要确认"))
        #expect(spoken[0].contains("正式异网入口"))
        #expect(spoken[0].contains("查看 Hub 配对"))
    }

    @Test
    func heartbeatVoiceCallsOutProjectCreationTriggerWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let appModel = AppModel()
        appModel.registry = .empty()
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        let emission = await manager.emitHeartbeatForTesting(reason: "project_creation_voice_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("项目创建差一句触发"))
        #expect(spoken[0].contains("贪食蛇游戏"))
        #expect(spoken[0].contains("直接说立项"))
        #expect(spoken[0].contains("创建一个project"))
    }

    @Test
    func heartbeatVoiceCallsOutQueuedGovernedReviewWhenNoHigherPrioritySignalExists() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            "queued governed review"
        }
        let root = try makeProjectRoot(named: "heartbeat-governed-review-voice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 1_800,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let staleAt: TimeInterval = 1_773_900_000
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: Int64((staleAt * 1000.0).rounded()),
            nowMs: Int64((staleAt * 1000.0).rounded())
        )

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Review Runtime",
            lastOpenedAt: staleAt,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: staleAt,
            lastEventAt: staleAt
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)

        let emission = await manager.emitHeartbeatForTesting(
            reason: "governed_review_voice_test",
            now: Date(timeIntervalSince1970: staleAt + 4_000)
        )
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("治理审查已排队"))
        #expect(spoken[0].contains("长时间无进展"))
        #expect(spoken[0].contains("打开项目并查看这次治理审查"))
    }

    @Test
    func heartbeatVoicePrefersHubBriefProjectionTtsWhenFetcherReturnsProjection() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "brief-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: "awaiting_authorization",
                    status: "awaiting_authorization",
                    criticalBlocker: "等待安全审批",
                    topline: "发布主线暂停，等待一项授权。",
                    nextBestAction: "处理 release grant。",
                    pendingGrantCount: 1,
                    ttsScript: [
                        "Supervisor Hub 简报。发布主线暂停，等待一项授权。",
                        "建议下一步：处理 release grant。"
                    ],
                    cardSummary: "One pending grant is blocking release.",
                    evidenceRefs: ["grant:req-1"],
                    generatedAtMs: 1_777_000_100_000,
                    expiresAtMs: 1_777_000_160_000,
                    auditRef: "audit-hub-brief-1"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-hub-brief")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(reason: "hub_projection_test")

        #expect(emission.path == "projection")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Supervisor Hub 简报"))
        #expect(spoken[0].contains("处理 release grant"))
        #expect(!spoken[0].contains("等待本地 blocker 文案"))
    }

    @Test
    func heartbeatProjectionHumanizesGovernedReviewFromHubTruth() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            "queued governed review"
        }
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "governed-review-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: payload.trigger,
                    status: "attention_required",
                    criticalBlocker: "",
                    topline: "Project \(payload.projectId) has queued strategic governance review. Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
                    nextBestAction: "Open the project and inspect why the queued governance review was scheduled.",
                    pendingGrantCount: 0,
                    ttsScript: [
                        "Project \(payload.projectId) has queued strategic governance review.",
                        "Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
                        "Next best action: Open the project and inspect why the queued governance review was scheduled."
                    ],
                    cardSummary: "GOVERNANCE REVIEW: queued strategic governance review.",
                    evidenceRefs: ["heartbeat:\(payload.projectId):1"],
                    generatedAtMs: 1_777_000_510_000,
                    expiresAtMs: 1_777_000_570_000,
                    auditRef: "audit-hub-governed-review-1"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-hub-governed-review")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 1_800,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: [.preDoneSummary]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let staleAt: TimeInterval = 1_773_900_000
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            observedProgressAtMs: Int64((staleAt * 1000.0).rounded()),
            nowMs: Int64((staleAt * 1000.0).rounded())
        )

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Governance Runtime",
            lastOpenedAt: staleAt,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: staleAt,
            lastEventAt: staleAt
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(
            reason: "hub_governed_review_projection_test",
            now: Date(timeIntervalSince1970: staleAt + 4_000)
        )
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(emission.path == "projection")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("治理审查已排队"))
        #expect(spoken[0].contains("长时间无进展"))
        #expect(spoken[0].contains("打开项目并查看这次治理审查"))
        #expect(!spoken[0].contains("strategic governance review"))
    }

    @Test
    func heartbeatVoiceFailsClosedWhenProjectionRequestExistsButFetcherReturnsUnavailable() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { _ in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: false,
                source: "test",
                projection: nil,
                reasonCode: "projection_unavailable"
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-hub-brief-unavailable")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )

        manager.setAppModel(appModel)
        let emission = await manager.emitHeartbeatForTesting(reason: "hub_projection_unavailable_test")

        #expect(emission.path == "projection_unavailable")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 简报当前不可用"))
        #expect(spoken[0].contains("打开 Hub Diagnostics"))
        #expect(!spoken[0].contains("等待本地 blocker 文案"))
    }

    @Test
    func heartbeatVoiceLeadsWithMemoryUnderfedWarningBeforeBlockerSummary() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let root = try makeProjectRoot(named: "heartbeat-memory-underfed")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Voice Runtime",
            blockerSummary: "等待 Hub grant 批准",
            nextStepSummary: "完成授权后继续运行语音回归"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                truncatedLayers: ["l1_canonical"]
            )
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "memory_underfed_test")

        #expect(emission.path == "fallback")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("当前项目背景记忆还没喂够"))
        #expect(spoken[0].contains("先不做战略纠偏"))
        #expect(spoken[0].contains("等待 Hub grant 批准"))
    }

    @Test
    func heartbeatProjectionVoicePrefixesMemoryUnderfedWarningWhenProjectionIsUsed() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.installSupervisorBriefProjectionFetcherForTesting { payload in
            HubIPCClient.SupervisorBriefProjectionResult(
                ok: true,
                source: "hub_supervisor_grpc",
                projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                    schemaVersion: "xhub.supervisor_brief_projection.v1",
                    projectionId: "memory-underfed-\(payload.projectId)",
                    projectionKind: payload.projectionKind,
                    projectId: payload.projectId,
                    runId: "",
                    missionId: "",
                    trigger: "blocked",
                    status: "blocked",
                    criticalBlocker: "等待安全审批",
                    topline: "发布主线暂停，等待一项授权。",
                    nextBestAction: "处理 release grant。",
                    pendingGrantCount: 1,
                    ttsScript: [
                        "Supervisor Hub 简报。发布主线暂停，等待一项授权。",
                        "建议下一步：处理 release grant。"
                    ],
                    cardSummary: "One pending grant is blocking release.",
                    evidenceRefs: ["grant:req-memory-underfed"],
                    generatedAtMs: 1_777_000_300_000,
                    expiresAtMs: 1_777_000_360_000,
                    auditRef: "audit-hub-brief-memory-underfed"
                ),
                reasonCode: nil
            )
        }

        let root = try makeProjectRoot(named: "heartbeat-hub-brief-memory-underfed")
        defer { try? FileManager.default.removeItem(at: root) }

        let project = makeProjectEntry(
            root: root,
            displayName: "Release Runtime",
            blockerSummary: "等待本地 blocker 文案",
            nextStepSummary: "完成本地 heartbeat next step"
        )
        let appModel = AppModel()
        appModel.registry = registry(with: [project])
        appModel.settingsStore.settings = configuredSettings(
            from: appModel.settingsStore.settings,
            autoReportMode: .summary
        )
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeMemorySnapshot(
                projectID: project.projectId,
                profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                contextRefsSelected: 0,
                evidenceItemsSelected: 0,
                truncatedLayers: ["l1_canonical"]
            )
        )

        let emission = await manager.emitHeartbeatForTesting(reason: "hub_projection_memory_underfed")

        #expect(emission.path == "projection")
        #expect(emission.outcome == "spoken")
        #expect(spoken.count == 1)
        #expect(spoken[0].contains("当前项目背景记忆还没喂够"))
        #expect(spoken[0].contains("Supervisor Hub 简报"))
        #expect(spoken[0].contains("处理 release grant"))
    }

    private func configuredSettings(
        from settings: XTerminalSettings,
        autoReportMode: VoiceAutoReportMode
    ) -> XTerminalSettings {
        var next = settings
        next.voice.autoReportMode = autoReportMode
        next.voice.quietHours.enabled = false
        return next
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(
        root: URL,
        displayName: String,
        blockerSummary: String?,
        nextStepSummary: String?
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=\(blockerSummary == nil ? "stable" : "blocked")",
            currentStateSummary: blockerSummary == nil ? "运行中" : "阻塞中",
            nextStepSummary: nextStepSummary,
            blockerSummary: blockerSummary,
            lastSummaryAt: Date().timeIntervalSince1970,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-heartbeat-fixtures", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func laneHealthVoiceState(
        id: String,
        status: LaneHealthStatus,
        heartbeatSeq: Int
    ) -> SupervisorLaneHealthLaneState {
        var state = LaneRuntimeState(
            laneID: id,
            taskId: UUID(),
            projectId: UUID(),
            agentProfile: "coder",
            status: status,
            blockedReason: status == .blocked ? .grantPending : nil,
            nextActionRecommendation: "notify_user"
        )
        state.heartbeatSeq = heartbeatSeq
        state.lastHeartbeatAtMs = 19_000
        return SupervisorLaneHealthLaneState(state: state)
    }

    private func makeRouteRepairEvent(fallbackReasonCode: String) -> AXModelRouteDiagnosticEvent {
        AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 100,
            projectId: "project-route-repair",
            projectDisplayName: "Route Repair",
            role: "coder",
            stage: "chat",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: fallbackReasonCode,
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )
    }

    private func makeVoiceReadinessSnapshot(
        overallState: XTUISurfaceState,
        overallSummary: String,
        checks: [VoiceReadinessCheck]
    ) -> VoiceReadinessSnapshot {
        VoiceReadinessSnapshot(
            schemaVersion: VoiceReadinessSnapshot.currentSchemaVersion,
            generatedAtMs: 0,
            overallState: overallState,
            overallSummary: overallSummary,
            primaryReasonCode: checks.first(where: { $0.state != .ready })?.reasonCode ?? "voice_readiness_ready",
            orderedFixes: checks.compactMap { $0.state == .ready ? nil : $0.nextStep },
            checks: checks,
            nodeSync: .empty
        )
    }

    private func makeVoiceReadinessCheck(
        kind: VoiceReadinessCheckKind,
        state: XTUISurfaceState,
        reasonCode: String,
        headline: String,
        summary: String,
        nextStep: String,
        repairEntry: UITroubleshootDestination = .xtDiagnostics
    ) -> VoiceReadinessCheck {
        VoiceReadinessCheck(
            kind: kind,
            state: state,
            reasonCode: reasonCode,
            headline: headline,
            summary: summary,
            nextStep: nextStep,
            repairEntry: repairEntry,
            detailLines: []
        )
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
    }

    private func makeMemorySnapshot(
        projectID: String,
        reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
        requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        contextRefsSelected: Int = 2,
        evidenceItemsSelected: Int = 2,
        omittedSections: [String] = [],
        truncatedLayers: [String] = []
    ) -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: reviewLevelHint.rawValue,
            requestedProfile: requestedProfile,
            profileFloor: profileFloor,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile, resolvedProfile],
            progressiveUpgradeCount: 0,
            focusedProjectId: projectID,
            selectedSections: [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            omittedSections: omittedSections,
            contextRefsSelected: contextRefsSelected,
            contextRefsOmitted: max(0, 2 - contextRefsSelected),
            evidenceItemsSelected: evidenceItemsSelected,
            evidenceItemsOmitted: max(0, 2 - evidenceItemsSelected),
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_040,
            truncatedLayers: truncatedLayers,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: resolvedProfile == profileFloor ? nil : "budget_guardrail",
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure"
        )
    }

    private func heartbeatDoctorTruthPresentation(
        statusLine: String,
        tone: SupervisorHeaderControlTone,
        detailLine: String
    ) -> SupervisorDoctorBoardPresentation {
        SupervisorDoctorBoardPresentation(
            iconName: "checkmark.shield.fill",
            iconTone: .success,
            title: "Supervisor 体检",
            statusLine: "体检检查通过",
            releaseBlockLine: "发布级体检门已满足。",
            skillDoctorTruthStatusLine: statusLine,
            skillDoctorTruthTone: tone,
            skillDoctorTruthDetailLine: detailLine,
            memoryReadinessLine: "战略记忆已就绪。",
            memoryReadinessTone: .success,
            memoryIssueSummaryLine: nil,
            memoryIssueDetailLine: nil,
            projectMemoryAdvisoryLine: nil,
            projectMemoryAdvisoryTone: .neutral,
            projectMemoryAdvisoryDetailLine: nil,
            memoryContinuitySummaryLine: nil,
            memoryContinuityDetailLine: nil,
            canonicalRetryStatusLine: nil,
            canonicalRetryTone: .neutral,
            canonicalRetryMetaLine: nil,
            canonicalRetryDetailLine: nil,
            emptyStateText: nil,
            reportLine: nil
        )
    }

    private func configureHeartbeatRecoveryGovernance(
        ctx: AXProjectContext,
        executionTier: AXProjectExecutionTier,
        supervisorTier: AXProjectSupervisorInterventionTier
    ) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorTier,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 3_600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .failureStreak]
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func makeHeartbeatRecoveryLaneSnapshot(
        projectId: String,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason?,
        nextActionRecommendation: String
    ) -> SupervisorLaneHealthSnapshot {
        let projectUUID = UUID(uuidString: oneShotDeterministicUUIDString(seed: projectId))
        var state = LaneRuntimeState(
            laneID: "lane-\(blockedReason?.rawValue ?? status.rawValue)",
            taskId: UUID(),
            projectId: projectUUID,
            agentProfile: "coder",
            status: status,
            blockedReason: blockedReason,
            nextActionRecommendation: nextActionRecommendation
        )
        state.heartbeatSeq = 4
        state.lastHeartbeatAtMs = 1_773_384_000_000
        state.oldestWaitMs = 1_773_383_940_000

        return SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_773_384_000_000,
            summary: LaneHealthSummary(
                total: 1,
                running: status == .running ? 1 : 0,
                blocked: status == .blocked ? 1 : 0,
                stalled: status == .stalled ? 1 : 0,
                failed: status == .failed ? 1 : 0,
                waiting: status == .waiting ? 1 : 0,
                recovering: status == .recovering ? 1 : 0,
                completed: status == .completed ? 1 : 0
            ),
            lanes: [SupervisorLaneHealthLaneState(state: state)]
        )
    }
}

private actor ProjectionRequestCapture {
    private var projectId: String?
    private var trigger: String?

    func record(projectId: String, trigger: String) {
        self.projectId = projectId
        self.trigger = trigger
    }

    func snapshot() -> (projectId: String?, trigger: String?) {
        (projectId, trigger)
    }
}
