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
        #expect(rendered.contains("Supervisor 当前无法通过 Hub 调用已选模型"))
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
    func legacyGrantFailureKeepsBriefFailClosedForStatusQueries() throws {
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
        #expect(rendered.contains("临时放行：到 REL Flow Hub → Grants & Permissions 完成一次 legacy grant。"))
        #expect(rendered.contains("长期修复：到 REL Flow Hub → Pairing & Device Trust 把这台设备升级到新 trust profile。"))
        #expect(rendered.contains("以下为本地直答结果："))
        #expect(rendered.contains("⚠️ Hub Brief 暂不可用 · xterminal-supervisor-manager-automation"))
        #expect(rendered.contains("按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"))
        #expect(rendered.contains("等 Hub brief 投影查询链接上后再问一次状态"))
        #expect(!rendered.contains("等待 paid model 授权"))
        #expect(!rendered.contains("完成授权后继续执行"))
        #expect(!rendered.contains("access_state="))
        #expect(!rendered.contains("policy_ref="))
        #expect(!rendered.contains("why_it_happened="))
        #expect(!rendered.contains("next_action="))
    }

    @Test
    func singleRequestBudgetFailureShowsCurrentDeviceBudgetTruth() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-single-budget-truth")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.hubRemotePaidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "all_paid_models",
            dailyTokenLimit: 640,
            singleRequestTokenLimit: 256
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "budget-truth-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            SupervisorMemoryAssemblySnapshot(
                source: "remote_budget_test",
                resolutionSource: "doctor",
                updatedAt: 1_741_300_000,
                reviewLevelHint: "strategic",
                requestedProfile: "project_ai_default",
                profileFloor: "project_ai_default",
                resolvedProfile: "project_ai_default",
                attemptedProfiles: ["project_ai_default"],
                progressiveUpgradeCount: 0,
                selectedSections: ["dialogue_window", "focused_project_anchor_pack"],
                omittedSections: ["evidence_pack"],
                contextRefsSelected: 1,
                contextRefsOmitted: 2,
                evidenceItemsSelected: 0,
                evidenceItemsOmitted: 4,
                budgetTotalTokens: nil,
                usedTotalTokens: nil,
                truncatedLayers: [],
                freshness: "fresh",
                cacheHit: false,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil,
                compressionPolicy: "balanced",
                remotePromptVariantLabel: "rescue",
                remotePromptMode: "minimal",
                remotePromptTokenEstimate: 220,
                remoteResponseTokenLimit: 36,
                remoteTotalTokenEstimate: 256,
                remoteSingleRequestBudget: 256,
                remoteSingleRequestBudgetSource: "paired_device_truth"
            )
        )

        let error = HubAIError.responseDoneNotOk(
            HubAIResponseFailureContext(
                reason: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew-MBP-XT;model_id=openai/gpt-5.4",
                deviceName: "Andrew-MBP-XT",
                modelId: "openai/gpt-5.4"
            )
        )

        let rendered = manager.renderSupervisorFailureResponse(
            error: error,
            userMessage: "继续"
        )

        #expect(rendered.contains("这次 paid model 请求超过了单次额度上限"))
        #expect(rendered.contains("当前设备真值：单次 256 tok · 当日 640 tok · 策略 全部付费模型"))
        #expect(rendered.contains("本轮远端 prompt：rescue 档 · 输入约 220 tokens · 输出上限 36 · 总量约 256 · 设备单次额度 256"))
        #expect(rendered.contains("缩小这次请求，或到 REL Flow Hub → Models & Paid Access 提升 single request token limit。"))
        #expect(!rendered.contains("device_single_request_token_exceeded"))
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
        #expect(rendered.contains("这条回复本身是本地直答，没有实际通过 Hub 调用模型"))
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
        #expect(rendered.contains("Supervisor 当前首选的模型路由是"))
        #expect(rendered.contains("openai/gpt-5.3-codex"))
        #expect(rendered.contains("这条回复本身是本地直答，没有实际通过 Hub 调用模型"))
        #expect(rendered.contains("不等于“这轮已经用了 GPT”"))
        #expect(rendered.contains("当前接管项目数：1"))
    }

    @Test
    func simpleGreetingUsesDeterministicLocalReply() throws {
        let manager = SupervisorManager.makeForTesting()

        let direct = try #require(manager.directSupervisorReplyIfApplicableForTesting("你好啊"))
        let preflight = try #require(manager.directSupervisorPreflightReplyIfApplicableForTesting("你好啊"))

        #expect(direct.contains("你好啊，我在。"))
        #expect(direct.contains("如果你想随便聊，我们就直接聊"))
        #expect(direct.contains("项目数：0"))
        #expect(preflight == direct)
        #expect(!direct.contains("高风险或不可逆的动作"))
        #expect(!direct.contains("项目治理流程"))
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

        #expect(rendered.contains("这条是本地直答，没有实际通过 Hub 调用模型"))
        #expect(rendered.contains("当前配置的 Supervisor 首选模型路由"))
        #expect(rendered.contains("openai/gpt-5.3-codex"))
        #expect(rendered.contains("当前验证状态"))
        #expect(rendered.contains("未验证。当前只能确认已配置好远端首选路由"))
        #expect(rendered.contains("最近一次真实调用记录"))
        #expect(rendered.contains("当前还没有可用的调用记录"))
        #expect(rendered.contains("会被 Supervisor 本地直答拦截"))
        #expect(rendered.contains("/hub route grpc"))
        #expect(rendered.contains("请用三句话总结当前项目状态，并给我两个下一步"))
    }

    @Test
    func supervisorLocalDirectActionDoesNotPretendHubLocalModelWasInvoked() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-local-direct-action-route-truth")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.3-codex"
        )
        appModel.registry = registry(
            with: [
                makeProjectEntry(
                    root: root,
                    displayName: "local-direct-action-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_direct_action",
            actualModelId: nil,
            requestedModelId: "openai/gpt-5.3-codex",
            failureReasonCode: nil
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("你现在是什么模型"))

        #expect(rendered.contains("最近一次回复属于本地直行动作路径，没有通过 Hub 的模型调用。"))
        #expect(rendered.contains("actual route=Local Control [local_direct_action]"))
        #expect(!rendered.contains("actual route=Hub (Local) [local_runtime]"))
    }

    @Test
    func supervisorLocalDirectActionDoesNotLeakPreviousRemoteFailureReason() throws {
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-local-direct-action-no-stale-failure")
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
                    displayName: "local-direct-action-no-stale-failure-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: nil,
            requestedModelId: "gpt-5.4",
            failureReasonCode: "device_single_request_token_exceeded"
        )
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_direct_action",
            actualModelId: nil,
            requestedModelId: "gpt-5.4",
            failureReasonCode: nil
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("你现在是什么模型"))

        #expect(rendered.contains("最近一次回复属于本地直行动作路径，没有通过 Hub 的模型调用。"))
        #expect(rendered.contains("actual route=Local Control [local_direct_action]"))
        #expect(!rendered.contains("device_single_request_token_exceeded"))
        #expect(!rendered.contains("当前请求超出了单次付费模型额度"))
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
        #expect(rendered.contains("最近一次 Supervisor 远端调用返回的实际模型 ID 是：openai/gpt-5.3-codex"))
        #expect(rendered.contains("actual route=Hub (Remote) -> openai/gpt-5.3-codex [remote_model]"))
        #expect(rendered.contains("这条回复本身仍然是本地直答"))
        #expect(rendered.contains("当前验证状态"))
        #expect(rendered.contains("已验证。最近一次可确认的远端实际模型 ID 是 openai/gpt-5.3-codex"))
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

        #expect(rendered.contains("没有拿到可确认的实际模型 ID"))
        #expect(rendered.contains("未验证成功"))
        #expect(!rendered.contains("最近一次可确认的远端实际模型 ID 是 gpt-5.4"))
        #expect(!rendered.contains("最近一次远端调用返回的实际模型 ID 是：gpt-5.4"))
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
        #expect(rendered.contains("actual route=Hub (Remote) -> qwen3-17b-mlx-bf16 [remote_model]"))
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
        #expect(rendered.contains("请求模型=openai/gpt-5-low"))
        #expect(rendered.contains("实际模型=qwen3-14b-mlx"))
        #expect(rendered.contains("configured route=openai/gpt-5-low"))
        #expect(rendered.contains("actual route=Hub (Local) -> qwen3-14b-mlx [local_fallback_after_remote_error]"))
        #expect(rendered.contains("fallback reason=目标模型当前不在可执行清单里（model_not_found）"))
        #expect(rendered.contains("当前原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(!rendered.contains("当前 reason=model_not_found"))
        #expect(rendered.contains("Supervisor 不读取 project override，也不使用 project route memory"))
        #expect(rendered.contains("/hub route grpc"))
    }

    @Test
    func remotePromptPreflightBlocksWhenRemoteLanIsBlockedAndLocalFallbackHubIsDegraded() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        XTHubLaunchStatusStore.installLoadOverrideForTesting { _ in
            XTHubLaunchStatusSnapshot(
                state: "DEGRADED_SERVING",
                degraded: XTHubLaunchStatusSnapshot.Degraded(
                    blockedCapabilities: ["ai.generate.paid", "web.fetch"],
                    isDegraded: true
                ),
                rootCause: XTHubLaunchStatusSnapshot.RootCause(
                    component: "bridge",
                    detail: "Bridge 心跳已过期或当前不可用",
                    errorCode: "XHUB_BRIDGE_UNAVAILABLE"
                )
            )
        }
        defer { XTHubLaunchStatusStore.installLoadOverrideForTesting(nil) }

        HubAIClient.setTransportMode(.auto)
        let manager = SupervisorManager.makeForTesting()
        let appModel = AppModel()
        appModel.hubConnected = true
        appModel.hubRemoteConnected = false
        appModel.hubSetupFailureCode = "local_network_discovery_blocked"
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
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
        manager.setAppModel(appModel)

        let block = try #require(
            manager.supervisorRemotePromptBlockForTesting(preferredModelId: "openai/gpt-5.4")
        )

        #expect(block.reasonCode == "local_network_discovery_blocked")
        #expect(block.responseText.contains("Supervisor 这轮先不继续空转"))
        #expect(block.responseText.contains("local_network_discovery_blocked"))
        #expect(block.responseText.contains("XHUB_BRIDGE_UNAVAILABLE"))
        #expect(block.responseText.contains("ai.generate.paid,web.fetch"))
        #expect(block.responseText.contains("Diagnostics & Recovery"))
    }

    @Test
    func routeDiagnoseReportsHubSideDowngradeToLocalForSupervisor() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }

        HubAIClient.setTransportMode(.grpc)
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-route-diagnose-hub-downgrade")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
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
                    displayName: "supervisor-route-diagnose-hub-downgrade-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "hub_downgraded_to_local",
            actualModelId: "qwen3-14b-mlx",
            requestedModelId: "openai/gpt-5.4",
            failureReasonCode: "downgrade_to_local",
            auditRef: "audit-route-7",
            denyCode: "remote_export_blocked"
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("/route diagnose"))

        #expect(rendered.contains("最近一次执行模式：hub_downgraded_to_local"))
        #expect(rendered.contains("请求模型=openai/gpt-5.4"))
        #expect(rendered.contains("实际模型=qwen3-14b-mlx"))
        #expect(rendered.contains("configured route=openai/gpt-5.4"))
        #expect(rendered.contains("actual route=Hub (Local) -> qwen3-14b-mlx [hub_downgraded_to_local]"))
        #expect(rendered.contains("fallback reason=Hub 端把远端请求降到本地（downgrade_to_local）"))
        #expect(rendered.contains("deny_code=Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("audit_ref=audit-route-7"))
        #expect(rendered.contains("grpc-only 提示：这更像 Hub 执行阶段 downgrade 或 export gate 生效"))
        #expect(rendered.contains("Hub 在执行阶段把远端请求降到了本地"))
        #expect(rendered.contains("ai.generate.downgraded_to_local"))
    }

    @Test
    func routeDiagnoseExplainsGrpcRemoteFailureAsUpstreamProblemForSupervisor() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }

        HubAIClient.setTransportMode(.grpc)
        let manager = SupervisorManager.makeForTesting()
        let root = try makeProjectRoot(named: "supervisor-route-diagnose-grpc-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            role: .supervisor,
            providerKind: .hub,
            model: "openai/gpt-5.4"
        )
        appModel.modelsState = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
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
                    displayName: "supervisor-route-diagnose-grpc-fallback-project",
                    blockerSummary: nil,
                    nextStepSummary: "继续推进"
                )
            ]
        )
        manager.setAppModel(appModel)
        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: "qwen3-14b-mlx",
            requestedModelId: "openai/gpt-5.4",
            failureReasonCode: "provider_not_ready"
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("/route diagnose"))

        #expect(rendered.contains("最近一次执行模式：local_fallback_after_remote_error"))
        #expect(rendered.contains("fallback reason=provider 尚未 ready（provider_not_ready）"))
        #expect(rendered.contains("grpc-only 提示：这更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成了本地。"))
        #expect(rendered.contains("更像上游远端不可用、provider 未 ready，或请求链在执行阶段失败后由本地兜底"))
        #expect(rendered.contains("下一步先看当前 fallback reason、Hub 链路和 provider ready"))
    }

    @Test
    func remoteFailureContextParsesAuditRefAndDenyCodeFromDoneNotOkReason() throws {
        let manager = SupervisorManager.makeForTesting()
        let failure = manager.supervisorRemoteFailureContextForTesting(
            reason: "grant_required;deny_code=remote_export_blocked;audit_ref=audit-route-failure-2;model_id=openai/gpt-5.4",
            preferredModelId: "openai/gpt-5.4"
        )

        #expect(failure.requestedModelId == "openai/gpt-5.4")
        #expect(failure.failureReasonCode == "grant_required")
        #expect(failure.denyCode == "remote_export_blocked")
        #expect(failure.auditRef == "audit-route-failure-2")

        manager.recordSupervisorReplyExecutionForTesting(
            mode: "local_fallback_after_remote_error",
            actualModelId: nil,
            requestedModelId: failure.requestedModelId,
            failureReasonCode: failure.failureReasonCode,
            auditRef: failure.auditRef,
            denyCode: failure.denyCode
        )

        let rendered = try #require(manager.directSupervisorReplyIfApplicableForTesting("/route diagnose"))
        #expect(rendered.contains("fallback reason=grant_required"))
        #expect(rendered.contains("deny_code=Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("audit_ref=audit-route-failure-2"))
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
                actualModelId: "qwen3-17b-mlx-bf16",
                requestedModelId: "openai/gpt-5-low",
                failureReasonCode: "remote_export_blocked",
                denyCode: "remote_export_blocked",
                auditRef: "audit-route-supervisor-mismatch-1",
                mode: "hub_downgraded_to_local"
            )
        )

        #expect(rendered.contains("已拒绝接受本次回复"))
        #expect(rendered.contains("openai/gpt-5-low"))
        #expect(rendered.contains("qwen3-17b-mlx-bf16"))
        #expect(rendered.contains("grpc-only"))
        #expect(rendered.contains("ai.generate.downgraded_to_local"))
        #expect(rendered.contains("fail-closed"))
        #expect(rendered.contains("执行证据 / route truth"))
        #expect(rendered.contains("- 请求模型=openai/gpt-5-low"))
        #expect(rendered.contains("- actual route=Hub (Local) -> qwen3-17b-mlx-bf16 [hub_downgraded_to_local]"))
        #expect(rendered.contains("- fallback reason=Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("- deny_code=Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("- audit_ref=audit-route-supervisor-mismatch-1"))
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
    func greetingTranscriptLeakFallsBackToLocalGreetingReply() {
        let manager = SupervisorManager.makeForTesting()
        let remote = """
你好啊。这是一条普通的问候语。我们需要检查是否有高风险或不可逆的动作。

- assistant: 根据当前项目治理流程，涉及项目状态的查询需先说明风险与后果。
"""

        let rendered = manager.sanitizedSupervisorRemoteResponseForTesting(
            remote,
            userMessage: "你好啊"
        )

        #expect(rendered.contains("你好啊，我在。"))
        #expect(rendered.contains("如果你想随便聊，我们就直接聊"))
        #expect(!rendered.contains("普通的问候语"))
        #expect(!rendered.contains("- assistant:"))
        #expect(!rendered.contains("项目治理流程"))
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
