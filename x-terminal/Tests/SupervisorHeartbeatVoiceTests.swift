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
}
