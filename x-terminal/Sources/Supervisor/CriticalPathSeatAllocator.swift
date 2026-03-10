import Foundation

enum SeatState: String, Codable, Equatable {
    case active
    case standby
}

struct SeatProgressWindow: Codable, Equatable {
    let windowID: String
    let deltaCount: Int

    enum CodingKeys: String, CodingKey {
        case windowID = "window_id"
        case deltaCount = "delta_count"
    }
}

struct CriticalPathLaneSnapshot: Codable, Equatable, Identifiable {
    let laneID: String
    let taskID: String
    let seatState: SeatState
    let criticalPathRank: Int
    let blockRiskScore: Double
    let requiresActiveSeat: Bool
    let isReleaseBlocker: Bool
    let priorityLabel: String
    let status: LaneHealthStatus
    let blockedReason: LaneBlockedReason?
    let progressWindows: [SeatProgressWindow]

    var id: String { laneID }

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case taskID = "task_id"
        case seatState = "seat_state"
        case criticalPathRank = "critical_path_rank"
        case blockRiskScore = "block_risk_score"
        case requiresActiveSeat = "requires_active_seat"
        case isReleaseBlocker = "is_release_blocker"
        case priorityLabel = "priority_label"
        case status
        case blockedReason = "blocked_reason"
        case progressWindows = "progress_windows"
    }

    var hasTwoWindowNoIncrement: Bool {
        guard progressWindows.count >= 2 else { return false }
        return progressWindows.suffix(2).allSatisfy { $0.deltaCount == 0 }
    }
}

struct SeatAssignmentAudit: Codable, Equatable, Identifiable {
    let auditID: String
    let laneID: String
    let taskID: String
    let seatBefore: SeatState
    let seatAfter: SeatState
    let preemptReason: String

    var id: String { auditID }

    enum CodingKeys: String, CodingKey {
        case auditID = "audit_id"
        case laneID = "lane_id"
        case taskID = "task_id"
        case seatBefore = "seat_before"
        case seatAfter = "seat_after"
        case preemptReason = "preempt_reason"
    }
}

struct CriticalPathSeatAllocationResult: Codable, Equatable {
    let seatBefore: [String: SeatState]
    let seatAfter: [String: SeatState]
    let audits: [SeatAssignmentAudit]
    let activeLaneCountViolations: Int
    let activeOverflowRecovered: Bool
    let downgradedNonCriticalLaneIDs: [String]
    let autoReleasedLaneIDs: [String]
    let criticalPathPreemptSuccessRate: Double
    let queueStarvationIncidents: Int
    let releaseBlockerProtected: Bool

    enum CodingKeys: String, CodingKey {
        case seatBefore = "seat_before"
        case seatAfter = "seat_after"
        case audits
        case activeLaneCountViolations = "active_lane_count_violations"
        case activeOverflowRecovered = "active_overflow_recovered"
        case downgradedNonCriticalLaneIDs = "downgraded_non_critical_lane_ids"
        case autoReleasedLaneIDs = "auto_released_lane_ids"
        case criticalPathPreemptSuccessRate = "critical_path_preempt_success_rate"
        case queueStarvationIncidents = "queue_starvation_incidents"
        case releaseBlockerProtected = "release_blocker_protected"
    }
}

/// XT-W2-25-B: keep at most 3 active lanes while protecting critical-path and release-blocker work.
struct CriticalPathSeatAllocator {
    let maxActiveSeats: Int

    init(maxActiveSeats: Int = 3) {
        self.maxActiveSeats = max(1, maxActiveSeats)
    }

    func allocate(lanes: [CriticalPathLaneSnapshot]) -> CriticalPathSeatAllocationResult {
        let sorted = lanes.sorted(by: laneSort)
        let seatBefore = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneID, $0.seatState) })
        let beforeActive = Set(lanes.filter { $0.seatState == .active }.map(\.laneID))
        let eligibleForActive = sorted.filter { !$0.hasTwoWindowNoIncrement || $0.isReleaseBlocker }
        let chosenActive = Array(eligibleForActive.prefix(maxActiveSeats))
        let afterActive = Set(chosenActive.map(\.laneID))
        let seatAfter = Dictionary(uniqueKeysWithValues: sorted.map { ($0.laneID, afterActive.contains($0.laneID) ? SeatState.active : .standby) })

        var audits: [SeatAssignmentAudit] = []
        var downgradedNonCritical: [String] = []
        var autoReleased: [String] = []
        var preemptOpportunities = 0
        var successfulPreemptions = 0

        let chosenCriticalLaneIDs = Set(chosenActive.filter { $0.requiresActiveSeat || $0.isReleaseBlocker }.map(\.laneID))
        let beforeActiveNonCritical = lanes.filter { beforeActive.contains($0.laneID) && !$0.requiresActiveSeat && !$0.isReleaseBlocker }
        let requestedCriticalStandbyBefore = lanes.filter { !beforeActive.contains($0.laneID) && ($0.requiresActiveSeat || $0.isReleaseBlocker) && !($0.hasTwoWindowNoIncrement && !$0.isReleaseBlocker) }
        preemptOpportunities = min(beforeActiveNonCritical.count, requestedCriticalStandbyBefore.count)
        successfulPreemptions = requestedCriticalStandbyBefore.filter { chosenCriticalLaneIDs.contains($0.laneID) }.count

        for lane in sorted {
            let before = seatBefore[lane.laneID] ?? .standby
            let after = seatAfter[lane.laneID] ?? .standby
            var reason = "seat_unchanged"
            if before == .active && after == .standby && lane.hasTwoWindowNoIncrement && !lane.isReleaseBlocker {
                reason = "two_windows_no_increment_auto_release"
                autoReleased.append(lane.laneID)
            } else if before == .active && after == .standby && !lane.requiresActiveSeat && !lane.isReleaseBlocker {
                reason = "downgraded_non_critical_for_critical_path"
                downgradedNonCritical.append(lane.laneID)
            } else if before == .standby && after == .active && (lane.requiresActiveSeat || lane.isReleaseBlocker) {
                reason = lane.isReleaseBlocker ? "release_blocker_preempted_into_active" : "critical_path_promoted_into_active"
            } else if before == .standby && after == .active {
                reason = "seat_activated"
            }

            if before != after || reason != "seat_unchanged" {
                audits.append(
                    SeatAssignmentAudit(
                        auditID: "seat_audit_\(lane.laneID)",
                        laneID: lane.laneID,
                        taskID: lane.taskID,
                        seatBefore: before,
                        seatAfter: after,
                        preemptReason: reason
                    )
                )
            }
        }

        let afterActiveCount = afterActive.count
        let activeViolations = max(0, afterActiveCount - maxActiveSeats)
        let activeOverflowRecovered = beforeActive.count > maxActiveSeats && afterActiveCount <= maxActiveSeats

        let starvedLanes = lanes.filter {
            ($0.requiresActiveSeat || $0.isReleaseBlocker) && !afterActive.contains($0.laneID)
        }
        let queueStarvationIncidents = starvedLanes.count

        let releaseBlockers = lanes.filter(\.isReleaseBlocker)
        let releaseBlockerProtected = releaseBlockers.allSatisfy { afterActive.contains($0.laneID) }

        let preemptSuccessRate: Double
        if preemptOpportunities == 0 {
            preemptSuccessRate = 1.0
        } else {
            preemptSuccessRate = Double(successfulPreemptions) / Double(preemptOpportunities)
        }

        return CriticalPathSeatAllocationResult(
            seatBefore: seatBefore,
            seatAfter: seatAfter,
            audits: audits,
            activeLaneCountViolations: activeViolations,
            activeOverflowRecovered: activeOverflowRecovered,
            downgradedNonCriticalLaneIDs: Array(Set(downgradedNonCritical)).sorted(),
            autoReleasedLaneIDs: Array(Set(autoReleased)).sorted(),
            criticalPathPreemptSuccessRate: preemptSuccessRate,
            queueStarvationIncidents: queueStarvationIncidents,
            releaseBlockerProtected: releaseBlockerProtected
        )
    }

    private func laneSort(lhs: CriticalPathLaneSnapshot, rhs: CriticalPathLaneSnapshot) -> Bool {
        if lhs.isReleaseBlocker != rhs.isReleaseBlocker {
            return lhs.isReleaseBlocker && !rhs.isReleaseBlocker
        }
        if lhs.requiresActiveSeat != rhs.requiresActiveSeat {
            return lhs.requiresActiveSeat && !rhs.requiresActiveSeat
        }
        if lhs.criticalPathRank != rhs.criticalPathRank {
            return lhs.criticalPathRank < rhs.criticalPathRank
        }
        if abs(lhs.blockRiskScore - rhs.blockRiskScore) > 0.0001 {
            return lhs.blockRiskScore > rhs.blockRiskScore
        }
        return lhs.laneID < rhs.laneID
    }
}

struct OneShotSeatGovernorDecision: Codable, Equatable {
    let schemaVersion: String
    let requestedLaneCount: Int
    let requestedPoolCount: Int
    let laneCap: Int
    let poolCap: Int
    let approvedLaneCount: Int
    let approvedPoolCount: Int
    let seatCap: Int
    let blockRiskScore: Double
    let riskSurface: OneShotRiskSurface
    let tokenBudgetClass: OneShotTokenBudgetClass
    let selectedProfile: OneShotSplitProfile
    let selectedParticipationMode: DeliveryParticipationMode
    let unsafeAutoLaunchPrevented: Bool
    let laneExplosionPrevented: Bool
    let crossPoolCycleDetected: Bool
    let decision: OneShotPlanDecision
    let denyCode: String
    let decisionExplain: [String]

    static let frozenFieldOrder = [
        "schema_version",
        "requested_lane_count",
        "requested_pool_count",
        "lane_cap",
        "pool_cap",
        "approved_lane_count",
        "approved_pool_count",
        "seat_cap",
        "block_risk_score",
        "risk_surface",
        "token_budget_class",
        "selected_profile",
        "selected_participation_mode",
        "unsafe_auto_launch_prevented",
        "lane_explosion_prevented",
        "cross_pool_cycle_detected",
        "decision",
        "deny_code",
        "decision_explain"
    ]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case requestedLaneCount = "requested_lane_count"
        case requestedPoolCount = "requested_pool_count"
        case laneCap = "lane_cap"
        case poolCap = "pool_cap"
        case approvedLaneCount = "approved_lane_count"
        case approvedPoolCount = "approved_pool_count"
        case seatCap = "seat_cap"
        case blockRiskScore = "block_risk_score"
        case riskSurface = "risk_surface"
        case tokenBudgetClass = "token_budget_class"
        case selectedProfile = "selected_profile"
        case selectedParticipationMode = "selected_participation_mode"
        case unsafeAutoLaunchPrevented = "unsafe_auto_launch_prevented"
        case laneExplosionPrevented = "lane_explosion_prevented"
        case crossPoolCycleDetected = "cross_pool_cycle_detected"
        case decision
        case denyCode = "deny_code"
        case decisionExplain = "decision_explain"
    }

    static func denied(
        requestedLaneCount: Int,
        requestedPoolCount: Int,
        seatCap: Int,
        blockRiskScore: Double,
        riskSurface: OneShotRiskSurface,
        tokenBudgetClass: OneShotTokenBudgetClass,
        selectedProfile: OneShotSplitProfile,
        selectedParticipationMode: DeliveryParticipationMode,
        denyCode: String,
        explain: [String]
    ) -> OneShotSeatGovernorDecision {
        OneShotSeatGovernorDecision(
            schemaVersion: "xt.one_shot_seat_governor_decision.v1",
            requestedLaneCount: requestedLaneCount,
            requestedPoolCount: requestedPoolCount,
            laneCap: max(1, requestedLaneCount),
            poolCap: max(1, requestedPoolCount),
            approvedLaneCount: 0,
            approvedPoolCount: 0,
            seatCap: max(0, seatCap),
            blockRiskScore: blockRiskScore,
            riskSurface: riskSurface,
            tokenBudgetClass: tokenBudgetClass,
            selectedProfile: selectedProfile,
            selectedParticipationMode: selectedParticipationMode,
            unsafeAutoLaunchPrevented: true,
            laneExplosionPrevented: false,
            crossPoolCycleDetected: denyCode == "cross_pool_cycle_detected",
            decision: .deny,
            denyCode: denyCode,
            decisionExplain: oneShotOrderedUniqueStrings(explain)
        )
    }
}

extension CriticalPathSeatAllocator {
    func govern(
        requestedLaneCount: Int,
        requestedPoolCount: Int,
        blockRiskScore: Double,
        riskSurface: OneShotRiskSurface,
        tokenBudgetClass: OneShotTokenBudgetClass,
        selectedProfile: OneShotSplitProfile,
        selectedParticipationMode: DeliveryParticipationMode,
        allowAutoLaunchRequested: Bool,
        requiresHumanAuthorizationTypes: [OneShotHumanAuthorizationType],
        hasBlockingValidationIssues: Bool,
        crossPoolCycleDetected: Bool
    ) -> OneShotSeatGovernorDecision {
        let resolvedProfile = selectedProfile == .auto ? .balanced : selectedProfile

        var laneCap: Int
        switch resolvedProfile {
        case .conservative:
            laneCap = 3
        case .balanced:
            laneCap = 4
        case .aggressive:
            laneCap = 6
        case .auto:
            laneCap = 4
        }

        switch tokenBudgetClass {
        case .tight:
            laneCap -= 1
        case .standard:
            break
        case .priorityDelivery:
            if riskSurface <= .medium {
                laneCap += 1
            }
        }

        if selectedParticipationMode == .criticalTouch {
            laneCap = min(laneCap, 3)
        }
        if riskSurface == .high {
            laneCap = min(laneCap, 3)
        }
        if riskSurface == .critical {
            laneCap = min(laneCap, 2)
        }
        laneCap = max(1, laneCap)

        var poolCap = resolvedProfile == .conservative ? 1 : 2
        if tokenBudgetClass == .tight {
            poolCap = 1
        }
        if riskSurface == .critical {
            poolCap = 1
        }
        poolCap = max(1, poolCap)

        var seatCap: Int
        switch resolvedProfile {
        case .conservative:
            seatCap = 1
        case .balanced:
            seatCap = 2
        case .aggressive:
            seatCap = 3
        case .auto:
            seatCap = 2
        }
        if blockRiskScore >= 0.68 {
            seatCap += 1
        }
        if tokenBudgetClass == .tight {
            seatCap -= 1
        }
        if selectedParticipationMode == .criticalTouch {
            seatCap = min(seatCap, 2)
        }
        if riskSurface == .critical {
            seatCap = min(seatCap, 1)
        }
        seatCap = min(maxActiveSeats, max(1, seatCap))

        let unsafeAutoLaunchPrevented = allowAutoLaunchRequested && (
            !requiresHumanAuthorizationTypes.isEmpty
            || riskSurface >= .high
            || crossPoolCycleDetected
            || hasBlockingValidationIssues
        )
        let laneExplosionPrevented = requestedLaneCount > laneCap
        let approvedLaneCount = min(requestedLaneCount, laneCap)
        let approvedPoolCount = min(requestedPoolCount, poolCap)

        var decision: OneShotPlanDecision = .allow
        var denyCode = "none"
        var explain: [String] = []

        if requestedLaneCount <= 0 {
            decision = .deny
            denyCode = "no_lanes_requested"
            explain.append("no_lanes_requested")
        } else if hasBlockingValidationIssues {
            decision = .deny
            denyCode = "split_proposal_blocking_issue"
            explain.append("split_proposal_blocking_issue")
        } else if crossPoolCycleDetected {
            decision = .deny
            denyCode = "cross_pool_cycle_detected"
            explain.append("cross_pool_cycle_detected")
        } else if approvedLaneCount <= 0 || approvedPoolCount <= 0 {
            decision = .deny
            denyCode = "insufficient_capacity_after_governor"
            explain.append("insufficient_capacity_after_governor")
        } else {
            if unsafeAutoLaunchPrevented {
                decision = .downgrade
                denyCode = "unsafe_auto_launch_prevented"
                explain.append("unsafe_auto_launch_prevented")
            }
            if laneExplosionPrevented {
                decision = .downgrade
                denyCode = denyCode == "none" ? "lane_cap_applied" : denyCode
                explain.append("lane_cap_applied")
            }
            if approvedPoolCount < requestedPoolCount {
                decision = .downgrade
                denyCode = denyCode == "none" ? "pool_cap_applied" : denyCode
                explain.append("pool_cap_applied")
            }
        }

        if selectedParticipationMode == .criticalTouch {
            explain.append("critical_touch_limits_parallelism")
        }
        if tokenBudgetClass == .tight {
            explain.append("tight_budget_caps_parallelism")
        }
        if riskSurface >= .high {
            explain.append("high_risk_caps_parallelism")
        }
        if blockRiskScore >= 0.68 {
            explain.append("block_risk_elevated")
        }
        if explain.isEmpty {
            explain.append("governor_allow_mainline_parallelism")
        }

        return OneShotSeatGovernorDecision(
            schemaVersion: "xt.one_shot_seat_governor_decision.v1",
            requestedLaneCount: requestedLaneCount,
            requestedPoolCount: requestedPoolCount,
            laneCap: laneCap,
            poolCap: poolCap,
            approvedLaneCount: approvedLaneCount,
            approvedPoolCount: approvedPoolCount,
            seatCap: seatCap,
            blockRiskScore: blockRiskScore,
            riskSurface: riskSurface,
            tokenBudgetClass: tokenBudgetClass,
            selectedProfile: resolvedProfile,
            selectedParticipationMode: selectedParticipationMode,
            unsafeAutoLaunchPrevented: unsafeAutoLaunchPrevented,
            laneExplosionPrevented: laneExplosionPrevented,
            crossPoolCycleDetected: crossPoolCycleDetected,
            decision: decision,
            denyCode: denyCode,
            decisionExplain: oneShotOrderedUniqueStrings(explain)
        )
    }
}
