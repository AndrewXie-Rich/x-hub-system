import Foundation
import Testing
@testable import XTerminal

struct AXProjectModelRouteMemoryTests {
    @Test
    func routeMemoryPrefersLastHealthyRemoteModelWhenConfiguredModelIsUnavailable() throws {
        let root = try makeProjectRoot(named: "route-memory-prefers-last-remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-4.1", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            )
        )

        #expect(decision.preferredModelId == "openai/gpt-4.1")
        #expect(decision.usedRememberedRemoteModel)
        #expect(decision.reasonCode == "project_last_remote_success_loaded")
    }

    @Test
    func routeMemoryTreatsEmbeddingOnlyConfiguredModelAsRetrievalOnlyAndFallsBackToRememberedRemote() throws {
        let root = try makeProjectRoot(named: "route-memory-retrieval-only-config")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "mlx-community/qwen3-embedding-0.6b-4bit",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "mlx-community/qwen3-embedding-0.6b-4bit",
                        state: .loaded,
                        backend: "mlx",
                        modelPath: "/models/qwen3-embedding",
                        taskKinds: ["embedding"]
                    ),
                    makeModel(id: "openai/gpt-4.1", state: .loaded)
                ],
                updatedAt: 300
            )
        )

        #expect(decision.preferredModelId == "openai/gpt-4.1")
        #expect(decision.usedRememberedRemoteModel)
        #expect(decision.reasonCode == "project_last_remote_success_loaded")
    }

    @Test
    func routeMemoryClearsPreferredRemoteWhenConfiguredModelIsRetrievalOnlyAndNoFallbackExists() throws {
        let root = try makeProjectRoot(named: "route-memory-retrieval-only-no-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "mlx-community/qwen3-embedding-0.6b-4bit",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "mlx-community/qwen3-embedding-0.6b-4bit",
                        state: .loaded,
                        backend: "mlx",
                        modelPath: "/models/qwen3-embedding",
                        taskKinds: ["embedding"]
                    )
                ],
                updatedAt: 300
            )
        )

        #expect(decision.preferredModelId == nil)
        #expect(!decision.usedRememberedRemoteModel)
        #expect(decision.reasonCode == "project_configured_model_retrieval_only")
    }

    @Test
    func heartbeatNoticeAppearsAfterConsecutiveRemoteFallbacks() throws {
        let root = try makeProjectRoot(named: "route-memory-heartbeat-notice")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: 300,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Route Memory Project",
            lastOpenedAt: 300,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: 300,
            lastEventAt: 300
        )

        let notice = try #require(AXProjectModelRouteMemoryStore.heartbeatNotice(for: entry))
        #expect(notice.contains("连续 2 次切到本地"))
        #expect(notice.contains("检查 Hub 配置"))
        #expect(notice.contains("openai/gpt-5.4"))
        #expect(notice.contains("/route diagnose"))
        #expect(notice.contains("点这条心跳提醒"))
        #expect(notice.contains("Hub -> Models"))
    }

    @Test
    func heartbeatNoticeDisappearsWhenConfiguredRemoteModelRemainsAvailableRemotely() throws {
        let root = try makeProjectRoot(named: "route-memory-heartbeat-remembered")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: 300,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Remembered Remote Project",
            lastOpenedAt: 300,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: 300,
            lastEventAt: 300
        )

        let notice = AXProjectModelRouteMemoryStore.heartbeatNotice(
            for: entry,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 400
            )
        )
        #expect(notice == nil)
    }

    @Test
    func configuredLoadedModelStillWinsOverRememberedRemoteModel() throws {
        let root = try makeProjectRoot(named: "route-memory-keeps-loaded-config")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .loaded),
                    makeModel(id: "openai/gpt-4.1", state: .loaded)
                ],
                updatedAt: 300
            )
        )

        #expect(decision.preferredModelId == "openai/gpt-5.4")
        #expect(!decision.usedRememberedRemoteModel)
    }

    @Test
    func routeMemoryDoesNotLockProjectToLocalModeWhenConfiguredRemoteModelRemainsAvailable() throws {
        let root = try makeProjectRoot(named: "route-memory-locks-local")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let now = Date().timeIntervalSince1970
        appendUsage(
            createdAt: now - 60,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 40,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 20,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .available)
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        #expect(!decision.forceLocalExecution)
        #expect(decision.preferredModelId == "openai/gpt-5.4")
        #expect(decision.preferredLocalModelId == nil)
        #expect(decision.reasonCode == nil)
    }

    @Test
    func routeMemoryDoesNotStayLockedWhenConfiguredRemoteModelHasRecovered() throws {
        let root = try makeProjectRoot(named: "route-memory-unlocks-after-remote-recovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let now = Date().timeIntervalSince1970
        appendUsage(
            createdAt: now - 60,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 40,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 20,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let decision = AXProjectModelRouteMemoryStore.resolvePreferredModel(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        #expect(!decision.forceLocalExecution)
        #expect(decision.preferredModelId == "openai/gpt-5.4")
        #expect(decision.preferredLocalModelId == nil)
    }

    @Test
    func heartbeatNoticeDisappearsWhenConfiguredRemoteModelHasRecovered() throws {
        let root = try makeProjectRoot(named: "route-memory-heartbeat-unlocks-after-remote-recovery")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let now = Date().timeIntervalSince1970
        appendUsage(
            createdAt: now - 60,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 40,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 20,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Recovered Remote Project",
            lastOpenedAt: now,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let notice = AXProjectModelRouteMemoryStore.heartbeatNotice(
            for: entry,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            now: now
        )

        #expect(notice == nil)
    }

    @Test
    func heartbeatNoticeReportsLockedLocalModeWhenRouteMemoryHasFreshLock() throws {
        let root = try makeProjectRoot(named: "route-memory-heartbeat-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let now = Date().timeIntervalSince1970
        appendUsage(
            createdAt: now - 50,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 30,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 10,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Locked Project",
            lastOpenedAt: now,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let notice = try #require(
            AXProjectModelRouteMemoryStore.heartbeatNotice(
                for: entry,
                snapshot: ModelStateSnapshot(
                    models: [
                        makeModel(id: "openai/gpt-5.4", state: .sleeping),
                        makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                    ],
                    updatedAt: now
                ),
                localSnapshot: ModelStateSnapshot(
                    models: [
                        makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                    ],
                    updatedAt: now
                ),
                now: now
            )
        )
        #expect(notice.contains("已切到本地模式"))
        #expect(notice.contains("qwen3-14b-mlx"))
        #expect(notice.contains("恢复远端"))
        #expect(notice.contains("/route diagnose"))
        #expect(notice.contains("点这条心跳提醒"))
    }

    @Test
    func heartbeatNoticePointsToDiagnosticsWhenHubDowngradesToLocal() throws {
        let root = try makeProjectRoot(named: "route-memory-heartbeat-downgrade")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "downgrade_to_local",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "downgrade_to_local",
            for: ctx
        )

        let entry = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Downgraded Project",
            lastOpenedAt: 200,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续当前任务",
            blockerSummary: nil,
            lastSummaryAt: 200,
            lastEventAt: 200
        )

        let notice = try #require(AXProjectModelRouteMemoryStore.heartbeatNotice(for: entry))
        #expect(notice.contains("/route diagnose"))
        #expect(notice.contains("点这条心跳提醒"))
        #expect(notice.contains("XT Settings -> Diagnostics"))
        #expect(notice.contains("Hub 审计"))
        #expect(notice.contains("downgrade_to_local"))
    }

    @Test
    func selectionWarningDoesNotAppearWhenConfiguredRemoteModelRemainsAvailable() throws {
        let root = try makeProjectRoot(named: "route-memory-selection-warning-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let now = Date().timeIntervalSince1970
        appendUsage(
            createdAt: now - 50,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 30,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 10,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", state: .loaded)
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        #expect(guidance == nil)
    }

    @Test
    func selectionWarningDoesNotOverrideConfiguredRemoteWhenItRemainsAvailable() throws {
        let root = try makeProjectRoot(named: "route-memory-selection-warning-remembered")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        appendUsage(
            createdAt: 100,
            requestedModelId: "openai/gpt-4.1",
            actualModelId: "openai/gpt-4.1",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            for: ctx
        )
        appendUsage(
            createdAt: 200,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let guidance = AXProjectModelRouteMemoryStore.selectionGuidance(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-4.1", state: .loaded),
                    makeModel(id: "openai/gpt-5.4", state: .available)
                ],
                updatedAt: 300
            )
        )

        #expect(guidance == nil)
    }

    private func appendUsage(
        createdAt: Double,
        requestedModelId: String,
        actualModelId: String,
        executionPath: String,
        fallbackReasonCode: String,
        for ctx: AXProjectContext
    ) {
        var entry: [String: Any] = [
            "type": "ai_usage",
            "created_at": createdAt,
            "stage": "chat_plan",
            "role": AXRole.coder.rawValue,
            "requested_model_id": requestedModelId,
            "actual_model_id": actualModelId,
            "execution_path": executionPath
        ]
        if !fallbackReasonCode.isEmpty {
            entry["fallback_reason_code"] = fallbackReasonCode
        }
        AXProjectStore.appendUsage(entry, for: ctx)
    }

    private func makeModel(
        id: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: backend,
            quant: "",
            contextLength: 128_000,
            paramsB: 0,
            roles: nil,
            state: state,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: modelPath,
            note: nil,
            taskKinds: taskKinds
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_route_memory_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
