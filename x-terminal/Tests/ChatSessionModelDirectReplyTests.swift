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
        #expect(rendered.contains("实际落到的模型 ID 是：qwen3-17b-mlx-bf16"))
        #expect(rendered.contains("实际落点：Hub (Local) -> qwen3-17b-mlx-bf16 [local_fallback_after_remote_error]"))
        #expect(rendered.contains("回落原因：目标模型当前不在可执行清单里（model_not_found）"))
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
            ),
            transportMode: .auto
        )

        #expect(rendered.contains("项目路由诊断：coder"))
        #expect(rendered.contains("配置来源：项目覆盖（当前项目单独配置）"))
        #expect(rendered.contains("全局对照："))
        #expect(rendered.contains("Project AI 全局分配：openai/gpt-5-low"))
        #expect(rendered.contains("Supervisor 全局分配：openai/gpt-5-low"))
        #expect(rendered.contains("关系说明：当前项目有项目覆盖；它会盖过 coder 全局分配 `openai/gpt-5-low`。Supervisor 仍只看自己的全局分配。"))
        #expect(rendered.contains("配置状态：Hub 候选列表已精确命中；当前会继续按远端执行尝试（远端，状态：可用未加载）。"))
        #expect(rendered.contains("当前决策：之前的本地锁已自动解除；当前按配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("路由记忆"))
        #expect(rendered.contains("最近连续远端回落：3"))
        #expect(rendered.contains("异常趋势：最近 3 次主要是 `model_not_found`"))
        #expect(rendered.contains("建议动作：先去 Supervisor Control Center · AI 模型确认目标模型已进入真实可执行列表"))
        #expect(rendered.contains("之前的本地锁已自动解除"))
        #expect(rendered.contains("提示：项目覆盖会优先于 coder 的全局分配；Supervisor 只看自己的全局分配"))
    }

    @Test
    func routeDiagnoseIncludesHubSupervisorRouteTruthWhenGrantPlaneBlocked() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-supervisor-grant")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        appendUsage(
            createdAt: now - 20,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let session = ChatSessionModel()
        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: LLMRouter(settingsStore: SettingsStore()),
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available)
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            supervisorRouteDecision: HubIPCClient.SupervisorRouteDecisionResult(
                ok: false,
                source: "hub_supervisor_grpc",
                route: HubIPCClient.SupervisorRouteDecisionSnapshot(
                    schemaVersion: "xhub.supervisor_route_decision.v1",
                    routeId: "route-test-1",
                    requestId: "req-test-1",
                    projectId: AXProjectRegistryStore.projectId(forRoot: root),
                    runId: "",
                    missionId: "",
                    decision: "fail_closed",
                    riskTier: "high",
                    preferredDeviceId: "xt-runner-01",
                    resolvedDeviceId: "xt-runner-01",
                    runnerId: "xt-runner-01",
                    xtOnline: true,
                    runnerRequired: true,
                    sameProjectScope: true,
                    requiresGrant: true,
                    grantScope: "project",
                    denyCode: "device_permission_owner_missing",
                    updatedAtMs: now * 1000,
                    auditRef: "audit-route-test-1"
                ),
                governanceRuntimeReadiness: HubIPCClient.SupervisorRouteGovernanceRuntimeReadinessSnapshot(
                    schemaVersion: "xhub.governance_runtime_readiness.v1",
                    source: "hub",
                    governanceSurface: "a4_agent",
                    context: "supervisor_route",
                    configured: true,
                    state: .blocked,
                    runtimeReady: false,
                    projectId: AXProjectRegistryStore.projectId(forRoot: root),
                    blockers: ["grant:device_permission_owner_missing"],
                    blockedComponentKeys: [.grantReady],
                    missingReasonCodes: ["permission_owner_not_ready"],
                    summaryLine: "A4 Agent runtime readiness 仍有缺口。",
                    missingSummaryLine: "缺口：权限宿主未就绪",
                    components: [
                        HubIPCClient.SupervisorRouteGovernanceComponentSnapshot(
                            key: .routeReady,
                            state: .ready,
                            denyCode: "",
                            summaryLine: "supervisor route ready: hub_to_runner",
                            missingReasonCodes: []
                        ),
                        HubIPCClient.SupervisorRouteGovernanceComponentSnapshot(
                            key: .grantReady,
                            state: .blocked,
                            denyCode: "device_permission_owner_missing",
                            summaryLine: "supervisor route governance blocked: device_permission_owner_missing",
                            missingReasonCodes: ["permission_owner_not_ready"]
                        )
                    ]
                ),
                reasonCode: "device_permission_owner_missing"
            ),
            transportMode: .grpc
        )

        #expect(rendered.contains("Supervisor 路由诊断："))
        #expect(rendered.contains("阻塞平面=grant_ready"))
        #expect(rendered.contains("deny code：当前 XT 绑定缺少 permission owner（device_permission_owner_missing）"))
        #expect(rendered.contains("治理判断：这更像是 Supervisor 的 grant / governance 面还没就绪。"))
        #expect(rendered.contains("grant plane：权限宿主未就绪"))
        #expect(rendered.contains("修复方向：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。"))
        #expect(rendered.contains("audit_ref=audit-route-test-1"))
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
            ),
            transportMode: .fileIPC
        )

        #expect(rendered.contains("配置状态：Hub 候选列表已精确命中；当前会继续按远端执行尝试（远端，状态：可用未加载）。"))
        #expect(rendered.contains("当前决策：按当前配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("判定："))
        #expect(rendered.contains("XT 当前传输模式是 fileIPC，所以这轮本来就不会强制走远端"))
        #expect(!rendered.contains("会先自动试上次稳定远端"))
    }

    @Test
    func sandboxSlashHumanizesDefaultRouteCopy() {
        let originalMode = ToolExecutor.sandboxMode()
        defer { ToolExecutor.setSandboxMode(originalMode) }
        ToolExecutor.setSandboxMode(.sandbox)

        let session = ChatSessionModel()
        let rendered = session.handleSlashSandboxForTesting(args: [])

        #expect(rendered.contains("工具执行路径："))
        #expect(rendered.contains("当前默认：沙箱环境（sandbox）"))
        #expect(rendered.contains("默认走沙箱环境"))
        #expect(!rendered.contains("Tool sandbox route:"))
        #expect(!rendered.contains("- mode:"))
    }

    @Test
    func memorySlashHumanizesCurrentSettingAndBehaviorCopy() {
        var config = AXProjectConfig.default(forProjectRoot: URL(fileURLWithPath: "/tmp/memory-copy"))
        config = config.settingHubMemoryPreference(enabled: false)

        let session = ChatSessionModel()
        let rendered = session.slashMemoryTextForTesting(config: config)

        #expect(rendered.contains("Memory 使用方式："))
        #expect(rendered.contains("当前设置：仅使用本地 Memory"))
        #expect(rendered.contains("默认设置：优先使用 Hub Memory"))
        #expect(rendered.contains("当前行为：只使用本地 `.xterminal/AX_MEMORY.md` 和 `recent_context.json`，这次不会读取 Hub Memory。"))
        #expect(rendered.contains("命令："))
        #expect(rendered.contains("/memory default          恢复默认使用方式（优先使用 Hub Memory）"))
        #expect(!rendered.contains("Memory 路由："))
        #expect(!rendered.contains("hub_preferred"))
        #expect(!rendered.contains("治理约束："))
    }

    @Test
    func memorySlashUsesUnifiedProjectConfigFailureCopy() {
        let session = ChatSessionModel()
        let ctx = AXProjectContext(root: URL(fileURLWithPath: "/dev/null"))
        let rendered = session.handleSlashMemoryForTesting(args: ["on"], ctx: ctx, config: nil)

        #expect(rendered == "无法读取当前项目配置，未修改。")
        #expect(!rendered.contains("project config"))
    }

    @Test
    func toolsSlashHumanizesProfileTokensAndEffectiveToolLabels() {
        var config = AXProjectConfig.default(forProjectRoot: URL(fileURLWithPath: "/tmp/tools-copy"))
        config = config.settingToolPolicy(
            profile: ToolProfile.coding.rawValue,
            allow: ["group:git"],
            deny: ["run_command"]
        )

        let session = ChatSessionModel()
        let rendered = session.slashToolsTextForTesting(config: config)

        #expect(rendered.contains("工具策略："))
        #expect(rendered.contains("当前档位：开发（coding）"))
        #expect(rendered.contains("额外放行：Git（group:git）"))
        #expect(rendered.contains("额外禁用：运行命令（run_command）"))
        #expect(rendered.contains("当前可直接调用："))
        #expect(rendered.contains("读取文件"))
        #expect(!rendered.contains("Tool policy:"))
        #expect(!rendered.contains("- profile:"))
        #expect(!rendered.contains("- allow:"))
        #expect(!rendered.contains("- effective tools:"))
    }

    @Test
    func guidanceSlashHumanizesTimingAndSummaryLabels() throws {
        let root = try makeProjectRoot(named: "guidance-copy-humanized")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-copy-1",
                reviewId: "review-copy-1",
                projectId: "proj-copy-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: """
收到，我会按《Release Runtime》这条指导继续推进：summary=先冻结 release runtime 范围，再补 source gate 证据。
verdict=watch
""",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_893_456_000_000,
                ackUpdatedAtMs: 0,
                expiresAtMs: 1_893_542_400_000,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 0,
                auditRef: "audit-guidance-copy-1"
            ),
            for: ctx
        )

        let session = ChatSessionModel()
        let rendered = session.handleSlashGuidanceForTesting(args: [], ctx: ctx)

        #expect(rendered.contains("Supervisor 指导："))
        #expect(rendered.contains("待确认指导："))
        #expect(rendered.contains("过期时间："))
        #expect(rendered.contains("下次重提：无"))
        #expect(rendered.contains("重提进度：未启用"))
        #expect(rendered.contains("指导摘要：先冻结 release runtime 范围，再补 source gate 证据。"))
        #expect(!rendered.contains("过期时间(ms)"))
        #expect(!rendered.contains("retry_at_ms"))
        #expect(!rendered.contains("guidance："))
        #expect(!rendered.contains("summary="))
    }

    @Test
    func guidanceAcceptWithoutNoteDoesNotLeakMachineDefaultNote() throws {
        let root = try makeProjectRoot(named: "guidance-copy-empty-note")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-empty-note-1",
                reviewId: "review-empty-note-1",
                projectId: "proj-empty-note-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextToolBoundary,
                guidanceText: "先看 blocker，再决定是否继续 patch。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_893_460_000_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-empty-note-1"
            ),
            for: ctx
        )

        let session = ChatSessionModel()
        let reply = session.handleSlashGuidanceForTesting(args: ["accept"], ctx: ctx)
        #expect(reply.contains("已更新指导确认"))

        let rendered = session.handleSlashGuidanceForTesting(args: [], ctx: ctx)
        let updated = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))

        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote.isEmpty)
        #expect(rendered.contains("确认备注：无"))
        #expect(!rendered.contains("manual_accept_from_slash_guidance"))
        #expect(!rendered.contains("manual_defer_from_slash_guidance"))
    }

    @Test
    func hubRouteSlashHumanizesCurrentModeAndBehaviorCopy() {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let session = ChatSessionModel()
        let rendered = session.slashHubRouteTextForTesting()

        #expect(rendered.contains("Hub 传输模式："))
        #expect(rendered.contains("当前模式：grpc"))
        #expect(rendered.contains("有远端 profile 时：只走远端；不再回落到本地"))
        #expect(rendered.contains("无远端 profile 时：直接失败并拦下"))
        #expect(!rendered.contains("remote only (no fallback)"))
        #expect(!rendered.contains("fail-closed ("))
    }

    @Test
    func hubRouteSelftestHumanizesCheckNamesAndDetails() {
        let session = ChatSessionModel()
        let rendered = session.slashHubRouteSelfTestTextForTesting()

        #expect(rendered.contains("Hub 路由自检：通过"))
        #expect(rendered.contains("[通过] auto 模式在有远端 profile 时优先走远端"))
        #expect(rendered.contains("auto 模式下如果存在远端 profile，会先走远端，并且保留 file IPC 回落。"))
        #expect(!rendered.contains("Hub route selftest:"))
        #expect(!rendered.contains("auto_remote_preferred"))
        #expect(!rendered.contains("remote first, file fallback allowed"))
    }

    @Test
    func grantFrontstageFormattingHumanizesRuntimeScanAndSelftestCopy() {
        let session = ChatSessionModel()

        let runtime = session.frontstageHighRiskGrantRuntimeStatusForTesting(
            """
            active grants:
            - grant=grant-123 capability=capability_web_fetch remaining=97s
            """
        )
        #expect(runtime.contains("当前有效授权："))
        #expect(runtime.contains("授权 ID：grant-123"))
        #expect(runtime.contains("能力：联网抓取（web_fetch）"))
        #expect(runtime.contains("剩余：97 秒"))
        #expect(!runtime.contains("grant="))

        let report = ToolExecutor.HighRiskGrantBypassScanReport(
            generatedAt: 1,
            scannedToolEvents: 8,
            webFetchEvents: 3,
            deniedEvents: 1,
            bypassCount: 1,
            findings: [
                ToolExecutor.HighRiskGrantBypassFinding(
                    id: "finding-1",
                    createdAt: 1,
                    action: "web_fetch",
                    detail: "bypass_grant_execution: web_fetch ok=true but input.grant_id is missing"
                )
            ]
        )
        let scan = session.frontstageHighRiskGrantBypassScanReportForTesting(report)
        #expect(scan.contains("高风险授权旁路扫描：发现风险"))
        #expect(scan.contains("联网抓取请求：3"))
        #expect(scan.contains("联网抓取请求已经执行成功，但输入里缺少 `grant_id`。"))
        #expect(!scan.contains("bypass_grant_execution"))

        let selftest = session.frontstageHighRiskGrantSelfTestSummaryForTesting(
            checks: [
                ToolExecutor.HighRiskGrantSelfCheck(
                    name: "registered grant is accepted",
                    ok: true,
                    detail: "state=valid"
                ),
                ToolExecutor.HighRiskGrantSelfCheck(
                    name: "expired grant is denied",
                    ok: false,
                    detail: "state=invalid"
                )
            ],
            scan: report
        )
        #expect(selftest.contains("高风险授权自检：失败 (1/2)"))
        #expect(selftest.contains("[通过] 已登记的授权会被接受：结果：有效"))
        #expect(selftest.contains("[失败] 过期授权会被拒绝：结果：无效"))
        #expect(!selftest.contains("state=valid"))
    }

    @Test
    func trustedAutomationStatusHumanizesStateAndIssueLabels() throws {
        let root = try makeProjectRoot(named: "trusted-automation-status-copy")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "paired-device-1",
            deviceToolGroups: ["device.browser.control"],
            workspaceBindingHash: "sha256:stale-binding"
        )

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeTrustedAutomationReadiness(
                automation: .missing,
                screenRecording: .granted,
                installState: "degraded",
                overallState: "partial",
                auditRef: "audit-ta-status-1"
            )
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let session = ChatSessionModel()
        let rendered = session.slashTrustedAutomationTextForTesting(config: config, ctx: ctx)

        #expect(rendered.contains("Trusted Automation："))
        #expect(rendered.contains("当前模式：Trusted Automation（设备级自动化）"))
        #expect(rendered.contains("当前状态：配置未完成，暂不可用"))
        #expect(rendered.contains("绑定设备：paired-device-1"))
        #expect(rendered.contains("工作区绑定：未匹配"))
        #expect(rendered.contains("权限宿主已就绪：否"))
        #expect(rendered.contains("需要权限：自动化"))
        #expect(rendered.contains("可直接打开的设置：自动化"))
        #expect(rendered.contains("仍缺少前提："))
        #expect(rendered.contains("当前工作区和绑定记录不一致"))
        #expect(rendered.contains("缺少权限：自动化"))
        #expect(!rendered.contains("trusted_automation_workspace_mismatch"))
        #expect(!rendered.contains("permission_automation_missing"))
    }

    @Test
    func trustedAutomationDoctorHumanizesPermissionAndOwnerLabels() throws {
        let root = try makeProjectRoot(named: "trusted-automation-doctor-copy")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "paired-device-2",
            deviceToolGroups: ["device.browser.control", "device.screen.capture"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: root)
        )

        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            makeTrustedAutomationReadiness(
                accessibility: .granted,
                automation: .missing,
                screenRecording: .granted,
                installState: "degraded",
                overallState: "partial",
                auditRef: "audit-ta-doctor-1"
            )
        }
        defer { AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting() }

        let session = ChatSessionModel()
        let rendered = session.slashTrustedAutomationDoctorTextForTesting(config: config, ctx: ctx)

        #expect(rendered.contains("Trusted Automation 自检："))
        #expect(rendered.contains("宿主类型：X-Terminal App"))
        #expect(rendered.contains("安装状态：安装位置不符合推荐"))
        #expect(rendered.contains("总体状态：部分就绪"))
        #expect(rendered.contains("可主动拉起授权：是"))
        #expect(rendered.contains("审计锚点：audit-ta-doctor-1"))
        #expect(rendered.contains("自动化：未授权 · 关联工具组：device.browser.control"))
        #expect(rendered.contains("屏幕录制：已授权 · 关联工具组：device.screen.capture"))
        #expect(rendered.contains("可直接打开的设置：自动化"))
        #expect(!rendered.contains("owner_type:"))
        #expect(!rendered.contains("overall_state:"))
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
            ),
            transportMode: .auto
        )

        #expect(rendered.contains("当前决策：之前的本地锁已自动解除；当前按配置继续尝试：openai/gpt-5.4"))
        #expect(rendered.contains("判定："))
        #expect(rendered.contains("之前的本地锁已自动解除"))
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

        #expect(rendered.contains("配置来源：全局角色分配"))
        #expect(rendered.contains("Project AI 全局分配：openai/gpt-5.4"))
        #expect(rendered.contains("Project AI 全局问题："))
        #expect(rendered.contains("Supervisor 全局分配：openai/gpt-5.4"))
        #expect(rendered.contains("Supervisor 全局问题："))
        #expect(rendered.contains("关系说明：Supervisor 和 project coder 的全局分配一致"))
    }

    @Test
    func routeDiagnoseSummarizesHubRecoveryTrendForRemoteExportBlocked() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-remote-export-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let store = SettingsStore()
        store.settings = store.settings.setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")
        store.settings = store.settings.setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")

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

        let router = LLMRouter(settingsStore: store)
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

        #expect(rendered.contains("执行路径：Hub 改派到本地（hub_downgraded_to_local）"))
        #expect(rendered.contains("原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("异常趋势：最近 2 次主要是 `remote_export_blocked`"))
        #expect(rendered.contains("建议动作：先去 Hub Recovery / Hub 审计看 `remote_export_blocked`"))
        #expect(rendered.contains("分叉解释：如果你看到 Supervisor 还能继续按 `openai/gpt-5.4` 尝试、但 project coder 这轮仍落到本地"))
        #expect(rendered.contains("项目提示词 / 记忆导出被 Hub remote export gate 挡住了"))
    }

    @Test
    func routeDiagnoseExplainsSupervisorVsProjectSplitForProjectLocalLock() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-supervisor-split-local-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        let store = SettingsStore()
        store.settings = store.settings.setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")
        store.settings = store.settings.setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")

        for offset in [60.0, 40.0, 20.0] {
            appendUsage(
                createdAt: now - offset,
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found",
                for: ctx
            )
        }

        let session = ChatSessionModel()
        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: nil,
            router: LLMRouter(settingsStore: store),
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .sleeping)
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            transportMode: .auto
        )

        #expect(rendered.contains("Project AI 全局分配：openai/gpt-5.4"))
        #expect(rendered.contains("Supervisor 全局分配：openai/gpt-5.4"))
        #expect(rendered.contains("分叉解释：如果你看到 Supervisor 还能继续按 `openai/gpt-5.4` 尝试、但 project coder 先落到本地"))
        #expect(rendered.contains("这个项目自己的项目级路由记忆 / 本地锁"))
        #expect(rendered.contains("Supervisor 不读取这份项目级记忆"))
    }

    @Test
    func routeDiagnoseUsesDenyCodeWhenFallbackReasonMissing() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-deny-only")
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
                "audit_ref": "audit-route-deny-only-1",
                "deny_code": "remote_export_blocked",
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
                "audit_ref": "audit-route-deny-only-2",
                "deny_code": "remote_export_blocked",
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
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 130
            )
        )

        #expect(rendered.contains("执行路径：Hub 改派到本地（hub_downgraded_to_local）"))
        #expect(rendered.contains("原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("- 配置目标：openai/gpt-5.4"))
        #expect(rendered.contains("- 实际落点：Hub (Local) -> qwen3-14b-mlx [hub_downgraded_to_local]"))
        #expect(rendered.contains("- 回落原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("- 路由状态：配置希望走远端，但 Hub export gate 直接把请求收回到了本地。"))
        #expect(rendered.contains("- 拒绝原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("审计锚点：audit-route-deny-only-2"))
        #expect(rendered.contains("Hub 审计锚点：审计锚点：audit-route-deny-only-2；拒绝原因：remote_export_blocked。去 Hub Recovery / Hub 审计优先查 `remote_export_blocked`。"))
        #expect(rendered.contains("异常趋势：最近 2 次主要是 `remote_export_blocked`"))
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
        #expect(rendered.contains("远端改试：openai/gpt-5.4 -> openai/gpt-4.1"))
        #expect(rendered.contains("最近一次 coder 真实记录"))
        #expect(rendered.contains("- 发生过远端改试：是"))
        #expect(rendered.contains("- 远端改试起点：openai/gpt-5.4"))
        #expect(rendered.contains("- 远端改试目标：openai/gpt-4.1"))
        #expect(rendered.contains("- 远端改试原因：目标模型当前不在可执行清单里（model_not_found）"))
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

        #expect(rendered.contains("- 配置目标：openai/gpt-5.4"))
        #expect(rendered.contains("- 实际落点：Hub (Local) -> qwen3-17b-mlx-bf16 [hub_downgraded_to_local]"))
        #expect(rendered.contains("- 回落原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"))
        #expect(rendered.contains("Hub 审计锚点：审计锚点：audit-route-789；拒绝原因：继续这个动作前，仍然需要先通过 Hub 授权。（grant_required）。去 Hub Recovery / Hub 审计优先查 `remote_export_blocked`。"))
        #expect(rendered.contains("- 审计锚点：audit-route-789"))
        #expect(rendered.contains("- 拒绝原因：grant_required"))
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
        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的实际模型 ID 是：openai/gpt-5.4"))
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
        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的实际模型 ID 是：openai/gpt-5.4"))
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

        #expect(rendered.contains("最近一次 Project AI / coder 真实调用返回的实际模型 ID 是：openai/gpt-5.4"))
        #expect(rendered.contains("实际落点：Hub (Remote) -> openai/gpt-5.4 [remote_model]"))
        #expect(rendered.contains("审计锚点：audit:project-remote-hit-1"))
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
        #expect(message.contains("执行证据 / 路由真相"))
        #expect(message.contains("- 实际落点：Hub (Local) -> qwen3-17b-mlx-bf16 [local_fallback_after_remote_error]"))
        #expect(message.contains("- 回落原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(message.contains("- 路由状态：远端尝试没有稳定成功，当前先由本地接住；更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成本地。"))
        #expect(message.contains("- 审计锚点：audit:project-mismatch-1"))
        #expect(message.contains("- 拒绝原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(message.contains("到 Supervisor Control Center · AI 模型确认 openai/gpt-5.4 已真正可执行"))
    }

    @Test
    func strictProjectMismatchFailClosedUsesDenyCodeWhenFallbackReasonMissing() throws {
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
                fallbackReasonCode: nil,
                auditRef: "audit:project-mismatch-deny-only-1",
                denyCode: "model_not_found"
            )
        )

        let message = try #require(rendered)
        #expect(message.contains("远端目标模型没有真正命中，随后回复被本地兜底运行时接管"))
        #expect(message.contains("- 回落原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(message.contains("- 审计锚点：audit:project-mismatch-deny-only-1"))
        #expect(message.contains("- 拒绝原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(message.contains("到 Supervisor Control Center · AI 模型确认 openai/gpt-5.4 已真正可执行"))
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
        #expect(message.contains("被项目路由记忆强制切到了本地执行"))
        #expect(message.contains("当前本地目标：qwen3-32b-mlx"))
        #expect(message.contains("在当前项目运行 `/route diagnose`"))
        #expect(message.contains("重新 `/model openai/gpt-5.4` 或 `/model auto` 再重试"))
    }

    @Test
    func grpcProjectRouteDecisionPreservesConfiguredModelInsteadOfProjectMemoryOverrides() throws {
        let root = try makeProjectRoot(named: "grpc-project-route-preserves-configured")
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
            createdAt: 220,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: 240,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        let session = ChatSessionModel()
        let decision = session.effectiveProjectRouteDecisionForTesting(
            configuredModelId: "openai/gpt-5.4",
            role: .coder,
            ctx: ctx,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .sleeping)
                ],
                updatedAt: 300
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "qwen3-14b-mlx",
                        name: "Qwen 3 14B",
                        state: .loaded,
                        backend: "mlx",
                        modelPath: "/models/qwen3"
                    )
                ],
                updatedAt: 300
            ),
            transportMode: .grpc
        )

        #expect(decision.preferredModelId == "openai/gpt-5.4")
        #expect(!decision.usedRememberedRemoteModel)
        #expect(!decision.forceLocalExecution)
        #expect(decision.reasonCode == "grpc_preserve_configured_model")
    }

    @Test
    func modelsSlashExplainsGrpcPreserveConfiguredModelInsteadOfProjectLocalLock() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let root = try makeProjectRoot(named: "grpc-project-models-preserve-configured")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        appendUsage(
            createdAt: now - 180,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 120,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 60,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
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
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: 300
            ),
            routeDecisionSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available)
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

        #expect(rendered.contains("路由状态：当前传输模式是 grpc-only；XT 会保留你配置的 `openai/gpt-5.4` 继续发起远端验证"))
        #expect(!rendered.contains("当前项目已锁定为本地模式"))
        #expect(!rendered.contains("会先自动试上次稳定远端"))
    }

    @Test
    func routeDiagnoseExplainsGrpcPreserveConfiguredModelInsteadOfProjectLocalLock() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let root = try makeProjectRoot(named: "grpc-project-route-diagnose-preserve-configured")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        appendUsage(
            createdAt: now - 180,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 120,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )
        appendUsage(
            createdAt: now - 60,
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "model_not_found",
            for: ctx
        )

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let session = ChatSessionModel()
        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: LLMRouter(settingsStore: SettingsStore()),
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available)
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

        #expect(rendered.contains("当前决策：当前传输模式是 grpc-only；XT 会保留配置的远端模型继续验证：openai/gpt-5.4"))
        #expect(rendered.contains("XT 当前处于 grpc-only 验证模式；这轮会继续按 `openai/gpt-5.4` 发起远端请求，不再让项目级本地锁或上次稳定远端抢路由。"))
        #expect(!rendered.contains("XT 当前仍会优先走本地"))
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
    func routeDiagnosePresentationAppendsAssistantOnlyWithoutPersistingConversation() throws {
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
        session.presentProjectRouteDiagnosisForTesting(
            ctx: ctx,
            config: nil,
            router: LLMRouter(settingsStore: SettingsStore()),
            routeSnapshot: .empty(),
            localSnapshot: .empty()
        )

        #expect(session.messages.count == 1)
        #expect(session.messages.first?.role == .assistant)
        #expect(session.messages.first?.tag == nil)
        #expect(session.messages.first?.content.contains("项目路由诊断：coder") == true)

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

        #expect(rendered.contains("状态：Hub 候选列表已精确命中；当前会继续按远端执行尝试（远端，状态：可用未加载）。"))
        #expect(rendered.contains("上次稳定远端模型：openai/gpt-4.1"))
        #expect(rendered.contains("默认加载配置：ctx 128000"))
        #expect(rendered.contains("本地加载上限：ctx 128000"))
        #expect(!rendered.contains("当前项目已锁定为本地模式"))
        #expect(!rendered.contains("会先自动试上次稳定远端"))
    }

    @Test
    func modelsSlashExplainsBrokenLocalCandidatePathAsNonRunnable() throws {
        let root = try makeProjectRoot(named: "project-slash-models-broken-local-path")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "qwen3-1.7b-mlx")

        let session = ChatSessionModel()
        let rendered = session.slashModelsTextForTesting(
            ctx: ctx,
            config: config,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "qwen3-1.7b-mlx",
                        name: "Qwen 3 1.7B",
                        state: .available,
                        backend: "mlx",
                        modelPath: "/models/qwen3-1.7b",
                        offlineReady: false
                    )
                ],
                updatedAt: 300
            )
        )

        #expect(rendered.contains("状态：已配置，但Hub 记录的本地 modelPath 当前已失效；这个候选现在不能自动加载。"))
        #expect(rendered.contains("Hub 候选列表："))
        #expect(rendered.contains("Qwen 3 1.7B · qwen3-1.7b-mlx · 本地路径失效，当前不可执行"))
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
            ),
            transportMode: .auto
        )

        #expect(rendered.contains("路由状态：之前因连续回落触发的本地锁已自动解除；`openai/gpt-5.4` 现在恢复可执行。"))
        #expect(rendered.contains("Hub 已加载模型："))
        #expect(rendered.contains("默认加载配置：ctx 128000"))
        #expect(rendered.contains("本地加载上限：ctx 128000"))
        #expect(!rendered.contains("当前项目已锁定为本地模式"))
    }

    @Test
    func projectRouteFailureReasonTextHumanizesCompositePaidModelReason() {
        let session = ChatSessionModel()
        let rendered = session.projectRouteFailureReasonTextForTesting(
            "grant_required;deny_code=device_paid_model_not_allowed"
        )

        #expect(rendered == "当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）")
    }

    @Test
    func projectExecutionSummaryHumanizesHubDowngradeReason() {
        let session = ChatSessionModel()
        let rendered = session.projectExecutionSummaryForTesting(
            configuredModelId: "openai/gpt-5.4",
            snapshot: AXRoleExecutionSnapshot(
                role: .coder,
                updatedAt: 1,
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "hub_downgraded_to_local",
                fallbackReasonCode: "grant_required;deny_code=device_paid_model_not_allowed",
                auditRef: "",
                denyCode: "",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: "",
                source: "usage"
            )
        )

        #expect(rendered.contains("原因：当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）"))
        #expect(!rendered.contains("reason=grant_required;deny_code=device_paid_model_not_allowed"))
    }

    @Test
    func projectExecutionDisclosureNoteHumanizesFallbackReason() {
        let session = ChatSessionModel()
        let rendered = session.projectExecutionDisclosureNoteForTesting(
            configuredModelId: "openai/gpt-5.4",
            snapshot: AXRoleExecutionSnapshot(
                role: .coder,
                updatedAt: 1,
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "provider_not_ready",
                auditRef: "",
                denyCode: "",
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: "",
                source: "usage"
            )
        )

        #expect(rendered == "本轮远端失败后由本地 qwen3-14b-mlx 兜底。原因：provider 尚未 ready（provider_not_ready）。")
    }

    @Test
    func projectExecutionSummaryHumanizesRetryAndFallbackReasonLabels() {
        let session = ChatSessionModel()
        let rendered = session.projectExecutionSummaryForTesting(
            configuredModelId: "openai/gpt-5.4",
            snapshot: AXRoleExecutionSnapshot(
                role: .coder,
                updatedAt: 1,
                stage: "chat_plan",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                runtimeProvider: "Hub (Local)",
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "model_not_found",
                auditRef: "",
                denyCode: "",
                remoteRetryAttempted: true,
                remoteRetryFromModelId: "openai/gpt-5.4",
                remoteRetryToModelId: "openai/gpt-5.4-mini",
                remoteRetryReasonCode: "remote_timeout",
                source: "usage"
            )
        )

        #expect(rendered.contains("远端改试原因："))
        #expect(rendered.contains("本地兜底原因：目标模型当前不在可执行清单里（model_not_found）"))
        #expect(!rendered.contains("retry_reason="))
        #expect(!rendered.contains("fallback_reason="))
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
    func modelSlashUnavailableWarningExplainsGrpcRouteTruthInsteadOfSilentLocalRewrite() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let root = try makeProjectRoot(named: "project-slash-model-grpc-warning")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let session = ChatSessionModel()
        let reply = session.handleSlashModelForTesting(
            args: ["openai/gpt-5.4"],
            userText: "/model openai/gpt-5.4",
            ctx: ctx,
            config: nil,
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT-5.4", state: .sleeping, backend: "openai")
                ],
                updatedAt: 1_776_401_000
            )
        )

        #expect(reply.contains("未修改当前 coder 模型配置。"))
        #expect(reply.contains("当前还不能直接执行"))
        #expect(reply.contains("当前传输模式是 grpc-only"))
        #expect(reply.contains("不是 XT 静默改成本地"))
    }

    @Test
    func routeDiagnoseHumanizesLocalLockDecisionReasonAndRouteMemoryFailure() throws {
        let root = try makeProjectRoot(named: "project-route-diagnose-paid-model-local-lock")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let now = Date().timeIntervalSince1970

        for offset in [60.0, 40.0, 20.0] {
            appendUsage(
                createdAt: now - offset,
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "qwen3-14b-mlx",
                executionPath: "local_fallback_after_remote_error",
                fallbackReasonCode: "grant_required;deny_code=device_paid_model_not_allowed",
                for: ctx
            )
        }

        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")

        let session = ChatSessionModel()
        let rendered = session.projectRouteDiagnosisTextForTesting(
            ctx: ctx,
            config: config,
            router: LLMRouter(settingsStore: SettingsStore()),
            routeSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .sleeping),
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "qwen3-14b-mlx", name: "Qwen 3 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
                ],
                updatedAt: now
            ),
            transportMode: .auto
        )

        #expect(rendered.contains("最近失败原因：当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）"))
        #expect(!rendered.contains("最近失败原因：grant_required;deny_code=device_paid_model_not_allowed"))
    }

    @Test
    func projectRouteDecisionSummaryHumanizesLocalLockReasonCode() {
        let session = ChatSessionModel()
        let rendered = session.projectRouteDecisionSummaryForTesting(
            AXProjectPreferredModelRouteDecision(
                preferredModelId: "qwen3-14b-mlx",
                configuredModelId: "openai/gpt-5.4",
                rememberedRemoteModelId: nil,
                preferredLocalModelId: "qwen3-14b-mlx",
                usedRememberedRemoteModel: false,
                forceLocalExecution: true,
                reasonCode: "project_remote_fallback_lock_local_recent_actual"
            ),
            transport: .auto
        )

        #expect(rendered.contains("XT 当前会先锁本地：qwen3-14b-mlx"))
        #expect(rendered.contains("原因：当前配置和上次稳定远端都还不能直接执行，XT 暂时沿用最近本地接管结果（project_remote_fallback_lock_local_recent_actual）"))
        #expect(!rendered.contains("，reason=project_remote_fallback_lock_local_recent_actual"))
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

    @Test
    func importContinuationApplyToDraftKeepsUserDraftAndClearsContinuation() throws {
        let root = try makeProjectRoot(named: "attachment-import-continuation-apply")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let externalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_external_apply_\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)

        let externalFile = externalRoot.appendingPathComponent("Worker.swift")
        try Data("struct Worker {}".utf8).write(to: externalFile, options: .atomic)

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx)
        session.handleDroppedFiles([externalFile], ctx: ctx)
        session.importAllExternalDraftAttachments(ctx: ctx)

        let continuation = try #require(session.importContinuation)
        let importedAttachment = try #require(session.draftAttachments.first)

        #expect(importedAttachment.scope == .projectWorkspace)
        #expect(importedAttachment.relativePath?.hasPrefix("Imported Attachments/") == true)

        session.draft = "请先看下这个文件该怎么接入当前项目。"
        session.applyImportContinuationToDraft()

        #expect(session.draft == "请先看下这个文件该怎么接入当前项目。")
        #expect(session.importContinuation == nil)
        #expect(session.draftAttachments == [importedAttachment])
        #expect(!continuation.suggestedPrompt.isEmpty)
    }

    @Test
    func importContinuationSendKeepsImportedAttachmentAndUsesOnlyUserDraft() throws {
        let root = try makeProjectRoot(named: "attachment-import-continuation-send")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let externalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_external_send_\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)

        let externalFile = externalRoot.appendingPathComponent("Guide.md")
        try Data("# imported guide".utf8).write(to: externalFile, options: .atomic)

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx)
        session.handleDroppedFiles([externalFile], ctx: ctx)
        session.importAllExternalDraftAttachments(ctx: ctx)

        let continuation = try #require(session.importContinuation)
        let importedAttachment = try #require(session.draftAttachments.first)

        session.draft = "你现在是什么模型"
        session.dismissImportContinuation()
        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: LLMRouter(settingsStore: SettingsStore())
        )

        let userTurn = try #require(session.messages.last(where: { $0.role == .user }))
        #expect(userTurn.content == "你现在是什么模型")
        #expect(!userTurn.content.contains(continuation.suggestedPrompt))
        #expect(userTurn.attachments == [importedAttachment])
        #expect(session.draft.isEmpty)
        #expect(session.draftAttachments.isEmpty)
        #expect(session.importContinuation == nil)
        #expect(session.isSending == false)
        #expect(session.messages.last?.role == .assistant)
        #expect(session.messages.last?.content.contains("这条回复本身是本地直答") == true)
    }

    @Test
    func sendWithAttachmentsOnlyUsesAttachmentPromptAndPersistsTurn() async throws {
        let root = try makeProjectRoot(named: "attachment-send-requires-user-draft")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let externalRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_external_only_\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: externalRoot) }
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)

        let externalFile = externalRoot.appendingPathComponent("Notes.txt")
        try Data("todo".utf8).write(to: externalFile, options: .atomic)

        let session = ChatSessionModel()
        session.ensureLoaded(ctx: ctx)
        session.handleDroppedFiles([externalFile], ctx: ctx)
        ChatSessionModel.installLLMGenerateOverrideForTesting { _, prompt, _ in
            #expect(prompt.contains("请先阅读并理解我附带的文件。"))
            return "{\"final\":\"已阅读附件。\"}"
        }
        defer { ChatSessionModel.resetLLMGenerateOverrideForTesting() }

        session.send(
            ctx: ctx,
            memory: nil,
            config: AXProjectConfig.default(forProjectRoot: root),
            router: LLMRouter(settingsStore: SettingsStore())
        )

        try await waitUntil(timeoutMs: 2_000) {
            session.isSending == false && session.messages.last?.role == .assistant
        }

        let userTurn = try #require(session.messages.first(where: { $0.role == .user }))
        #expect(userTurn.content == "请先阅读并理解我附带的文件。")
        #expect(userTurn.attachments.count == 1)
        #expect(session.messages.last?.content.contains("已阅读附件") == true)
        #expect(session.draft.isEmpty)
        #expect(session.draftAttachments.isEmpty)
        #expect(session.importContinuation == nil)
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "xt_chat_direct_reply_\(name)_\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeTrustedAutomationReadiness(
        accessibility: AXTrustedAutomationPermissionStatus = .granted,
        automation: AXTrustedAutomationPermissionStatus = .granted,
        screenRecording: AXTrustedAutomationPermissionStatus = .missing,
        fullDiskAccess: AXTrustedAutomationPermissionStatus = .missing,
        inputMonitoring: AXTrustedAutomationPermissionStatus = .missing,
        installState: String = "ready",
        overallState: String = "ready",
        canPromptUser: Bool = true,
        managedByMDM: Bool = false,
        auditRef: String = "audit-ta-test"
    ) -> AXTrustedAutomationPermissionOwnerReadiness {
        AXTrustedAutomationPermissionOwnerReadiness(
            schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
            ownerID: "local_owner",
            ownerType: "xterminal_app",
            bundleID: "com.xterminal.app",
            installState: installState,
            mode: "managed_or_prompted",
            accessibility: accessibility,
            automation: automation,
            screenRecording: screenRecording,
            fullDiskAccess: fullDiskAccess,
            inputMonitoring: inputMonitoring,
            canPromptUser: canPromptUser,
            managedByMDM: managedByMDM,
            overallState: overallState,
            openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map(\.openSettingsAction),
            auditRef: auditRef
        )
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil,
        offlineReady: Bool? = nil,
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
            taskKinds: taskKinds,
            offlineReady: offlineReady
        )
    }

    private func appendUsage(
        createdAt: Double,
        requestedModelId: String,
        actualModelId: String,
        executionPath: String,
        fallbackReasonCode: String,
        for ctx: AXProjectContext
    ) {
        AXProjectStore.appendUsage(
            [
                "type": "ai_usage",
                "created_at": createdAt,
                "role": AXRole.coder.rawValue,
                "requested_model_id": requestedModelId,
                "actual_model_id": actualModelId,
                "execution_path": executionPath,
                "fallback_reason_code": fallbackReasonCode
            ],
            for: ctx
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
