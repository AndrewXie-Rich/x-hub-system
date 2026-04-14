import SwiftUI

struct ExecutionRouteBadgePresentation {
    var text: String
    var color: Color
}

enum ExecutionRoutePresentation {
    static func shortModelLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "auto" }
        if let slash = trimmed.lastIndex(of: "/") {
            let suffix = trimmed[trimmed.index(after: slash)...]
            if suffix.count <= 30 {
                return String(suffix)
            }
        }
        if trimmed.count <= 30 {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 30)
        return String(trimmed[..<end]) + "..."
    }

    static func shortReasonLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        if trimmed.count <= 28 {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 28)
        return String(trimmed[..<end]) + "..."
    }

    static func displayReasonText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return XTRouteTruthPresentation.routeReasonDisplayText(trimmed) ?? trimmed
    }

    static func displayDenyCodeText(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return XTRouteTruthPresentation.denyCodeText(trimmed)
            ?? XTRouteTruthPresentation.routeReasonDisplayText(trimmed)
            ?? trimmed
    }

    static func shortAuditLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }
        if trimmed.count <= 24 {
            return trimmed
        }
        let end = trimmed.index(trimmed.startIndex, offsetBy: 24)
        return String(trimmed[..<end]) + "..."
    }

    static func normalizedModelIdentity(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func modelIdentitiesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = normalizedModelIdentity(lhs)
        let right = normalizedModelIdentity(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right {
            return true
        }

        let leftQualified = left.contains("/")
        let rightQualified = right.contains("/")
        guard !leftQualified || !rightQualified else { return false }

        let leftBase = left.split(separator: "/").last.map(String.init) ?? left
        let rightBase = right.split(separator: "/").last.map(String.init) ?? right
        return !leftBase.isEmpty && leftBase == rightBase
    }

    static func configuredModelLabel(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !configured.isEmpty {
            return shortModelLabel(configured)
        }

        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty {
            return shortModelLabel(requested)
        }

        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !actual.isEmpty {
            return shortModelLabel(actual)
        }

        return "auto"
    }

    static func activeModelLabel(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> String {
        configuredModelLabel(
            configuredModelId: configuredModelId,
            snapshot: snapshot
        )
    }

    static func actualModelLabel(snapshot: AXRoleExecutionSnapshot) -> String? {
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !actual.isEmpty else { return nil }
        return shortModelLabel(actual)
    }

    static func reasonBadge(snapshot: AXRoleExecutionSnapshot) -> ExecutionRouteBadgePresentation? {
        let reason = snapshot.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reason.isEmpty else { return nil }

        switch snapshot.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime", "remote_error":
            return ExecutionRouteBadgePresentation(
                text: "Reason \(compactIssueLabel(displayReasonText(reason) ?? reason))",
                color: statusColor(snapshot: snapshot)
            )
        default:
            return nil
        }
    }

    static func routeSummaryText(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) -> String? {
        guard snapshot.hasRecord else { return nil }
        let transportMode = HubAIClient.transportMode()
        var lines = XTRouteTruthPresentation.evidence(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode.rawValue,
            paidAccessSnapshot: paidAccessSnapshot
        )
        .lines
        if let supervisorHint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: snapshot.effectiveFailureReasonCode,
            denyCode: snapshot.denyCode
        ) {
            lines.append("repair hint=\(supervisorHint.repairHintText)")
        }
        if let hint = grpcInterpretationText(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode
        ) {
            lines.append(hint)
        }
        return lines.joined(separator: "；")
    }

    static func grpcTransportMismatchHint(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage
    ) -> String {
        guard snapshot.hasRecord else { return "" }
        guard isGrpcTransport(transportMode) else { return "" }

        let configured = normalized(configuredModelId) ?? normalized(snapshot.requestedModelId)
        let actual = normalized(snapshot.actualModelId)
        let hasMismatch = {
            guard let configured, let actual else { return false }
            return !modelIdentitiesMatch(configured, actual)
        }()

        switch normalized(snapshot.executionPath) {
        case "hub_downgraded_to_local":
            return XTL10n.text(
                language,
                zhHans: " 当前 transport 是 grpc-only；如果最近实际仍落到本地，更像 Hub 执行阶段降级或 export gate 生效，不是设置页把模型静默改成了本地。",
                en: " The current transport is grpc-only. If the latest actual route still landed on local, it is more likely a Hub-side downgrade or export gate than the settings page silently changing the model to local."
            )
        case "local_fallback_after_remote_error":
            return XTL10n.text(
                language,
                zhHans: " 当前 transport 是 grpc-only；如果最近实际仍落到本地，更像上游远端不可用、provider 未 ready，或执行链失败，不是设置页把模型静默改成了本地。",
                en: " The current transport is grpc-only. If the latest actual route still landed on local, it is more likely upstream remote unavailability, provider readiness, or execution-chain failure than the settings page silently changing the model to local."
            )
        case "remote_error":
            return XTL10n.text(
                language,
                zhHans: " 当前 transport 是 grpc-only；最近停在失败态，说明 XT 没把这轮悄悄改成本地，优先检查 Hub 与上游远端链路。",
                en: " The current transport is grpc-only. The latest route stopped in a failed state, which means XT did not silently convert this turn to local. Check Hub and the upstream remote path first."
            )
        default:
            guard hasMismatch else { return "" }
            return XTL10n.text(
                language,
                zhHans: " 当前 transport 是 grpc-only；如果 configured route 和 actual route 仍不一致，更可能是 Hub 执行阶段改派，不是设置页把模型静默改写成了别的目标。",
                en: " The current transport is grpc-only. If the configured route and actual route still differ, a Hub-side execution reroute is more likely than the settings page silently rewriting the model target."
            )
        }
    }

    static func recentGrpcRouteTruthHint(
        snapshot: AXRoleExecutionSnapshot,
        transportMode: String,
        language: XTInterfaceLanguage
    ) -> String {
        guard snapshot.hasRecord else { return "" }
        guard isGrpcTransport(transportMode) else { return "" }

        switch normalized(snapshot.executionPath) {
        case "hub_downgraded_to_local":
            return XTL10n.text(
                language,
                zhHans: "当前 transport 是 grpc-only；最近一次 route truth 里实际落到本地，更像 Hub 执行阶段降级或 export gate 生效，不是 XT 把这次设置静默改成本地。",
                en: "The current transport is grpc-only. The latest route truth still landed on local, which looks more like a Hub-side downgrade or export gate than XT silently rewriting this setting to local."
            )
        case "local_fallback_after_remote_error":
            return XTL10n.text(
                language,
                zhHans: "当前 transport 是 grpc-only；最近一次 route truth 里实际落到本地，更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 把这次设置静默改成本地。",
                en: "The current transport is grpc-only. The latest route truth still landed on local, which looks more like upstream remote unavailability, provider readiness, or execution-chain failure than XT silently rewriting this setting to local."
            )
        case "remote_error":
            return XTL10n.text(
                language,
                zhHans: "当前 transport 是 grpc-only；最近一次 route truth 停在失败态，说明 XT 没把请求静默改成本地，优先检查 Hub 与上游远端链路。",
                en: "The current transport is grpc-only. The latest route truth stopped in a failed state, which means XT did not silently convert the request to local. Check Hub and the upstream remote path first."
            )
        default:
            return ""
        }
    }

    static func detailBadge(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot
    ) -> ExecutionRouteBadgePresentation? {
        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = !configured.isEmpty ? configured : requested
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = snapshot.effectiveFailureReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && !modelIdentitiesMatch(target, actual)

        switch snapshot.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            if !actual.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "\(runtimeBadgePrefix(snapshot: snapshot)) \(shortModelLabel(actual))",
                    color: statusColor(snapshot: snapshot)
                )
            }
            if !reason.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "Reason \(compactIssueLabel(displayReasonText(reason) ?? reason))",
                    color: statusColor(snapshot: snapshot)
                )
            }
        case "remote_model", "direct_provider":
            if hasMismatch {
                return ExecutionRouteBadgePresentation(
                    text: "Actual \(shortModelLabel(actual))",
                    color: .orange
                )
            }
        case "remote_error":
            if !reason.isEmpty {
                return ExecutionRouteBadgePresentation(
                    text: "Reason \(compactIssueLabel(displayReasonText(reason) ?? reason))",
                    color: .red
                )
            }
        default:
            if hasMismatch {
                return ExecutionRouteBadgePresentation(
                    text: "Actual \(shortModelLabel(actual))",
                    color: .orange
                )
            }
        }

        return nil
    }

    static func interpretationBadge(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> ExecutionRouteBadgePresentation? {
        guard let text = compactGrpcInterpretationText(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode
        ) else {
            return nil
        }

        let color: Color = snapshot.executionPath == "remote_error" ? .red : .orange
        return ExecutionRouteBadgePresentation(text: text, color: color)
    }

    static func evidenceBadge(snapshot: AXRoleExecutionSnapshot) -> ExecutionRouteBadgePresentation? {
        let denyCode = snapshot.denyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !denyCode.isEmpty {
            return ExecutionRouteBadgePresentation(
                text: "Deny \(compactIssueLabel(displayDenyCodeText(denyCode) ?? denyCode))",
                color: snapshot.executionPath == "remote_error" ? .red : .orange
            )
        }

        let auditRef = snapshot.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !auditRef.isEmpty else { return nil }
        return ExecutionRouteBadgePresentation(
            text: "Audit \(shortAuditLabel(auditRef))",
            color: .secondary
        )
    }

    static func statusText(snapshot: AXRoleExecutionSnapshot) -> String {
        switch snapshot.executionPath {
        case "remote_model":
            return "Remote"
        case "direct_provider":
            return "Direct"
        case "hub_downgraded_to_local":
            return "Downgraded"
        case "local_fallback_after_remote_error":
            return "Fallback"
        case "local_runtime":
            return "Local"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return "Control"
        case "remote_error":
            return "Failed"
        default:
            return snapshot.hasRecord ? "Observed" : "Pending"
        }
    }

    static func inlineExplanationText(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> String? {
        guard snapshot.hasRecord else { return nil }

        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = configured.isEmpty ? requested : configured
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && !modelIdentitiesMatch(target, actual)
        let normalizedReason = normalizedIssueCode(snapshot.effectiveFailureReasonCode)
        let normalizedDenyCode = normalizedIssueCode(snapshot.denyCode)

        if let supervisorHint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: normalizedReason,
            denyCode: normalizedDenyCode
        ) {
            return "\(supervisorHint.summaryText) \(supervisorHint.repairHintText)"
        }

        if isRemoteExportGateIssue(normalizedReason) || isRemoteExportGateIssue(normalizedDenyCode) {
            switch snapshot.executionPath {
            case "hub_downgraded_to_local", "local_fallback_after_remote_error", "remote_error":
                return "这更像是 Hub remote export gate、设备范围或策略把 paid 远端挡住了，不是 XT 静默改成本地。"
            default:
                break
            }
        }

        switch snapshot.executionPath {
        case "hub_downgraded_to_local":
            if transportMode == .grpc {
                return "这更像是 Hub 在执行阶段把远端请求降到了本地，不是 XT 静默改路由。"
            }
            return "这轮是 Hub 执行阶段降到本地，不是你在 XT 里手动切成了本地。"
        case "local_fallback_after_remote_error":
            return "这更像是远端没 ready 或执行链失败后由本地兜底，不是 XT 静默改成本地。"
        case "local_runtime":
            guard hasMismatch else { return nil }
            return "当前项目先走本地；通常是项目级本地锁，或上一轮 fallback 后继续由本地接管。"
        case "remote_error":
            return "这轮停在远端失败态，先看 Hub 链路、provider ready 和上游错误。"
        case "remote_model", "direct_provider":
            guard hasMismatch else { return nil }
            if snapshot.remoteRetryAttempted,
               !snapshot.remoteRetryToModelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "这轮命中的是远端备选，不是配置里的精确目标。"
            }
            if transportMode == .grpc {
                return "命中了远端但不是配置目标，更像 Hub 执行阶段改派，不是 XT 静默改写模型。"
            }
            return "命中了远端但不是配置目标，可能是远端备选或 Hub 执行阶段改派。"
        default:
            return nil
        }
    }

    static func statusColor(snapshot: AXRoleExecutionSnapshot) -> Color {
        switch snapshot.executionPath {
        case "remote_model", "direct_provider":
            return .green
        case "hub_downgraded_to_local", "local_fallback_after_remote_error":
            return .orange
        case "local_runtime":
            return .yellow
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return .yellow
        case "remote_error":
            return .red
        default:
            return .secondary
        }
    }

    static func tooltip(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        paidAccessSnapshot: HubRemotePaidAccessSnapshot? = nil
    ) -> String {
        let transportMode = HubAIClient.transportMode()
        var lines = XTRouteTruthPresentation.evidence(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode.rawValue,
            paidAccessSnapshot: paidAccessSnapshot
        )
        .lines
        if let supervisorHint = XTRouteTruthPresentation.supervisorRouteGovernanceHint(
            routeReasonCode: snapshot.effectiveFailureReasonCode,
            denyCode: snapshot.denyCode
        ) {
            lines.append("repair hint=\(supervisorHint.repairHintText)")
        }
        if let hint = grpcInterpretationText(
            configuredModelId: configuredModelId,
            snapshot: snapshot,
            transportMode: transportMode
        ) {
            lines.append(hint)
        }
        return lines.joined(separator: "\n")
    }

    @MainActor
    static func supervisorSnapshot(from manager: SupervisorManager) -> AXRoleExecutionSnapshot {
        let mode = manager.lastSupervisorReplyExecutionMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let executionPath: String
        switch mode {
        case "remote_model":
            executionPath = "remote_model"
        case "hub_downgraded_to_local":
            executionPath = "hub_downgraded_to_local"
        case "local_fallback_after_remote_error":
            executionPath = "local_fallback_after_remote_error"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            executionPath = mode
        default:
            executionPath = "no_record"
        }

        let runtimeProvider: String
        switch executionPath {
        case "remote_model":
            runtimeProvider = "Hub (Remote)"
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            runtimeProvider = "Hub (Local)"
        default:
            runtimeProvider = ""
        }

        return AXRoleExecutionSnapshots.snapshot(
            role: .supervisor,
            updatedAt: Date().timeIntervalSince1970,
            stage: "supervisor",
            requestedModelId: manager.lastSupervisorRequestedModelId,
            actualModelId: manager.lastSupervisorActualModelId,
            runtimeProvider: runtimeProvider,
            executionPath: executionPath,
            fallbackReasonCode: manager.lastSupervisorRemoteFailureReasonCode,
            source: "supervisor_live_state"
        )
    }

    private static func runtimeBadgePrefix(snapshot: AXRoleExecutionSnapshot) -> String {
        switch snapshot.executionPath {
        case "hub_downgraded_to_local", "local_fallback_after_remote_error", "local_runtime":
            return "Local"
        case "local_preflight", "local_direct_reply", "local_direct_action", "hub_brief_projection":
            return "Control"
        case "remote_model":
            return "Remote"
        case "direct_provider":
            return "Direct"
        default:
            let provider = snapshot.runtimeProvider.trimmingCharacters(in: .whitespacesAndNewlines)
            return provider.isEmpty ? "Actual" : shortModelLabel(provider)
        }
    }

    private static func grpcInterpretationText(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> String? {
        guard snapshot.hasRecord, transportMode == .grpc else { return nil }

        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = configured.isEmpty ? requested : configured
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && !modelIdentitiesMatch(target, actual)

        switch snapshot.executionPath {
        case "hub_downgraded_to_local":
            return "grpc-only 提示：这次落到本地更像 Hub 执行阶段降级或 export gate 生效，不是 XT 静默改成本地。"
        case "local_fallback_after_remote_error":
            return "grpc-only 提示：这次落到本地更像上游远端不可用、provider 未 ready，或执行链失败，不是 XT 静默改成本地。"
        case "remote_error":
            return "grpc-only 提示：这轮停在失败态，XT 没有把请求静默改成本地，优先检查 Hub 和上游远端链路。"
        default:
            guard hasMismatch else { return nil }
            return "grpc-only 提示：configured route 和 actual route 不一致，更像 Hub 执行阶段改派，不是 XT 静默改写模型。"
        }
    }

    private static func compactGrpcInterpretationText(
        configuredModelId: String,
        snapshot: AXRoleExecutionSnapshot,
        transportMode: HubTransportMode = HubAIClient.transportMode()
    ) -> String? {
        guard snapshot.hasRecord, transportMode == .grpc else { return nil }

        let configured = configuredModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = snapshot.requestedModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = configured.isEmpty ? requested : configured
        let actual = snapshot.actualModelId.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasMismatch = !target.isEmpty && !actual.isEmpty && !modelIdentitiesMatch(target, actual)
        let normalizedReason = normalizedIssueCode(snapshot.effectiveFailureReasonCode)
        let normalizedDenyCode = normalizedIssueCode(snapshot.denyCode)

        switch snapshot.executionPath {
        case "hub_downgraded_to_local":
            return "Hub Downgrade"
        case "local_fallback_after_remote_error":
            if isRemoteExportGateIssue(normalizedReason) || isRemoteExportGateIssue(normalizedDenyCode) {
                return "Hub Gate"
            }
            return "Upstream Issue"
        case "remote_error":
            return "Remote Error"
        default:
            guard hasMismatch else { return nil }
            return "Hub Reroute"
        }
    }

    private static func compactIssueLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "unknown" }

        let strippedMachineCode = trimmed
            .replacingOccurrences(
                of: #"\s*（[^）]+）\s*$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\s*\([^)]+\)\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate = strippedMachineCode.isEmpty ? trimmed : strippedMachineCode
        guard candidate.count > 30 else { return candidate }
        let end = candidate.index(candidate.startIndex, offsetBy: 30)
        return String(candidate[..<end]) + "..."
    }

    private static func normalizedIssueCode(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func isRemoteExportGateIssue(_ raw: String) -> Bool {
        [
            "remote_export_blocked",
            "device_remote_export_denied",
            "policy_remote_denied",
            "budget_remote_denied",
            "remote_disabled_by_user_pref"
        ].contains(raw)
    }

    private static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isGrpcTransport(_ raw: String) -> Bool {
        switch normalized(raw)?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_") {
        case "grpc", "grpc_only":
            return true
        default:
            return false
        }
    }
}
