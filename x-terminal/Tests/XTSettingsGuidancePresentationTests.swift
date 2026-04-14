import Foundation
import Testing
@testable import XTerminal

struct XTSettingsGuidancePresentationTests {

    @Test
    func tightenedPrivacyModeClampsRecentRawContextCeilingToStandardOrLower() {
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.autoMax) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.extended40Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.deep20Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.standard12Pairs) == .standard12Pairs)
        #expect(XTPrivacyMode.tightenedContext.effectiveRecentRawContextProfile(.floor8Pairs) == .floor8Pairs)
    }

    @Test
    func modelGuidanceSummarizesLoadedInteractiveAndSupportModels() {
        let presentation = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded),
                    makeModel(
                        id: "qwen3-14b-mlx",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/qwen3"
                    ),
                    makeModel(
                        id: "mlx-community/qwen3-embedding-0.6b-4bit",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/embedding",
                        taskKinds: ["embedding"]
                    )
                ],
                updatedAt: 42
            )
        )

        #expect(presentation.inventorySummary.contains("远端对话 1 个"))
        #expect(presentation.inventorySummary.contains("本地对话 1 个"))
        #expect(presentation.inventorySummary.contains("辅助模型 1 个"))
        #expect(presentation.items.contains(where: { $0.id == "coder" }))
        #expect(presentation.items.contains(where: { $0.id == "supervisor" }))
        #expect(presentation.items.contains(where: { $0.id == "support_models" }))
    }

    @Test
    func modelGuidanceTreatsLocalOnlyPostureAsHealthyButExplainable() {
        let presentation = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(
                        id: "qwen3-14b-mlx",
                        backend: "mlx",
                        state: .loaded,
                        modelPath: "/models/qwen3"
                    )
                ],
                updatedAt: 42
            )
        )

        #expect(presentation.inventorySummary.contains("纯本地"))
        #expect(presentation.items.contains(where: { $0.id == "local_only_ready" }))
        #expect(presentation.items.contains(where: { $0.detail.contains("不配置云 provider / API key") }))
    }

    @Test
    func modelGuidanceAppendsRecentGrpcRouteTruthHintForCurrentProject() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let ctx = AXProjectContext(root: root)
        try FileManager.default.createDirectory(at: ctx.xterminalDir, withIntermediateDirectories: true)

        let usageLine = """
        {"type":"ai_usage","role":"coder","created_at":42,"stage":"reply","requested_model_id":"openai/gpt-5.4","actual_model_id":"qwen3-14b-mlx","runtime_provider":"Hub (Local)","execution_path":"local_fallback_after_remote_error","fallback_reason_code":"provider_not_ready","audit_ref":"audit-guidance-1"}
        """
        try Data((usageLine + "\n").utf8).write(to: ctx.usageLogURL)

        let presentation = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", backend: "openai", state: .available)
                ],
                updatedAt: 42
            ),
            currentProjectName: "Alpha",
            currentProjectContext: ctx,
            currentProjectCoderModelId: "openai/gpt-5.4"
        )

        let hint = try #require(presentation.routeMemoryHint)
        #expect(hint.contains("当前项目 Alpha："))
        #expect(hint.contains("最近一次 route truth"))
        #expect(hint.contains("provider 未 ready"))
    }

    @Test
    func modelGuidanceCanCarryPairedDeviceBudgetTruthIntoRouteMemoryHint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ctx = AXProjectContext(root: root)
        try FileManager.default.createDirectory(at: ctx.xterminalDir, withIntermediateDirectories: true)

        let usageLine = """
        {"type":"ai_usage","role":"coder","created_at":42,"stage":"reply","requested_model_id":"openai/gpt-5.4","actual_model_id":"qwen3-14b-mlx","runtime_provider":"Hub (Local)","execution_path":"local_fallback_after_remote_error","fallback_reason_code":"device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4","audit_ref":"audit-guidance-paid-1"}
        """
        try Data((usageLine + "\n").utf8).write(to: ctx.usageLogURL)

        let presentation = XTModelGuidancePresentation.build(
            settings: .default(),
            snapshot: ModelStateSnapshot(
                models: [
                    makeModel(id: "openai/gpt-5.4", backend: "openai", state: .sleeping)
                ],
                updatedAt: 42
            ),
            currentProjectName: "Budgeted",
            currentProjectContext: ctx,
            currentProjectCoderModelId: "openai/gpt-5.4",
            currentRemotePaidAccessSnapshot: HubRemotePaidAccessSnapshot(
                trustProfilePresent: true,
                paidModelPolicyMode: "all_paid_models",
                dailyTokenLimit: 640,
                singleRequestTokenLimit: 256
            )
        )

        let hint = try #require(presentation.routeMemoryHint)
        #expect(hint.contains("当前设备真值：单次 256 tok · 当日 640 tok · 策略 全部付费模型。"))
    }

    @Test
    func securityRuntimeGuidanceExplainsSandboxAutomationAndPrivacy() {
        let presentation = XTSecurityRuntimeGuidancePresentation.build(
            sandboxMode: .sandbox,
            workMode: .governedAutomation,
            privacyMode: .tightenedContext
        )

        let rendered = presentation.items
            .map { "\($0.title): \($0.detail)" }
            .joined(separator: "\n")

        #expect(rendered.contains("当前默认走沙箱执行"))
        #expect(rendered.contains("项目聊天里的会话开关"))
        #expect(rendered.contains("A-tier、S-tier、授权和运行时状态都允许"))
        #expect(rendered.contains("收紧模式"))
    }

    @Test
    func recentRawContextNoticeExplainsEffectiveClampWhenPrivacyIsTightened() {
        let notice = XTSettingsChangeNoticeBuilder.supervisorRecentRawContext(
            profile: .extended40Pairs,
            privacyMode: .tightenedContext
        )

        #expect(notice.title == "最近原始上下文已更新")
        #expect(notice.detail.contains("Extended"))
        #expect(notice.detail.contains("Standard"))
        #expect(notice.detail.contains("实际按"))
    }

    @Test
    func sandboxModeNoticeExplainsGuardrails() {
        let notice = XTSettingsChangeNoticeBuilder.defaultToolSandboxMode(.sandbox)

        #expect(notice.title == "默认工具路径已更新")
        #expect(notice.detail.contains("沙箱"))
        #expect(notice.detail.contains("项目授权和运行时状态约束"))
    }

    @Test
    func globalRoleModelNoticeConfirmsLoadedInteractiveModel() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .coder,
            modelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(notice.title == "\(AXRole.coder.displayName) 模型已更新")
        #expect(notice.detail.contains("已加载"))
        #expect(notice.detail.contains("远端模型"))
    }

    @Test
    func globalRoleModelNoticeWarnsWhenModelIsMissingFromInventory() {
        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .supervisor,
            modelId: "openai/gpt-5.9",
            snapshot: .empty()
        )

        #expect(notice.title == "\(AXRole.supervisor.displayName) 模型已更新")
        #expect(notice.detail.contains("没有精确匹配"))
        #expect(notice.detail.contains("刷新模型列表"))
    }

    @Test
    func globalRoleModelNoticePointsUnavailableModelToSupervisorControlCenter() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .available)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .coder,
            modelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(notice.detail.contains("Supervisor Control Center · AI 模型"))
        #expect(notice.detail.contains("真实可执行列表"))
    }

    @Test
    func globalRoleModelNoticeExplainsRecentGrpcHubSideDowngrade() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .available)
            ],
            updatedAt: 42
        )
        let executionSnapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-settings-notice-1",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .coder,
            modelId: "openai/gpt-5.4",
            snapshot: snapshot,
            executionSnapshot: executionSnapshot,
            transportMode: "grpc",
            language: .defaultPreference
        )

        #expect(notice.detail.contains("当前 transport 是 grpc-only"))
        #expect(notice.detail.contains("最近一次 route truth"))
        #expect(notice.detail.contains("Hub 执行阶段降级或 export gate 生效"))
    }

    @Test
    func globalRoleModelNoticeRendersInEnglish() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.globalRoleModel(
            role: .coder,
            modelId: "openai/gpt-5.4",
            snapshot: snapshot,
            language: .english
        )

        #expect(notice.title == "Coder Model Updated")
        #expect(notice.detail.contains("Set the default model for Coder"))
        #expect(notice.detail.contains("remote"))
    }

    @Test
    func projectRoleModelNoticeExplainsInheritedGlobalWhenOverrideIsCleared() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: "Alpha",
            role: .coder,
            modelId: nil,
            inheritedModelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(notice.title == "项目模型已更新")
        #expect(notice.detail.contains("已清空 Alpha 的 \(AXRole.coder.displayName) 项目覆盖"))
        #expect(notice.detail.contains("回到全局模型"))
        #expect(notice.detail.contains("已加载"))
    }

    @Test
    func projectRoleModelNoticeRendersInEnglish() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: "Alpha",
            role: .coder,
            modelId: nil,
            inheritedModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            language: .english
        )

        #expect(notice.title == "Project Model Updated")
        #expect(notice.detail.contains("Cleared the project override for Coder in Alpha"))
        #expect(notice.detail.contains("global model `openai/gpt-5.4`"))
    }

    @Test
    func projectRoleModelNoticeExplainsRecentGrpcUpstreamIssueInEnglish() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .available)
            ],
            updatedAt: 42
        )
        let executionSnapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-settings-notice-2",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModel(
            projectName: "Alpha",
            role: .coder,
            modelId: "openai/gpt-5.4",
            inheritedModelId: nil,
            snapshot: snapshot,
            executionSnapshot: executionSnapshot,
            transportMode: "grpc_only",
            language: .english
        )

        #expect(notice.detail.contains("The current transport is grpc-only"))
        #expect(notice.detail.contains("latest route truth still landed on local"))
        #expect(notice.detail.contains("provider readiness"))
    }

    @Test
    func projectRoleModelBatchNoticeSummarizesChangedProjectCount() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModelBatch(
            role: .reviewer,
            modelId: "openai/gpt-5.4",
            changedProjectCount: 2,
            totalProjectCount: 5,
            snapshot: snapshot
        )

        #expect(notice.title == "批量应用已完成")
        #expect(notice.detail.contains("2/5"))
        #expect(notice.detail.contains("openai/gpt-5.4"))
        #expect(notice.detail.contains("已加载"))
    }

    @Test
    func projectRoleModelBatchNoticeRendersInEnglish() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", backend: "openai", state: .loaded)
            ],
            updatedAt: 42
        )

        let notice = XTSettingsChangeNoticeBuilder.projectRoleModelBatch(
            role: .reviewer,
            modelId: "openai/gpt-5.4",
            changedProjectCount: 2,
            totalProjectCount: 5,
            snapshot: snapshot,
            language: .english
        )

        #expect(notice.title == "Batch Apply Complete")
        #expect(notice.detail.contains("Reviewer"))
        #expect(notice.detail.contains("2/5"))
        #expect(notice.detail.contains("openai/gpt-5.4"))
    }

    @Test
    func globalAssignmentIssueRendersInEnglish() throws {
        let issue = try #require(
            HubModelSelectionAdvisor.globalAssignmentIssue(
                for: .supervisor,
                configuredModelId: "openai/gpt-5.4",
                snapshot: ModelStateSnapshot(
                    models: [
                        makeModel(id: "openai/gpt-5.4", backend: "openai", state: .available),
                        makeModel(id: "openai/gpt-4.1", backend: "openai", state: .loaded)
                    ],
                    updatedAt: 42
                ),
                language: .english
            )
        )

        #expect(issue.message.contains("Supervisor is currently set to `openai/gpt-5.4`"))
        #expect(issue.message.contains("Available, Not Loaded"))
        #expect(issue.message.contains("openai/gpt-4.1"))
    }

    private func makeModel(
        id: String,
        backend: String,
        state: HubModelState,
        modelPath: String? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: id,
            backend: backend,
            quant: "bf16",
            contextLength: 8_192,
            paramsB: 14,
            state: state,
            modelPath: modelPath,
            taskKinds: taskKinds
        )
    }
}
