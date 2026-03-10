import Foundation

/// 泳道健康态（XT-W2-13）
enum LaneHealthStatus: String, Codable, CaseIterable {
    case waiting
    case running
    case blocked
    case stalled
    case failed
    case recovering
    case completed

    var isTerminal: Bool {
        switch self {
        case .failed, .completed:
            return true
        default:
            return false
        }
    }
}

/// 泳道阻塞原因（与 gate 文档保持一致）
enum LaneBlockedReason: String, Codable, CaseIterable {
    case skillPreflightFailed = "skill_preflight_failed"
    case skillGrantPending = "skill_grant_pending"
    case skillRuntimeError = "skill_runtime_error"
    case grantPending = "grant_pending"
    case awaitingInstruction = "awaiting_instruction"
    case dependencyBlocked = "dependency_blocked"
    case runtimeError = "runtime_error"
    case quotaExceeded = "quota_exceeded"
    case authzDenied = "authz_denied"
    case webhookUnhealthy = "webhook_unhealthy"
    case authChallengeLoop = "auth_challenge_loop"
    case queueStarvation = "queue_starvation"
    case restartDrain = "restart_drain"
    case contextOverflow = "context_overflow"
    case routeOriginUnavailable = "route_origin_unavailable"
    case dispatchIdleTimeout = "dispatch_idle_timeout"
    case unknown

    init(metadataValue: String?) {
        guard let raw = metadataValue?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            self = .unknown
            return
        }
        let lowered = raw.lowercased()
        switch lowered {
        case "skill_preflight_failed", "preflight_failed":
            self = .skillPreflightFailed
        case "skill_grant_pending":
            self = .skillGrantPending
        case "skill_runtime_error":
            self = .skillRuntimeError
        default:
            self = LaneBlockedReason(rawValue: lowered) ?? .unknown
        }
    }

    /// 统一 incident 输出语义（XT-Ready 固定为 grant/await/runtime）
    var canonicalIncidentCode: String? {
        switch self {
        case .skillPreflightFailed:
            return LaneBlockedReason.awaitingInstruction.rawValue
        case .skillGrantPending:
            return LaneBlockedReason.grantPending.rawValue
        case .skillRuntimeError:
            return LaneBlockedReason.runtimeError.rawValue
        case .contextOverflow:
            return LaneBlockedReason.contextOverflow.rawValue
        case .routeOriginUnavailable:
            return LaneBlockedReason.routeOriginUnavailable.rawValue
        case .dispatchIdleTimeout:
            return LaneBlockedReason.dispatchIdleTimeout.rawValue
        case .grantPending, .awaitingInstruction, .runtimeError:
            return rawValue
        default:
            return nil
        }
    }
}

/// 单条 lane 的运行时状态快照
struct LaneRuntimeState: Identifiable, Codable {
    var id: String { laneID }

    let laneID: String
    let taskId: UUID
    var projectId: UUID?
    var agentProfile: String?

    var status: LaneHealthStatus
    var heartbeatSeq: Int
    var lastHeartbeatAtMs: Int64
    var oldestWaitMs: Int64
    var blockedReason: LaneBlockedReason?
    var nextActionRecommendation: String
    var lastNote: String?
    var updatedAtMs: Int64

    init(
        laneID: String,
        taskId: UUID,
        projectId: UUID?,
        agentProfile: String?,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason? = nil,
        nextActionRecommendation: String = "continue"
    ) {
        let now = Date().millisecondsSinceEpoch
        self.laneID = laneID
        self.taskId = taskId
        self.projectId = projectId
        self.agentProfile = agentProfile
        self.status = status
        self.heartbeatSeq = 1
        self.lastHeartbeatAtMs = now
        self.oldestWaitMs = 0
        self.blockedReason = blockedReason
        self.nextActionRecommendation = nextActionRecommendation
        self.lastNote = nil
        self.updatedAtMs = now
    }

    mutating func applyHeartbeat(
        status: LaneHealthStatus,
        projectId: UUID?,
        blockedReason: LaneBlockedReason?,
        recommendation: String,
        note: String?,
        at nowMs: Int64
    ) {
        heartbeatSeq += 1
        self.status = status
        self.projectId = projectId ?? self.projectId
        self.blockedReason = blockedReason
        self.nextActionRecommendation = recommendation
        self.lastNote = note
        self.updatedAtMs = nowMs
        lastHeartbeatAtMs = nowMs

        if status == .blocked || status == .stalled {
            if oldestWaitMs == 0 {
                oldestWaitMs = nowMs
            }
        } else {
            oldestWaitMs = 0
        }
    }
}

/// 健康态迁移记录
struct LaneHealthTransition {
    let laneID: String
    let from: LaneHealthStatus
    let to: LaneHealthStatus
    let atMs: Int64
    let reason: String
}

/// lane 健康聚合快照（用于 Supervisor 主动托管观察）
struct LaneHealthSummary: Codable, Equatable {
    let total: Int
    let running: Int
    let blocked: Int
    let stalled: Int
    let failed: Int
    let waiting: Int
    let recovering: Int
    let completed: Int

    static let empty = LaneHealthSummary(
        total: 0,
        running: 0,
        blocked: 0,
        stalled: 0,
        failed: 0,
        waiting: 0,
        recovering: 0,
        completed: 0
    )

    static func build(from states: [String: LaneRuntimeState]) -> LaneHealthSummary {
        guard !states.isEmpty else { return .empty }

        var running = 0
        var blocked = 0
        var stalled = 0
        var failed = 0
        var waiting = 0
        var recovering = 0
        var completed = 0

        for state in states.values {
            switch state.status {
            case .running:
                running += 1
            case .blocked:
                blocked += 1
            case .stalled:
                stalled += 1
            case .failed:
                failed += 1
            case .waiting:
                waiting += 1
            case .recovering:
                recovering += 1
            case .completed:
                completed += 1
            }
        }

        return LaneHealthSummary(
            total: states.count,
            running: running,
            blocked: blocked,
            stalled: stalled,
            failed: failed,
            waiting: waiting,
            recovering: recovering,
            completed: completed
        )
    }
}

/// lane 健康快照中的单 lane 行
struct SupervisorLaneHealthLaneState: Codable, Equatable, Identifiable {
    var id: String { laneID }

    let laneID: String
    let taskID: UUID
    let projectID: UUID?
    let agentProfile: String?
    let status: LaneHealthStatus
    let heartbeatSeq: Int
    let lastHeartbeatAtMs: Int64
    let oldestWaitMs: Int64
    let blockedReason: LaneBlockedReason?
    let nextActionRecommendation: String

    init(state: LaneRuntimeState) {
        laneID = state.laneID
        taskID = state.taskId
        projectID = state.projectId
        agentProfile = state.agentProfile
        status = state.status
        heartbeatSeq = state.heartbeatSeq
        lastHeartbeatAtMs = state.lastHeartbeatAtMs
        oldestWaitMs = state.oldestWaitMs
        blockedReason = state.blockedReason
        nextActionRecommendation = state.nextActionRecommendation
    }
}

/// Supervisor lane 健康主动巡检快照（用于事件汇聚）
struct SupervisorLaneHealthSnapshot: Codable, Equatable {
    let generatedAtMs: Int64
    let summary: LaneHealthSummary
    let lanes: [SupervisorLaneHealthLaneState]

    var fingerprint: String {
        lanes.map { lane in
            "\(lane.laneID)|\(lane.status.rawValue)|\(lane.blockedReason?.rawValue ?? "none")|\(lane.nextActionRecommendation)"
        }.joined(separator: ";")
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
