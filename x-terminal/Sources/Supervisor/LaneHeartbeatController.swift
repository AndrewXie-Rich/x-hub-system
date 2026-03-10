import Foundation

/// 主动 heartbeat 巡检控制器（XT-W2-13）
@MainActor
final class LaneHeartbeatController: ObservableObject {
    @Published private(set) var laneStates: [String: LaneRuntimeState] = [:]

    private let stallTimeoutMs: Int64

    init(stallTimeoutMs: Int64 = 2_000) {
        self.stallTimeoutMs = max(500, stallTimeoutMs)
    }

    func registerLane(
        laneID: String,
        taskId: UUID,
        projectId: UUID?,
        agentProfile: String?,
        initialStatus: LaneHealthStatus,
        blockedReason: LaneBlockedReason? = nil,
        recommendation: String = "continue"
    ) {
        laneStates[laneID] = LaneRuntimeState(
            laneID: laneID,
            taskId: taskId,
            projectId: projectId,
            agentProfile: agentProfile,
            status: initialStatus,
            blockedReason: blockedReason,
            nextActionRecommendation: recommendation
        )
    }

    func recordHeartbeat(
        laneID: String,
        taskId: UUID,
        projectId: UUID?,
        agentProfile: String?,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason?,
        recommendation: String,
        note: String?
    ) {
        let nowMs = Date().millisecondsSinceEpoch

        if var state = laneStates[laneID] {
            state.agentProfile = agentProfile ?? state.agentProfile
            state.applyHeartbeat(
                status: status,
                projectId: projectId,
                blockedReason: blockedReason,
                recommendation: recommendation,
                note: note,
                at: nowMs
            )
            laneStates[laneID] = state
            return
        }

        var newState = LaneRuntimeState(
            laneID: laneID,
            taskId: taskId,
            projectId: projectId,
            agentProfile: agentProfile,
            status: status,
            blockedReason: blockedReason,
            nextActionRecommendation: recommendation
        )
        newState.lastNote = note
        laneStates[laneID] = newState
    }

    func markFailed(
        laneID: String,
        note: String,
        blockedReason: LaneBlockedReason? = nil
    ) {
        guard var state = laneStates[laneID] else { return }
        let nowMs = Date().millisecondsSinceEpoch
        let resolvedReason = blockedReason ?? state.blockedReason
        state.applyHeartbeat(
            status: .failed,
            projectId: state.projectId,
            blockedReason: resolvedReason,
            recommendation: "pause_lane",
            note: note,
            at: nowMs
        )
        laneStates[laneID] = state
    }

    func markCompleted(laneID: String, note: String? = nil) {
        guard var state = laneStates[laneID] else { return }
        let nowMs = Date().millisecondsSinceEpoch
        state.applyHeartbeat(
            status: .completed,
            projectId: state.projectId,
            blockedReason: nil,
            recommendation: "mergeback",
            note: note,
            at: nowMs
        )
        laneStates[laneID] = state
    }

    /// 主动巡检：根据心跳年龄和阻塞语义修正健康态
    @discardableResult
    func inspect(now: Date = Date()) -> [LaneHealthTransition] {
        let nowMs = now.millisecondsSinceEpoch
        var transitions: [LaneHealthTransition] = []

        for laneID in laneStates.keys.sorted() {
            guard var state = laneStates[laneID] else { continue }
            let previous = state.status

            var next = previous
            var reason = "heartbeat_ok"

            if previous.isTerminal {
                continue
            } else if nowMs - state.lastHeartbeatAtMs > stallTimeoutMs {
                next = .stalled
                reason = "heartbeat_timeout"
            } else if state.blockedReason != nil {
                next = .blocked
                reason = "blocked_reason_present"
            } else {
                next = .running
                reason = "heartbeat_fresh"
            }

            if next != previous {
                state.status = next
                state.updatedAtMs = nowMs
                state.nextActionRecommendation = defaultRecommendation(for: next, blockedReason: state.blockedReason)
                if (next == .blocked || next == .stalled) && state.oldestWaitMs == 0 {
                    state.oldestWaitMs = nowMs
                }
                if next == .running {
                    state.oldestWaitMs = 0
                }
                laneStates[laneID] = state

                transitions.append(
                    LaneHealthTransition(
                        laneID: laneID,
                        from: previous,
                        to: next,
                        atMs: nowMs,
                        reason: reason
                    )
                )
            }
        }

        return transitions
    }

    func snapshot() -> [String: LaneRuntimeState] {
        laneStates
    }

    func healthSummary() -> LaneHealthSummary {
        LaneHealthSummary.build(from: laneStates)
    }

    private func defaultRecommendation(for status: LaneHealthStatus, blockedReason: LaneBlockedReason?) -> String {
        switch status {
        case .running:
            return "continue"
        case .blocked:
            switch blockedReason ?? .unknown {
            case .skillPreflightFailed:
                return "notify_user"
            case .skillGrantPending:
                return "notify_user"
            case .skillRuntimeError:
                return "auto_retry"
            case .grantPending:
                return "notify_user"
            case .awaitingInstruction:
                return "replan"
            case .dependencyBlocked:
                return "wait_dependency"
            case .runtimeError:
                return "auto_retry"
            case .quotaExceeded:
                return "rebalance_budget"
            case .authzDenied:
                return "notify_user"
            case .webhookUnhealthy:
                return "replan"
            case .authChallengeLoop:
                return "notify_user"
            case .queueStarvation:
                return "rebalance"
            case .restartDrain:
                return "wait_drain_recover"
            case .contextOverflow:
                return "trim_context"
            case .routeOriginUnavailable:
                return "fallback_same_origin"
            case .dispatchIdleTimeout:
                return "restart_dispatch"
            case .unknown:
                return "inspect"
            }
        case .stalled:
            return "triage"
        case .failed:
            return "pause_lane"
        case .waiting:
            return "await_launch"
        case .recovering:
            return "observe"
        case .completed:
            return "mergeback"
        }
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
