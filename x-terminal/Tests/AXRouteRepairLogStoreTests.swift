import Darwin
import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct AXRouteRepairLogStoreTests {
    @Test
    func recordsRecentEventsInReverseChronologicalOrder() throws {
        let root = try makeProjectRoot(named: "route-repair-log")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_xt_diagnostics",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "connect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeEvent(fallbackReasonCode: "runtime_not_running"),
            repairReasonCode: "grpc_route_unavailable",
            note: "remote tunnel timeout",
            createdAt: 200,
            for: ctx
        )

        let events = AXRouteRepairLogStore.recentEvents(for: ctx, limit: 10)
        #expect(events.count == 2)
        #expect(events.first?.actionId == "connect_hub_and_diagnose")
        #expect(events.first?.outcome == "failed")
        #expect(events.first?.repairReasonCode == "grpc_route_unavailable")
        #expect(events.first?.note == "remote tunnel timeout")

        let lines = AXRouteRepairLogStore.summaryLines(for: ctx, limit: 10)
        #expect(lines.count == 2)
        #expect(lines[0].contains("action=connect_hub_and_diagnose"))
        #expect(lines[0].contains("outcome=failed"))
        #expect(lines[0].contains("route_reason=runtime_not_running"))
        #expect(lines[0].contains("repair_reason=grpc_route_unavailable"))

        let humanLines = AXRouteRepairLogStore.userFacingSummaryLines(for: ctx, limit: 10)
        #expect(humanLines.count == 2)
        #expect(humanLines[0].contains("连接 Hub 并重诊断（失败）"))
        #expect(humanLines[0].contains("路由问题 Hub runtime 未启动（runtime_not_running）"))
        #expect(humanLines[0].contains("修复原因 远端链路不可用（grpc_route_unavailable）"))
        #expect(humanLines[0].contains("备注 remote tunnel timeout"))
    }

    @Test
    func digestHighlightsTopReasonsAndLatestOutcome() throws {
        let root = try makeProjectRoot(named: "route-repair-digest")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_model_picker",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "open_choose_model",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 200,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 300,
            for: ctx
        )

        let digest = AXRouteRepairLogStore.digest(for: ctx, limit: 50)
        #expect(digest.totalEvents == 3)
        #expect(digest.failureCount == 1)
        #expect(digest.topRouteReason == "model_not_found")
        #expect(digest.topRouteReasonCount == 2)
        #expect(digest.topRepairReason == "grpc_route_unavailable")
        #expect(digest.topRepairReasonCount == 1)
        #expect(digest.latestFailure?.actionId == "reconnect_hub_and_diagnose")
        #expect(digest.latestSuccess?.actionId == "open_choose_model")
        #expect(digest.headline.contains("最近 3 次路由修复"))
        #expect(digest.headline.contains("目标模型未加载"))
        #expect(digest.headline.contains("重连并重诊断"))
        #expect(!digest.headline.contains("reconnect_hub_and_diagnose"))
        #expect(digest.detailLines.contains(where: { $0.contains("top_route_reason=model_not_found count=2") }))
        #expect(digest.detailLines.contains(where: { $0.contains("latest_failure=action=reconnect_hub_and_diagnose") }))
    }

    @Test
    func headlineHumanizesLatestSuccessOutcomeWithoutChangingRawDetailLines() throws {
        let root = try makeProjectRoot(named: "route-repair-success-headline")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_xt_diagnostics",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "downgrade_to_local"),
            createdAt: 100,
            for: ctx
        )

        let digest = AXRouteRepairLogStore.digest(for: ctx, limit: 20)
        #expect(digest.headline.contains("打开 XT Diagnostics"))
        #expect(digest.headline.contains("已打开"))
        #expect(digest.detailLines.contains(where: { $0.contains("latest_success=action=open_xt_diagnostics outcome=opened") }))
    }

    @Test
    func unifiedSupervisorControlCenterLabelIsUsedForModelSettingsRepairAction() throws {
        let root = try makeProjectRoot(named: "route-repair-supervisor-control-center")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_model_settings",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 100,
            for: ctx
        )

        let lines = AXRouteRepairLogStore.userFacingSummaryLines(for: ctx, limit: 10)
        #expect(lines.count == 1)
        #expect(lines[0].contains("打开 Supervisor 控制中心 · AI 模型（已打开）"))
        #expect(lines[0].contains("目标模型未加载（model_not_found）"))
    }

    @Test
    func userFacingSummaryLineHumanizesInternalSourceAndTargetModelNotes() throws {
        let root = try makeProjectRoot(named: "route-repair-user-facing-notes")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_xt_diagnostics",
            outcome: "auto_opened",
            latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
            note: "source=connect_hub_and_diagnose_failed",
            createdAt: 100,
            for: ctx
        )
        AXRouteRepairLogStore.record(
            actionId: "apply_recommended_model",
            outcome: "selected",
            latestEvent: makeEvent(fallbackReasonCode: "remote_model_not_found"),
            note: "target_model=openai/gpt-4.1",
            createdAt: 200,
            for: ctx
        )

        let lines = AXRouteRepairLogStore.userFacingSummaryLines(for: ctx, limit: 10)
        #expect(lines.count == 2)
        #expect(lines[0].contains("改用推荐模型（已选择）"))
        #expect(lines[0].contains("目标模型 openai/gpt-4.1"))
        #expect(lines[0].contains("目标模型未加载（remote_model_not_found）"))
        #expect(lines[1].contains("打开 XT Diagnostics（已自动打开）"))
        #expect(lines[1].contains("来源 连接 Hub 失败后自动打开"))
    }

    @Test
    func userFacingActionLabelUsesXTAIModelNamingForChooseModelEntry() {
        #expect(AXRouteRepairLogStore.userFacingActionLabel("open_choose_model") == "打开 XT AI 模型")
    }

    @Test
    func recordUsesFriendlyRegistryDisplayNameWhenPresent() async throws {
        let root = try makeProjectRoot(named: "route-repair-log-friendly")
        let registryBase = root.appendingPathComponent("registry", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: registryBase, withIntermediateDirectories: true)

        try await withTemporaryEnvironment([
            "XTERMINAL_PROJECT_REGISTRY_BASE_DIR": registryBase.path
        ]) {
            let ctx = AXProjectContext(root: root)
            try ctx.ensureDirs()

            let projectId = AXProjectRegistryStore.projectId(forRoot: root)
            let registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 950,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [
                    AXProjectEntry(
                        projectId: projectId,
                        rootPath: root.path,
                        displayName: "耳机复盘项目",
                        lastOpenedAt: 950,
                        manualOrderIndex: 0,
                        pinned: false,
                        statusDigest: nil,
                        currentStateSummary: nil,
                        nextStepSummary: nil,
                        blockerSummary: nil,
                        lastSummaryAt: nil,
                        lastEventAt: nil
                    )
                ]
            )
            AXProjectRegistryStore.save(registry)

            AXRouteRepairLogStore.record(
                actionId: "open_xt_diagnostics",
                outcome: "opened",
                latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
                createdAt: 100,
                for: ctx
            )

            let event = try #require(AXRouteRepairLogStore.recentEvents(for: ctx, limit: 1).first)
            #expect(event.projectDisplayName == "耳机复盘项目")
            #expect(event.summaryLine(includeProject: true).contains("project=耳机复盘项目"))
        }
    }

    @Test
    func watchItemsPrioritizeProjectsWithMoreFailures() throws {
        let rootA = try makeProjectRoot(named: "route-repair-watch-a")
        let rootB = try makeProjectRoot(named: "route-repair-watch-b")
        let rootC = try makeProjectRoot(named: "route-repair-watch-c")
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
            try? FileManager.default.removeItem(at: rootC)
        }

        let ctxA = AXProjectContext(root: rootA)
        let ctxB = AXProjectContext(root: rootB)
        let ctxC = AXProjectContext(root: rootC)
        try ctxA.ensureDirs()
        try ctxB.ensureDirs()
        try ctxC.ensureDirs()

        AXRouteRepairLogStore.record(
            actionId: "open_model_picker",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "model_not_found"),
            createdAt: 100,
            for: ctxA
        )

        AXRouteRepairLogStore.record(
            actionId: "reconnect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeEvent(fallbackReasonCode: "grpc_route_unavailable"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 200,
            for: ctxB
        )
        AXRouteRepairLogStore.record(
            actionId: "connect_hub_and_diagnose",
            outcome: "failed",
            latestEvent: makeEvent(fallbackReasonCode: "runtime_not_running"),
            repairReasonCode: "grpc_route_unavailable",
            createdAt: 300,
            for: ctxB
        )

        AXRouteRepairLogStore.record(
            actionId: "open_xt_diagnostics",
            outcome: "opened",
            latestEvent: makeEvent(fallbackReasonCode: "downgrade_to_local"),
            createdAt: 400,
            for: ctxC
        )

        let items = AXRouteRepairLogStore.watchItems(
            for: [
                makeProjectEntry(root: rootA, displayName: "A 项目"),
                makeProjectEntry(root: rootB, displayName: "B 项目"),
                makeProjectEntry(root: rootC, displayName: "C 项目")
            ],
            limit: 3
        )

        #expect(items.count == 3)
        #expect(items[0].projectDisplayName == "B 项目")
        #expect(items[0].digest.failureCount == 2)
        #expect(items[1].projectDisplayName == "C 项目")
        #expect(items[2].projectDisplayName == "A 项目")
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_route_repair_log_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeEvent(fallbackReasonCode: String) -> AXModelRouteDiagnosticEvent {
        AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 100,
            projectId: "project-1",
            projectDisplayName: "Project 1",
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

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: 100,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }
}

private func currentEnvironmentValue(_ key: String) -> String? {
    guard let value = getenv(key) else { return nil }
    return String(cString: value)
}

private func withTemporaryEnvironment<T>(
    _ overrides: [String: String?],
    operation: () async throws -> T
) async rethrows -> T {
    let original = Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, currentEnvironmentValue($0)) })
    for (key, value) in overrides {
        if let value {
            setenv(key, value, 1)
        } else {
            unsetenv(key)
        }
    }
    defer {
        for (key, value) in original {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
    }
    return try await operation()
}
