import Foundation
import Testing
@testable import XTerminal

struct ModelSettingsRouteTruthPresentationTests {
    @Test
    func buildBindsCurrentProjectOverrideAndObservedRouteTruth() {
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5-low")
        let projectConfig = AXProjectConfig.default(
            forProjectRoot: URL(fileURLWithPath: "/tmp/model-settings-route-truth-alpha", isDirectory: true)
        )
        .settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-model-settings-1",
            denyCode: "device_remote_export_denied",
            source: "test"
        )

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .coder,
            selectedProjectID: "project-alpha",
            selectedProjectName: "Alpha",
            projectConfig: projectConfig,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(presentation.title == "编程助手 · 实际路由记录")
        #expect(presentation.lines.contains("你设定的目标：openai/gpt-5.4"))
        #expect(presentation.lines.contains("配置来源：当前项目单独设置"))
        #expect(presentation.lines.contains("适用范围：当前项目 Alpha (project-alpha)"))
        #expect(
            presentation.lines.contains(
                "这次实际命中：Hub (Local) -> qwen3-14b-mlx [hub_downgraded_to_local]"
            )
        )
        #expect(
            presentation.lines.contains(
                "没按预期走的原因：Hub remote export gate 阻断了远端请求（remote_export_blocked）"
            )
        )
        #expect(
            presentation.lines.contains(
                "明确拦截原因：当前设备不允许远端 export（device_remote_export_denied）"
            )
        )
        #expect(presentation.lines.contains("当前链路：grpc_only"))
        #expect(presentation.pickerTruth.badges.map(\.text).contains("项目单独设置"))
        #expect(presentation.pickerTruth.badges.map(\.text).contains("Downgraded"))
        #expect(presentation.pickerTruth.badges.map(\.text).contains("Local qwen3-14b-mlx"))
        #expect(
            presentation.pickerTruth.badges.contains(where: {
                $0.kind == .evidence && $0.text.hasPrefix("Deny ")
            })
        )
        #expect(presentation.pickerTruth.summaryText.contains("Alpha (project-alpha)"))
        #expect(presentation.pickerTruth.summaryText.contains("这里改的是全局默认"))
        #expect(presentation.pickerTruth.summaryText.contains("当前 transport 是 grpc-only"))
        #expect(presentation.pickerTruth.summaryText.contains("更像 Hub 执行阶段降级或 export gate 生效"))
        #expect(presentation.pickerTruth.tooltip?.contains("你设定的目标：openai/gpt-5.4") == true)
    }

    @Test
    func buildAddsRepairHintForSupervisorGovernanceBlockers() {
        let settings = XTerminalSettings.default()
            .setting(role: .supervisor, providerKind: .hub, model: "openai/gpt-5.4")
        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "grant_required",
            auditRef: "audit-model-settings-supervisor-1",
            denyCode: "device_permission_owner_missing",
            source: "test"
        )

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .supervisor,
            selectedProjectID: "project-alpha",
            selectedProjectName: "Alpha",
            projectConfig: nil,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(presentation.lines.contains(where: { $0.contains("修复建议：先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。") }))
        #expect(presentation.pickerTruth.summaryText.contains("先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定"))
    }

    @Test
    func buildExplainsGlobalScopeWhenNoProjectExecutionExists() {
        let settings = XTerminalSettings.default()
            .setting(role: .reviewer, providerKind: .hub, model: "openai/gpt-5.3-codex")

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .reviewer,
            selectedProjectID: nil,
            selectedProjectName: nil,
            projectConfig: nil,
            settings: settings,
            snapshot: .empty(role: .reviewer, source: "test"),
            transportMode: "grpc_only"
        )

        #expect(presentation.lines.contains("你设定的目标：openai/gpt-5.3-codex"))
        #expect(presentation.lines.contains("配置来源：全局角色设置"))
        #expect(presentation.lines.contains("适用范围：当前未绑定项目；这里只能核对全局角色设置"))
        #expect(presentation.lines.contains("这次实际命中：尚未观测到当前角色的最近执行"))
        #expect(
            presentation.lines.contains(
                "当前状态说明：当前还没有足够执行证据；先让该角色实际跑一轮，再判断这次实际路由。"
            )
        )
        #expect(presentation.lines.contains("当前链路：grpc_only"))
        #expect(presentation.pickerTruth.badges.map(\.text) == ["待观察"])
        #expect(presentation.pickerTruth.summaryText.contains("当前未绑定项目"))
        #expect(presentation.pickerTruth.summaryText.contains("先让该角色实际跑一轮"))
    }

    @Test
    func buildCanRenderEnglishRouteTruthCopy() {
        let settings = XTerminalSettings.default()
            .setting(role: .reviewer, providerKind: .hub, model: "openai/gpt-5.3-codex")

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .reviewer,
            selectedProjectID: nil,
            selectedProjectName: nil,
            projectConfig: nil,
            settings: settings,
            snapshot: .empty(role: .reviewer, source: "test"),
            transportMode: "grpc_only",
            language: .english
        )

        #expect(presentation.title == "Reviewer · Route Record")
        #expect(presentation.detail.contains("configured target, actual route"))
        #expect(presentation.lines.contains("Config Source：global role override"))
        #expect(presentation.lines.contains("Scope：no project selected; only the global role override can be checked here"))
        #expect(presentation.pickerTruth.badges.map(\.text) == ["Pending"])
        #expect(presentation.pickerTruth.summaryText.contains("No project is currently selected"))
    }

    @Test
    func buildExplainsGrpcOnlyFailureStateAsUpstreamProblemInEnglish() {
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")

        let snapshot = AXRoleExecutionSnapshots.snapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "",
            denyCode: "",
            source: "test"
        )

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .coder,
            selectedProjectID: nil,
            selectedProjectName: nil,
            projectConfig: nil,
            settings: settings,
            snapshot: snapshot,
            transportMode: "grpc_only",
            language: .english
        )

        #expect(presentation.pickerTruth.summaryText.contains("transport is grpc-only"))
        #expect(presentation.pickerTruth.summaryText.contains("XT did not silently convert this turn to local"))
    }

    @Test
    func buildSurfacesA4RuntimeReadinessTruthForProjectScope() {
        let root = URL(fileURLWithPath: "/tmp/model-settings-route-truth-a4", isDirectory: true)
        let settings = XTerminalSettings.default()
            .setting(role: .coder, providerKind: .hub, model: "openai/gpt-5.4")
        let projectConfig = AXProjectConfig.default(forProjectRoot: root)
            .settingModelOverride(role: .coder, modelId: "openai/gpt-5.4")
            .settingProjectGovernance(
                executionTier: .a4OpenClaw,
                supervisorInterventionTier: .s3StrategicCoach
            )

        let presentation = ModelSettingsRouteTruthBuilder.build(
            role: .coder,
            selectedProjectID: "project-a4",
            selectedProjectName: "A4",
            projectConfig: projectConfig,
            projectRuntimeReadiness: blockedA4RuntimeReadinessSnapshotForModelSettings(),
            settings: settings,
            snapshot: .empty(role: .coder, source: "test"),
            transportMode: "grpc_only"
        )

        #expect(presentation.lines.contains("A4 Runtime Ready：未就绪"))
        #expect(
            presentation.lines.contains(
                "A4 五维检查：route ready 已就绪 · capability ready 已就绪 · grant ready 未就绪 · checkpoint/recovery ready 已就绪 · evidence/export ready 已就绪"
            )
        )
        #expect(presentation.lines.contains(where: { $0.contains("A4 当前缺口：grant ready：受治理自动化未就绪 / 权限宿主未就绪") }))
        #expect(presentation.pickerTruth.summaryText.contains("A4 Agent 已配置，但 runtime ready 还没完成。"))
    }
}

private func blockedA4RuntimeReadinessSnapshotForModelSettings() -> AXProjectGovernanceRuntimeReadinessSnapshot {
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
