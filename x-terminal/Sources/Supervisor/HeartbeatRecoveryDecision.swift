import Foundation

enum HeartbeatRecoveryAction: String, Codable, CaseIterable, Sendable {
    case resumeRun = "resume_run"
    case replayFollowUp = "replay_follow_up"
    case requestGrantFollowUp = "request_grant_follow_up"
    case repairRoute = "repair_route"
    case rehydrateContext = "rehydrate_context"
    case queueStrategicReview = "queue_strategic_review"
    case holdForUser = "hold_for_user"
}

enum HeartbeatRecoveryUrgency: String, Codable, CaseIterable, Sendable {
    case observe
    case active
    case urgent
}

struct HeartbeatRecoveryDecision: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "xt.heartbeat_recovery_decision.v1"

    var schemaVersion: String
    var action: HeartbeatRecoveryAction
    var urgency: HeartbeatRecoveryUrgency
    var reasonCode: String
    var summary: String
    var sourceSignals: [String]
    var anomalyTypes: [HeartbeatAnomalyType]
    var blockedLaneReasons: [LaneBlockedReason]
    var blockedLaneCount: Int
    var stalledLaneCount: Int
    var failedLaneCount: Int
    var recoveringLaneCount: Int
    var requiresUserAction: Bool
    var queuedReviewTrigger: SupervisorReviewTrigger?
    var queuedReviewLevel: SupervisorReviewLevel?
    var queuedReviewRunKind: SupervisorReviewRunKind?

    init(
        action: HeartbeatRecoveryAction,
        urgency: HeartbeatRecoveryUrgency,
        reasonCode: String,
        summary: String,
        sourceSignals: [String],
        anomalyTypes: [HeartbeatAnomalyType],
        blockedLaneReasons: [LaneBlockedReason],
        blockedLaneCount: Int,
        stalledLaneCount: Int,
        failedLaneCount: Int,
        recoveringLaneCount: Int,
        requiresUserAction: Bool,
        queuedReviewTrigger: SupervisorReviewTrigger? = nil,
        queuedReviewLevel: SupervisorReviewLevel? = nil,
        queuedReviewRunKind: SupervisorReviewRunKind? = nil
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.action = action
        self.urgency = urgency
        self.reasonCode = reasonCode
        self.summary = summary
        self.sourceSignals = sourceSignals
        self.anomalyTypes = anomalyTypes
        self.blockedLaneReasons = blockedLaneReasons
        self.blockedLaneCount = max(0, blockedLaneCount)
        self.stalledLaneCount = max(0, stalledLaneCount)
        self.failedLaneCount = max(0, failedLaneCount)
        self.recoveringLaneCount = max(0, recoveringLaneCount)
        self.requiresUserAction = requiresUserAction
        self.queuedReviewTrigger = queuedReviewTrigger
        self.queuedReviewLevel = queuedReviewLevel
        self.queuedReviewRunKind = queuedReviewRunKind
    }

    func detailLines() -> [String] {
        var lines = [
            "heartbeat_recovery action=\(action.rawValue) urgency=\(urgency.rawValue) reason=\(sanitized(reasonCode, fallback: "none")) requires_user=\(requiresUserAction) blocked_lanes=\(blockedLaneCount) stalled_lanes=\(stalledLaneCount) failed_lanes=\(failedLaneCount) recovering_lanes=\(recoveringLaneCount)",
            "heartbeat_recovery_signals sources=\(csv(sourceSignals)) anomalies=\(csv(anomalyTypes.map(\.rawValue))) blocked_reasons=\(csv(blockedLaneReasons.map(\.rawValue)))",
            "heartbeat_recovery_summary=\(sanitized(summary, fallback: "Recovery decision available"))"
        ]
        if queuedReviewTrigger != nil || queuedReviewLevel != nil || queuedReviewRunKind != nil {
            lines.append(
                "heartbeat_recovery_review trigger=\(queuedReviewTrigger?.rawValue ?? "none") level=\(queuedReviewLevel?.rawValue ?? "none") run_kind=\(queuedReviewRunKind?.rawValue ?? "none")"
            )
        }
        return lines
    }

    private func csv(_ values: [String]) -> String {
        let normalized = values
            .map { sanitized($0) }
            .filter { !$0.isEmpty }
        return normalized.isEmpty ? "none" : normalized.joined(separator: ",")
    }

    private func sanitized(
        _ raw: String,
        fallback: String = ""
    ) -> String {
        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

extension HeartbeatRecoveryDecision {
    func userFacingSystemNextStepText() -> String {
        HeartbeatRecoveryUserFacingText.systemNextStepText(
            action: action,
            failedLaneCount: failedLaneCount,
            blockedLaneReasons: blockedLaneReasons,
            queuedReviewLevel: queuedReviewLevel,
            trigger: queuedReviewTrigger,
            runKind: queuedReviewRunKind
        )
    }
}

enum HeartbeatRecoveryUserFacingText {
    static func actionText(_ action: HeartbeatRecoveryAction?) -> String? {
        switch action {
        case .some(.resumeRun):
            return "受控恢复执行"
        case .some(.replayFollowUp):
            return "重放 follow-up / 续跑链"
        case .some(.requestGrantFollowUp):
            return "grant / 授权跟进"
        case .some(.repairRoute):
            return "修复 route / dispatch"
        case .some(.rehydrateContext):
            return "重建项目上下文"
        case .some(.queueStrategicReview):
            return "排队治理复盘"
        case .some(.holdForUser):
            return "等待用户 / operator"
        case nil:
            return nil
        }
    }

    static func systemNextStepText(
        action: HeartbeatRecoveryAction?,
        failedLaneCount: Int = 0,
        blockedLaneReasons: [LaneBlockedReason] = [],
        queuedReviewLevel: SupervisorReviewLevel? = nil,
        trigger: SupervisorReviewTrigger? = nil,
        runKind: SupervisorReviewRunKind? = nil
    ) -> String {
        switch action {
        case .some(.resumeRun):
            if failedLaneCount > 0 {
                return "系统会先做一次受控恢复执行，确认失败 lane 已回到可继续状态。"
            }
            return "系统会先尝试受控恢复执行，再观察 lane 活性是否恢复。"
        case .some(.replayFollowUp):
            if blockedLaneReasons.contains(.restartDrain) {
                return "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。"
            }
            return "系统会先重放挂起的 follow-up / 续跑链，再观察队列推进是否恢复。"
        case .some(.requestGrantFollowUp):
            if blockedLaneReasons.contains(.authzDenied) || blockedLaneReasons.contains(.authChallengeLoop) {
                return "系统会先发起所需授权跟进，待权限路径恢复后再继续恢复执行。"
            }
            return "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。"
        case .some(.repairRoute):
            return "系统会先修复当前 route / dispatch 健康，再尝试恢复执行。"
        case .some(.rehydrateContext):
            if blockedLaneReasons.contains(.contextOverflow) {
                return "系统会先收束并重建项目上下文，再继续下一次执行尝试。"
            }
            return "系统会先重建项目上下文，再继续下一次执行尝试。"
        case .some(.queueStrategicReview):
            return queuedReviewNextStep(
                reviewLevel: queuedReviewLevel,
                trigger: trigger,
                runKind: runKind
            )
        case .some(.holdForUser):
            if blockedLaneReasons.contains(.awaitingInstruction) {
                return "系统会先停在当前边界，等待你或 operator 补齐缺失指令。"
            }
            return "系统会先等待所需授权或 grant 放行，再继续恢复执行。"
        case nil:
            return "系统会继续观察当前状态，并在下一次 heartbeat 再重新评估。"
        }
    }

    static func queuedReviewNextStep(
        reviewLevel: SupervisorReviewLevel?,
        trigger: SupervisorReviewTrigger?,
        runKind: SupervisorReviewRunKind?
    ) -> String {
        let levelText = queuedReviewLevelText(reviewLevel)
        let metadata = orderedUnique(
            [queuedReviewRunKindText(runKind), queuedReviewTriggerText(trigger)].compactMap { $0 }
        )
        guard !metadata.isEmpty else {
            return "系统会先排队\(levelText)，并在下一个 safe point 注入 guidance。"
        }
        return "系统会先基于\(metadata.joined(separator: " · "))排队\(levelText)，并在下一个 safe point 注入 guidance。"
    }

    static func doctorExplainabilityText(
        action: HeartbeatRecoveryAction?,
        urgency: HeartbeatRecoveryUrgency?,
        reasonCode: String?,
        sourceSignals: [String] = [],
        blockedLaneReasons: [LaneBlockedReason] = [],
        failedLaneCount: Int = 0,
        requiresUserAction: Bool = false,
        queuedReviewLevel: SupervisorReviewLevel? = nil,
        trigger: SupervisorReviewTrigger? = nil,
        runKind: SupervisorReviewRunKind? = nil
    ) -> String {
        let actionText = trimTerminalPunctuation(
            systemNextStepText(
                action: action,
                failedLaneCount: failedLaneCount,
                blockedLaneReasons: blockedLaneReasons,
                queuedReviewLevel: queuedReviewLevel,
                trigger: trigger,
                runKind: runKind
            )
        )

        var details: [String] = []
        if let urgencyText = urgencyText(urgency) {
            details.append("紧急度 \(urgencyText)")
        }
        if let reasonText = reasonText(reasonCode) {
            details.append("原因 \(reasonText)")
        }
        if requiresUserAction {
            details.append("需要用户动作")
        }
        if !sourceSignals.isEmpty {
            details.append(
                "信号 " + sourceSignals.map(humanizeRecoverySourceSignal).joined(separator: "、")
            )
        }

        let parts = [actionText] + details
        return parts.joined(separator: " · ")
    }

    static func queuedReviewLevelText(_ reviewLevel: SupervisorReviewLevel?) -> String {
        switch reviewLevel {
        case .some(.r1Pulse):
            return "一次脉冲复盘"
        case .some(.r2Strategic):
            return "一次战略复盘"
        case .some(.r3Rescue):
            return "一次救援复盘"
        case nil:
            return "一次治理复盘"
        }
    }

    static func queuedReviewTriggerText(_ trigger: SupervisorReviewTrigger?) -> String? {
        switch trigger {
        case .some(.periodicHeartbeat):
            return "周期心跳"
        case .some(.periodicPulse):
            return "周期 pulse"
        case .some(.failureStreak):
            return "失败累积"
        case .some(.blockerDetected):
            return "blocker 触发"
        case .some(.noProgressWindow):
            return "无进展窗口"
        case .some(.planDrift):
            return "计划偏航"
        case .some(.preHighRiskAction):
            return "高风险动作前"
        case .some(.preDoneSummary):
            return "pre-done 信号"
        case .some(.manualRequest), .some(.userOverride):
            return "手动请求"
        case nil:
            return nil
        }
    }

    static func queuedReviewRunKindText(_ runKind: SupervisorReviewRunKind?) -> String? {
        switch runKind {
        case .some(.pulse):
            return "周期脉冲"
        case .some(.brainstorm):
            return "无进展复盘"
        case .some(.eventDriven):
            return "事件触发"
        case .some(.manual):
            return "手动请求"
        case nil:
            return nil
        }
    }

    static func urgencyText(_ urgency: HeartbeatRecoveryUrgency?) -> String? {
        switch urgency {
        case .some(.observe):
            return "持续观察"
        case .some(.active):
            return "主动处理"
        case .some(.urgent):
            return "紧急处理"
        case nil:
            return nil
        }
    }

    static func reasonText(_ raw: String?) -> String? {
        let normalized = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        switch normalized {
        case "awaiting_user_or_operator_instruction":
            return "等待补齐用户或 operator 指令"
        case "follow_up_queue_stall_requires_replay":
            return "follow-up 队列停滞，需要先重放"
        case "restart_drain_requires_follow_up_replay":
            return "当前 drain 收口后需要重放 follow-up"
        case "grant_follow_up_required":
            return "需要先发起 grant 跟进"
        case "authorization_follow_up_required":
            return "需要先补齐授权跟进"
        case "user_authorization_or_grant_required":
            return "等待用户授权或 grant 放行"
        case "route_flaky_requires_repair":
            return "route 波动，需要先修复"
        case "route_or_dispatch_repair_required":
            return "route / dispatch 需要先修复"
        case "context_window_overflow_requires_rehydrate":
            return "上下文窗口溢出，需要先重建"
        case "heartbeat_hollow_progress_requires_context_rehydrate":
            return "heartbeat 空转，需要先重建上下文"
        case "heartbeat_or_lane_signal_requires_governance_review":
            return "heartbeat 或 lane 信号要求先做治理复盘"
        case "lane_failure_requires_controlled_resume":
            return "lane 失败后先做受控恢复"
        case "lane_vitality_degraded_resume_candidate":
            return "lane 活性下降，先尝试受控恢复"
        default:
            return humanizeToken(raw)
        }
    }

    static func humanizeRecoverySourceSignal(_ raw: String) -> String {
        if let anomaly = trimmedSuffix(raw, prefix: "anomaly:") {
            return "异常 \(HeartbeatGovernanceUserFacingText.anomalyTypeText(anomaly) ?? humanizeToken(anomaly))"
        }
        if let blockedReason = trimmedSuffix(raw, prefix: "lane_blocked_reason:") {
            return "阻塞原因 \(blockedReasonText(blockedReason))"
        }
        if let count = trimmedSuffix(raw, prefix: "lane_blocked_count:") {
            return "阻塞 lane \(count) 条"
        }
        if let count = trimmedSuffix(raw, prefix: "lane_stalled_count:") {
            return "停滞 lane \(count) 条"
        }
        if let count = trimmedSuffix(raw, prefix: "lane_failed_count:") {
            return "失败 lane \(count) 条"
        }
        if let count = trimmedSuffix(raw, prefix: "lane_recovering_count:") {
            return "恢复中 lane \(count) 条"
        }
        if let reviewCandidate = trimmedSuffix(raw, prefix: "review_candidate:") {
            let parts = reviewCandidate.split(separator: ":").map(String.init)
            let trigger = parts.count > 0 ? SupervisorReviewTrigger(rawValue: parts[0]) : nil
            let level = parts.count > 1 ? SupervisorReviewLevel(rawValue: parts[1]) : nil
            let runKind = parts.count > 2 ? SupervisorReviewRunKind(rawValue: parts[2]) : nil
            let details = [
                queuedReviewTriggerText(trigger),
                level.map(queuedReviewLevelText),
                queuedReviewRunKindText(runKind)
            ].compactMap { $0 }
            if details.isEmpty {
                return "复盘候选"
            }
            return "复盘候选 " + details.joined(separator: " / ")
        }
        return humanizeToken(raw)
    }

    static func sourceSignalTexts(_ values: [String]) -> [String] {
        orderedUnique(values.map(humanizeRecoverySourceSignal))
    }

    static func anomalyTypeTexts(_ values: [String]) -> [String] {
        orderedUnique(values.compactMap(HeartbeatGovernanceUserFacingText.anomalyTypeText))
    }

    static func blockedReasonTexts(_ values: [String]) -> [String] {
        orderedUnique(values.map(blockedReasonText))
    }

    static func blockedReasonText(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case LaneBlockedReason.skillGrantPending.rawValue:
            return "等待技能授权"
        case LaneBlockedReason.grantPending.rawValue:
            return "等待授权"
        case LaneBlockedReason.awaitingInstruction.rawValue:
            return "等待指令"
        case LaneBlockedReason.authzDenied.rawValue:
            return "授权被拒绝"
        case LaneBlockedReason.authChallengeLoop.rawValue:
            return "授权挑战循环"
        case LaneBlockedReason.contextOverflow.rawValue:
            return "上下文溢出"
        case LaneBlockedReason.routeOriginUnavailable.rawValue:
            return "route 源不可用"
        case LaneBlockedReason.dispatchIdleTimeout.rawValue:
            return "dispatch 空闲超时"
        case LaneBlockedReason.queueStarvation.rawValue:
            return "队列饥饿"
        case LaneBlockedReason.restartDrain.rawValue:
            return "等待 drain 恢复"
        default:
            return humanizeToken(raw)
        }
    }

    static func trimTerminalPunctuation(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = value.last, ["。", ".", "!", "！"].contains(String(last)) {
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    private static func trimmedSuffix(
        _ raw: String,
        prefix: String
    ) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        let suffix = String(raw.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return suffix.isEmpty ? nil : suffix
    }

    private static func humanizeToken(_ raw: String?) -> String {
        let value = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "暂无" }
        return value.replacingOccurrences(of: "_", with: " ")
    }
}
