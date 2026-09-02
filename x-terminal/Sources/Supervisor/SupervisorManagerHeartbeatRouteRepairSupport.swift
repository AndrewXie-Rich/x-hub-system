import Foundation

extension SupervisorManager {
    func heartbeatRouteRepairAttentionItems(
        projects: [AXProjectEntry],
        limit: Int
    ) -> [AXRouteRepairProjectWatchItem] {
        guard limit > 0 else { return [] }
        return AXRouteRepairLogStore.watchItems(for: projects, limit: limit)
            .filter { $0.digest.failureCount > 0 }
    }

    func heartbeatLeadRouteRepairAttentionItem(
        projects: [AXProjectEntry]
    ) -> AXRouteRepairProjectWatchItem? {
        heartbeatRouteRepairAttentionItems(projects: projects, limit: 1).first
    }

    func heartbeatRouteAttentionAlertToken(
        _ item: AXRouteRepairProjectWatchItem?
    ) -> String {
        guard let item else { return "" }

        let topRouteReason = (item.digest.topRouteReason ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let latestFailureAction = item.digest.latestFailure?.actionId
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let severityBucket: String
        switch item.digest.failureCount {
        case 4...:
            severityBucket = "4plus"
        case 2...:
            severityBucket = "2plus"
        default:
            severityBucket = "1"
        }

        return [
            item.projectId,
            topRouteReason,
            latestFailureAction,
            severityBucket
        ]
        .map { $0.replacingOccurrences(of: "\n", with: " ") }
        .joined(separator: "|")
    }

    func heartbeatRouteAttentionSignal(
        item: AXRouteRepairProjectWatchItem?,
        now: TimeInterval
    ) -> HeartbeatRouteAttentionSignal? {
        guard let item else { return nil }

        let latestFailureAt = item.digest.latestFailure?.createdAt ?? item.latestEventAt ?? 0
        let isFreshFailure = latestFailureAt > 0 &&
            (now - latestFailureAt) <= heartbeatRouteAttentionFreshnessWindowSec
        let proactiveSeverity = item.digest.failureCount >= 2 || item.digest.topRouteReasonCount >= 2
        let alertToken = heartbeatRouteAttentionAlertToken(item)
        let tokenChanged = alertToken != lastHeartbeatRouteAttentionAlertToken
        let cooldownElapsed = lastHeartbeatRouteAttentionAlertAt <= 0 ||
            (now - lastHeartbeatRouteAttentionAlertAt) >= heartbeatRouteAttentionReminderCooldownSec
        let statusBarFollowUp = AXRouteRepairLogStore.latestStatusBarFollowUp(
            for: item.digest,
            now: now
        )

        return HeartbeatRouteAttentionSignal(
            item: item,
            alertToken: alertToken,
            shouldAlertOnTimer: proactiveSeverity && isFreshFailure && (tokenChanged || cooldownElapsed),
            statusBarFollowUp: statusBarFollowUp
        )
    }

    func recordHeartbeatRouteAttentionAlertIfNeeded(
        _ signal: HeartbeatRouteAttentionSignal?,
        reason: String,
        blockerCount: Int,
        permissionCount: Int,
        queueCount: Int,
        now: TimeInterval
    ) {
        guard let signal else {
            updateHeartbeatRouteAttentionAlertState(token: "", at: 0)
            return
        }
        guard blockerCount == 0, permissionCount == 0, queueCount == 0 else {
            return
        }
        guard reason != "timer" || signal.shouldAlertOnTimer else {
            return
        }
        updateHeartbeatRouteAttentionAlertState(token: signal.alertToken, at: now)
    }

    func heartbeatRouteRepairSummaryLine(
        _ item: AXRouteRepairProjectWatchItem,
        now: TimeInterval
    ) -> String {
        let topRouteReason = capped(
            AXRouteRepairLogStore.userFacingRouteReason(
                item.digest.topRouteReason ?? "",
                includeCode: true
            ),
            maxChars: 48
        )
        let latestFailureAction = capped(
            AXRouteRepairLogStore.userFacingActionLabel(
                item.digest.latestFailure?.actionId ?? ""
            ),
            maxChars: 40
        )
        let statusBarFollowUp = AXRouteRepairLogStore.latestStatusBarFollowUp(
            for: item.digest,
            now: now
        )

        var clauses: [String] = ["模型路由：\(item.projectDisplayName)"]
        if !topRouteReason.isEmpty, item.digest.topRouteReasonCount > 0 {
            clauses.append("最近最常见是 \(topRouteReason)（\(item.digest.topRouteReasonCount) 次）")
        } else {
            clauses.append("最近有 \(item.digest.failureCount) 次 route repair 失败")
        }
        if !latestFailureAction.isEmpty {
            clauses.append("最近一次失败停在 \(latestFailureAction)")
        }
        if let hint = AXRouteRepairLogStore.watchRouteTruthHint(
            for: item.digest,
            paidAccessSnapshot: appModel?.hubRemotePaidAccessSnapshot
        )?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !hint.isEmpty {
            let normalizedHint = hint.hasSuffix("。") ? String(hint.dropLast()) : hint
            clauses.append(normalizedHint)
        }
        if let followUpClause = heartbeatRouteRepairFollowUpSummaryClause(statusBarFollowUp) {
            clauses.append(followUpClause)
        }
        return clauses.joined(separator: "；") + "。\(heartbeatRouteRepairRecommendationLine(statusBarFollowUp))"
    }

    func heartbeatRouteRepairFollowUpActionID(
        _ followUp: AXRouteRepairLogEvent?
    ) -> String {
        followUp?.actionId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
    }

    func heartbeatRouteRepairFollowUpSummaryClause(
        _ followUp: AXRouteRepairLogEvent?
    ) -> String? {
        switch heartbeatRouteRepairFollowUpActionID(followUp) {
        case "open_model_settings", "open_choose_model":
            return "刚刚已从顶部状态栏打开 AI 模型"
        case "open_xt_diagnostics":
            return "刚刚已从顶部状态栏打开 XT Diagnostics"
        case "open_hub_recovery":
            return "刚刚已从顶部状态栏打开 Hub Recovery"
        case "open_hub_connection_log":
            return "刚刚已从顶部状态栏打开 Hub 日志"
        case "open_route_diagnose":
            return "刚刚已从顶部状态栏打开 /route diagnose"
        default:
            return nil
        }
    }

    func heartbeatRouteRepairRecommendationLine(
        _ followUp: AXRouteRepairLogEvent?
    ) -> String {
        switch heartbeatRouteRepairFollowUpActionID(followUp) {
        case "open_model_settings", "open_choose_model":
            return "建议先查看 AI 模型。"
        case "open_xt_diagnostics":
            return "建议先查看 XT Diagnostics。"
        case "open_hub_recovery":
            return "建议先查看 Hub Recovery。"
        case "open_hub_connection_log":
            return "建议先查看 Hub 日志。"
        case "open_route_diagnose":
            return "建议先看 /route diagnose。"
        default:
            return "建议先看 /route diagnose。"
        }
    }

    func heartbeatRouteRepairVoiceFollowUpLine(
        _ followUp: AXRouteRepairLogEvent?
    ) -> String? {
        switch heartbeatRouteRepairFollowUpActionID(followUp) {
        case "open_model_settings", "open_choose_model":
            return "我刚从顶部状态栏打开了 AI 模型"
        case "open_xt_diagnostics":
            return "我刚从顶部状态栏打开了 XT Diagnostics"
        case "open_hub_recovery":
            return "我刚从顶部状态栏打开了 Hub Recovery"
        case "open_hub_connection_log":
            return "我刚从顶部状态栏打开了 Hub 日志"
        case "open_route_diagnose":
            return "我刚从顶部状态栏打开了项目路由诊断"
        default:
            return nil
        }
    }

    func heartbeatRouteRepairVoiceNextStepLine(
        _ followUp: AXRouteRepairLogEvent?
    ) -> String? {
        switch heartbeatRouteRepairFollowUpActionID(followUp) {
        case "open_model_settings", "open_choose_model":
            return "查看 AI 模型"
        case "open_xt_diagnostics":
            return "查看 XT Diagnostics"
        case "open_hub_recovery":
            return "查看 Hub Recovery"
        case "open_hub_connection_log":
            return "查看 Hub 日志"
        case "open_route_diagnose":
            return "看 route diagnose"
        default:
            return nil
        }
    }

    func heartbeatRouteRepairFollowUpActionURL(
        _ followUp: AXRouteRepairLogEvent?,
        projectId: String?
    ) -> String? {
        switch heartbeatRouteRepairFollowUpActionID(followUp) {
        case "open_model_settings", "open_choose_model":
            return XTDeepLinkURLBuilder.supervisorModelSettingsURL()?.absoluteString
        case "open_xt_diagnostics":
            return XTDeepLinkURLBuilder.settingsURL(sectionId: "diagnostics")?.absoluteString
        case "open_hub_recovery":
            return XTDeepLinkURLBuilder.hubSetupURL(sectionId: "troubleshoot")?.absoluteString
        case "open_hub_connection_log":
            return XTDeepLinkURLBuilder.hubSetupURL(sectionId: "connection_log")?.absoluteString
        case "open_route_diagnose":
            return routeDiagnoseActionURL(projectId: projectId ?? followUp?.projectId)
        default:
            return nil
        }
    }

    func heartbeatRouteMemorySnapshot() -> ModelStateSnapshot? {
        guard let snapshot = appModel?.modelsState,
              !snapshot.models.isEmpty else {
            return nil
        }
        return snapshot
    }
}
