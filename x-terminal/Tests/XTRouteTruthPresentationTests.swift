import Foundation
import Testing
@testable import XTerminal

struct XTRouteTruthPresentationTests {
    @Test
    func snapshotEvidenceExplainsDowngradeChain() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 123,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "downgrade_to_local",
            auditRef: "audit-route-123",
            denyCode: "credential_finding",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let evidence = XTRouteTruthPresentation.evidence(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(evidence.configuredRouteLine == "configured route=openai/gpt-5.4")
        #expect(evidence.actualRouteLine == "actual route=Hub (Local) -> qwen3-14b-mlx [hub_downgraded_to_local]")
        #expect(evidence.fallbackReasonLine == "fallback reason=Hub 端把远端请求降到本地（downgrade_to_local）")
        #expect(evidence.routeStateLine == "route state=配置希望走远端，但这轮执行被 Hub 降到了本地。")
        #expect(evidence.auditRefLine == "audit_ref=audit-route-123")
        #expect(evidence.denyCodeLine == "deny_code=Hub remote export gate 检测到疑似凭据内容（credential_finding）")
        #expect(evidence.transportLine == "transport=grpc_only")
    }

    @Test
    func eventFocusDetailExplainsBlockedWaitingUpstream() {
        let event = AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 42,
            projectId: "project-alpha",
            projectDisplayName: "Alpha",
            role: "coder",
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "",
            executionPath: "remote_error",
            fallbackReasonCode: "blocked_waiting_upstream",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )

        let detail = XTRouteTruthPresentation.focusDetail(
            latestEvent: event,
            fallback: "先看诊断。"
        )

        #expect(detail.contains("configured route=openai/gpt-5.4"))
        #expect(detail.contains("actual route=Remote Attempt [remote_error]"))
        #expect(detail.contains("fallback reason=上游还没准备好，当前保持等待态（blocked_waiting_upstream）"))
        #expect(detail.contains("route state=当前远端链路被上游阻塞"))
    }

    @Test
    func eventEvidenceCarriesAuditAndDenyLines() {
        let event = AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 99,
            projectId: "project-beta",
            projectDisplayName: "Beta",
            role: "coder",
            stage: "reply",
            requestedModelId: "openai/gpt-5.2",
            actualModelId: "qwen3-17b-mlx-bf16",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-route-456",
            denyCode: "grant_required",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )

        let evidence = XTRouteTruthPresentation.evidence(latestEvent: event)

        #expect(evidence.auditRefLine == "audit_ref=audit-route-456")
        #expect(evidence.denyCodeLine == "deny_code=grant_required")
        #expect(evidence.inlineText.contains("audit_ref=audit-route-456"))
        #expect(evidence.inlineText.contains("deny_code=grant_required"))
    }

    @Test
    func snapshotEvidenceUsesDenyCodeWhenFallbackReasonMissing() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 123,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "local_fallback_after_remote_error",
            fallbackReasonCode: "",
            auditRef: "audit-route-deny-only",
            denyCode: "remote_export_blocked",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let evidence = XTRouteTruthPresentation.evidence(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc_only"
        )

        #expect(evidence.fallbackReasonLine == "fallback reason=Hub remote export gate 阻断了远端请求（remote_export_blocked）")
        #expect(evidence.denyCodeLine == "deny_code=Hub remote export gate 阻断了远端请求（remote_export_blocked）")
        #expect(evidence.routeStateLine == "route state=远端导出或策略边界还没放行，当前先由本地接住。")
    }

    @Test
    func eventEvidenceUsesDenyCodeWhenFallbackReasonMissing() {
        let event = AXModelRouteDiagnosticEvent(
            schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
            createdAt: 42,
            projectId: "project-gamma",
            projectDisplayName: "Gamma",
            role: "coder",
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "",
            executionPath: "remote_error",
            fallbackReasonCode: "",
            auditRef: "audit-route-deny-event",
            denyCode: "model_not_found",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: ""
        )

        let evidence = XTRouteTruthPresentation.evidence(latestEvent: event)

        #expect(evidence.fallbackReasonLine == "fallback reason=目标模型当前不在可执行清单里（model_not_found）")
        #expect(evidence.denyCodeLine == "deny_code=目标模型当前不在可执行清单里（model_not_found）")
        #expect(evidence.routeStateLine == "route state=这轮远端路由没有成功命中，当前停在失败态；优先检查 fallback reason 和上游状态，不是 XT 静默改成本地。")
    }

    @Test
    func routeReasonTextHumanizesConnectivityFailures() {
        #expect(XTRouteTruthPresentation.routeReasonText("remote_unreachable") == "远端链路不可达（remote_unreachable）")
        #expect(XTRouteTruthPresentation.routeReasonText("remote_timeout") == "远端请求超时（remote_timeout）")
        #expect(XTRouteTruthPresentation.routeReasonText("response_timeout") == "上游响应超时（response_timeout）")
    }

    @Test
    func routeTruthNormalizesLegacySpacedAndHyphenatedReasonCodes() {
        #expect(
            XTRouteTruthPresentation.routeReasonText("remote export blocked")
                == "Hub remote export gate 阻断了远端请求（remote_export_blocked）"
        )
        #expect(
            XTRouteTruthPresentation.routeReasonText("provider-not-ready")
                == "provider 尚未 ready（provider_not_ready）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("device remote export denied")
                == "当前设备不允许远端 export（device_remote_export_denied）"
        )
        #expect(
            XTRouteTruthPresentation.routeStateText(
                executionPath: "remote-error",
                routeReasonCode: "provider not ready"
            ) == "当前远端 provider 还没 ready，所以路由停在失败态。"
        )
    }

    @Test
    func routeTruthHumanizesStructuredConnectorAndPaidModelReasonCodes() {
        #expect(
            XTRouteTruthPresentation.routeReasonText("grant_required;deny_code=remote_export_blocked")
                == "Hub remote export gate 阻断了远端请求（remote_export_blocked）"
        )
        #expect(
            XTRouteTruthPresentation.routeReasonText("credential_finding")
                == "Hub remote export gate 检测到疑似凭据内容（credential_finding）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("secret_mode_deny")
                == "Hub remote export gate 认定当前内容含 secret，按策略拒绝外发（secret_mode_deny）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("secret_sanitize_required")
                == "Hub remote export gate 要求先完成 secret 脱敏后再外发（secret_sanitize_required）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("allow_class_denied")
                == "当前导出类型不在 Hub 允许清单内（allow_class_denied）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("secondary_dlp_error")
                == "Hub 二次 DLP 检查失败，按 fail-closed 阻断外发（secondary_dlp_error）"
        )
        #expect(
            XTRouteTruthPresentation.routeReasonText("device_paid_model_not_allowed;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4")
                == "当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("grant_required;deny_code=device_paid_model_not_allowed")
                == "当前模型不在这台设备的付费模型允许范围内（device_paid_model_not_allowed）"
        )
        #expect(
            XTRouteTruthPresentation.routeStateText(
                executionPath: "remote_error",
                routeReasonCode: "device_daily_token_budget_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4"
            ) == "当前付费模型资格或预算还没收敛，所以路由停在失败态。"
        )
    }

    @Test
    func routeTruthHumanizesSupervisorRouteGovernanceCodes() {
        #expect(
            XTRouteTruthPresentation.routeReasonText("preferred_device_offline")
                == "首选 XT 设备当前离线（preferred_device_offline）"
        )
        #expect(
            XTRouteTruthPresentation.routeReasonText("trusted_automation_not_ready")
                == "受治理自动化还没就绪（trusted_automation_not_ready）"
        )
        #expect(
            XTRouteTruthPresentation.denyCodeText("device_permission_owner_missing")
                == "当前 XT 绑定缺少 permission owner（device_permission_owner_missing）"
        )
    }

    @Test
    func routeStateTextExplainsSupervisorRouteAndGrantPlanes() {
        #expect(
            XTRouteTruthPresentation.routeStateText(
                executionPath: "remote_error",
                routeReasonCode: "preferred_device_offline"
            ) == "Supervisor 到 XT / runner 的 route 面还没就绪，所以当前停在失败态。"
        )
        #expect(
            XTRouteTruthPresentation.routeStateText(
                executionPath: "local_fallback_after_remote_error",
                routeReasonCode: "grant_required",
                denyCode: "device_permission_owner_missing"
            ) == "Supervisor grant / governance 面还没就绪，当前先由本地接住。"
        )
    }

    @Test
    func routeTruthEvidenceCarriesPairedDeviceBudgetTruthForPaidModelBlocks() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 123,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "",
            runtimeProvider: "Remote Attempt",
            executionPath: "remote_error",
            fallbackReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4",
            auditRef: "audit-route-paid-budget-1",
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

        let evidence = XTRouteTruthPresentation.evidence(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc_only",
            paidAccessSnapshot: paidAccessSnapshot
        )
        let focusDetail = XTRouteTruthPresentation.focusDetail(
            latestEvent: AXModelRouteDiagnosticEvent(
                schemaVersion: AXModelRouteDiagnosticEvent.currentSchemaVersion,
                createdAt: 42,
                projectId: "project-paid-budget",
                projectDisplayName: "Paid Budget",
                role: "coder",
                stage: "reply",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "",
                runtimeProvider: "Remote Attempt",
                executionPath: "remote_error",
                fallbackReasonCode: "device_single_request_token_exceeded;policy_mode=new_profile;device_name=Andrew;model_id=openai/gpt-5.4",
                auditRef: "audit-route-paid-budget-event",
                denyCode: nil,
                remoteRetryAttempted: false,
                remoteRetryFromModelId: "",
                remoteRetryToModelId: "",
                remoteRetryReasonCode: ""
            ),
            fallback: "先看诊断。",
            paidAccessSnapshot: paidAccessSnapshot
        )

        #expect(evidence.pairedDeviceTruthLine == "paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型")
        #expect(evidence.inlineText.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型"))
        #expect(focusDetail.contains("paired_device_truth=单次 256 tok · 当日 640 tok · 策略 全部付费模型"))
    }

    @Test
    func routeTruthCanRenderInEnglish() {
        let snapshot = AXRoleExecutionSnapshot(
            role: .coder,
            updatedAt: 123,
            stage: "reply",
            requestedModelId: "openai/gpt-5.4",
            actualModelId: "qwen3-14b-mlx",
            runtimeProvider: "Hub (Local)",
            executionPath: "hub_downgraded_to_local",
            fallbackReasonCode: "remote_export_blocked",
            auditRef: "audit-route-english",
            denyCode: "device_remote_export_denied",
            remoteRetryAttempted: false,
            remoteRetryFromModelId: "",
            remoteRetryToModelId: "",
            remoteRetryReasonCode: "",
            source: "test"
        )

        let evidence = XTRouteTruthPresentation.evidence(
            configuredModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: "grpc_only",
            language: .english
        )

        #expect(evidence.fallbackReasonLine == "fallback reason=Hub remote export gating blocked the remote request (remote_export_blocked)")
        #expect(evidence.routeStateLine == "route state=The configuration expected a remote route, but Hub export gating pulled the request back to local immediately.")
        #expect(evidence.denyCodeLine == "deny_code=This device does not allow remote export (device_remote_export_denied)")
    }
}
