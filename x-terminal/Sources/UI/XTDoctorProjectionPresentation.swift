import Foundation

struct XTDoctorProjectionSummary: Equatable {
    var title: String
    var lines: [String]
}

enum XTDoctorRouteTruthPresentation {
    static func summary(projection: AXModelRouteTruthProjection) -> XTDoctorProjectionSummary {
        XTDoctorProjectionSummary(
            title: "路由真相",
            lines: [
                configuredRouteLine(projection),
                actualRouteLine(projection),
                fallbackReasonLine(projection),
                denyCodeLine(projection),
                budgetExportPostureLine(projection),
                projectionLine(projection)
            ]
        )
    }

    private static func configuredRouteLine(_ projection: AXModelRouteTruthProjection) -> String {
        let completeness = normalizedToken(projection.completeness)
        let bindingText = observedBindingText(projection.winningBinding)

        if completeness == "partial_counts_only" {
            return "configured route：XT 当前只有 incident 计数，还没有单次 configured route 投影。"
        }

        if completeness.hasPrefix("partial_") || completeness == "unknown" {
            if let bindingText {
                return "configured route：上游 route truth 未导出；XT 当前只拿到结果投影，最近一次 observed binding=\(bindingText)。"
            }
            return "configured route：上游 route truth 未导出；XT 当前只知道最近一次结果投影。"
        }

        if let bindingText {
            return "configured route：\(bindingText)"
        }

        return "configured route：未导出"
    }

    private static func actualRouteLine(_ projection: AXModelRouteTruthProjection) -> String {
        let actualRoute = XTRouteTruthPresentation.actualRouteText(
            executionPath: unknownAsEmpty(projection.routeResult.routeSource),
            runtimeProvider: unknownAsEmpty(projection.winningBinding.provider),
            actualModelId: unknownAsEmpty(projection.winningBinding.modelID)
        )
        return "actual route：\(actualRoute)"
    }

    private static func fallbackReasonLine(_ projection: AXModelRouteTruthProjection) -> String {
        let fallbackApplied = normalizedToken(projection.routeResult.fallbackApplied)
        let reasonCode = firstMeaningfulToken(
            projection.routeResult.fallbackReason,
            projection.routeResult.routeReasonCode
        )
        let reasonText = routeReasonText(reasonCode)

        switch fallbackApplied {
        case "true":
            if let reasonText {
                return "fallback reason：\(reasonText)"
            }
            return "fallback reason：已发生 fallback，但原因仍未知"
        case "false":
            if let reasonText {
                return "fallback reason：当前还没进入 fallback；最近停在 \(reasonText)"
            }
            return "fallback reason：none"
        default:
            if let reasonText {
                return "fallback reason：\(reasonText)"
            }
            return "fallback reason：unknown"
        }
    }

    private static func denyCodeLine(_ projection: AXModelRouteTruthProjection) -> String {
        guard let denyCode = explicitDenyCode(
            projection.routeResult.denyCode,
            routeReasonCode: projection.routeResult.routeReasonCode
        ) else {
            return "deny code：未观测到明确 deny code"
        }

        return "deny code：\(denyCodeText(denyCode))"
    }

    private static func budgetExportPostureLine(_ projection: AXModelRouteTruthProjection) -> String {
        let trust = displayToken(projection.requestSnapshot.trustLevel)
        let budget = firstMeaningfulToken(
            projection.constraintSnapshot.budgetClass,
            projection.requestSnapshot.budgetClass
        ) ?? "unknown"
        let remotePolicy = remotePolicyText(
            request: projection.requestSnapshot,
            constraints: projection.constraintSnapshot
        )
        let userPref = allowedStateText(projection.constraintSnapshot.remoteAllowedAfterUserPref)

        return "budget / export posture：trust=\(trust) · budget=\(displayToken(budget)) · remote policy=\(remotePolicy) · user pref=\(userPref)"
    }

    private static func projectionLine(_ projection: AXModelRouteTruthProjection) -> String {
        "projection：source=\(displayToken(projection.projectionSource)) · completeness=\(displayToken(projection.completeness))"
    }

    private static func observedBindingText(_ binding: AXModelRouteTruthWinningBinding) -> String? {
        let provider = normalizedMeaningfulValue(binding.provider)
        let modelID = normalizedMeaningfulValue(binding.modelID)

        if let provider, let modelID {
            return "\(provider) -> \(modelID)"
        }
        if let modelID {
            return modelID
        }
        if let provider {
            return provider
        }
        return nil
    }

    private static func routeReasonText(_ raw: String?) -> String? {
        XTRouteTruthPresentation.routeReasonText(unknownAsEmpty(raw)) ?? normalizedMeaningfulValue(raw)
    }

    private static func explicitDenyCode(_ raw: String?, routeReasonCode: String?) -> String? {
        guard let token = normalizedMeaningfulValue(raw)?.lowercased() else { return nil }
        let routeReason = normalizedMeaningfulValue(routeReasonCode)?.lowercased()

        if token.contains("deny") || token.contains("denied") || token.contains("blocked") {
            return token
        }
        if let routeReason, token != routeReason {
            return token
        }
        return nil
    }

    private static func denyCodeText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "device_remote_export_denied":
            return "当前设备不允许远端 export（device_remote_export_denied）"
        case "policy_remote_denied":
            return "当前策略不允许远端执行（policy_remote_denied）"
        case "budget_remote_denied":
            return "当前预算策略不允许远端执行（budget_remote_denied）"
        case "remote_disabled_by_user_pref":
            return "用户偏好当前禁用了远端执行（remote_disabled_by_user_pref）"
        default:
            return routeReasonText(raw) ?? raw
        }
    }

    private static func remotePolicyText(
        request: AXModelRouteTruthRequestSnapshot,
        constraints: AXModelRouteTruthConstraintSnapshot
    ) -> String {
        if boolish(constraints.policyBlockedRemote) == true {
            return "blocked"
        }
        if let allowed = boolish(constraints.remoteAllowedAfterPolicy) {
            return allowed ? "allowed" : "blocked"
        }
        if let allowed = boolish(request.remoteAllowedByPolicy) {
            return allowed ? "allowed" : "blocked"
        }
        return "unknown"
    }
}

enum XTDoctorDurableCandidateMirrorPresentation {
    static func summary(
        projection: XTUnifiedDoctorDurableCandidateMirrorProjection
    ) -> XTDoctorProjectionSummary {
        var lines = [
            "mirror status：\(statusText(projection.status))",
            "mirror target：\(targetText(projection.target))",
            "local store role：\(displayToken(projection.localStoreRole))",
            "durable boundary：XT 本地候选只做 cache/fallback/edit buffer；durable write 仍经 Hub Writer + Gate。"
        ]

        if let errorCode = normalizedMeaningfulValue(projection.errorCode) {
            lines.append("mirror reason：\(reasonText(errorCode))")
        }

        return XTDoctorProjectionSummary(
            title: "记忆镜像边界",
            lines: lines
        )
    }

    private static func statusText(_ status: SupervisorDurableCandidateMirrorStatus) -> String {
        switch status {
        case .notNeeded:
            return "当前不需要向 Hub 镜像 durable candidates"
        case .pending:
            return "已进入 Hub 镜像队列"
        case .mirroredToHub:
            return "已镜像到 Hub"
        case .localOnly:
            return "当前只保留 XT 本地候选"
        case .hubMirrorFailed:
            return "尝试写入 Hub，但镜像失败"
        }
    }

    private static func targetText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case XTSupervisorDurableCandidateMirror.mirrorTarget:
            return "Hub candidate carrier（shadow thread）"
        default:
            return displayToken(raw)
        }
    }

    private static func reasonText(_ raw: String) -> String {
        switch normalizedToken(raw) {
        case "remote_route_not_preferred":
            return "当前远端路由不是首选（remote_route_not_preferred）"
        case "runtime_not_running":
            return "Hub 远端运行时未启动（runtime_not_running）"
        case "hub_append_failed":
            return "Hub append 未成功完成（hub_append_failed）"
        case "candidate_payload_empty":
            return "候选负载为空，Hub 无法接收（candidate_payload_empty）"
        case "supervisor_candidate_session_participation_invalid":
            return "candidate session participation 非法（supervisor_candidate_session_participation_invalid）"
        case "supervisor_candidate_session_participation_denied":
            return "candidate 不允许进入 scoped_write 会话（supervisor_candidate_session_participation_denied）"
        case "supervisor_candidate_scope_mismatch":
            return "candidate 写权限 scope 与记录 scope 不一致（supervisor_candidate_scope_mismatch）"
        default:
            return XTDoctorRouteTruthPresentation.summaryTextFallback(raw)
        }
    }
}

private extension XTDoctorRouteTruthPresentation {
    static func summaryTextFallback(_ raw: String) -> String {
        routeReasonText(raw) ?? XTMemorySourceTruthPresentation.humanizeToken(raw)
    }
}

private func normalizedMeaningfulValue(_ raw: String?) -> String? {
    let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    switch trimmed.lowercased() {
    case "unknown", "none", "(none)", "n/a":
        return nil
    default:
        return trimmed
    }
}

private func normalizedToken(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw)?.lowercased() ?? "unknown"
}

private func displayToken(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw) ?? "unknown"
}

private func firstMeaningfulToken(_ values: String?...) -> String? {
    for value in values {
        if let token = normalizedMeaningfulValue(value) {
            return token
        }
    }
    return nil
}

private func unknownAsEmpty(_ raw: String?) -> String {
    normalizedMeaningfulValue(raw) ?? ""
}

private func boolish(_ raw: String?) -> Bool? {
    switch normalizedToken(raw) {
    case "true", "yes", "allowed":
        return true
    case "false", "no", "blocked", "denied":
        return false
    default:
        return nil
    }
}

private func allowedStateText(_ raw: String?) -> String {
    guard let value = boolish(raw) else { return "unknown" }
    return value ? "allowed" : "blocked"
}
