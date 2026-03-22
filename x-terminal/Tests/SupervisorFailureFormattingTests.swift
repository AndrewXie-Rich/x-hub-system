import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorFailureFormattingTests {

    @Test
    @MainActor
    func fallbackReplyStillPublishesTurnExplainabilityAndFailureRouteState() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-fallback-explainability")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "亮亮",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let rendered = manager.renderSupervisorFailureResponse(
            error: HubAIError.runtimeNotRunning,
            userMessage: "帮我看下今天最重要的事"
        )
        #expect(rendered.contains("已切换为本地直答兜底"))

        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: nil,
            requestedModelId: "openai/gpt-5.4",
            failureReasonCode: "runtime_not_running"
        )
        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "帮我看下今天最重要的事",
            responseText: rendered,
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.9,
                routingReasons: ["personal_planning_language", "portfolio_review_language"]
            )
        )

        let routing = try #require(manager.supervisorLatestTurnRoutingDecisionForTesting())
        #expect(routing.mode == .personalFirst)
        #expect(routing.focusedProjectId == nil)
        #expect(routing.routingReasons.contains("personal_planning_language"))

        let assembly = try #require(manager.supervisorLatestTurnContextAssemblyForTesting())
        #expect(assembly.turnMode == .personalFirst)
        #expect(assembly.selectedSlots.contains(.dialogueWindow))
        #expect(assembly.selectedSlots.contains(.personalCapsule))
        #expect(assembly.selectedRefs.contains("dialogue_window"))

        let routeSummary = try #require(
            manager.directSupervisorReplyIfApplicableForTesting("刚刚上一轮实际调用了什么模型")
        )
        #expect(routeSummary.contains("openai/gpt-5.4"))
        #expect(routeSummary.contains("本地兜底"))
    }

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
        #expect(rendered.contains("xterminal-supervisor-manager-automation"))
        #expect(rendered.contains("等待 paid model 授权"))
        #expect(rendered.contains("完成授权后继续执行"))
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

        #expect(rendered.contains("不是。当前这个入口的身份是"))
        #expect(rendered.contains("不是一个裸的 GPT 聊天窗口"))
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
    func routeDiagnoseExplainsSupervisorUsesGlobalAssignmentOnly() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }

        HubAIClient.setTransportMode(.auto)
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-route-diagnose")
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
                    name: "GPT 5 Low",
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
                    displayName: "supervisor-route-diagnose-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: "qwen3-14b-mlx",
            requestedModelId: "openai/gpt-5-low",
            failureReasonCode: "model_not_found"
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("/route diagnose"))

        #expect(rendered.contains("Supervisor route diagnose"))
        #expect(rendered.contains("配置来源：global assignment"))
        #expect(rendered.contains("最近一次执行模式：local_fallback_after_remote_error"))
        #expect(rendered.contains("requested_model=openai/gpt-5-low"))
        #expect(rendered.contains("actual_model=qwen3-14b-mlx"))
        #expect(rendered.contains("Supervisor 不读取 project override，也不使用 project route memory"))
        #expect(rendered.contains("/hub route grpc"))
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

        #expect(rendered.contains("新的交付任务来收敛"))
        #expect(rendered.contains("网页版"))
        #expect(!rendered.contains("纯 JSON"))
        #expect(!rendered.contains("不能直接落地文件"))
        #expect(!rendered.contains("开始生成"))
        #expect(!rendered.contains("我已收到你的指令"))
    }

    @Test
    func delegatedExecutionCapabilityQuestionUsesDeterministicLocalReply() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-delegated-execution-capability")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "亮亮",
                    blockerSummary: "等待下一步执行",
                    nextStepSummary: "由 Supervisor 建 job 并继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)

        let rendered = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "你能不能直接把工单丢给project AI去执行，然后等它干完再回来跟我说？"
            )
        )

        #expect(rendered.contains("受治理委派"))
        #expect(rendered.contains("建 job 和 initial plan"))
        #expect(rendered.contains("Project AI / coder / governed skill"))
        #expect(rendered.contains("完成、阻塞、待授权或失败时再回来跟你汇报"))
        #expect(rendered.contains("当前接管项目数：1"))
        #expect(!rendered.contains("做不到"))
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
    func fabricatedDelegatedExecutionConstraintRemoteReplyFallsBackToLocalCapabilityAnswer() {
        let manager = SupervisorManager.makeForTesting()
        let remote = """
不行。我没办法直接把工单丢给 project AI 去执行，然后等它干完再回来跟你说。
"""

        let rendered = manager.sanitizedSupervisorRemoteResponseForTesting(
            remote,
            userMessage: "你能不能直接把工单丢给project AI去执行，然后等它干完再回来跟我说？"
        )

        #expect(rendered.contains("受治理委派"))
        #expect(rendered.contains("建 job 和 initial plan"))
        #expect(rendered.contains("Project AI / coder / governed skill"))
        #expect(!rendered.contains("没办法直接把工单丢给 project ai"))
        #expect(!rendered.contains("不行。"))
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
