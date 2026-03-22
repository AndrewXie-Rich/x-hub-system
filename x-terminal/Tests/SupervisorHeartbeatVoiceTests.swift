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
                resultSummary: "project governance blocks process_start under execution tier a0_observe",
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
                resultSummary: "project governance blocks process_start under execution tier a0_observe",
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
                resultSummary: "project governance blocks process_start under execution tier a0_observe",
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
        #expect(nextStepSummary.contains("Execution Tier"))
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
                resultSummary: "project governance blocks process_start under execution tier a0_observe",
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
        #expect(spoken[0].contains("Execution Tier"))
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
        #expect(spoken[0].contains("grant_pending"))
        #expect(spoken[0].contains("查看泳道健康"))
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
            latestEvent: makeRouteRepairEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "runtime_not_running",
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
    func explicitVoiceStatusQueryFallsBackToLocalGovernanceBriefWhenProjectionUnavailable() async throws {
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

        try await waitUntil("voice status local governance fallback emitted") {
            spoken.contains(where: { $0.contains("Hub 待处理授权") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("Hub 待处理授权") &&
                $0.content.contains("查看：查看授权板")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 待处理授权"))
        #expect(spoken[0].contains("查看授权板"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("打开授权并批准设备级权限") &&
            $0.content.contains("查看：查看授权板")
        }))
    }

    @Test
    func explicitVoiceStatusQueryFallsBackToLocalGovernanceBriefForLaneHealth() async throws {
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

        try await waitUntil("voice status local lane health fallback emitted") {
            spoken.contains(where: { $0.contains("泳道健康需要关注") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("泳道健康需要关注") &&
                $0.content.contains("查看：查看泳道健康")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("泳道健康需要关注"))
        #expect(spoken[0].contains("查看泳道健康"))
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("grant_pending") &&
            $0.content.contains("查看：查看泳道健康")
        }))
    }

    @Test
    func explicitTextStatusQueryFallsBackToLocalGovernanceBriefWhenProjectionUnavailable() async throws {
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

        try await waitUntil("text status local governance fallback emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief") &&
                $0.content.contains("Hub 待处理授权") &&
                $0.content.contains("查看：查看授权板")
            })
        }

        #expect(spoken.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("打开授权并批准设备级权限") &&
            $0.content.contains("查看：查看授权板")
        }))
    }

    @Test
    func explicitTextStatusQueryWithoutFocusedProjectUsesGlobalGovernanceBrief() async throws {
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

        try await waitUntil("text global governance brief emitted") {
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief · 当前工作台") &&
                $0.content.contains("Hub 待处理授权") &&
                $0.content.contains("查看：查看授权板")
            })
        }

        #expect(spoken.isEmpty)
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
            $0.content.contains("打开授权并批准设备级权限") &&
            $0.content.contains("🧭 Supervisor Brief · 当前工作台")
        }))
    }

    @Test
    func explicitVoiceStatusQueryWithoutFocusedProjectUsesGlobalGovernanceBrief() async throws {
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

        try await waitUntil("voice global governance brief emitted") {
            spoken.contains(where: { $0.contains("Hub 待处理授权") }) &&
            manager.messages.contains(where: {
                $0.role == .assistant &&
                $0.content.contains("🧭 Supervisor Brief · 当前工作台") &&
                $0.content.contains("查看：查看授权板")
            })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Hub 待处理授权"))
        #expect(spoken[0].contains("查看授权板"))
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
            governanceRepairSummary: "• Governance Runtime：Execution Tier 需要调整；Open Project Settings -> Execution Tier and raise it to A2 Repo Auto or above before starting, inspecting, or stopping managed processes.",
            progressSummary: "",
            nextStepSummary: "1. 治理修复：Governance Runtime — Execution Tier 需要调整；建议先打开 Project Governance -> Execution Tier。",
            queuePendingCount: 0,
            permissionPendingCount: 0,
            governanceRepairCount: 1,
            focusActionURL: focusActionURL
        )

        #expect(presentation.title.contains("治理修复"))
        #expect(presentation.unread)
        #expect(presentation.body.contains("待治理修复项目数：1"))
        #expect(presentation.body.contains("项目治理设置"))
        #expect(presentation.body.contains("Execution Tier"))
        let highlightRange = try #require(presentation.body.range(of: "优先建议："))
        let nextStepRange = try #require(presentation.body.range(of: "Coder 下一步建议："))
        #expect(highlightRange.lowerBound < nextStepRange.lowerBound)
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
        #expect(presentation.body.contains("语音运行时相关设置或诊断页"))
        #expect(presentation.body.contains("Open Hub Diagnostics & Recovery"))
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
