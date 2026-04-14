import Foundation
import Testing
@testable import XTerminal

struct HubModelRoutingTruthBuilderTests {
    @Test
    func projectScopeTruthExplainsProjectOverrideAndObservedFallback() {
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5-low")
        let projectConfig = AXProjectConfig.default(
            forProjectRoot: URL(fileURLWithPath: "/tmp/hub-model-routing-truth-project-alpha", isDirectory: true)
        )
        .settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-project-scope-1",
            denyCode: "device_remote_export_denied",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .coder,
            selectedProjectID: "project-alpha",
            selectedProjectName: "Alpha",
            projectConfig: projectConfig,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(truth.lines.contains("配置来源：当前项目单独设置"))
        #expect(truth.lines.contains("适用范围：当前项目 Alpha (project-alpha)"))
        #expect(truth.pickerTruth.badges.map(\.text).contains("项目单独设置"))
        #expect(truth.pickerTruth.badges.map(\.text).contains("Fallback"))
        #expect(truth.pickerTruth.badges.map(\.text).contains("Local qwen3-14b-mlx"))
        #expect(
            truth.pickerTruth.badges.contains(where: {
                $0.kind == .evidence && $0.text.hasPrefix("Deny ")
            })
        )
        #expect(truth.pickerTruth.summaryText.contains("这里改的是当前项目，不会改全局默认"))
        #expect(truth.pickerTruth.summaryText.contains("全局默认当前是 openai/gpt-5-low"))
        #expect(truth.pickerTruth.summaryText.contains("当前 transport 是 grpc-only"))
        #expect(truth.pickerTruth.summaryText.contains("更像上游远端不可用、provider 未 ready，或执行链失败"))
        #expect(truth.pickerTruth.tooltip?.contains("审计编号：audit-project-scope-1") == true)
    }

    @Test
    func compactButtonPresentationKeepsStatusAndActualButDropsSourceAndEvidence() {
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5-low")
        let projectConfig = AXProjectConfig.default(
            forProjectRoot: URL(fileURLWithPath: "/tmp/hub-model-routing-truth-project-compact", isDirectory: true)
        )
        .settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-project-scope-compact",
            denyCode: "device_remote_export_denied",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .coder,
            selectedProjectID: "project-compact",
            selectedProjectName: "Compact",
            projectConfig: projectConfig,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        let compact = truth.pickerTruth.compactButtonPresentation

        #expect(compact.badges.map(\.text) == ["Fallback", "Local qwen3-14b-mlx"])
        #expect(compact.summaryText.isEmpty)
        #expect(compact.tooltip?.contains("审计编号：audit-project-scope-compact") == true)
    }

    @Test
    func projectScopeTruthExplainsInheritedGlobalBindingWhenExecutionNotObserved() {
        let settings = XTerminalSettings.default()
            .setting(role: .reviewer, providerKind: .hub, model: "openai/gpt-5.3-codex")

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .reviewer,
            selectedProjectID: "project-beta",
            selectedProjectName: "Beta",
            projectConfig: AXProjectConfig.default(
                forProjectRoot: URL(fileURLWithPath: "/tmp/hub-model-routing-truth-project-beta", isDirectory: true)
            ),
            settings: settings,
            snapshot: .empty(role: .reviewer, source: "test"),
            transportMode: "grpc_only"
        )

        #expect(truth.lines.contains("配置来源：当前项目没有单独设置；沿用全局角色设置"))
        #expect(truth.pickerTruth.badges.map(\.text) == ["沿用全局", "待观察"])
        #expect(truth.pickerTruth.summaryText.contains("当前沿用全局模型 `openai/gpt-5.3-codex`"))
        #expect(truth.pickerTruth.summaryText.contains("你在这里一旦选择，就会写成项目单独设置"))
        #expect(truth.pickerTruth.summaryText.contains("先在当前项目跑一轮该角色"))
    }

    @Test
    func projectScopeTruthForSupervisorCallsOutGlobalConversationEvidence() {
        let settings = XTerminalSettings.default()
            .setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: 99,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .supervisor,
            selectedProjectID: "project-gamma",
            selectedProjectName: "Gamma",
            projectConfig: AXProjectConfig.default(
                forProjectRoot: URL(fileURLWithPath: "/tmp/hub-model-routing-truth-project-gamma", isDirectory: true)
            ),
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(
            truth.lines.contains(
                "适用范围：Supervisor 全局对话；当前项目焦点 Gamma (project-gamma)"
            )
        )
        #expect(truth.pickerTruth.badges.map(\.text).contains("沿用全局"))
        #expect(truth.pickerTruth.badges.map(\.text).contains("Remote"))
        #expect(truth.pickerTruth.summaryText.contains("最近一次可见的实际路由仍来自 Supervisor 全局对话"))
        #expect(truth.pickerTruth.summaryText.contains("当前沿用全局模型 `openai/gpt-5.4`"))
    }

    @Test
    func globalScopeTruthExplainsGrpcOnlyMismatchAsHubSideReroute() {
        let settings = XTerminalSettings.default()
            .setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: 99,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-4.1",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .globalRoleSettings,
            role: .supervisor,
            selectedProjectID: nil,
            selectedProjectName: nil,
            projectConfig: nil,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(truth.pickerTruth.summaryText.contains("当前 transport 是 grpc-only"))
        #expect(truth.pickerTruth.summaryText.contains("更可能是 Hub 执行阶段改派"))
    }

    @Test
    func projectScopeTruthCanRenderInEnglish() {
        let settings = XTerminalSettings.default()
            .setting(role: .reviewer, providerKind: .hub, model: "openai/gpt-5.3-codex")

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .reviewer,
            selectedProjectID: "project-beta",
            selectedProjectName: "Beta",
            projectConfig: AXProjectConfig.default(
                forProjectRoot: URL(fileURLWithPath: "/tmp/hub-model-routing-truth-project-beta", isDirectory: true)
            ),
            settings: settings,
            snapshot: .empty(role: .reviewer, source: "test"),
            transportMode: "grpc_only",
            language: .english
        )

        #expect(truth.lines.contains("Config Source：no project override; inheriting the global role override"))
        #expect(truth.lines.contains("Scope：current project Beta (project-beta)"))
        #expect(truth.pickerTruth.badges.map(\.text) == ["Inherited Global", "Pending"])
        #expect(truth.pickerTruth.summaryText.contains("is currently inheriting the global model `openai/gpt-5.3-codex`"))
        #expect(truth.pickerTruth.summaryText.contains("Choosing here will write a project override"))
        #expect(truth.pickerTruth.summaryText.contains("Run this role once in the current project"))
    }

    @Test
    func projectScopeTruthCarriesA4RuntimeReadinessMatrixWhenConfigured() {
        let root = URL(fileURLWithPath: "/tmp/hub-model-routing-truth-a4-runtime", isDirectory: true)
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")
        let projectConfig = AXProjectConfig.default(forProjectRoot: root)
            .settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s3StrategicCoach
            )
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 99,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .projectRoleSettings,
            role: .coder,
            selectedProjectID: "project-a4",
            selectedProjectName: "A4",
            projectConfig: projectConfig,
            projectRuntimeReadiness: blockedA4RuntimeReadinessSnapshot(),
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(truth.lines.contains("A4 Runtime Ready：未就绪"))
        #expect(
            truth.lines.contains(
                "A4 五维检查：route ready 已就绪 · capability ready 已就绪 · grant ready 未就绪 · checkpoint/recovery ready 已就绪 · evidence/export ready 已就绪"
            )
        )
        #expect(truth.lines.contains(where: { $0.contains("A4 当前缺口：grant ready：受治理自动化未就绪 / 权限宿主未就绪") }))
        #expect(truth.pickerTruth.summaryText.contains("A4 Agent 已配置，但 runtime ready 还没完成。"))
    }

    @Test
    func globalScopeTruthAppendsSupervisorRepairHintWhenGovernancePlaneBlocked() {
        let settings = XTerminalSettings.default()
            .setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: 88,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "grant_required",
            auditRef: "audit-hub-model-routing-supervisor-1",
            denyCode: "device_permission_owner_missing",
            source: "test"
        )

        let truth = HubModelRoutingTruthBuilder.build(
            surface: .globalRoleSettings,
            role: .supervisor,
            selectedProjectID: "project-alpha",
            selectedProjectName: "Alpha",
            projectConfig: nil,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(truth.lines.contains(where: { $0.contains("修复建议：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。") }))
        #expect(truth.pickerTruth.summaryText.contains("先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定"))
    }
}

private func blockedA4RuntimeReadinessSnapshot() -> AXProjectGovernanceRuntimeReadinessSnapshot {
    let detailLines = [
        "project_governance_runtime_readiness_schema_version=\(AXProjectGovernanceRuntimeReadinessSnapshot.currentSchemaVersion)",
        "project_governance_configured_execution_tier=a4_openclaw",
        "project_governance_effective_execution_tier=a4_openclaw",
        "project_governance_configured_runtime_surface_mode=trusted_openclaw_mode",
        "project_governance_effective_runtime_surface_mode=trusted_openclaw_mode",
        "project_governance_runtime_surface_override_mode=none",
        "project_governance_trusted_automation_state=blocked",
        "project_governance_requires_a4_runtime_ready=true",
        "project_governance_runtime_ready=false",
        "project_governance_runtime_readiness_state=blocked",
        "project_governance_effective_surface_capabilities=device,browser,connector,extension",
        "project_governance_missing_readiness=trusted_automation_not_ready,permission_owner_not_ready",
        "project_governance_runtime_readiness_summary=A4 Agent 已配置，但 runtime ready 还没完成。",
        "project_governance_runtime_readiness_missing_summary=缺口：受治理自动化未就绪 / 权限宿主未就绪"
    ]
    return AXProjectGovernanceRuntimeReadinessSnapshot(detailLines: detailLines)!
}
