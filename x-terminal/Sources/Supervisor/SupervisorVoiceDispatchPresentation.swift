import Foundation

struct SupervisorVoiceDispatchAuditEntry: Identifiable, Equatable {
    var id: String
    var createdAt: Double
    var source: String
    var state: String
    var reasonCode: String
    var detail: String
}

struct SupervisorVoiceDispatchPresentation: Equatable {
    var text: String
    var helpText: String?
    var headerTone: SupervisorHeaderStatusTone
    var surfaceState: XTUISurfaceState
}

enum SupervisorVoiceDispatchPresentationResolver {
    static func map(
        latestRuntimeActivityText: String?
    ) -> SupervisorVoiceDispatchPresentation? {
        guard let event = parseRuntimeEvent(latestRuntimeActivityText) else {
            return nil
        }

        let state = event.state
        let source = event.source
        let reason = event.reasonCode
        let detail = event.detail

        if state == "suppressed"
            && (reason == "source_duplicate_suppressed"
                || reason == "cross_source_duplicate_suppressed"
                || reason == "inflight_duplicate_suppressed"
                || reason == "duplicate_suppressed") {
            let detailText = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let helpText: String
            if reason == "cross_source_duplicate_suppressed" && !detailText.isEmpty {
                helpText = "短时间内来自不同来源的重复语音已被自动去重，不再重复播报。上一条来源：\(sourceLabel(for: detailText))。"
            } else {
                helpText = "同一来源或同一内容的短时间重复语音已被自动去重，不再重复播报。"
            }
            return SupervisorVoiceDispatchPresentation(
                text: "已抑制重复播报",
                helpText: helpText,
                headerTone: .success,
                surfaceState: .ready
            )
        }

        if state == "cancelled",
           source == "heartbeat",
           reason.hasPrefix("preempted_by_") {
            let replacement = reason
                .replacingOccurrences(of: "preempted_by_", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let replacementText = replacement.isEmpty ? "新的语音任务" : replacement
            return SupervisorVoiceDispatchPresentation(
                text: "已取消旧心跳",
                helpText: "为避免旧心跳和新播报重叠，上一条心跳语音已取消。接管来源：\(replacementText)。",
                headerTone: .neutral,
                surfaceState: .inProgress
            )
        }

        if state == "dropped",
           source == "heartbeat",
           reason == "stale_generation" {
            let detailText = detail.isEmpty ? "心跳语音结果" : detail
            return SupervisorVoiceDispatchPresentation(
                text: "已丢弃过期心跳",
                helpText: "旧的心跳语音已过期，已在播报前丢弃。来源：\(detailText)。",
                headerTone: .neutral,
                surfaceState: .ready
            )
        }

        return nil
    }

    static func auditChip(
        entries: [SupervisorVoiceDispatchAuditEntry],
        limit: Int = 3
    ) -> SupervisorConversationVoiceRailChip? {
        let selected = Array(entries.prefix(max(0, limit)))
        guard !selected.isEmpty else { return nil }

        let ordered = selected.sorted { $0.createdAt < $1.createdAt }
        let labels = ordered.map { sourceLabel(for: $0.source) }
        let latest = selected.first ?? ordered.last!
        let helpLines = ordered.enumerated().map { index, entry in
            let detailText = entry.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            let suffix = detailText.isEmpty ? "" : "（\(sourceLabel(for: detailText))）"
            return "\(index + 1). \(sourceLabel(for: entry.source)) - \(stateLabel(for: entry))\(suffix)"
        }

        return SupervisorConversationVoiceRailChip(
            id: "voice_dispatch_audit",
            text: "最近语音：\(labels.joined(separator: " → "))",
            state: auditSurfaceState(for: latest),
            prefersMonospacedText: false,
            helpText: helpLines.joined(separator: "\n")
        )
    }

    private static func parseRuntimeEvent(
        _ text: String?
    ) -> SupervisorVoiceDispatchAuditEntry? {
        guard let trimmed = text?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.hasPrefix("voice_dispatch") else {
            return nil
        }

        let tokens = runtimeTokens(trimmed)
        return SupervisorVoiceDispatchAuditEntry(
            id: UUID().uuidString.lowercased(),
            createdAt: 0,
            source: tokens["source"] ?? "",
            state: tokens["state"] ?? "",
            reasonCode: tokens["reason"] ?? "",
            detail: tokens["detail"] ?? ""
        )
    }

    private static func sourceLabel(
        for rawSource: String
    ) -> String {
        let source = rawSource.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == "heartbeat" {
            return "心跳"
        }
        if source == "voice_skill" {
            return "显式播报"
        }
        if source == "user_query_reply" {
            return "自然回复"
        }
        if source == "voice_authorization" {
            return "语音授权"
        }
        if source == "voice_preview" {
            return "语音预览"
        }
        if source == "pending_grant_arrival" {
            return "Grant 到达"
        }
        if source == "pending_grant_follow_up" {
            return "Grant 跟进"
        }
        if source == "pending_skill_approval_arrival" {
            return "技能审批"
        }
        if source == "brief_projection_reply" {
            return "投影回复"
        }
        if source == "voice_input" {
            return "语音输入"
        }
        if source.hasPrefix("operator_xt_command:") {
            return "远程命令"
        }
        if source.hasPrefix("connector_ingress:") {
            return "外部入口"
        }
        return source.replacingOccurrences(of: "_", with: " ")
    }

    private static func stateLabel(
        for entry: SupervisorVoiceDispatchAuditEntry
    ) -> String {
        switch entry.state {
        case "spoken":
            return "已播报"
        case "suppressed":
            if entry.reasonCode == "cross_source_duplicate_suppressed"
                || entry.reasonCode == "source_duplicate_suppressed"
                || entry.reasonCode == "inflight_duplicate_suppressed"
                || entry.reasonCode == "duplicate_suppressed" {
                return "已抑制重复"
            }
            return "已抑制"
        case "cancelled":
            return "已取消"
        case "dropped":
            return "已丢弃"
        default:
            return entry.state
        }
    }

    private static func auditSurfaceState(
        for entry: SupervisorVoiceDispatchAuditEntry
    ) -> XTUISurfaceState {
        switch entry.state {
        case "spoken":
            return .ready
        case "suppressed":
            return .blockedWaitingUpstream
        case "cancelled":
            return .inProgress
        case "dropped":
            return .ready
        default:
            return .ready
        }
    }

    private static func runtimeTokens(
        _ text: String
    ) -> [String: String] {
        var result: [String: String] = [:]

        for token in text.split(separator: " ") {
            guard let separator = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<separator])
            let value = String(token[token.index(after: separator)...])
            result[key] = value
        }

        return result
    }
}
