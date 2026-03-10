import Foundation

struct LaneMergebackGateAssertion: Codable, Equatable, Identifiable {
    var id: String
    var ok: Bool
    var detail: String
}

struct LaneMergebackRollbackPoint: Codable, Equatable, Identifiable {
    var id: String { stablePointID }
    let laneID: String
    let taskID: UUID
    let projectID: UUID?
    let status: LaneHealthStatus
    let heartbeatSeq: Int
    let stablePointID: String
    let assignmentSnapshotRef: String
    let incidentPolicyVersion: String
    let mergePolicyVersion: String
    let rollbackHints: [String]
    let capturedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case taskID = "task_id"
        case projectID = "project_id"
        case status
        case heartbeatSeq = "heartbeat_seq"
        case stablePointID = "stable_point_id"
        case assignmentSnapshotRef = "assignment_snapshot_ref"
        case incidentPolicyVersion = "incident_policy_version"
        case mergePolicyVersion = "merge_policy_version"
        case rollbackHints = "rollback_hints"
        case capturedAtMs = "captured_at_ms"
    }
}

struct LaneMergebackKPISnapshot: Codable, Equatable {
    let laneStallDetectP95Ms: Int64
    let supervisorActionLatencyP95Ms: Int64
    let highRiskLaneWithoutGrant: Int
    let unauditedAutoResolution: Int
    let mergebackRollbackReadyRate: Double

    enum CodingKeys: String, CodingKey {
        case laneStallDetectP95Ms = "lane_stall_detect_p95_ms"
        case supervisorActionLatencyP95Ms = "supervisor_action_latency_p95_ms"
        case highRiskLaneWithoutGrant = "high_risk_lane_without_grant"
        case unauditedAutoResolution = "unaudited_auto_resolution"
        case mergebackRollbackReadyRate = "mergeback_rollback_ready_rate"
    }
}

struct LaneMergebackGateReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let splitPlanID: String
    let pass: Bool
    let assertions: [LaneMergebackGateAssertion]
    let rollbackPoints: [LaneMergebackRollbackPoint]
    let kpi: LaneMergebackKPISnapshot

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case splitPlanID = "split_plan_id"
        case pass
        case assertions
        case rollbackPoints = "rollback_points"
        case kpi
    }
}

/// XT-W3-11：mergeback 前质量门禁与回滚点断言（fail-closed）
@MainActor
final class LaneMergebackGateEvaluator {
    private let incidentPolicyVersion = "incident_arbiter.skill_takeover.v1"
    private let mergePolicyVersion = "mergeback_gate.v1"

    func evaluate(
        splitPlanID: String,
        lanes: [MaterializedLane],
        laneStates: [String: LaneRuntimeState],
        incidents: [SupervisorLaneIncident],
        promptCompilationResult: PromptCompilationResult?,
        launchReport: LaneLaunchReport?,
        strictIncidentCoverage: Bool = true,
        now: Date = Date()
    ) -> LaneMergebackGateReport {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let laneIDs = lanes.map { $0.plan.laneID }
        let laneIDSet = Set(laneIDs)
        let laneStatesByID = Dictionary(uniqueKeysWithValues: laneStates.values.map { ($0.laneID, $0) })
        let incidentsForPlan = incidents
            .filter { laneIDSet.contains($0.laneID) && $0.status == .handled }
            .sorted { lhs, rhs in
                if lhs.detectedAtMs != rhs.detectedAtMs {
                    return lhs.detectedAtMs < rhs.detectedAtMs
                }
                return lhs.id < rhs.id
            }

        let contractsByLaneID = Dictionary(
            uniqueKeysWithValues: (promptCompilationResult?.contracts ?? []).map { ($0.laneId, $0) }
        )

        let highRiskLaneIDs = Set(
            lanes
                .filter { $0.plan.riskTier >= .high }
                .map { $0.plan.laneID }
        )

        let highRiskLaneWithoutGrant = incidentsForPlan.filter { incident in
            highRiskLaneIDs.contains(incident.laneID)
                && incident.incidentCode == LaneBlockedReason.grantPending.rawValue
                && incident.proposedAction == .autoGrant
        }.count
        let unauditedAutoResolution = incidentsForPlan.filter { incident in
            incident.autoResolvable
                && incident.auditRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        let actionLatencies = incidentsForPlan.compactMap(\.takeoverLatencyMs).filter { $0 >= 0 }
        let supervisorActionLatencyP95Ms = percentile95(actionLatencies)

        let stallLatencies = laneIDs.compactMap { laneID -> Int64? in
            guard let lane = laneStatesByID[laneID] else { return nil }
            guard lane.oldestWaitMs > 0 else { return nil }
            return max(0, nowMs - lane.oldestWaitMs)
        }
        let laneStallDetectP95Ms = percentile95(stallLatencies)

        let assignmentSnapshotRef = launchReport?.reproducibilitySignature
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rollbackPoints = buildRollbackPoints(
            laneIDs: laneIDs,
            laneStatesByID: laneStatesByID,
            contractsByLaneID: contractsByLaneID,
            assignmentSnapshotRef: assignmentSnapshotRef,
            nowMs: nowMs
        )
        let rollbackReadyRate = laneIDs.isEmpty
            ? 0
            : Double(rollbackPoints.count) / Double(laneIDs.count)

        var assertions: [LaneMergebackGateAssertion] = []
        assertions.append(
            makeAssertion(
                id: "assignment_strategy_snapshot",
                ok: !assignmentSnapshotRef.isEmpty,
                detail: !assignmentSnapshotRef.isEmpty
                    ? "assignment snapshot captured"
                    : "missing allocation reproducibility signature"
            )
        )

        let missingContracts = laneIDs.filter { contractsByLaneID[$0] == nil }
        let promptReady = promptCompilationResult?.canLaunch == true && missingContracts.isEmpty
        assertions.append(
            makeAssertion(
                id: "mergeback_prompt_contract_coverage",
                ok: promptReady,
                detail: promptReady
                    ? "prompt contracts cover all lanes"
                    : "missing contracts for lanes: \(missingContracts.joined(separator: ","))"
            )
        )

        let nonCompletedLanes = laneIDs.filter { laneStatesByID[$0]?.status != .completed }
        assertions.append(
            makeAssertion(
                id: "mergeback_only_completed_lanes",
                ok: nonCompletedLanes.isEmpty,
                detail: nonCompletedLanes.isEmpty
                    ? "all lanes reached completed stable point"
                    : "non-completed lanes: \(nonCompletedLanes.joined(separator: ","))"
            )
        )

        let requiredIncidentCodes: Set<String> = [
            LaneBlockedReason.grantPending.rawValue,
            LaneBlockedReason.awaitingInstruction.rawValue,
            LaneBlockedReason.runtimeError.rawValue,
        ]
        let incidentCodesObserved = Set(incidentsForPlan.map(\.incidentCode))
        let missingIncidentCodes: [String]
        if strictIncidentCoverage {
            missingIncidentCodes = requiredIncidentCodes.subtracting(incidentCodesObserved).sorted()
        } else {
            missingIncidentCodes = []
        }
        assertions.append(
            makeAssertion(
                id: "incident_takeover_coverage",
                ok: missingIncidentCodes.isEmpty,
                detail: missingIncidentCodes.isEmpty
                    ? "grant/await/runtime takeover evidence present"
                    : "missing incident coverage: \(missingIncidentCodes.joined(separator: ","))"
            )
        )

        assertions.append(
            makeAssertion(
                id: "mergeback_rollback_points_ready",
                ok: rollbackPoints.count == laneIDs.count,
                detail: "rollback_points=\(rollbackPoints.count)/\(laneIDs.count)"
            )
        )

        assertions.append(
            makeAssertion(
                id: "kpi_lane_stall_detect_p95",
                ok: laneStallDetectP95Ms <= 2_000,
                detail: "lane_stall_detect_p95_ms=\(laneStallDetectP95Ms)"
            )
        )
        assertions.append(
            makeAssertion(
                id: "kpi_supervisor_action_latency_p95",
                ok: supervisorActionLatencyP95Ms <= 1_500,
                detail: "supervisor_action_latency_p95_ms=\(supervisorActionLatencyP95Ms)"
            )
        )
        assertions.append(
            makeAssertion(
                id: "kpi_high_risk_lane_without_grant",
                ok: highRiskLaneWithoutGrant == 0,
                detail: "high_risk_lane_without_grant=\(highRiskLaneWithoutGrant)"
            )
        )
        assertions.append(
            makeAssertion(
                id: "kpi_unaudited_auto_resolution",
                ok: unauditedAutoResolution == 0,
                detail: "unaudited_auto_resolution=\(unauditedAutoResolution)"
            )
        )

        let pass = assertions.allSatisfy(\.ok)
        return LaneMergebackGateReport(
            schemaVersion: "xterminal.mergeback_gate.v1",
            generatedAtMs: nowMs,
            splitPlanID: splitPlanID,
            pass: pass,
            assertions: assertions,
            rollbackPoints: rollbackPoints,
            kpi: LaneMergebackKPISnapshot(
                laneStallDetectP95Ms: laneStallDetectP95Ms,
                supervisorActionLatencyP95Ms: supervisorActionLatencyP95Ms,
                highRiskLaneWithoutGrant: highRiskLaneWithoutGrant,
                unauditedAutoResolution: unauditedAutoResolution,
                mergebackRollbackReadyRate: rollbackReadyRate
            )
        )
    }

    private func buildRollbackPoints(
        laneIDs: [String],
        laneStatesByID: [String: LaneRuntimeState],
        contractsByLaneID: [String: PromptContract],
        assignmentSnapshotRef: String,
        nowMs: Int64
    ) -> [LaneMergebackRollbackPoint] {
        laneIDs.compactMap { laneID in
            guard let state = laneStatesByID[laneID], state.status == .completed else { return nil }
            let contractRollbackPoints = contractsByLaneID[laneID]?.rollbackPoints ?? []
            let rollbackHints = contractRollbackPoints
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard !rollbackHints.isEmpty else { return nil }

            return LaneMergebackRollbackPoint(
                laneID: laneID,
                taskID: state.taskId,
                projectID: state.projectId,
                status: state.status,
                heartbeatSeq: state.heartbeatSeq,
                stablePointID: "stable-\(laneID)-hb\(state.heartbeatSeq)-\(state.updatedAtMs)",
                assignmentSnapshotRef: assignmentSnapshotRef,
                incidentPolicyVersion: incidentPolicyVersion,
                mergePolicyVersion: mergePolicyVersion,
                rollbackHints: rollbackHints,
                capturedAtMs: nowMs
            )
        }
    }

    private func makeAssertion(id: String, ok: Bool, detail: String) -> LaneMergebackGateAssertion {
        LaneMergebackGateAssertion(id: id, ok: ok, detail: detail)
    }

    private func percentile95(_ values: [Int64]) -> Int64 {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * 0.95).rounded(.toNearestOrAwayFromZero))
        return sorted[min(max(0, index), sorted.count - 1)]
    }
}
