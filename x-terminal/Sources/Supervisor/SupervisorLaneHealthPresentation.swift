import Foundation

enum SupervisorLaneHealthFilter: CaseIterable, Hashable {
    case all
    case abnormal
    case running
    case blocked
    case stalled
    case failed

    var label: String {
        switch self {
        case .all: return "全部"
        case .abnormal: return "异常"
        case .running: return "运行中"
        case .blocked: return "阻塞"
        case .stalled: return "停滞"
        case .failed: return "失败"
        }
    }
}

enum SupervisorLaneHealthTone: Equatable {
    case neutral
    case success
    case info
    case warning
    case danger
}

enum SupervisorLaneHealthRowAction: Equatable {
    case openProject(URL)
    case focusLane(String)
}

struct SupervisorLaneHealthRowActionDescriptor: Equatable, Identifiable {
    var action: SupervisorLaneHealthRowAction
    var label: String
    var isEnabled: Bool

    var id: String {
        "\(label)|\(isEnabled)|\(action)"
    }
}

struct SupervisorLaneHealthRowPresentation: Equatable, Identifiable {
    var laneID: String
    var isFocused: Bool
    var title: String
    var statusIconName: String
    var statusTone: SupervisorLaneHealthTone
    var reasonLine: String
    var reasonTone: SupervisorLaneHealthTone
    var contractText: String?
    var nextSafeActionText: String?
    var heartbeatSequenceText: String
    var heartbeatAgeText: String
    var taskText: String
    var splitPlanText: String
    var waitText: String?
    var openAction: SupervisorLaneHealthRowActionDescriptor?
    var focusAction: SupervisorLaneHealthRowActionDescriptor

    var id: String { laneID }
}

enum SupervisorLaneHealthPresentation {
    static func summaryTone(_ summary: LaneHealthSummary) -> SupervisorLaneHealthTone {
        if summary.failed > 0 {
            return .danger
        }
        if summary.stalled > 0 || summary.blocked > 0 {
            return .warning
        }
        if summary.running > 0 || summary.recovering > 0 {
            return .success
        }
        return .neutral
    }

    static func filteredLanes(
        from snapshot: SupervisorLaneHealthSnapshot?,
        filter: SupervisorLaneHealthFilter
    ) -> [SupervisorLaneHealthLaneState] {
        guard let snapshot else { return [] }
        return snapshot.lanes
            .filter { lane in
                switch filter {
                case .all:
                    return true
                case .abnormal:
                    return lane.status == .blocked || lane.status == .stalled || lane.status == .failed
                case .running:
                    return lane.status == .running
                case .blocked:
                    return lane.status == .blocked
                case .stalled:
                    return lane.status == .stalled
                case .failed:
                    return lane.status == .failed
                }
            }
            .sorted { lhs, rhs in
                if statusPriority(lhs.status) != statusPriority(rhs.status) {
                    return statusPriority(lhs.status) > statusPriority(rhs.status)
                }
                return lhs.laneID < rhs.laneID
            }
    }

    static func rowPresentation(
        lane: SupervisorLaneHealthLaneState,
        splitPlanText: String,
        focusedLaneID: String?,
        now: Date = Date()
    ) -> SupervisorLaneHealthRowPresentation {
        let isFocused = lane.laneID == normalizedScalar(focusedLaneID)
        let contract = guidanceContract(for: lane)
        return SupervisorLaneHealthRowPresentation(
            laneID: lane.laneID,
            isFocused: isFocused,
            title: "\(lane.laneID) · \(statusText(lane.status))",
            statusIconName: statusIconName(lane.status),
            statusTone: statusTone(lane.status),
            reasonLine: "原因：\(blockedReasonText(lane.blockedReason)) · 下一步：\(nextActionText(lane.nextActionRecommendation))",
            reasonTone: (lane.status == .failed || lane.status == .stalled) ? .warning : .neutral,
            contractText: contract.map(SupervisorGuidanceContractLinePresentation.contractLine),
            nextSafeActionText: contract.map(SupervisorGuidanceContractLinePresentation.nextSafeActionLine),
            heartbeatSequenceText: "hb#\(lane.heartbeatSeq)",
            heartbeatAgeText: heartbeatAgeText(lane.lastHeartbeatAtMs, now: now),
            taskText: "task=\(lane.taskID.uuidString.prefix(8))",
            splitPlanText: "plan=\(splitPlanText)",
            waitText: lane.oldestWaitMs > 0 ? "wait=\(waitText(lane.oldestWaitMs, now: now))" : nil,
            openAction: projectURL(projectID: lane.projectID).map {
                SupervisorLaneHealthRowActionDescriptor(
                    action: .openProject($0),
                    label: "查看项目",
                    isEnabled: true
                )
            },
            focusAction: SupervisorLaneHealthRowActionDescriptor(
                action: .focusLane(lane.laneID),
                label: isFocused ? "已定位" : "定位",
                isEnabled: true
            )
        )
    }

    static func statusTone(_ status: LaneHealthStatus) -> SupervisorLaneHealthTone {
        switch status {
        case .failed:
            return .danger
        case .stalled, .blocked:
            return .warning
        case .recovering:
            return .info
        case .running:
            return .success
        case .waiting, .completed:
            return .neutral
        }
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

    static func statusIconName(_ status: LaneHealthStatus) -> String {
        switch status {
        case .failed:
            return "xmark.octagon.fill"
        case .stalled:
            return "hourglass.circle.fill"
        case .blocked:
            return "pause.circle.fill"
        case .recovering:
            return "arrow.clockwise.circle.fill"
        case .running:
            return "play.circle.fill"
        case .waiting:
            return "clock.badge.questionmark.fill"
        case .completed:
            return "checkmark.circle.fill"
        }
    }

    static func heartbeatAgeText(
        _ lastHeartbeatAtMs: Int64,
        now: Date = Date()
    ) -> String {
        guard lastHeartbeatAtMs > 0 else { return "heartbeat=unknown" }
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let ageMs = max(0, nowMs - lastHeartbeatAtMs)
        if ageMs < 1_000 {
            return "heartbeat<1s"
        }
        return "heartbeat=\(ageMs / 1_000)s"
    }

    static func waitText(
        _ oldestWaitMs: Int64,
        now: Date = Date()
    ) -> String {
        guard oldestWaitMs > 0 else { return "-" }
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let ageMs = max(0, nowMs - oldestWaitMs)
        if ageMs < 1_000 {
            return "<1s"
        }
        return "\(ageMs / 1_000)s"
    }

    static func projectURL(projectID: UUID?) -> URL? {
        guard let projectID else { return XTDeepLinkURLBuilder.supervisorURL() }
        return XTDeepLinkURLBuilder.projectURL(
            projectId: projectID.uuidString,
            pane: .chat,
            resumeRequested: true
        )
    }

    static func statusPriority(_ status: LaneHealthStatus) -> Int {
        switch status {
        case .failed: return 6
        case .stalled: return 5
        case .blocked: return 4
        case .recovering: return 3
        case .running: return 2
        case .waiting: return 1
        case .completed: return 0
        }
    }

    static func guidanceContract(
        for lane: SupervisorLaneHealthLaneState
    ) -> SupervisorGuidanceContractSummary? {
        let recommendation = lane.nextActionRecommendation.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocker = lane.blockedReason

        let kind: SupervisorGuidanceContractSummary.Kind?
        switch blocker {
        case .grantPending, .skillGrantPending:
            kind = .grantResolution
        case .awaitingInstruction, .skillPreflightFailed:
            kind = .awaitingInstruction
        case .runtimeError, .skillRuntimeError, .authzDenied, .webhookUnhealthy,
             .authChallengeLoop, .dispatchIdleTimeout, .routeOriginUnavailable,
             .restartDrain, .quotaExceeded, .contextOverflow:
            kind = .incidentRecovery
        case .dependencyBlocked, .queueStarvation:
            kind = .supervisorReplan
        case .unknown, .none:
            switch lane.status {
            case .failed, .stalled:
                kind = .incidentRecovery
            default:
                kind = nil
            }
        }

        guard let kind else { return nil }

        let primaryBlocker: String = {
            if let blocker {
                return blocker.rawValue
            }
            switch lane.status {
            case .failed:
                return "lane_failed"
            case .stalled:
                return "lane_stalled"
            default:
                return ""
            }
        }()

        return SupervisorGuidanceContractSummary(
            kind: kind,
            trigger: "Lane Health",
            reviewLevel: "",
            verdict: "",
            summary: "lane=\(lane.laneID) · status=\(lane.status.rawValue)",
            primaryBlocker: primaryBlocker,
            currentState: lane.status.rawValue,
            nextStep: recommendation,
            nextSafeAction: nextSafeAction(
                kind: kind,
                recommendation: recommendation
            ),
            recommendedActions: recommendation.isEmpty ? [] : [recommendation],
            workOrderRef: "",
            effectiveSupervisorTier: "",
            effectiveWorkOrderDepth: ""
        )
    }

    private static func nextSafeAction(
        kind: SupervisorGuidanceContractSummary.Kind,
        recommendation: String
    ) -> String {
        let normalizedRecommendation = recommendation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch kind {
        case .grantResolution:
            return "open_hub_grants"
        case .awaitingInstruction:
            return "clarify_with_user"
        case .incidentRecovery:
            switch normalizedRecommendation {
            case "auto_retry", "pause_lane", "restart_dispatch":
                return "inspect_incident_and_replan"
            default:
                return "inspect_incident_and_replan"
            }
        case .supervisorReplan:
            return "apply_supervisor_replan"
        case .uiReviewRepair:
            return "repair_before_execution"
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

    private static func normalizedScalar(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
