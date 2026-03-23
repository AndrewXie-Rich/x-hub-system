import Foundation

struct XTRouteTruthEvidence: Equatable {
    var configuredRouteLine: String
    var actualRouteLine: String
    var fallbackReasonLine: String?
    var routeStateLine: String
    var auditRefLine: String?
    var transportLine: String?
    var denyCodeLine: String?

    var lines: [String] {
        [
            configuredRouteLine,
            actualRouteLine,
            fallbackReasonLine,
            routeStateLine,
            auditRefLine,
            denyCodeLine,
            transportLine
        ]
        .compactMap { line in
            let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    var inlineText: String {
        lines.joined(separator: "；")
    }
}

enum XTRouteTruthPresentation {
    static func evidence(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String
    ) -> XTRouteTruthEvidence {
        let configuredTarget = normalized(configuredModelId)
            ?? normalized(snapshot.requestedModelId)
            ?? "auto"
        let actualRoute = actualRouteText(
            executionPath: snapshot.executionPath,
            runtimeProvider: snapshot.runtimeProvider,
            actualModelId: snapshot.actualModelId
        )
        let fallbackReason = routeReasonText(snapshot.fallbackReasonCode)
        let auditRef = normalized(snapshot.auditRef)
        let denyCode = normalized(snapshot.denyCode)

        return XTRouteTruthEvidence(
            configuredRouteLine: "configured route=\(configuredTarget)",
            actualRouteLine: "actual route=\(actualRoute)",
            fallbackReasonLine: fallbackReason.map { "fallback reason=\($0)" },
            routeStateLine: "route state=\(routeStateText(executionPath: snapshot.executionPath, fallbackReasonCode: snapshot.fallbackReasonCode))",
            auditRefLine: auditRef.map { "audit_ref=\($0)" },
            transportLine: normalized(transportMode).map { "transport=\($0)" },
            denyCodeLine: denyCode.map { "deny_code=\($0)" }
        )
    }

    static func evidence(
        latestEvent: AXModelRouteDiagnosticEvent
    ) -> XTRouteTruthEvidence {
        let configuredTarget = normalized(latestEvent.requestedModelId) ?? "auto"
        let actualRoute = actualRouteText(
            executionPath: latestEvent.executionPath,
            runtimeProvider: latestEvent.runtimeProvider,
            actualModelId: latestEvent.actualModelId
        )
        let fallbackReason = routeReasonText(latestEvent.fallbackReasonCode)
        let auditRef = normalized(latestEvent.auditRef)
        let denyCode = normalized(latestEvent.denyCode)

        return XTRouteTruthEvidence(
            configuredRouteLine: "configured route=\(configuredTarget)",
            actualRouteLine: "actual route=\(actualRoute)",
            fallbackReasonLine: fallbackReason.map { "fallback reason=\($0)" },
            routeStateLine: "route state=\(routeStateText(executionPath: latestEvent.executionPath, fallbackReasonCode: latestEvent.fallbackReasonCode))",
            auditRefLine: auditRef.map { "audit_ref=\($0)" },
            transportLine: nil,
            denyCodeLine: denyCode.map { "deny_code=\($0)" }
        )
    }

    static func focusDetail(
        latestEvent: AXModelRouteDiagnosticEvent?,
        fallback: String
    ) -> String {
        guard let latestEvent else { return fallback }
        let evidence = evidence(latestEvent: latestEvent)
        return evidence.inlineText.isEmpty ? fallback : "\(evidence.inlineText)。\(fallback)"
    }

    static func actualRouteText(
        executionPath: String,
        runtimeProvider: String,
        actualModelId: String
    ) -> String {
        let provider = normalized(runtimeProvider) ?? providerLabel(executionPath: executionPath)
        let actualModel = normalized(actualModelId)
        let path = normalized(executionPath)

        if let provider, let actualModel, let path {
            return "\(provider) -> \(actualModel) [\(path)]"
        }
        if let provider, let actualModel {
            return "\(provider) -> \(actualModel)"
        }
        if let actualModel, let path {
            return "\(actualModel) [\(path)]"
        }
        if let provider, let path {
            return "\(provider) [\(path)]"
        }
        if let provider {
            return provider
        }
        if let actualModel {
            return actualModel
        }
        if let path {
            return path
        }
        return "未观测到稳定执行"
    }

    private static func providerLabel(executionPath: String) -> String? {
        switch normalized(executionPath) {
        case "remote_model":
            return "Hub (Remote)"
        case "direct_provider":
            return "Direct Provider"
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            return "Hub (Local)"
        case "remote_error":
            return "Remote Attempt"
        default:
            return nil
        }
    }

    static func routeReasonText(_ raw: String?) -> String? {
        guard let token = normalized(raw)?.lowercased() else { return nil }

        switch token {
        case "downgrade_to_local":
            return "Hub 端把远端请求降到本地（downgrade_to_local）"
        case "remote_export_blocked":
            return "Hub remote export gate 阻断了远端请求（remote_export_blocked）"
        case "blocked_waiting_upstream":
            return "上游还没准备好，当前保持等待态（blocked_waiting_upstream）"
        case "provider_not_ready":
            return "provider 尚未 ready（provider_not_ready）"
        case "grpc_route_unavailable":
            return "grpc 路由当前不可用（grpc_route_unavailable）"
        case "runtime_not_running":
            return "运行时尚未启动（runtime_not_running）"
        case "request_write_failed":
            return "请求没有成功写到上游（request_write_failed）"
        case "remote_unreachable":
            return "远端链路不可达（remote_unreachable）"
        case "remote_timeout":
            return "远端请求超时（remote_timeout）"
        case "response_timeout":
            return "上游响应超时（response_timeout）"
        case "model_not_found":
            return "目标模型当前不在可执行清单里（model_not_found）"
        case "remote_model_not_found":
            return "目标远端模型当前不可用（remote_model_not_found）"
        default:
            return token
        }
    }

    private static func routeStateText(
        executionPath: String,
        fallbackReasonCode: String
    ) -> String {
        let path = normalized(executionPath)?.lowercased() ?? ""
        let reason = normalized(fallbackReasonCode)?.lowercased() ?? ""

        switch path {
        case "remote_model":
            return "当前实际已经命中远端执行。"
        case "direct_provider":
            return "当前直接走 provider 路由，不经过 Hub 降级链。"
        case "hub_downgraded_to_local":
            if reason == "remote_export_blocked" {
                return "配置希望走远端，但 Hub export gate 直接把请求收回到了本地。"
            }
            return "配置希望走远端，但这轮执行被 Hub 降到了本地。"
        case "local_fallback_after_remote_error":
            if reason == "blocked_waiting_upstream" || reason == "provider_not_ready" {
                return "远端链路还没 ready，当前先由本地接住。"
            }
            return "远端尝试没有稳定成功，当前已回退到本地继续。"
        case "local_runtime":
            return "当前这轮就是本地执行，不存在远端命中。"
        case "remote_error":
            if reason == "blocked_waiting_upstream" {
                return "当前远端链路被上游阻塞，XT 保持等待/失败可见。"
            }
            if reason == "provider_not_ready" || reason == "runtime_not_running" {
                return "当前远端 provider 还没 ready，所以路由停在失败态。"
            }
            return "这轮远端路由没有成功命中，需要继续看 fallback reason 和上游状态。"
        default:
            if reason == "blocked_waiting_upstream" {
                return "当前链路仍在等待上游，不应把它误判成已经成功命中。"
            }
            if reason == "provider_not_ready" {
                return "当前 provider 尚未 ready，所以还不能把 configured route 当成 actual route。"
            }
            return "当前还没有足够证据证明 configured route 已和 actual route 一致。"
        }
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
