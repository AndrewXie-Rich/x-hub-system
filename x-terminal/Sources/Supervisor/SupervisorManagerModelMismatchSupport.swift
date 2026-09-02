import Foundation

extension SupervisorManager {
    func currentSupervisorModelMismatchSummary() -> String? {
        let configured = currentPreferredModelID(for: .supervisor)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let expected = resolvedPreferredSupervisorModelID(configuredModelId: configured)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actual = lastSupervisorActualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expected.isEmpty, !actual.isEmpty else { return nil }
        guard normalizedModelIdentity(expected) != normalizedModelIdentity(actual) else { return nil }
        let mode = SupervisorReplyExecutionMode(rawValue: lastSupervisorReplyExecutionMode) ?? .idle
        let effectiveFailureReason = effectiveSupervisorFailureReasonCode(
            failureReason: lastSupervisorRemoteFailureReasonCode,
            denyCode: lastSupervisorDenyCode
        )
        let configuredLabel = {
            guard !configured.isEmpty else { return expected }
            guard !expected.isEmpty, normalizedModelIdentity(configured) != normalizedModelIdentity(expected) else {
                return configured
            }
            return "\(configured)（当前对话实际请求 \(expected)）"
        }()
        switch HubAIClient.transportMode() {
        case .grpc:
            switch mode {
            case .hubDowngradedToLocal:
                return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致基本不是 XT 本地 auto fallback；更可能是 Hub 端触发了 downgrade_to_local，或 Hub 的 remote_export gate 主动把 paid 请求降到了本地模型。
下一步不要再看 XT 路由设置，直接去 Hub 侧查 `ai.generate.downgraded_to_local` / `remote_export_blocked` 审计。
"""
            case .localFallbackAfterRemoteError:
                if [
                    "blocked_waiting_upstream",
                    "provider_not_ready",
                    "grpc_route_unavailable",
                    "runtime_not_running",
                    "request_write_failed",
                    "response_timeout",
                    "remote_timeout",
                    "remote_unreachable"
                ].contains(effectiveFailureReason) {
                    return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致更像上游远端不可用、provider 未 ready，或请求链在执行阶段失败后由本地兜底；不是 XT 静默改写了 Supervisor 配置。
下一步先看当前 fallback reason、Hub 链路和 provider ready；只有出现 `downgrade_to_local` / `remote_export_blocked` 证据时，再去查对应 Hub 审计。
"""
                }
                return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致更像远端请求失败后由本地兜底，或 Hub 在执行阶段把请求改派到了别的落点；不是 XT 静默改写了 Supervisor 配置。
下一步优先检查当前 fallback reason，以及 Hub 侧 `downgrade_to_local` / `remote_export_blocked` 审计。
"""
            case .remoteModel:
                return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致更像 Hub 在执行阶段改派到了另一条模型路由，而不是 XT 静默改写了 Supervisor 配置。
下一步直接去核对 route truth、audit_ref，以及 Hub 侧对应执行记录。
"""
            default:
                break
            }
            return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前已经是 grpc-only，所以这次不一致基本不是 XT 本地 auto fallback；更可能是 Hub 端触发了 downgrade_to_local，或 Hub 的 remote_export gate 主动把 paid 请求降到了本地模型。
下一步不要再看 XT 路由设置，直接去 Hub 侧查 `ai.generate.downgraded_to_local` / `remote_export_blocked` 审计。
"""
        case .auto:
            return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
这通常表示远端 paid 路由没有真正命中，而是发生了 XT 自动回退到本地模型，或 Hub 端触发了 downgrade_to_local。
如果你要强制验证 paid GPT，请先把 Hub transport 切到 `/hub route grpc`，这样远端不可用时会直接报错，不会静默掉回本地。
"""
        case .fileIPC:
            return """
当前配置首选是 \(configuredLabel)，但最近一次实际执行是 \(actual)。
XT 当前 transport 是 fileIPC，所以这轮本来就不会强制走远端 paid GPT；请先在 Supervisor 里执行 `/hub route grpc`，再重新验证。
"""
        }
    }

    func strictSupervisorRemoteModelMismatchResponse(
        preferredModelId: String?,
        actualModelId: String?,
        requestedModelId: String? = nil,
        failureReasonCode: String? = nil,
        denyCode: String? = nil,
        auditRef: String? = nil,
        mode: SupervisorReplyExecutionMode = .hubDowngradedToLocal
    ) -> String? {
        guard HubAIClient.transportMode() == .grpc else { return nil }
        let configured = preferredModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actual = actualModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !configured.isEmpty, !actual.isEmpty else { return nil }
        guard normalizedModelIdentity(configured) != normalizedModelIdentity(actual) else { return nil }

        let normalizedRequestedModelId = requestedModelId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedFailureReason = failureReasonCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedDenyCode = denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalizedAuditRef = auditRef?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var evidenceLines: [String] = []
        if !normalizedRequestedModelId.isEmpty {
            evidenceLines.append("- 请求模型=\(normalizedRequestedModelId)")
        }
        evidenceLines.append(
            contentsOf: supervisorRouteTruthLines(
                configuredModelId: configured,
                actualModelId: actual,
                mode: mode,
                failureReason: normalizedFailureReason,
                denyCode: normalizedDenyCode,
                auditRef: normalizedAuditRef,
                includeConfiguredRoute: false,
                includeRouteState: true
            ).map { "- \($0)" }
        )
        let evidenceBlock = evidenceLines.isEmpty
            ? ""
            : "\n\n执行证据 / route truth：\n" + evidenceLines.joined(separator: "\n")

        return """
❌ Supervisor 已拒绝接受本次回复：当前配置首选是 \(configured)，但这轮实际执行返回的是 \(actual)。

XT 当前 transport 是 grpc-only，这不属于 XT 本地 auto fallback；更可能是 Hub 端触发了 `downgrade_to_local`，或 `remote_export_blocked` 把 paid 请求降到了本地模型。
为了避免“界面选了 GPT，但实际 quietly 用本地模型继续执行”，这轮结果已按 fail-closed 丢弃。\(evidenceBlock.isEmpty ? "" : evidenceBlock)

下一步：
1. 到 Hub 审计里查 `ai.generate.downgraded_to_local`
2. 查同 request_id 对应的 `remote_export_blocked` deny_code
3. 修完 Hub export gate 后，再重试当前请求
"""
    }
}
