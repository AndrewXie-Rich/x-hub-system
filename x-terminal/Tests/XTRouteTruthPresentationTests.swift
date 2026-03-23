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
        #expect(evidence.denyCodeLine == "deny_code=credential_finding")
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
    func routeReasonTextHumanizesConnectivityFailures() {
        #expect(XTRouteTruthPresentation.routeReasonText("remote_unreachable") == "远端链路不可达（remote_unreachable）")
        #expect(XTRouteTruthPresentation.routeReasonText("remote_timeout") == "远端请求超时（remote_timeout）")
        #expect(XTRouteTruthPresentation.routeReasonText("response_timeout") == "上游响应超时（response_timeout）")
    }
}
