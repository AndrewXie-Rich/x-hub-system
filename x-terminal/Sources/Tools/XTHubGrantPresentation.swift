import Foundation

enum XTHubGrantPresentation {
    enum DecisionIntent {
        case approve
        case deny
    }

    static func capabilityLabel(
        capability: String,
        modelId: String
    ) -> String {
        let normalizedCapability = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanedModelID = modelId.trimmingCharacters(in: .whitespacesAndNewlines)

        if normalizedCapability.contains("web_fetch") || normalizedCapability.contains("web.fetch") {
            return "联网访问"
        }
        if normalizedCapability.contains("ai_generate_paid") || normalizedCapability.contains("ai.generate.paid") {
            return cleanedModelID.isEmpty ? "付费模型调用" : "付费模型调用（\(cleanedModelID)）"
        }
        if normalizedCapability.contains("ai_generate_local") || normalizedCapability.contains("ai.generate.local") {
            return cleanedModelID.isEmpty ? "本地模型调用" : "本地模型调用（\(cleanedModelID)）"
        }
        if normalizedCapability.isEmpty {
            return "高风险能力"
        }
        return capability.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func awaitingSummary(
        capability: String,
        modelId: String
    ) -> String {
        "等待 Hub 授权后才能继续：\(capabilityLabel(capability: capability, modelId: modelId))。"
    }

    static func awaitingStateSummary(
        capability: String,
        modelId: String,
        grantRequestId: String?
    ) -> String {
        var parts = ["waiting for Hub grant approval"]
        let capabilityText = capabilityLabel(capability: capability, modelId: modelId)
        let cleanedCapability = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedCapability.isEmpty || !cleanedModelId.isEmpty {
            parts.append(capabilityText)
        }
        let grantText = (grantRequestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !grantText.isEmpty {
            parts.append("grant=\(grantText)")
        }
        return parts.joined(separator: " · ")
    }

    static func deniedStateSummary(
        capability: String,
        modelId: String,
        deniedByUser: Bool
    ) -> String {
        let prefix = deniedByUser ? "Hub grant denied by user" : "Hub grant denied"
        let cleanedCapability = capability.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedCapability.isEmpty || !cleanedModelId.isEmpty else {
            return prefix
        }
        return "\(prefix) · \(capabilityLabel(capability: capability, modelId: modelId))"
    }

    static func emptyPendingReply(projectName: String?) -> String {
        let cleanedProjectName = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedProjectName.isEmpty {
            return "当前没有待处理的 Hub grant。"
        }
        return "项目 \(cleanedProjectName) 当前没有待处理的 Hub grant。"
    }

    static func ambiguityHeader(projectName: String?) -> String {
        let cleanedProjectName = (projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedProjectName.isEmpty {
            return "当前有多个待处理 Hub grant，我不能替你盲选。"
        }
        return "项目 \(cleanedProjectName) 还有多个待处理 Hub grant，我不能替你盲选。"
    }

    static func voiceDecisionFailureReply(
        projectName: String,
        intent: DecisionIntent,
        capability: String,
        modelId: String,
        grantRequestId: String,
        reasonCode: String?
    ) -> String {
        let cleanedProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let draft = decisionFailureDraft(
            intent: intent,
            capability: capability,
            modelId: modelId,
            grantRequestId: grantRequestId,
            reasonCode: reasonCode
        )
        if cleanedProjectName.isEmpty {
            return "语音授权已验证，但\(draft)"
        }
        return "语音授权已验证，但《\(cleanedProjectName)》\(draft)"
    }

    static func supplementaryReason(
        _ rawReason: String,
        capability: String,
        modelId: String
    ) -> String? {
        let cleaned = rawReason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        let lower = cleaned.lowercased()
        if lower == "hub grant required"
            || lower == "grant required"
            || lower.hasPrefix("waiting for hub grant approval")
            || lower.hasPrefix("hub grant denied") {
            return nil
        }

        let summary = awaitingSummary(capability: capability, modelId: modelId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.localizedCaseInsensitiveContains(summary) {
            return nil
        }

        return cleaned
    }

    static func scopeSummary(
        requestedTtlSec: Int,
        requestedTokenCap: Int
    ) -> String? {
        var parts: [String] = []
        if requestedTtlSec > 0 {
            parts.append("TTL \(ttlText(requestedTtlSec))")
        }
        if requestedTokenCap > 0 {
            parts.append("token 上限 \(requestedTokenCap)")
        }
        guard !parts.isEmpty else { return nil }
        return "授权范围：\(parts.joined(separator: " · "))"
    }

    static func approvalFooterNote(count: Int) -> String {
        let normalizedCount = max(1, count)
        if normalizedCount == 1 {
            return "Approve 只放行当前这笔待处理的 Hub capability 请求；Deny 会保持阻断，但不会影响其它对话和项目。"
        }
        return "Approve 会分别放行这些待处理的 Hub capability 请求；Deny 会保持对应动作阻断，但不会影响其它对话和项目。"
    }

    static func decisionFailureDraft(
        intent: DecisionIntent,
        capability: String,
        modelId: String,
        grantRequestId: String,
        reasonCode: String?
    ) -> String {
        let capabilityText = capabilityLabel(
            capability: capability,
            modelId: modelId
        )
        let grantText = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        let reasonText = (reasonCode ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let actionText = intent == .approve ? "放行" : "拒绝"

        var message = "这笔\(capabilityText) Hub 授权\(actionText)未完成"
        if !grantText.isEmpty {
            message += "（grant=\(grantText)"
            if !reasonText.isEmpty {
                message += "，reason=\(reasonText)"
            }
            message += "）"
        } else if !reasonText.isEmpty {
            message += "（reason=\(reasonText)）"
        }
        message += "。请检查 Hub 状态后再试。"
        return message
    }

    private static func ttlText(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds) 秒"
        }
        if seconds < 3600 {
            let minutes = Int(ceil(Double(seconds) / 60.0))
            return "\(minutes) 分钟"
        }
        if seconds < 86_400 {
            let hours = Int(ceil(Double(seconds) / 3600.0))
            return "\(hours) 小时"
        }
        let days = Int(ceil(Double(seconds) / 86_400.0))
        return "\(days) 天"
    }
}
