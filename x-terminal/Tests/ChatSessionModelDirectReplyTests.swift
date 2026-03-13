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
                    )
                ],
                updatedAt: 130
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "qwen3-14b-mlx",
                        name: "Qwen 3 14B",
                        backend: "mlx",
                        quant: "bf16",
                        contextLength: 32_768,
                        paramsB: 14,
                        roles: nil,
                        state: .loaded,
                        memoryBytes: nil,
                        tokensPerSec: nil,
                        modelPath: "/models/qwen3",
                        note: nil
                    )
                ],
                updatedAt: 130
            )
        )

        #expect(rendered.contains("Project route diagnose: coder"))
        #expect(rendered.contains("配置来源：project override"))
        #expect(rendered.contains("当前决策：XT 当前会先锁本地：qwen3-14b-mlx"))
        #expect(rendered.contains("route memory"))
        #expect(rendered.contains("consecutive_remote_fallbacks=3"))
        #expect(rendered.contains("提示：project override 会优先于全局 assignment"))
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
        #expect(history.contains("Secret Vault credential"))
        #expect(history.contains("browser_runtime_driver_state"))
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_direct_reply_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
