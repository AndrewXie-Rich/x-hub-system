import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ChatSessionModelDirectReplyTests {
    @Test
    func modelRouteQuestionUsesLocalProjectExecutionRecord() throws {
        let root = try makeProjectRoot(named: "project-direct-model-route")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.2",
                "actual_model_id": "qwen3-17b-mlx-bf16",
                "runtime_provider": "Hub (Local)",
                "execution_path": "local_fallback_after_remote_error",
                "fallback_reason_code": "model_not_found",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.2")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = try #require(
            session.directProjectReplyIfApplicableForTesting(
                "你现在是什么模型",
                ctx: ctx,
                config: config,
                router: router
            )
        )

        #expect(rendered.contains("这条回复本身是本地直答"))
        #expect(rendered.contains("coder 首选模型路由是 openai/gpt-5.2"))
        #expect(rendered.contains("最近一次实际执行没有按当前配置模型命中；实际执行的是：qwen3-17b-mlx-bf16"))
        #expect(rendered.contains("以下记录只针对当前项目的 coder 角色"))
    }

    @Test
    func routeDiagnoseShowsProjectOverrideRouteMemoryAndCurrentDecision() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": now - 60,
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
                "created_at": now - 40,
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
                "created_at": now - 20,
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

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let store = SettingsStore()
        store.settings = store.settings.setting(role: .coder, providerKind: .hub, model: "openai/gpt-5-low")
        store.settings = store.settings.setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5-low")
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-5-low", name: "GPT 5 Low", state: .loaded)
                ],
                updatedAt: 130
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 130
            )
        )

        #expect(rendered.contains("Project route diagnose: coder"))
        #expect(rendered.contains("配置来源：project override"))
        #expect(rendered.contains("全局对照："))
        #expect(rendered.contains("global_coder_assignment=openai/gpt-5-low"))
        #expect(rendered.contains("global_supervisor_assignment=openai/gpt-5-low"))
        #expect(rendered.contains("relation=当前项目有 project override；它会盖过 coder 全局 assignment `openai/gpt-5-low`。Supervisor 仍只看自己的全局 assignment。"))
        #expect(rendered.contains("配置状态：Hub inventory 已精确命中；当前会继续按远端执行尝试（远端，状态=可用未加载）。"))
        #expect(rendered.contains("当前决策：之前的本地锁已自动解除；当前按配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("route memory"))
        #expect(rendered.contains("consecutive_remote_fallbacks=3"))
        #expect(rendered.contains("异常趋势：最近 3 次主要是 `model_not_found`"))
        #expect(rendered.contains("建议动作：先去 Hub -> Models 确认目标模型已加载"))
        #expect(rendered.contains("项目级本地锁已经解除"))
        #expect(rendered.contains("提示：project override 会优先于 coder 全局 assignment；Supervisor 只看自己的全局 assignment"))
    }

    @Test
    func routeDiagnoseShowsConfiguredRemoteAvailableBypassesRememberedFallback() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-remembered-remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-4.1",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
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

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let router = LLMRouter(settingsStore: SettingsStore())
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ],
                updatedAt: 300
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            )
        )

        #expect(rendered.contains("配置状态：Hub inventory 已精确命中；当前会继续按远端执行尝试（远端，状态=可用未加载）。"))
        #expect(rendered.contains("当前决策：按当前配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("判定："))
        #expect(rendered.contains("XT 当前 transport 是 fileIPC，所以这轮本来就不会强制走远端"))
        #expect(!rendered.contains("会先自动试上次稳定远端"))
    }

    @Test
    func routeDiagnoseExplainsRecoveredConfiguredModelClearedLocalLock() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-recovered-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        for offset in [60.0, 40.0, 20.0] {
            AXProjectStore.appendUsage(
                [
                    "type": "ai_usage",
                    "created_at": now - offset,
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
        }

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let router = LLMRouter(settingsStore: SettingsStore())
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        #expect(rendered.contains("当前决策：之前的本地锁已自动解除；当前按配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("判定："))
        #expect(rendered.contains("之前因连续 fallback 触发的项目级本地锁已经解除"))
    }

    @Test
    func routeDiagnoseShowsGlobalAssignmentIssueWhenSupervisorAndCoderMatch() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-global-match")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let store = SettingsStore()
        store.settings = store.settings.setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")
        store.settings = store.settings.setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: nil,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ],
                updatedAt: 130
            ),
            localSnapshot: ModelStateSnapshot.empty()
        )

        #expect(rendered.contains("配置来源：global assignment"))
        #expect(rendered.contains("global_coder_assignment=openai/gpt-5.4"))
        #expect(rendered.contains("global_coder_issue="))
        #expect(rendered.contains("global_supervisor_assignment=openai/gpt-5.4"))
        #expect(rendered.contains("global_supervisor_issue="))
        #expect(rendered.contains("relation=Supervisor 和 project coder 的全局 assignment 一致"))
    }

    @Test
    func routeDiagnoseSummarizesHubRecoveryTrendForRemoteExportBlocked() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-remote-export-blocked")
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
                "execution_path": "hub_downgraded_to_local",
                "fallback_reason_code": "remote_export_blocked",
            ],
            for: ctx
        )
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 110,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-14b-mlx",
                "runtime_provider": "Hub (Local)",
                "execution_path": "hub_downgraded_to_local",
                "fallback_reason_code": "remote_export_blocked",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let router = LLMRouter(settingsStore: SettingsStore())
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .loaded)
                ],
                updatedAt: 130
            ),
            localSnapshot: ModelStateSnapshot.empty()
        )

        #expect(rendered.contains("path=hub_downgraded_to_local"))
        #expect(rendered.contains("reason=remote_export_blocked"))
        #expect(rendered.contains("异常趋势：最近 2 次主要是 `remote_export_blocked`"))
        #expect(rendered.contains("建议动作：先去 Hub Recovery / Hub 审计看 `remote_export_blocked`"))
    }

    @Test
    func routeDiagnoseShowsRemoteBackupPlanBeforeLocalFallback() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.auto)

        let root = try makeProjectRoot(named: "project-route-diagnose-remote-backup")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "openai/gpt-5.4",
                        name: "GPT 5.4",
                        backend: "openai",
                        quant: "n/a",
                        contextLength: 200_000,
                        paramsB: 0,
                        roles: nil,
                        state: .available,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: nil,
                        note: nil
                    ),
                    HubModel(
                        id: "openai/gpt-4.1",
                        name: "GPT 4.1",
                        backend: "openai",
                        quant: "n/a",
                        contextLength: 200_000,
                        paramsB: 0,
                        roles: nil,
                        state: .loaded,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: nil,
                        note: nil
                    )
                ],
                updatedAt: 130
            ),
            localSnapshot: ModelStateSnapshot.empty()
        )

        #expect(rendered.contains("当前决策：按当前配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("远端备选：首选远端失败时，XT 会先改试同族已加载远端：openai/gpt-4.1"))
    }

    @Test
    func routeDiagnoseShowsLastObservedRemoteRetryExecution() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.auto)

        let root = try makeProjectRoot(named: "project-route-diagnose-remote-retry-observed")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 200,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
                "remote_retry_attempted": true,
                "remote_retry_from_model_id": "openai/gpt-5.4",
                "remote_retry_to_model_id": "openai/gpt-4.1",
                "remote_retry_reason_code": "model_not_found",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "openai/gpt-5.4",
                        name: "GPT 5.4",
                        backend: "openai",
                        quant: "n/a",
                        contextLength: 200_000,
                        paramsB: 0,
                        roles: nil,
                        state: .available,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: nil,
                        note: nil
                    ),
                    HubModel(
                        id: "openai/gpt-4.1",
                        name: "GPT 4.1",
                        backend: "openai",
                        quant: "n/a",
                        contextLength: 200_000,
                        paramsB: 0,
                        roles: nil,
                        state: .loaded,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: nil,
                        note: nil
                    )
                ],
                updatedAt: 220
            ),
            localSnapshot: ModelStateSnapshot.empty()
        )

        #expect(rendered.contains("最近路由异常 / 重试记录"))
        #expect(rendered.contains("remote_retry=openai/gpt-5.4->openai/gpt-4.1"))
        #expect(rendered.contains("最近一次 coder 真实记录"))
        #expect(rendered.contains("- remote_retry_attempted=true"))
        #expect(rendered.contains("- remote_retry_from_model=openai/gpt-5.4"))
        #expect(rendered.contains("- remote_retry_to_model=openai/gpt-4.1"))
        #expect(rendered.contains("- remote_retry_reason=model_not_found"))
    }

    @Test
    func routeDiagnoseSurfacesHubAuditAnchorForDowngradeEvidence() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-audit-anchor")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 210,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "qwen3-17b-mlx-bf16",
                "runtime_provider": "Hub (Local)",
                "execution_path": "hub_downgraded_to_local",
                "fallback_reason_code": "remote_export_blocked",
                "audit_ref": "audit-route-789",
                "deny_code": "grant_required",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let router = LLMRouter(settingsStore: SettingsStore())
        let session = ChatSessionModel()

        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: router,
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available)
                ],
                updatedAt: 250
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-17b-mlx-bf16", name: "Qwen 3 17B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 250
            )
        )

        #expect(rendered.contains("Hub 审计锚点：audit_ref=audit-route-789 deny_code=grant_required。去 Hub Recovery / Hub 审计优先查 `remote_export_blocked`。"))
        #expect(rendered.contains("- audit_ref=audit-route-789"))
        #expect(rendered.contains("- deny_code=grant_required"))
    }

    @Test
    func identityQuestionDoesNotPretendRemoteModelWasUsed() throws {
        let root = try makeProjectRoot(named: "project-direct-identity")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 200,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-5.4",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = try #require(
            session.directProjectReplyIfApplicableForTesting(
                "你是不是GPT",
                ctx: ctx,
                config: config,
                router: router
            )
        )

        #expect(rendered.contains("我是 X-Terminal 里的 Project AI"))
        #expect(rendered.contains("这条回复本身是本地直答"))
        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的 actual model_id 是：openai/gpt-5.4"))
        #expect(rendered.contains("Supervisor / reviewer / 其他项目的模型路由彼此独立"))
    }

    @Test
    func bareConfiguredModelIdMatchesQualifiedActualModelId() throws {
        let root = try makeProjectRoot(named: "project-direct-bare-model-match")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 300,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-5.4",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "gpt-5.4")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = try #require(
            session.directProjectReplyIfApplicableForTesting(
                "刚刚上一轮实际调用了什么模型",
                ctx: ctx,
                config: config,
                router: router
            )
        )

        #expect(!rendered.contains("最近一次实际执行没有按当前配置模型命中"))
        #expect(!rendered.contains("当前配置首选是 gpt-5.4"))
        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的 actual model_id 是：openai/gpt-5.4"))
    }

    @Test
    func actualModelReplyIncludesAuditReferenceFromUsageRecord() throws {
        let root = try makeProjectRoot(named: "project-direct-audit-ref")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 320,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-5.4",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
                "audit_ref": "audit:project-remote-hit-1",
            ],
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = try #require(
            session.directProjectReplyIfApplicableForTesting(
                "刚刚上一轮实际调用了什么模型",
                ctx: ctx,
                config: config,
                router: router
            )
        )

        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的 actual model_id 是：openai/gpt-5.4"))
        #expect(rendered.contains("audit_ref=audit:project-remote-hit-1"))
    }

    @Test
    func strictProjectMismatchFailClosedSurfacesAuditEvidenceForLocalFallback() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let session = ChatSessionModel()
        let rendered = session.strictProjectRemoteModelMismatchResponseForTesting(
            configuredModelId: "openai/gpt-5.4",
            routeDecision: AXProjectPreferredModelRouteDecision(
                preferredModelId: "openai/gpt-5.4",
                configuredModelId: "openai/gpt-5.4",
                rememberedRemoteModelId: nil,
                preferredLocalModelId: nil,
                usedRememberedRemoteModel: false,
                forceLocalExecution: false,
                reasonCode: nil
            ),
            usage: LLMUsage(
                promptTokens: 10,
                completionTokens: 20,
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-17b-mlx-bf16",
                runtimeProvider: "Hub (Local)",
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found",
                auditRef: "audit:project-mismatch-1",
                denyCode: "model_not_found"
            )
        )

        let message = try #require(rendered)
        #expect(message.contains("❌ Project AI 已拒绝接受本次回复"))
        #expect(message.contains("当前配置首选是 openai/gpt-5.4，但这轮实际执行返回的是 qwen3-17b-mlx-bf16"))
        #expect(message.contains("远端目标模型没有真正命中，随后回复被本地兜底运行时接管"))
        #expect(message.contains("- audit_ref=audit:project-mismatch-1"))
        #expect(message.contains("- deny_code=model_not_found"))
        #expect(message.contains("到 Hub Models 确认 openai/gpt-5.4 已真正可执行"))
    }

    @Test
    func strictProjectMismatchFailClosedExplainsProjectLocalLock() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let session = ChatSessionModel()
        let rendered = session.strictProjectRemoteModelMismatchResponseForTesting(
            configuredModelId: "openai/gpt-5.4",
            routeDecision: AXProjectPreferredModelRouteDecision(
                preferredModelId: "qwen3-32b-mlx",
                configuredModelId: "openai/gpt-5.4",
                rememberedRemoteModelId: nil,
                preferredLocalModelId: "qwen3-32b-mlx",
                usedRememberedRemoteModel: false,
                forceLocalExecution: true,
                reasonCode: "project_remote_fallback_lock_local_recent_actual"
            ),
            usage: LLMUsage(
                promptTokens: 10,
                completionTokens: 20,
                requestedModelId: "qwen3-32b-mlx",
                actualModelId: "qwen3-32b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "local_runtime",
                fallbackReasonCode: nil,
                auditRef: nil,
                denyCode: nil
            )
        )

        let message = try #require(rendered)
        #expect(message.contains("project route-memory 强制切到了本地执行"))
        #expect(message.contains("当前本地目标：qwen3-32b-mlx"))
        #expect(message.contains("在当前项目运行 `/route diagnose`"))
        #expect(message.contains("重新 `/model openai/gpt-5.4` 或 `/model auto` 再重试"))
    }

    @Test
    func explicitStartCodingIntentEnablesBootstrapTools() {
        let session = ChatSessionModel()
        let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let config = AXProjectConfig.default(forProjectRoot: root)

        #expect(session.immediateProjectExecutionIntentForTesting("你现在开始编写我的世界的代码吧"))

        let calls = session.immediateProjectExecutionBootstrapCallsForTesting(config: config, projectRoot: root)
        #expect(calls.contains(where: { $0.tool == .list_dir }))
        #expect(!calls.contains(where: { $0.tool == .git_status }))
    }

    @Test
    func explicitStartCodingIntentIncludesGitStatusInsideNestedGitRepo() throws {
        let session = ChatSessionModel()
        let repoRoot = try makeProjectRoot(named: "project-bootstrap-git")
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        let nestedRoot = repoRoot.appendingPathComponent("workspace/app", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedRoot, withIntermediateDirectories: true)
        let config = AXProjectConfig.default(forProjectRoot: nestedRoot)

        let calls = session.immediateProjectExecutionBootstrapCallsForTesting(
            config: config,
            projectRoot: nestedRoot
        )

        #expect(calls.contains(where: { $0.tool == .list_dir }))
        #expect(calls.contains(where: { $0.tool == .git_status }))
    }

    @Test
    func paraphraseOnlyReplyForExplicitCodingIntentTriggersExecutionRepair() {
        let session = ChatSessionModel()

        let needsRepair = session.shouldRepairImmediateExecutionForTesting(
            userText: "你现在开始编写我的世界的代码吧",
            toolResults: [
                ToolResult(id: "bootstrap_list_dir", tool: .list_dir, ok: true, output: "README.md")
            ],
            assistantText: "开始编写我的世界还原项目代码。"
        )

        #expect(needsRepair)
    }

    @Test
    func englishParaphraseOnlyReplyAlsoTriggersExecutionRepair() {
        let session = ChatSessionModel()

        let needsRepair = session.shouldRepairImmediateExecutionForTesting(
            userText: "start coding the minecraft project now",
            toolResults: [
                ToolResult(id: "bootstrap_git_status", tool: .git_status, ok: true, output: "clean")
            ],
            assistantText: "beginning of minecraft coding project"
        )

        #expect(needsRepair)
    }

    @Test
    func concreteExecutionProgressDoesNotTriggerExecutionRepair() {
        let session = ChatSessionModel()

        let needsRepair = session.shouldRepairImmediateExecutionForTesting(
            userText: "你现在开始编写我的世界的代码吧",
            toolResults: [
                ToolResult(id: "write_main", tool: .write_file, ok: true, output: "wrote main.swift")
            ],
            assistantText: "已创建 `main.swift` 并写入第一版入口。"
        )

        #expect(!needsRepair)
    }

    @Test
    func planningContractFailureMessageHidesRawPlanningJSON() {
        let session = ChatSessionModel()
        let message = session.planningContractFailureMessageForTesting(
            userText: "你现在开始编写我的世界的代码吧",
            modelOutput: #"{"project":"我的世界还原项目","goal":"Create a Minecraft-like game","requirements":[]}"#
        )

        #expect(message.contains("计划对象"))
        #expect(!message.contains(#""project":"#))
        #expect(message.contains("fail-closed"))
    }

    @Test
    func secretVaultBrowserFillSuccessProducesAssistantOutcomeLine() {
        let session = ChatSessionModel()
        let lines = session.assistantToolOutcomeLinesForTesting(
            toolResults: [
                ToolResult(
                    id: "browser_secret_fill_ok",
                    tool: .deviceBrowserControl,
                    ok: true,
                    output: ToolExecutor.structuredOutput(
                        summary: [
                            "tool": .string(ToolName.deviceBrowserControl.rawValue),
                            "ok": .bool(true),
                            "action": .string("type"),
                            "selector": .string("input[type=password]"),
                            "browser_runtime_driver_state": .string("secret_vault_applescript_fill")
                        ],
                        body: "session_id=browser_session_1"
                    )
                )
            ]
        )

        #expect(lines.count == 1)
        #expect(lines[0].contains("Hub Secret Vault"))
        #expect(lines[0].contains("input[type=password]"))
    }

    @Test
    func toolHistoryForPromptIncludesHumanReadableSummaryLine() {
        let session = ChatSessionModel()
        let history = session.toolHistoryForPromptForTesting(
            toolResults: [
                ToolResult(
                    id: "browser_secret_fill_ok",
                    tool: .deviceBrowserControl,
                    ok: true,
                    output: ToolExecutor.structuredOutput(
                        summary: [
                            "tool": .string(ToolName.deviceBrowserControl.rawValue),
                            "ok": .bool(true),
                            "action": .string("type"),
                            "selector": .string("input[type=password]"),
                            "browser_runtime_driver_state": .string("secret_vault_applescript_fill")
                        ],
                        body: "session_id=browser_session_1"
                    )
                )
            ]
        )

        #expect(history.contains("summary="))
        #expect(history.contains("已使用 Secret Vault 凭据填充"))
        #expect(history.contains("browser_runtime_driver_state"))
    }

    @Test
    func resumeDirectReplyUsesStructuredProjectArtifacts() throws {
        let root = try makeProjectRoot(named: "project-direct-resume")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        var memory = AXMemory.new(projectName: "project-direct-resume", projectRoot: root.path)
        memory.goal = "Keep resume / handoff summaries accurate across AI switches."
        memory.currentState = ["Remote retry routing is already in place"]
        memory.decisions = ["Resume summary must stay local-only and not enter the normal prompt context."]
        memory.nextSteps = ["Land the /resume entry and direct trigger"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Need a handoff entry that does not pollute the main prompt.",
            createdAt: 100
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "Use a local-only structured summary built from canonical memory and recent context.",
            createdAt: 101
        )

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 120,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-5.4",
                "actual_model_id": "openai/gpt-5.4",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
            ],
            for: ctx
        )

        try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "resume-local-only",
                projectId: projectId,
                category: .scopeFreeze,
                status: .approved,
                statement: "Resume entry reads structured memory only and does not replay the full chat history.",
                source: "owner",
                reversible: true,
                approvalRequired: false,
                auditRef: "audit:resume-local-only",
                createdAtMs: 130_000
            ),
            for: ctx
        )
        try SupervisorBackgroundPreferenceTrackStore.upsert(
            SupervisorBackgroundPreferenceTrackBuilder.build(
                noteId: "resume-style",
                projectId: projectId,
                domain: .uxStyle,
                strength: .strong,
                statement: "交接摘要要短、准、能直接继续，不要灌回主上下文。",
                createdAtMs: 131_000
            ),
            for: ctx
        )

        let store = SettingsStore()
        let router = LLMRouter(settingsStore: store)
        let session = ChatSessionModel()

        let rendered = try #require(
            session.directProjectReplyIfApplicableForTesting(
                "帮我接上次的进度",
                ctx: ctx,
                config: nil,
                router: router
            )
        )

        #expect(rendered.contains("项目接续摘要（本地整理，不额外调用远端模型）"))
        #expect(rendered.contains("当前目标：Keep resume / handoff summaries accurate across AI switches."))
        #expect(rendered.contains("建议下一步：Land the /resume entry and direct trigger"))
        #expect(rendered.contains("最近一次 coder 执行：远端 openai/gpt-5.4"))
        #expect(rendered.contains("重要决策："))
        #expect(rendered.contains("Resume entry reads structured memory only"))
        #expect(rendered.contains("长期偏好："))
        #expect(rendered.contains("要不要从这里继续？"))
    }

    @Test
    func resumeSlashCommandDoesNotPolluteRecentContextOrRawLog() throws {
        let root = try makeProjectRoot(named: "project-slash-resume")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "project-slash-resume", projectRoot: root.path)
        memory.goal = "Provide a clean resume entry."
        memory.currentState = ["Structured memory already exists"]
        memory.nextSteps = ["Render local-only resume summary"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Need a clean resume entry",
            createdAt: 200
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "We should keep it local-only.",
            createdAt: 201
        )

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx, limit: 20)
        session.draft = "/resume"
        session.send(
            ctx: ctx,
            memory: memory,
            config: nil,
            router: LLMRouter(settingsStore: SettingsStore())
        )

        let assistantText = try #require(session.messages.last?.content)
        #expect(assistantText.contains("项目接续摘要（本地整理，不额外调用远端模型）"))

        let recent = AXRecentContextStore.load(for: ctx)
        #expect(recent.messages.count == 2)
        #expect(recent.messages.last?.content == "We should keep it local-only.")
        #expect(!recent.messages.contains(where: { $0.content == "/resume" }))
        #expect(!recent.messages.contains(where: { $0.content.contains("项目接续摘要（本地整理，不额外调用远端模型）") }))
        #expect(!FileManager.default.fileExists(atPath: ctx.rawLogURL.path))
    }

    @Test
    func resumeButtonPresentationAppendsAssistantOnlyWithoutPersistingConversation() throws {
        let root = try makeProjectRoot(named: "project-button-resume")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "project-button-resume", projectRoot: root.path)
        memory.goal = "Expose a clean resume entry in the chat header."
        memory.currentState = ["The project already has durable memory"]
        memory.nextSteps = ["Show a local-only resume brief from the UI"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Keep the resume entry out of the main prompt state.",
            createdAt: 220
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "Use an assistant-only local summary presentation.",
            createdAt: 221
        )

        let session = ChatSessionModel()
        session.presentProjectResumeBrief(ctx: ctx)

        #expect(session.messages.count == 1)
        #expect(session.messages.first?.role == .assistant)
        #expect(session.messages.first?.tag == nil)
        #expect(session.messages.first?.content.contains("项目接续摘要（本地整理，不额外调用远端模型）") == true)

        let recent = AXRecentContextStore.load(for: ctx)
        #expect(recent.messages.count == 2)
        #expect(recent.messages.last?.content == "Use an assistant-only local summary presentation.")
        #expect(!FileManager.default.fileExists(atPath: ctx.rawLogURL.path))
    }

    @Test
    func routeDiagnosePresentationAppendsAssistantOnlyWithoutPersistingConversation() async throws {
        let root = try makeProjectRoot(named: "project-button-route-diagnose")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Keep route diagnosis out of the main prompt state.",
            createdAt: 260
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "Use an assistant-only route diagnosis presentation.",
            createdAt: 261
        )

        let session = ChatSessionModel()
        session.presentProjectRouteDiagnosis(
            ctx: ctx,
            config: nil,
            router: LLMRouter(settingsStore: SettingsStore())
        )

        try await waitUntil(timeoutMs: 5_000) {
            session.messages.count == 1 &&
            session.messages.first?.content.contains("Project route diagnose: coder") == true
        }

        #expect(session.messages.count == 1)
        #expect(session.messages.first?.role == .assistant)
        #expect(session.messages.first?.tag == nil)
        #expect(session.messages.first?.content.contains("Project route diagnose: coder") == true)

        let recent = AXRecentContextStore.load(for: ctx)
        #expect(recent.messages.count == 2)
        #expect(recent.messages.last?.content == "Use an assistant-only route diagnosis presentation.")
        #expect(!FileManager.default.fileExists(atPath: ctx.rawLogURL.path))
    }

    @Test
    func modelSlashWritesSessionSummaryCapsuleBeforeAISwitch() throws {
        let root = try makeProjectRoot(named: "project-slash-model-summary")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var memory = AXMemory.new(projectName: "project-slash-model-summary", projectRoot: root.path)
        memory.goal = "Persist the latest state before switching the coder model."
        memory.currentState = ["Current project context is active"]
        memory.nextSteps = ["Switch coder model after writing a session summary"]
        try AXProjectStore.saveMemory(memory, for: ctx)

        AXRecentContextStore.appendUserMessage(
            ctx: ctx,
            text: "Need to preserve a handoff before switching models.",
            createdAt: 300
        )
        AXRecentContextStore.appendAssistantMessage(
            ctx: ctx,
            text: "I will keep a session summary at the switch boundary.",
            createdAt: 301
        )

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx, limit: 20)
        _ = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: .empty()
        )

        #expect(FileManager.default.fileExists(atPath: ctx.latestSessionSummaryURL.path))
        let data = try Data(contentsOf: ctx.latestSessionSummaryURL)
        let summary = try JSONDecoder().decode(AXSessionSummaryCapsule.self, from: data)
        #expect(summary.reason == "ai_switch")
        #expect(summary.memorySummary.goal == "Persist the latest state before switching the coder model.")
        #expect(summary.workingSetSummary.latestUserMessage == "Need to preserve a handoff before switching models.")
    }

    @Test
    func modelSlashPersistsRemoteAvailableCoderModel() throws {
        let root = try makeProjectRoot(named: "project-slash-model-unavailable")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(config, for: ctx)

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ],
                updatedAt: 1_776_400_000
            )
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(reply == "已将 coder 模型设置为：openai/gpt-5.4")
    }

    @Test
    func modelSlashPrefersRequestedRemoteWhenItRemainsAvailable() throws {
        let root = try makeProjectRoot(named: "project-slash-model-preflight-remembered")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(config, for: ctx)

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-4.1",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
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

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            )
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(reply == "已将 coder 模型设置为：openai/gpt-5.4")
    }

    @Test
    func modelSlashSkipsProjectLocalLockWhenRequestedRemoteRemainsAvailable() throws {
        let root = try makeProjectRoot(named: "project-slash-model-preflight-local-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(config, for: ctx)

        for offset in [60.0, 40.0, 20.0] {
            AXProjectStore.appendUsage(
                [
                    "type": "ai_usage",
                    "created_at": now - offset,
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
        }

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(reply == "已将 coder 模型设置为：openai/gpt-5.4")
    }

    @Test
    func modelsSlashShowsConfiguredRemoteAvailableAsDirectlyRunnable() throws {
        let root = try makeProjectRoot(named: "project-slash-models-remembered-remote")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": 100,
                "stage": "chat_plan",
                "role": "coder",
                "requested_model_id": "openai/gpt-4.1",
                "actual_model_id": "openai/gpt-4.1",
                "runtime_provider": "Hub (Remote)",
                "execution_path": "remote_model",
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

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let session = ChatSessionModel()
        let rendered = session.slashModelsTextForTesting(
            ctx: ctx,
            config: config,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            )
        )

        #expect(rendered.contains("状态：Hub inventory 已精确命中；当前会继续按远端执行尝试（远端，状态=可用未加载）。"))
        #expect(rendered.contains("上次稳定远端模型：openai/gpt-4.1"))
        #expect(rendered.contains("默认加载配置：ctx 128000"))
        #expect(rendered.contains("本地加载上限：ctx 128000"))
        #expect(!rendered.contains("当前 project 已锁到本地模式"))
        #expect(!rendered.contains("会先自动试上次稳定远端"))
    }

    @Test
    func modelsSlashExplainsRecoveredConfiguredModelClearedLocalLock() throws {
        let root = try makeProjectRoot(named: "project-slash-models-recovered-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        for offset in [60.0, 40.0, 20.0] {
            AXProjectStore.appendUsage(
                [
                    "type": "ai_usage",
                    "created_at": now - offset,
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
        }

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let session = ChatSessionModel()
        let rendered = session.slashModelsTextForTesting(
            ctx: ctx,
            config: config,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .loaded),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            )
        )

        #expect(rendered.contains("路由状态：之前因连续 fallback 触发的本地锁已自动解除；`openai/gpt-5.4` 现在恢复可执行。"))
        #expect(rendered.contains("Hub loaded 模型："))
        #expect(rendered.contains("默认加载配置：ctx 128000"))
        #expect(rendered.contains("本地加载上限：ctx 128000"))
        #expect(!rendered.contains("当前 project 已锁到本地模式"))
    }

    @Test
    func modelSlashDoesNotPersistNonInteractiveCoderModel() throws {
        let root = try makeProjectRoot(named: "project-slash-model-noninteractive")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(config, for: ctx)

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["mlx-community/qwen3-embedding-0.6b-4bit"],
            userText: "/model mlx-community/qwen3-embedding-0.6b-4bit",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "mlx-community/qwen3-embedding-0.6b-4bit",
                        name: "Qwen3 Embedding 0.6B",
                        state: .loaded,
                        backend: "mlx",
                        modelPath: "/models/qwen3-embedding",
                        taskKinds: ["embedding"]
                    ),
                    makeModel(
                        id: "mlx-community/qwen3-8b-4bit",
                        name: "Qwen3 8B",
                        state: .loaded,
                        backend: "mlx",
                        modelPath: "/models/qwen3-8b"
                    )
                ],
                updatedAt: 1_776_400_010
            )
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .coder) == "openai/gpt-4.1")
        #expect(reply.contains("未修改当前 coder 模型配置。"))
        #expect(reply.contains("不能直接用于对话执行"))
        #expect(reply.contains("/model mlx-community/qwen3-8b-4bit"))
    }

    @Test
    func roleModelSlashPersistsRemoteAvailableRoleModel() throws {
        let root = try makeProjectRoot(named: "project-slash-role-model-unavailable")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .reviewer, modelId: "anthropic/reviewer-pro")
        try AXProjectStore.saveConfig(config, for: ctx)

        let session = ChatSessionModel()
        let reply = session.handleSlashRoleModelForTesting(
            args: ["reviewer", "anthropic/reviewer-max"],
            userText: "/rolemodel reviewer anthropic/reviewer-max",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "anthropic/reviewer-max", name: "Reviewer Max", state: .available, backend: "anthropic"),
                    makeModel(id: "anthropic/reviewer-pro", name: "Reviewer Pro", state: .loaded, backend: "anthropic")
                ],
                updatedAt: 1_776_400_020
            )
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .reviewer) == "anthropic/reviewer-max")
        #expect(reply == "已将 reviewer 模型设置为：anthropic/reviewer-max")
    }

    @Test
    func modelSlashStillAllowsSaveWhenHubSnapshotIsUnavailable() throws {
        let root = try makeProjectRoot(named: "project-slash-model-no-snapshot")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-4.1")
        try AXProjectStore.saveConfig(config, for: ctx)

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: .empty()
        )

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.modelOverride(for: .coder) == "openai/gpt-5.4")
        #expect(reply.contains("已将 coder 模型设置为：openai/gpt-5.4"))
        #expect(reply.contains("当前拿不到 Hub 的模型快照"))
    }

    @Test
    func pendingToolApprovalPersistenceUsesFriendlyProjectDisplayName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "friendly-project-pending-tool-approval-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Supervisor 耳机项目"
        let previousRegistry = AXProjectRegistryStore.load()
        defer { AXProjectRegistryStore.save(previousRegistry) }
        let registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 900,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [
                AXProjectEntry(
                    projectId: projectId,
                    rootPath: root.path,
                    displayName: friendlyName,
                    lastOpenedAt: 900,
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

        let session = ChatSessionModel()
        AXPendingActionsStore.clearAll(for: ctx)
        session.persistPendingToolApprovalForTesting(
            ctx: ctx,
            calls: [
                ToolCall(
                    tool: .write_file,
                    args: [
                        "path": .string("notes.txt"),
                        "content": .string("hello")
                    ]
                )
            ],
            reason: "tools",
            userText: "帮我写个文件"
        )

        let pending = try #require(AXPendingActionsStore.pendingToolApproval(for: ctx))
        #expect(pending.projectId == projectId)
        #expect(pending.projectName == friendlyName)
        #expect(pending.projectName.contains(root.lastPathComponent) == false)
        #expect(pending.reason == "tools")
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_direct_reply_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: name,
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

    private func waitUntil(timeoutMs: UInt64, condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("condition not met within \(timeoutMs) ms")
        throw CancellationError()
    }
}
