import Foundation
import Testing
@testable import XTerminal

struct ExecutionRoutePresentationTests {
    @Test
    func shortModelLabelPrefersQualifiedSuffixForCompactHeaders() {
        #expect(ExecutionRoutePresentation.shortModelLabel("openai/gpt-5.4") == "gpt-5.4")
        #expect(ExecutionRoutePresentation.shortModelLabel("anthropic/claude-opus-4.1") == "claude-opus-4.1")
        #expect(ExecutionRoutePresentation.shortModelLabel("qwen3-17b-mlx-bf16") == "qwen3-17b-mlx-bf16")
    }

    @Test
    func routeSummaryTextUsesUnifiedRouteTruthEvidence() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "downgrade_to_local",
            auditRef: "audit-route-summary-1",
            denyCode: "credential_finding",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let summary = try #require(
            ExecutionRoutePresentation.routeSummaryText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(summary.contains("configured route=openai/gpt-5.4"))
        #expect(summary.contains("actual route=Hub (Local) -> qwen3-14b-mlx [hub_downgraded_to_local]"))
        #expect(summary.contains("fallback reason=Hub 端把远端请求降到本地（downgrade_to_local）"))
        #expect(summary.contains("route state=配置希望走远端，但这轮执行被 Hub 降到了本地。"))
        #expect(summary.contains("audit_ref=audit-route-summary-1"))
        #expect(summary.contains("deny_code=Hub remote export gate 检测到疑似凭据内容（credential_finding）"))
        #expect(summary.contains("transport=grpc"))
        #expect(summary.contains("grpc-only 提示：这次落到本地更像 Hub 执行阶段降级或 export gate 生效"))
    }

    @Test
    func routeSummaryTextReturnsNilWithoutObservedExecution() {
        #expect(
            ExecutionRoutePresentation.routeSummaryText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: .empty(role: .coder, source: "test")
            ) == nil
        )
    }

    @Test
    func detailBadgeUsesDenyCodeWhenFallbackReasonMissing() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_error",
            fallbackReasonCode: "",
            auditRef: "audit-route-badge-1",
            denyCode: "remote_export_blocked",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let badge = try #require(
            ExecutionRoutePresentation.detailBadge(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(badge.text == "Reason Hub remote export gate 阻断了远端请求")
    }

    @Test
    func detailBadgeShowsLocalActualModelForDowngradedRuns() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "model_not_found",
            auditRef: "audit-route-badge-2",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let badge = try #require(
            ExecutionRoutePresentation.detailBadge(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(badge.text == "Local qwen3-17b-mlx-bf16")
    }

    @Test
    func interpretationBadgeExplainsGrpcDowngradeAsHubSide() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "model_not_found",
            auditRef: "audit-route-badge-2",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let badge = try #require(
            ExecutionRoutePresentation.interpretationBadge(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(badge.text == "Hub Downgrade")
    }

    @Test
    func inlineExplanationTextFlagsHubGateAsNotXtSilentRewrite() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-inline-explanation-1",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let summary = try #require(
            ExecutionRoutePresentation.inlineExplanationText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(summary.contains("Hub remote export gate"))
        #expect(summary.contains("不是 XT 静默改成本地"))
    }

    @Test
    func inlineExplanationTextExplainsProjectLevelLocalTakeover() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "qwen3-14b-mlx",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_runtime",
            fallbackReasonCode: "",
            auditRef: "audit-inline-explanation-2",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let summary = try #require(
            ExecutionRoutePresentation.inlineExplanationText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(summary.contains("项目级本地锁"))
        #expect(summary.contains("本地接管"))
    }

    @Test
    func inlineExplanationTextExplainsSupervisorGrantPlaneBlockers() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .supervisor,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "grant_required",
            auditRef: "audit-inline-explanation-supervisor-1",
            denyCode: "device_permission_owner_missing",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let summary = try #require(
            ExecutionRoutePresentation.inlineExplanationText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(summary.contains("Supervisor 的 grant / governance 面还没就绪"))
        #expect(summary.contains("trusted automation"))
        #expect(summary.contains("permission owner"))
    }

    @Test
    func grpcTransportMismatchHintExplainsHubGateBeforeExecution() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-warning-hint-1",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let hint = ExecutionRoutePresentation.grpcTransportMismatchHint(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc_only",
            language: .simplifiedChinese
        )

        #expect(hint.contains("当前 transport 是 grpc-only"))
        #expect(hint.contains("Hub 执行阶段降级或 export gate 生效"))
        #expect(hint.contains("不是设置页把模型静默改成了本地"))
    }

    @Test
    func grpcTransportMismatchHintExplainsUpstreamIssueBeforeExecution() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-warning-hint-2",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let hint = ExecutionRoutePresentation.grpcTransportMismatchHint(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc",
            language: .simplifiedChinese
        )

        #expect(hint.contains("当前 transport 是 grpc-only"))
        #expect(hint.contains("上游远端不可用、provider 未 ready"))
        #expect(hint.contains("不是设置页把模型静默改成了本地"))
    }

    @Test
    func reasonBadgeShowsFallbackReasonForDowngradedRuns() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "model_not_found",
            auditRef: "audit-route-badge-3",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let badge = try #require(
            ExecutionRoutePresentation.reasonBadge(snapshot: snapshot)
        )

        #expect(badge.text == "Reason 目标模型当前不在可执行清单里")
    }

    @Test
    func evidenceBadgeHumanizesDenyCodeForCompactDisplay() throws {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "",
            auditRef: "audit-route-badge-4",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let badge = try #require(
            ExecutionRoutePresentation.evidenceBadge(snapshot: snapshot)
        )

        #expect(badge.text == "Deny 当前设备不允许远端 export")
    }

    @Test
    func displayReasonAndDenyCodeTextHumanizeStructuredFailures() {
        #expect(
            ExecutionRoutePresentation.displayReasonText(
                "grant_required;deny_code=device_paid_model_not_allowed"
            ) == "当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）"
        )
        #expect(
            ExecutionRoutePresentation.displayDenyCodeText(
                "device_remote_export_denied"
            ) == "当前设备不允许远端 export（device_remote_export_denied）"
        )
    }

    @Test
    func tooltipAddsGrpcHintForRemoteError() {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "provider_not_ready",
            auditRef: "audit-route-tooltip-1",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(tooltip.contains("transport=grpc"))
        #expect(tooltip.contains("grpc-only 提示：这轮停在失败态"))
        #expect(tooltip.contains("XT 没有把请求静默改成本地"))
    }

    @Test
    func routeSummaryAndTooltipCarryPairedDeviceBudgetTruthForPaidModelBlocks() throws {
        let originalMode = HubAIClient.transportMode()
        defer { HubAIClient.setTransportMode(originalMode) }
        HubAIClient.setTransportMode(.grpc)

        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4",
            auditRef: "audit-route-paid-budget-summary",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )
        let paidAccessSnapshot = HubRemotePaidAccessSnapshot(
            trustProfilePresent: true,
            paidModelPolicyMode: "all_paid_models",
            dailyTokenLimit: 640,
            singleRequestTokenLimit: 256
        )

        let summary = try #require(
            ExecutionRoutePresentation.routeSummaryText(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                paidAccessSnapshot: paidAccessSnapshot
            )
        )
        let tooltip = ExecutionRoutePresentation.tooltip(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            paidAccessSnapshot: paidAccessSnapshot
        )

        #expect(summary.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型"))
        #expect(tooltip.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型"))
    }

    @Test
    func interpretationBadgeRemainsNilForCleanRemoteHit() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "openai/gpt-5.4",
            runtimeProvider: "Hub (Remote)",
            executionPath: "remote_model",
            fallbackReasonCode: "",
            auditRef: "audit-route-clean-remote-hit",
            denyCode: "",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        #expect(
            ExecutionRoutePresentation.interpretationBadge(
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot,
                transportMode: .grpc
            ) == nil
        )
    }
}
