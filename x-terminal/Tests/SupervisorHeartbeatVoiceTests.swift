import Foundation
import Testing
@testable import XTerminal

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
            manager.messages.contains(where: { $0.role == .assistant && $0.content.contains("Automation Runtime 命令") })
        }

        #expect(spoken.count == 1)
        #expect(spoken[0].contains("Automation Runtime 命令"))
        #expect(spoken[0].contains("/automation status"))
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
