import Foundation

extension ChatSessionModel {
    func handleSlashGuidance(args: [String], ctx: AXProjectContext) -> String {
        let head = args.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "status"
        switch head {
        case "status", "show", "list":
            return slashGuidanceText(ctx: ctx)
        case "accept", "accepted":
            return acknowledgePendingGuidance(
                ctx: ctx,
                status: .accepted,
                note: args.dropFirst().joined(separator: " ")
            )
        case "defer", "deferred":
            return acknowledgePendingGuidance(
                ctx: ctx,
                status: .deferred,
                note: args.dropFirst().joined(separator: " ")
            )
        case "reject", "rejected":
            let note = args.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !note.isEmpty else {
                return "用法：/guidance reject <reason>"
            }
            return acknowledgePendingGuidance(
                ctx: ctx,
                status: .rejected,
                note: note
            )
        default:
            return slashGuidanceUsageText()
        }
    }

    func slashGuidanceText(ctx: AXProjectContext) -> String {
        let latest = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pending = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
        guard latest != nil || pending != nil else {
            return "当前项目没有 Supervisor 指导。\n\n" + slashGuidanceUsageText()
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        var lines: [String] = ["Supervisor 指导："]
        if let pending {
            lines.append("")
            lines.append("待确认指导：")
            lines.append("- 指导 ID：\(pending.injectionId)")
            lines.append("- 交付方式：\(frontstageGuidanceDisplayValue(label: "delivery", value: pending.deliveryMode.displayName))")
            lines.append("- 干预方式：\(frontstageGuidanceDisplayValue(label: "intervention", value: pending.interventionMode.displayName))")
            lines.append("- 安全点：\(frontstageGuidanceDisplayValue(label: "safe_point", value: pending.safePointPolicy.displayName))")
            lines.append("- 确认状态：\(frontstageGuidanceAckSummary(status: pending.ackStatus, required: pending.ackRequired))")
            lines.append("- 生命周期：\(frontstageGuidanceLifecycleText(for: pending, nowMs: nowMs))")
            lines.append("- 过期时间：\(frontstageGuidanceTimestampText(pending.expiresAtMs))")
            lines.append("- 下次重提：\(frontstageGuidanceTimestampText(pending.retryAtMs))")
            lines.append("- 重提进度：\(frontstageGuidanceRetryProgressText(retryCount: pending.retryCount, maxRetryCount: pending.maxRetryCount))")
            lines.append("- 指导摘要：\(presentedSupervisorGuidanceSummary(pending.guidanceText, maxChars: 220))")
        }
        if let latest, latest.injectionId != pending?.injectionId {
            if pending != nil { lines.append("") }
            lines.append("最新指导：")
            lines.append("- 指导 ID：\(latest.injectionId)")
            lines.append("- 确认状态：\(frontstageGuidanceAckSummary(status: latest.ackStatus, required: latest.ackRequired))")
            lines.append("- 确认备注：\(latest.ackNote.isEmpty ? "无" : latest.ackNote)")
            lines.append("- 生命周期：\(frontstageGuidanceLifecycleText(for: latest, nowMs: nowMs))")
            lines.append("- 过期时间：\(frontstageGuidanceTimestampText(latest.expiresAtMs))")
            lines.append("- 下次重提：\(frontstageGuidanceTimestampText(latest.retryAtMs))")
            lines.append("- 重提进度：\(frontstageGuidanceRetryProgressText(retryCount: latest.retryCount, maxRetryCount: latest.maxRetryCount))")
            lines.append("- 交付方式：\(frontstageGuidanceDisplayValue(label: "delivery", value: latest.deliveryMode.displayName))")
            lines.append("- 干预方式：\(frontstageGuidanceDisplayValue(label: "intervention", value: latest.interventionMode.displayName))")
            lines.append("- 指导摘要：\(presentedSupervisorGuidanceSummary(latest.guidanceText, maxChars: 220))")
        }
        lines.append("")
        lines.append(slashGuidanceUsageText())
        return lines.joined(separator: "\n")
    }

    func presentedSupervisorGuidanceSummary(
        _ guidanceText: String,
        maxChars: Int
    ) -> String {
        let summary = SupervisorGuidanceTextPresentation.summary(
            guidanceText,
            maxChars: maxChars
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? ProjectGovernanceActivityDisplay.noneText : summary
    }

    func slashGuidanceAckSummary(
        status: SupervisorGuidanceAckStatus,
        required: Bool
    ) -> String {
        "\(status.displayName) · \(required ? "required" : "optional")"
    }

    func frontstageGuidanceDisplayValue(label: String, value: String) -> String {
        ProjectGovernanceActivityDisplay.displayValue(label: label, value: value)
    }

    func frontstageGuidanceAckSummary(
        status: SupervisorGuidanceAckStatus,
        required: Bool
    ) -> String {
        frontstageGuidanceDisplayValue(
            label: "ack",
            value: slashGuidanceAckSummary(status: status, required: required)
        )
    }

    func frontstageGuidanceLifecycleText(
        for record: SupervisorGuidanceInjectionRecord,
        nowMs: Int64
    ) -> String {
        frontstageGuidanceDisplayValue(
            label: "lifecycle",
            value: SupervisorGuidanceInjectionStore.lifecycleSummary(for: record, nowMs: nowMs)
        )
    }

    func frontstageGuidanceTimestampText(_ value: Int64) -> String {
        guard value > 0 else { return "无" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(value) / 1000.0))
    }

    func frontstageGuidanceRetryProgressText(
        retryCount: Int,
        maxRetryCount: Int
    ) -> String {
        guard maxRetryCount > 0 else { return "未启用" }
        return "\(retryCount)/\(maxRetryCount)"
    }

    func slashGuidanceUsageText() -> String {
        """
命令：
- /guidance
- /guidance status
- /guidance accept [note]
- /guidance defer [note]
- /guidance reject <reason>
"""
    }

    func acknowledgePendingGuidance(
        ctx: AXProjectContext,
        status: SupervisorGuidanceAckStatus,
        note: String
    ) -> String {
        guard let pending = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx) else {
            return "当前没有待确认的 Supervisor 指导。\n\n" + slashGuidanceUsageText()
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNote: String
        switch status {
        case .accepted:
            normalizedNote = trimmedNote
        case .deferred:
            normalizedNote = trimmedNote
        case .rejected:
            normalizedNote = trimmedNote
        case .pending:
            normalizedNote = trimmedNote
        }

        let nowMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        do {
            try SupervisorGuidanceInjectionStore.acknowledge(
                injectionId: pending.injectionId,
                status: status,
                note: normalizedNote,
                atMs: nowMs,
                for: ctx
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "supervisor_guidance_ack",
                    "action": "manual_ack",
                    "source": "slash_guidance",
                    "project_id": pending.projectId,
                    "review_id": pending.reviewId,
                    "injection_id": pending.injectionId,
                    "ack_status": status.rawValue,
                    "ack_note": normalizedNote,
                    "timestamp_ms": nowMs
                ],
                for: ctx
            )
            publishSupervisorGuidanceAckEvent(
                ctx: ctx,
                injectionId: pending.injectionId
            )
            return "已更新指导确认：\(pending.injectionId)，状态已改为\(ProjectGovernanceActivityDisplay.ackStatusLabel(status))。"
        } catch {
            return "更新指导确认失败：\(String(describing: error))"
        }
    }
}
