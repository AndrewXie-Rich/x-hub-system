import Foundation

enum SplitProposalPanelPresentation {
    static func validationIssueSummary(_ issue: SplitProposalValidationIssue) -> String {
        "\(validationSeverityText(issue.severity))：\(issueCodeText(issue.code))"
    }

    static func promptStatusText(_ status: PromptCompilationStatus) -> String {
        switch status {
        case .ready:
            return "已就绪"
        case .rejected:
            return "未通过"
        }
    }

    static func promptLintIssueSummary(_ issue: PromptLintIssue) -> String {
        "\(promptLintSeverityText(issue.severity))：\(issueCodeText(issue.code))"
    }

    static func auditEventText(_ eventType: SplitAuditEventType) -> String {
        switch eventType {
        case .splitProposed:
            return "已生成拆分提案"
        case .splitConfirmed:
            return "已确认拆分提案"
        case .splitOverridden:
            return "已覆写拆分提案"
        case .splitRejected:
            return "已放弃拆分提案"
        case .promptCompiled:
            return "提示词已编译"
        case .promptRejected:
            return "提示词未通过"
        }
    }

    static func replayFlagText(_ isReplay: Bool) -> String {
        isReplay ? "是" : "否"
    }

    static func blockingIssueCodesText(_ codes: [String]) -> String {
        codes.map(issueCodeText).joined(separator: "，")
    }

    static func launchBlockedLaneSummary(laneID: String, reason: String) -> String {
        "\(laneID)：\(launchBlockedReasonText(reason))"
    }

    static func hotspotSummary(for lane: LaneRuntimeState) -> String {
        hotspotSummary(
            laneID: lane.laneID,
            status: lane.status,
            blockedReason: lane.blockedReason,
            nextActionRecommendation: lane.nextActionRecommendation
        )
    }

    static func hotspotSummary(for lane: SupervisorLaneHealthLaneState) -> String {
        hotspotSummary(
            laneID: lane.laneID,
            status: lane.status,
            blockedReason: lane.blockedReason,
            nextActionRecommendation: lane.nextActionRecommendation
        )
    }

    static func incidentSummary(for incident: SupervisorLaneIncident) -> String {
        let incidentText = reasonTokenText(incident.incidentCode)
        let actionText = incidentActionText(incident.proposedAction)
        let latencyText = incidentLatencyText(incident.takeoverLatencyMs)
        let denyToken = normalizedReasonToken(incident.denyCode)
        let incidentToken = normalizedReasonToken(incident.incidentCode)

        if let denyToken, denyToken != incidentToken {
            return "\(incidentText) → \(actionText) · 阻断原因：\(reasonTokenText(denyToken)) · 接管耗时：\(latencyText)"
        }

        return "\(incidentText) → \(actionText) · 接管耗时：\(latencyText)"
    }

    private static func hotspotSummary(
        laneID: String,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason?,
        nextActionRecommendation: String
    ) -> String {
        "\(laneID) · \(statusText(status)) · 原因：\(blockedReasonText(blockedReason)) · 下一步：\(nextActionText(nextActionRecommendation))"
    }

    private static func statusText(_ status: LaneHealthStatus) -> String {
        switch status {
        case .waiting:
            return "等待中"
        case .running:
            return "运行中"
        case .blocked:
            return "阻塞"
        case .stalled:
            return "停滞"
        case .failed:
            return "失败"
        case .recovering:
            return "恢复中"
        case .completed:
            return "已完成"
        }
    }

    private static func blockedReasonText(_ reason: LaneBlockedReason?) -> String {
        guard let reason else { return "无显式阻塞原因（none）" }
        switch reason {
        case .skillPreflightFailed:
            return "技能预检失败（\(reason.rawValue)）"
        case .skillGrantPending:
            return "技能授权待处理（\(reason.rawValue)）"
        case .skillRuntimeError:
            return "技能运行失败（\(reason.rawValue)）"
        case .grantPending:
            return "等待授权（\(reason.rawValue)）"
        case .awaitingInstruction:
            return "等待用户指令（\(reason.rawValue)）"
        case .dependencyBlocked:
            return "依赖任务未完成（\(reason.rawValue)）"
        case .runtimeError:
            return "运行时错误（\(reason.rawValue)）"
        case .quotaExceeded:
            return "额度已超限（\(reason.rawValue)）"
        case .authzDenied:
            return "授权被拒绝（\(reason.rawValue)）"
        case .webhookUnhealthy:
            return "Webhook 不健康（\(reason.rawValue)）"
        case .authChallengeLoop:
            return "授权挑战循环未收敛（\(reason.rawValue)）"
        case .queueStarvation:
            return "队列饥饿（\(reason.rawValue)）"
        case .restartDrain:
            return "等待重启排空（\(reason.rawValue)）"
        case .contextOverflow:
            return "上下文超限（\(reason.rawValue)）"
        case .routeOriginUnavailable:
            return "原始路由不可用（\(reason.rawValue)）"
        case .dispatchIdleTimeout:
            return "派发空转超时（\(reason.rawValue)）"
        case .unknown:
            return "未知阻塞原因（\(reason.rawValue)）"
        }
    }

    private static func validationSeverityText(_ severity: SplitProposalIssueSeverity) -> String {
        switch severity {
        case .warning:
            return "提醒"
        case .blocking:
            return "阻塞"
        }
    }

    private static func promptLintSeverityText(_ severity: PromptLintSeverity) -> String {
        switch severity {
        case .warning:
            return "提醒"
        case .error:
            return "错误"
        }
    }

    private static func issueCodeText(_ raw: String) -> String {
        let normalized = normalizedReasonToken(raw) ?? raw

        switch normalized {
        case "override_lane_not_found":
            return "覆写目标泳道不存在（override_lane_not_found）"
        case "high_risk_hard_to_soft_confirmation_required":
            return "高风险泳道从独立项目降级到项目内执行前需要明确确认（high_risk_hard_to_soft_confirmation_required）"
        case "high_risk_hard_to_soft_override":
            return "高风险泳道已从独立项目降级到项目内执行（high_risk_hard_to_soft_override）"
        case "empty_lanes":
            return "未生成任何泳道（empty_lanes）"
        case "duplicate_lane_id":
            return "泳道 ID 重复（duplicate_lane_id）"
        case "lane_missing_dod":
            return "泳道缺少完成标准（lane_missing_dod）"
        case "lane_missing_artifact":
            return "泳道缺少预期产物（lane_missing_artifact）"
        case "lane_dependency_not_found":
            return "泳道依赖引用无效（lane_dependency_not_found）"
        case "high_risk_soft_split":
            return "高风险泳道被设为项目内执行（high_risk_soft_split）"
        case "dag_cycle_detected":
            return "泳道依赖存在循环（dag_cycle_detected）"
        case "token_budget_mismatch":
            return "总 token 预算与泳道预算不一致（token_budget_mismatch）"
        case "high_risk_missing_grant_boundary":
            return "高风险泳道缺少授权边界（high_risk_missing_grant_boundary）"
        case "prompt_coverage_gap":
            return "提示词合同覆盖数量与泳道数不一致（prompt_coverage_gap）"
        case "missing_goal":
            return "缺少目标（missing_goal）"
        case "missing_dod":
            return "缺少完成标准（missing_dod）"
        case "missing_risk_boundary":
            return "缺少风险边界（missing_risk_boundary）"
        case "missing_prohibitions":
            return "缺少禁止事项（missing_prohibitions）"
        case "missing_refusal_semantics":
            return "缺少拒绝语义（missing_refusal_semantics）"
        case "missing_rollback_points":
            return "缺少回滚点（missing_rollback_points）"
        default:
            return "\(normalized.replacingOccurrences(of: "_", with: " "))（\(normalized)）"
        }
    }

    private static func reasonTokenText(_ raw: String?) -> String {
        guard let normalized = normalizedReasonToken(raw) else {
            return "未知原因（none）"
        }

        switch normalized {
        case "preflight_failed":
            return blockedReasonText(.skillPreflightFailed)
        case "grant_required":
            return XTGuardrailMessagePresentation.displayDenyCode(normalized)
        case "local_approval_required":
            return XTGuardrailMessagePresentation.displayDenyCode(normalized)
        case "permission_denied":
            return "权限被拒绝（permission_denied）"
        case "forbidden":
            return "访问被禁止（forbidden）"
        default:
            break
        }

        if let blockedReason = LaneBlockedReason(rawValue: normalized) {
            return blockedReasonText(blockedReason)
        }

        if let userVisible = XTRouteTruthPresentation.userVisibleReasonText(normalized) {
            return userVisible
        }

        return "\(normalized.replacingOccurrences(of: "_", with: " "))（\(normalized)）"
    }

    private static func nextActionText(_ raw: String) -> String {
        let trimmed = normalizedScalar(raw) ?? "none"
        if trimmed.lowercased() == "none" {
            return "暂无（none）"
        }
        return SupervisorGuidanceTextPresentation.actionDisplayText(
            trimmed,
            includeRawToken: true
        ) ?? "\(trimmed.replacingOccurrences(of: "_", with: " "))（\(trimmed)）"
    }

    private static func launchBlockedReasonText(_ raw: String) -> String {
        let trimmed = normalizedScalar(raw) ?? "unknown"
        if trimmed.contains("=") || trimmed.contains(";") || trimmed.contains(":") || trimmed.contains(",") {
            return trimmed
        }

        switch normalizedReasonToken(trimmed) {
        case "dependency_not_ready":
            return "依赖泳道尚未就绪（dependency_not_ready）"
        case "launch_queue_waiting":
            return "等待执行队列腾挪（launch_queue_waiting）"
        case "allocation_blocked":
            return "资源分配被阻塞（allocation_blocked）"
        default:
            return reasonTokenText(trimmed)
        }
    }

    private static func incidentActionText(_ action: SupervisorIncidentAction) -> String {
        switch action {
        case .autoRetry:
            return "自动重试（auto_retry）"
        case .autoGrant:
            return "自动授权（auto_grant）"
        case .notifyUser:
            return "通知用户（notify_user）"
        case .pauseLane:
            return "暂停当前泳道（pause_lane）"
        case .replan:
            return "重新规划（replan）"
        }
    }

    private static func incidentLatencyText(_ ms: Int64?) -> String {
        guard let ms else { return "未知" }
        return "\(max(0, ms))ms"
    }

    private static func normalizedReasonToken(_ raw: String?) -> String? {
        normalizedScalar(raw)?
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
