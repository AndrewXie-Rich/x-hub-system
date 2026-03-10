import Foundation

/// incident 严重级别
enum SupervisorIncidentSeverity: String, Codable, CaseIterable {
    case low
    case medium
    case high
    case critical
}

/// incident 分类
enum SupervisorIncidentCategory: String, Codable, CaseIterable {
    case permission
    case instruction
    case runtime
}

/// incident 推荐动作（与工单策略对齐）
enum SupervisorIncidentAction: String, Codable, CaseIterable {
    case autoRetry = "auto_retry"
    case autoGrant = "auto_grant"
    case notifyUser = "notify_user"
    case pauseLane = "pause_lane"
    case replan
}

enum SupervisorIncidentStatus: String, Codable, CaseIterable {
    case detected
    case handled
}

/// 泳道 incident 记录（machine-readable）
struct SupervisorLaneIncident: Identifiable, Codable, Equatable {
    let id: String
    let laneID: String
    let taskID: UUID
    let projectID: UUID?

    let incidentCode: String
    let eventType: String
    let denyCode: String

    let severity: SupervisorIncidentSeverity
    let category: SupervisorIncidentCategory
    var autoResolvable: Bool
    var requiresUserAck: Bool
    var proposedAction: SupervisorIncidentAction

    let detectedAtMs: Int64
    var handledAtMs: Int64?
    var takeoverLatencyMs: Int64?

    let auditRef: String
    var detail: String
    var status: SupervisorIncidentStatus
}

struct IncidentDecision {
    let laneID: String
    let taskID: UUID
    let action: SupervisorIncidentAction
    var incident: SupervisorLaneIncident
}

/// XT-W2-14：阻塞与权限事件秒级接管
@MainActor
final class IncidentArbiter {
    private var lastFingerprintAtMs: [String: Int64] = [:]
    private var terminalIncidentFingerprints: Set<String> = []
    private var activeBlockedIncidentCodeByLaneID: [String: String] = [:]
    private let dedupeWindowMs: Int64
    private let maxRuntimeAutoRetryAttempts = 3
    private let maxSkillRuntimeAutoRetryAttempts = 1

    init(dedupeWindowMs: Int64 = 5_000) {
        self.dedupeWindowMs = max(300, dedupeWindowMs)
    }

    func evaluate(
        laneStates: [String: LaneRuntimeState],
        taskStates: [UUID: TaskExecutionState],
        now: Date = Date()
    ) -> [IncidentDecision] {
        let nowMs = now.millisecondsSinceEpoch
        var decisions: [IncidentDecision] = []

        var taskByLaneID: [String: TaskExecutionState] = [:]
        for state in taskStates.values {
            let laneID = state.task.metadata["lane_id"] ?? "lane-\(state.task.id.uuidString.prefix(8))"
            if taskByLaneID[laneID] == nil {
                taskByLaneID[laneID] = state
            }
        }

        for laneID in laneStates.keys.sorted() {
            guard let laneState = laneStates[laneID] else { continue }
            let taskState = taskByLaneID[laneID]
            let terminalFingerprintPrefix = "\(laneID)|"
            if !laneState.status.isTerminal {
                terminalIncidentFingerprints = terminalIncidentFingerprints.filter { !$0.hasPrefix(terminalFingerprintPrefix) }
            }
            if laneState.status != .blocked {
                activeBlockedIncidentCodeByLaneID.removeValue(forKey: laneID)
            }

            guard let incidentCode = incidentCode(for: laneState) else { continue }
            if laneState.status == .blocked,
               activeBlockedIncidentCodeByLaneID[laneID] == incidentCode {
                continue
            }
            let terminalFingerprint = "\(laneID)|\(incidentCode)|terminal"
            if laneState.status.isTerminal, terminalIncidentFingerprints.contains(terminalFingerprint) {
                continue
            }

            let fingerprint = "\(laneID)|\(incidentCode)|\(laneState.status.rawValue)"
            if let last = lastFingerprintAtMs[fingerprint], nowMs - last < dedupeWindowMs {
                continue
            }

            let riskTier = resolvedRiskTier(taskState: taskState, laneState: laneState)
            let action = chooseAction(
                incidentCode: incidentCode,
                riskTier: riskTier,
                laneState: laneState,
                taskState: taskState
            )
            let category = chooseCategory(for: incidentCode)
            let severity = chooseSeverity(incidentCode: incidentCode, riskTier: riskTier)
            let requiresUserAck = action == .notifyUser
            let autoResolvable = [.autoRetry, .autoGrant, .replan].contains(action)
            let taskID = taskState?.task.id ?? laneState.taskId
            let projectID = taskState?.projectId ?? laneState.projectId

            let incident = SupervisorLaneIncident(
                id: "incident-\(UUID().uuidString.lowercased())",
                laneID: laneID,
                taskID: taskID,
                projectID: projectID,
                incidentCode: incidentCode,
                eventType: "supervisor.incident.\(incidentCode).handled",
                denyCode: incidentCode,
                severity: severity,
                category: category,
                autoResolvable: autoResolvable,
                requiresUserAck: requiresUserAck,
                proposedAction: action,
                detectedAtMs: nowMs,
                handledAtMs: nil,
                takeoverLatencyMs: nil,
                auditRef: "audit-\(UUID().uuidString.lowercased())",
                detail: "lane=\(laneID),status=\(laneState.status.rawValue),reason=\(laneState.blockedReason?.rawValue ?? "none"),action=\(action.rawValue)",
                status: .detected
            )

            decisions.append(
                IncidentDecision(
                    laneID: laneID,
                    taskID: taskID,
                    action: action,
                    incident: incident
                )
            )

            lastFingerprintAtMs[fingerprint] = nowMs
            if laneState.status.isTerminal {
                terminalIncidentFingerprints.insert(terminalFingerprint)
            }
            if laneState.status == .blocked {
                activeBlockedIncidentCodeByLaneID[laneID] = incidentCode
            }
        }

        trimFingerprintCache(nowMs: nowMs)
        return decisions
    }

    private func incidentCode(for laneState: LaneRuntimeState) -> String? {
        switch laneState.status {
        case .blocked:
            guard let reason = laneState.blockedReason else { return nil }
            if let canonical = reason.canonicalIncidentCode {
                return canonical
            }
            switch reason {
            case .contextOverflow, .routeOriginUnavailable, .dispatchIdleTimeout:
                return reason.rawValue
            default:
                return nil
            }

        case .failed:
            let note = (laneState.lastNote ?? "").lowercased()
            // Allocation failures happen before lane execution starts. They should not
            // be rewritten into runtime_error incidents, otherwise XT-Ready evidence is polluted.
            if note.contains("allocation_blocked")
                || note.contains("no_project_available")
                || note.contains("risk_profile_mismatch")
                || note.contains("budget_exhausted")
                || note.contains("skill_profile_mismatch")
                || note.contains("reliability_history_insufficient") {
                return nil
            }
            if let reason = laneState.blockedReason,
               let canonical = reason.canonicalIncidentCode {
                return canonical
            }
            if let reason = laneState.blockedReason {
                switch reason {
                case .contextOverflow, .routeOriginUnavailable, .dispatchIdleTimeout:
                    return reason.rawValue
                default:
                    break
                }
            }
            if laneState.lastNote?.contains(LaneBlockedReason.skillPreflightFailed.rawValue) == true {
                return LaneBlockedReason.awaitingInstruction.rawValue
            }
            if laneState.lastNote?.contains(LaneBlockedReason.skillGrantPending.rawValue) == true {
                return LaneBlockedReason.grantPending.rawValue
            }
            if laneState.lastNote?.contains(LaneBlockedReason.skillRuntimeError.rawValue) == true {
                return LaneBlockedReason.runtimeError.rawValue
            }
            if laneState.lastNote?.contains(LaneBlockedReason.grantPending.rawValue) == true {
                return LaneBlockedReason.grantPending.rawValue
            }
            if laneState.lastNote?.contains(LaneBlockedReason.awaitingInstruction.rawValue) == true {
                return LaneBlockedReason.awaitingInstruction.rawValue
            }
            if laneState.lastNote?.contains("runtime_error") == true {
                return LaneBlockedReason.runtimeError.rawValue
            }
            // Fail-closed default: terminal lane failures are treated as runtime incidents.
            return LaneBlockedReason.runtimeError.rawValue

        default:
            return nil
        }
    }

    private func chooseAction(
        incidentCode: String,
        riskTier: LaneRiskTier,
        laneState: LaneRuntimeState,
        taskState: TaskExecutionState?
    ) -> SupervisorIncidentAction {
        switch incidentCode {
        case LaneBlockedReason.grantPending.rawValue:
            if taskState?.task.metadata["auto_grant_exhausted"] == "1" {
                return .notifyUser
            }
            // When task state is unavailable (e.g. lane failed fast and state already evicted),
            // prefer explicit user action instead of speculative auto grant.
            if taskState == nil {
                return .notifyUser
            }
            return riskTier >= .high ? .notifyUser : .autoGrant

        case LaneBlockedReason.awaitingInstruction.rawValue:
            if laneState.blockedReason == .skillPreflightFailed {
                return .notifyUser
            }
            if taskState == nil {
                return .notifyUser
            }
            return riskTier >= .high ? .notifyUser : .replan

        case LaneBlockedReason.runtimeError.rawValue:
            if laneState.blockedReason == .skillRuntimeError,
               (taskState?.attempts ?? 0) >= maxSkillRuntimeAutoRetryAttempts {
                return .pauseLane
            }
            if taskState == nil
                || taskState?.currentStatus == .failed
                || (taskState?.attempts ?? 0) >= maxRuntimeAutoRetryAttempts
                || laneState.status == .failed {
                return .pauseLane
            }
            return .autoRetry
        case LaneBlockedReason.contextOverflow.rawValue:
            return riskTier >= .high ? .notifyUser : .replan
        case LaneBlockedReason.routeOriginUnavailable.rawValue:
            return .replan
        case LaneBlockedReason.dispatchIdleTimeout.rawValue:
            return .pauseLane

        default:
            return .pauseLane
        }
    }

    private func chooseCategory(for incidentCode: String) -> SupervisorIncidentCategory {
        switch incidentCode {
        case LaneBlockedReason.grantPending.rawValue:
            return .permission
        case LaneBlockedReason.awaitingInstruction.rawValue:
            return .instruction
        default:
            return .runtime
        }
    }

    private func chooseSeverity(incidentCode: String, riskTier: LaneRiskTier) -> SupervisorIncidentSeverity {
        switch incidentCode {
        case LaneBlockedReason.grantPending.rawValue:
            return riskTier >= .high ? .high : .medium
        case LaneBlockedReason.awaitingInstruction.rawValue:
            return riskTier >= .high ? .high : .medium
        case LaneBlockedReason.runtimeError.rawValue:
            return riskTier >= .high ? .critical : .high
        case LaneBlockedReason.contextOverflow.rawValue:
            return riskTier >= .high ? .critical : .high
        case LaneBlockedReason.routeOriginUnavailable.rawValue:
            return riskTier >= .high ? .critical : .high
        case LaneBlockedReason.dispatchIdleTimeout.rawValue:
            return .critical
        default:
            return .medium
        }
    }

    private func resolvedRiskTier(
        taskState: TaskExecutionState?,
        laneState: LaneRuntimeState
    ) -> LaneRiskTier {
        if let raw = taskState?.task.metadata["risk_tier"],
           let tier = LaneRiskTier(rawValue: raw) {
            return tier
        }

        let profile = (laneState.agentProfile ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if profile.contains("critical") || profile.contains("trusted_high") || profile.contains("high") {
            return .high
        }
        if profile.contains("low") {
            return .low
        }
        return .medium
    }

    private func trimFingerprintCache(nowMs: Int64) {
        let ttl: Int64 = 30_000
        if lastFingerprintAtMs.count < 256 {
            return
        }
        lastFingerprintAtMs = lastFingerprintAtMs.filter { nowMs - $0.value <= ttl }
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
