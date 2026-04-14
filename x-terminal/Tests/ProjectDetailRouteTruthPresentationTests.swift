import Foundation
import Testing
@testable import XTerminal

struct ProjectDetailRouteTruthPresentationTests {
    @Test
    func rowsKeepConfiguredActualFallbackAndDenyTruthAligned() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 42,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-route-project-detail",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "openai/gpt-5.4",
            fallbackConfiguredModelId: "fallback/model",
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(rows.map(\.label) == [
            "configured route",
            "route state",
            "actual route",
            "fallback reason",
            "deny code",
            "audit ref"
        ])
        #expect(rows[0].value == "openai/gpt-5.4")
        #expect(rows[1].value == "远端导出或策略边界还没放行，当前先由本地接住。 当前 transport 是 grpc-only；如果最近实际仍落到本地，更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 把配置静默改成了本地。")
        #expect(rows[2].value == "Hub (Local) -> qwen3-14b-mlx [local_fallback_after_remote_error]")
        #expect(rows[3].value == "Hub remote export gate 阻断了远端请求（remote_export_blocked）")
        #expect(rows[4].value == "当前设备不允许远端 export（device_remote_export_denied）")
        #expect(rows[5].value == "audit-route-project-detail")
    }

    @Test
    func rowsFallBackToProjectModelIdWithoutObservedExecution() {
        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "",
            fallbackConfiguredModelId: "local/default-model",
            snapshot: .empty(role: .coder, source: "project_detail_tests")
        )

        #expect(rows == [
            ProjectDetailRouteTruthRow(
                label: "configured route",
                value: "local/default-model"
            )
        ])
    }

    @Test
    func rowsExplainGrpcOnlyDowngradeAsHubSideInEnglish() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 99,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-route-project-detail-en",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "openai/gpt-5.4",
            fallbackConfiguredModelId: nil,
            snapshot: snapshot,
            transportMode: "grpc_only",
            language: .english
        )

        #expect(rows[1].value.contains("The current transport is grpc-only."))
        #expect(rows[1].value.contains("more likely a Hub-side downgrade or export gate"))
        #expect(rows[1].value.contains("than XT silently changing the configured route to local"))
    }

    @Test
    func rowsHumanizeRemoteExportGateRuleDetails() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 120,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "credential_finding",
            auditRef: "audit-route-project-detail-credential",
            denyCode: "credential_finding",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "openai/gpt-5.4",
            fallbackConfiguredModelId: nil,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(rows[1].value.contains("export gate"))
        #expect(rows[3].value == "Hub remote export gate 检测到疑似凭据内容（credential_finding）")
        #expect(rows[4].value == "Hub remote export gate 检测到疑似凭据内容（credential_finding）")
    }

    @Test
    func rowsShowPairedDeviceTruthForPaidModelBudgetBlocks() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 140,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4",
            auditRef: "audit-route-project-detail-paid-budget",
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

        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "openai/gpt-5.4",
            fallbackConfiguredModelId: nil,
            snapshot: snapshot,
            paidAccessSnapshot: paidAccessSnapshot,
            transportMode: "grpc_only"
        )

        #expect(rows.map(\.label) == [
            "configured route",
            "route state",
            "actual route",
            "fallback reason",
            "device truth",
            "audit ref"
        ])
        #expect(rows[4].value == "单次 256 tok · 当日 640 tok · 策略 全部付费模型")
    }

    @Test
    func rowsAddRepairHintForSupervisorGovernanceBlockers() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .supervisor,
            updatedAt: 150,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "grant_required",
            auditRef: "audit-route-project-detail-supervisor",
            denyCode: "device_permission_owner_missing",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let rows = ProjectDetailRouteTruthPresentation.rows(
            configuredModelId: "openai/gpt-5.4",
            fallbackConfiguredModelId: nil,
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(rows.map(\.label) == [
            "configured route",
            "route state",
            "actual route",
            "fallback reason",
            "deny code",
            "audit ref",
            "repair hint"
        ])
        #expect(rows[1].value.contains("Supervisor 的 grant / governance 面还没就绪"))
        #expect(rows[6].value == "先检查 trusted automation、permission owner、kill-switch、TTL 和当前项目绑定。")
    }
}
