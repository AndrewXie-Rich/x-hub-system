import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorFailureFormattingTests {

    @Test
    func legacyGrantFailureRendersConciseChineseFallbackCard() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-failure-formatting")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "xterminal-supervisor-manager-automation",
                    blockerSummary: "等待 paid model 授权",
                    nextStepSummary: "完成授权后继续执行"
                )
            ]
        )
        manager.setAppModel(appModel)

        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "grant_required;policy_mode=legacy_grant;device_name=Andrew.Xie's Laptop;model_id=openai/gpt-5.3-codex",
                deviceName: "Andrew.Xie's Laptop",
                modelId: "openai/gpt-5.3-codex"
            )
        )

        let rendered = manager.renderSupervisorFailureResponse(
            error: error,
            userMessage: "汇总项目进度"
        )

        #expect(rendered.contains("Supervisor 当前无法调用已分配模型"))
        #expect(rendered.contains("临时放行：到 Hub Settings -> Grants & Permissions 完成一次 legacy grant。"))
        #expect(rendered.contains("长期修复：到 Hub Settings -> Pairing & Device Trust 把这台设备升级到新 trust profile。"))
        #expect(rendered.contains("以下为本地直答结果："))
        #expect(rendered.contains("📊 项目进度报告"))
        #expect(rendered.contains("xterminal-supervisor-manager-automation"))
        #expect(!rendered.contains("access_state="))
        #expect(!rendered.contains("policy_ref="))
        #expect(!rendered.contains("why_it_happened="))
        #expect(!rendered.contains("next_action="))
    }

    @Test
    func legacyGrantFailureUsesIdentityFallbackForIdentityQuestion() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-identity-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "voice-runtime-project",
                    blockerSummary: "等待 paid model 授权",
                    nextStepSummary: "完成授权后继续"
                )
            ]
        )
        manager.setAppModel(appModel)

        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "grant_required;policy_mode=legacy_grant;device_name=Andrew.Xie's Laptop;model_id=openai/gpt-5.3-codex",
                deviceName: "Andrew.Xie's Laptop",
                modelId: "openai/gpt-5.3-codex"
            )
        )

        let rendered = manager.renderSupervisorFailureResponse(
            error: error,
            userMessage: "你是不是GPT"
        )

        #expect(rendered.contains("不是。当前这个入口的身份是 Supervisor"))
        #expect(rendered.contains("这条回复本身是本地直答，没有实际调用远端模型"))
        #expect(rendered.contains("不等于“这轮已经用了 GPT”"))
        #expect(rendered.contains("当前接管项目数：1"))
        #expect(!rendered.contains("我已收到你的指令。作为 Supervisor"))
        #expect(!rendered.contains("你刚才说的是"))
    }

    @Test
    func identityQuestionUsesDeterministicDirectReplyTemplate() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-direct-identity")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            supervisorPrompt: SupervisorPromptPreferences(
                identityName: "Atlas Supervisor",
                roleSummary: "Project control AI for delivery orchestration.",
                toneDirectives: "Answer directly\nKeep the distinction between configured route and actual model usage explicit.",
                extraSystemPrompt: "Prefer blunt wording over ceremony."
            )
        )
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.3-codex"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "remote",
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
            updatedAt: Date().timeIntervalSince1970
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "identity-direct-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("你是不是GPT"))

        #expect(rendered.contains("不是。当前这个入口的身份是 Atlas Supervisor"))
        #expect(rendered.contains("Project control AI for delivery orchestration."))
        #expect(rendered.contains("Supervisor 当前首选的远端模型路由是"))
        #expect(rendered.contains("openai/gpt-5.3-codex"))
        #expect(rendered.contains("这条回复本身是本地直答，没有实际调用远端模型"))
        #expect(rendered.contains("不等于“这轮已经用了 GPT”"))
        #expect(rendered.contains("当前接管项目数：1"))
    }

    @Test
    func modelRouteQuestionUsesDeterministicLocalReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-model-route-direct")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.3-codex"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "remote",
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
            updatedAt: Date().timeIntervalSince1970
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "model-route-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("你现在是什么模型"))

        #expect(rendered.contains("这条是本地直答，没有实际调用远端模型"))
        #expect(rendered.contains("当前配置的 Supervisor 首选远端模型路由"))
        #expect(rendered.contains("openai/gpt-5.3-codex"))
        #expect(rendered.contains("当前验证状态"))
        #expect(rendered.contains("未验证。当前只能确认已配置好远端首选路由"))
        #expect(rendered.contains("最近一次真实调用记录"))
        #expect(rendered.contains("当前还没有可用的调用记录"))
    }

    @Test
    func lastActualModelQuestionUsesFocusedInvocationReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-last-actual-model")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.3-codex"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.3-codex",
                    name: "GPT 5.3 Codex",
                    backend: "remote",
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
            updatedAt: Date().timeIntervalSince1970
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "last-actual-model-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "openai/gpt-5.3-codex"
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("刚刚上一轮实际调用了什么模型"))

        #expect(rendered.contains("如果你问的是刚刚上一轮真正触发到的模型"))
        #expect(rendered.contains("最近一次 Supervisor 远端调用实际返回的 model_id 是：openai/gpt-5.3-codex"))
        #expect(rendered.contains("这条回复本身仍然是本地直答"))
        #expect(rendered.contains("当前验证状态"))
        #expect(rendered.contains("已验证。最近一次可确认的远端实际 model_id 是 openai/gpt-5.3-codex"))
        #expect(!rendered.contains("当前还没有可用的调用记录"))
    }

    @Test
    func modelRouteReplyStatesSupervisorScopeExplicitly() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-model-scope")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "gpt-5.4"
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "scope-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("你现在是什么模型"))

        #expect(rendered.contains("以下记录只针对 Supervisor 角色"))
        #expect(rendered.contains("Project AI / coder / reviewer"))
    }

    @Test
    func fallbackWithoutActualModelClearsPreviousVerifiedModelState() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-fallback-clears-stale-state")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "gpt-5.4"
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "fallback-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "gpt-5.4"
        )
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: nil
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("刚刚上一轮实际调用了什么模型"))

        #expect(rendered.contains("没有拿到可确认的实际 model_id"))
        #expect(rendered.contains("未验证成功"))
        #expect(!rendered.contains("最近一次可确认的远端实际 model_id 是 gpt-5.4"))
        #expect(!rendered.contains("最近一次远端调用实际返回的 model_id 是：gpt-5.4"))
    }

    @Test
    func modelRouteQuestionShowsMismatchWhenConfiguredAndActualModelDiffer() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-model-route-mismatch")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5-low"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5-low",
                    name: "gpt-5-low",
                    backend: "remote",
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
            updatedAt: Date().timeIntervalSince1970
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "model-route-mismatch-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "remote_model",
            actualModelId: "qwen3-17b-mlx-bf16"
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("刚刚上一轮实际调用了什么模型"))

        #expect(rendered.contains("最近一次实际执行没有按当前配置模型命中"))
        #expect(rendered.contains("当前配置首选是 openai/gpt-5-low"))
        #expect(rendered.contains("最近一次实际执行是 qwen3-17b-mlx-bf16"))
        #expect(rendered.contains("/hub route grpc"))
        #expect(rendered.contains("未按配置模型执行"))
    }

    @Test
    func supervisorHubRouteCommandCanSwitchToGrpcMode() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }

        HubAIClient.setTransportMode(.auto)
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("/hub route grpc"))

        #expect(HubAIClient.transportMode() == .grpc)
        #expect(rendered.contains("已设置 Supervisor 所在 Hub 通道：grpc"))
        #expect(rendered.contains("当前 Hub transport"))
        #expect(rendered.contains("remote only (no fallback)"))
    }

    @Test
    func grpcModeRejectsMismatchedActualRemoteModel() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }

        HubAIClient.setTransportMode(.grpc)
        let manager = SupervisorManager.makeForTesting()

        let rendered = try #require(
            manager.strictSupervisorRemoteModelMismatchResponseForTesting(
                preferredModelId: "openai/gpt-5-low",
                actualModelId: "qwen3-17b-mlx-bf16"
            )
        )

        #expect(rendered.contains("已拒绝接受本次回复"))
        #expect(rendered.contains("openai/gpt-5-low"))
        #expect(rendered.contains("qwen3-17b-mlx-bf16"))
        #expect(rendered.contains("grpc-only"))
        #expect(rendered.contains("ai.generate.downgraded_to_local"))
        #expect(rendered.contains("fail-closed"))
    }

    @Test
    func executionIntakeRequestUsesNaturalLocalReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("帮我做个贪食蛇游戏"))

        #expect(rendered.contains("这类需求我会把它当成一个新的交付任务来收敛"))
        #expect(rendered.contains("网页版"))
        #expect(!rendered.contains("纯 JSON"))
        #expect(!rendered.contains("不能直接落地文件"))
        #expect(!rendered.contains("开始生成"))
        #expect(!rendered.contains("我已收到你的指令"))
    }

    @Test
    func fabricatedRuntimeConstraintRemoteReplyFallsBackToLocalExecutionIntake() {
        let manager = SupervisorManager.makeForTesting()
        let remote = """
可以！不过我先说明一下：我现在在这个回合不能直接落地文件并运行（因为你这条消息要求我只能回纯 JSON 结果，且当前我还没执行工具调用）。

回复我一句：开始生成
"""

        let rendered = manager.sanitizedSupervisorRemoteResponseForTesting(
            remote,
            userMessage: "帮我做个贪食蛇游戏"
        )

        #expect(rendered.contains("新的交付任务"))
        #expect(rendered.contains("网页版"))
        #expect(!rendered.contains("纯 JSON"))
        #expect(!rendered.contains("不能直接落地文件"))
        #expect(!rendered.contains("开始生成"))
    }

    @Test
    func outboundPromptSanitizesUUIDAndLongHexTokens() {
        let manager = SupervisorManager.makeForTesting()
        let raw = """
project_id=886EDC18-D71D-49B9-A816-DB2D6E6A3282
request_id=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
"""

        let rendered = manager.sanitizedSupervisorOutboundPromptForTesting(raw)

        #expect(!rendered.contains("886EDC18-D71D-49B9-A816-DB2D6E6A3282"))
        #expect(!rendered.contains("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"))
        #expect(rendered.contains("project_id=id:886EDC18"))
        #expect(rendered.contains("request_id=hex:01234567"))
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
            lastSummaryAt: nil,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt-\(name)-\(UUID().uuidString)"
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
