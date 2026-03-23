import Foundation

struct MergebackConflictTriageRecord: Codable, Equatable, Identifiable {
    let id: String
    let laneID: String
    let poolID: String
    let kind: AssemblyConflictKind
    let routeTarget: AssemblyConflictRoute
    let autoTriaged: Bool
    let fixSuggestion: String

    enum CodingKeys: String, CodingKey {
        case id
        case laneID = "lane_id"
        case poolID = "pool_id"
        case kind
        case routeTarget = "route_target"
        case autoTriaged = "auto_triaged"
        case fixSuggestion = "fix_suggestion"
    }
}

struct MergebackRunSnapshot: Codable, Equatable, Identifiable {
    let runID: String
    let laneID: String
    let poolID: String
    let precheckPassed: Bool
    let mergeSucceeded: Bool
    let verifyPassed: Bool
    let committed: Bool
    let stablePointID: String
    let rollbackAnchorID: String
    let qualityGateBlockedOnFailure: Bool
    let rolledBackToStablePoint: Bool
    let conflicts: [MergebackConflictTriageRecord]

    var id: String { runID }

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case laneID = "lane_id"
        case poolID = "pool_id"
        case precheckPassed = "precheck_passed"
        case mergeSucceeded = "merge_succeeded"
        case verifyPassed = "verify_passed"
        case committed
        case stablePointID = "stable_point_id"
        case rollbackAnchorID = "rollback_anchor_id"
        case qualityGateBlockedOnFailure = "quality_gate_block_on_failure"
        case rolledBackToStablePoint = "rolled_back_to_stable_point"
        case conflicts
    }

    var firstPassSuccess: Bool {
        precheckPassed && mergeSucceeded && verifyPassed && committed && !rolledBackToStablePoint
    }

    var hasRollbackPoint: Bool {
        !stablePointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !rollbackAnchorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var mergebackFailed: Bool {
        !precheckPassed || !mergeSucceeded || !verifyPassed
    }
}

struct MergebackQualityGateReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let processStages: [String]
    let sampleCount: Int
    let mergebackFirstPassRate: Double
    let laneRollbackPointCoverage: Double
    let conflictAutoTriageRate: Double
    let qualityGateBlockOnMergeFailure: Bool
    let laneConflictFixSuggestionCoverage: Double
    let mergeFailureAutoRollbackCoverage: Double
    let runAudits: [MergebackRunSnapshot]
    let minimalGaps: [String]

    var pass: Bool { minimalGaps.isEmpty }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case processStages = "process_stages"
        case sampleCount = "sample_count"
        case mergebackFirstPassRate = "mergeback_first_pass_rate"
        case laneRollbackPointCoverage = "lane_rollback_point_coverage"
        case conflictAutoTriageRate = "conflict_auto_triage_rate"
        case qualityGateBlockOnMergeFailure = "quality_gate_block_on_merge_failure"
        case laneConflictFixSuggestionCoverage = "lane_conflict_fix_suggestion_coverage"
        case mergeFailureAutoRollbackCoverage = "merge_failure_auto_rollback_coverage"
        case runAudits = "run_audits"
        case minimalGaps = "minimal_gaps"
    }
}

/// XT-W3-11: fail-closed mergeback quality gate for lane-level rollback and conflict triage.
final class MergebackQualityGateEvaluator {
    private let schemaVersion = "xterminal.xt_w3_11.mergeback_quality_gate.v1"
    private let requiredStages = ["precheck", "merge", "verify", "commit"]

    func evaluate(runs: [MergebackRunSnapshot], now: Date = Date()) -> MergebackQualityGateReport {
        let sampleCount = runs.count
        let firstPassCount = runs.filter(\.firstPassSuccess).count
        let mergebackFirstPassRate = rate(firstPassCount, sampleCount)
        let rollbackPointCoverage = rate(runs.filter(\.hasRollbackPoint).count, sampleCount)

        let allConflicts = runs.flatMap(\.conflicts)
        let autoTriagedConflicts = allConflicts.filter { conflict in
            conflict.autoTriaged && !conflict.fixSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let conflictAutoTriageRate = allConflicts.isEmpty ? 1.0 : rate(autoTriagedConflicts.count, allConflicts.count)
        let fixSuggestionCoverage = allConflicts.isEmpty ? 1.0 : rate(
            allConflicts.filter { !$0.fixSuggestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count,
            allConflicts.count
        )

        let failingRuns = runs.filter(\.mergebackFailed)
        let rollbackProtectedFailures = failingRuns.filter {
            $0.qualityGateBlockedOnFailure && $0.rolledBackToStablePoint && !$0.committed && $0.hasRollbackPoint
        }
        let mergeFailureAutoRollbackCoverage = failingRuns.isEmpty ? 1.0 : rate(rollbackProtectedFailures.count, failingRuns.count)
        let qualityGateBlockOnMergeFailure = failingRuns.allSatisfy {
            $0.qualityGateBlockedOnFailure && $0.rolledBackToStablePoint && !$0.committed && $0.hasRollbackPoint
        }

        var minimalGaps: [String] = []
        if mergebackFirstPassRate < 0.70 { minimalGaps.append("mergeback_first_pass_rate_below_0_70") }
        if rollbackPointCoverage < 1.0 { minimalGaps.append("lane_rollback_point_coverage_incomplete") }
        if conflictAutoTriageRate < 1.0 { minimalGaps.append("conflict_auto_triage_rate_incomplete") }
        if fixSuggestionCoverage < 1.0 { minimalGaps.append("lane_conflict_fix_suggestion_coverage_incomplete") }
        if !qualityGateBlockOnMergeFailure { minimalGaps.append("quality_gate_did_not_block_and_rollback_merge_failure") }
        if mergeFailureAutoRollbackCoverage < 1.0 { minimalGaps.append("merge_failure_auto_rollback_coverage_incomplete") }

        return MergebackQualityGateReport(
            schemaVersion: schemaVersion,
            generatedAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
            processStages: requiredStages,
            sampleCount: sampleCount,
            mergebackFirstPassRate: mergebackFirstPassRate,
            laneRollbackPointCoverage: rollbackPointCoverage,
            conflictAutoTriageRate: conflictAutoTriageRate,
            qualityGateBlockOnMergeFailure: qualityGateBlockOnMergeFailure,
            laneConflictFixSuggestionCoverage: fixSuggestionCoverage,
            mergeFailureAutoRollbackCoverage: mergeFailureAutoRollbackCoverage,
            runAudits: runs,
            minimalGaps: minimalGaps
        )
    }

    private func rate(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}

/// XT-W3-11: build machine-readable mergeback run audits from runtime state.
struct MergebackRunSnapshotBuilder {
    func build(
        lanes: [MaterializedLane],
        promptCompilationResult: PromptCompilationResult?,
        taskStates: [UUID: TaskExecutionState],
        laneStates: [String: LaneRuntimeState],
        rollbackPoints: [LaneMergebackRollbackPoint],
        incidents: [SupervisorLaneIncident],
        conflicts: [AssemblyConflict] = []
    ) -> [MergebackRunSnapshot] {
        let contractsByLaneID = Dictionary(
            uniqueKeysWithValues: (promptCompilationResult?.contracts ?? []).map { ($0.laneId, $0) }
        )
        let rollbackByLaneID = Dictionary(uniqueKeysWithValues: rollbackPoints.map { ($0.laneID, $0) })
        let incidentsByLaneID = Dictionary(grouping: incidents, by: \.laneID)
        let conflictsByLaneID = Dictionary(grouping: conflicts, by: \.laneID)
        let taskStateByLaneID = latestTaskStateByLaneID(taskStates)

        return lanes
            .sorted { $0.plan.laneID < $1.plan.laneID }
            .map { lane in
                let laneID = lane.plan.laneID
                let taskState = taskStateByLaneID[laneID]
                let runtimeState = laneStates[laneID]
                let rollbackPoint = rollbackByLaneID[laneID]
                let laneIncidents = incidentsByLaneID[laneID] ?? []
                let metadata = mergedMetadata(base: lane.task.metadata, override: taskState?.task.metadata ?? [:])
                let stablePointID = firstNonEmpty(
                    metadata["stable_point_id"],
                    rollbackPoint?.stablePointID
                )
                let rollbackAnchorID = firstNonEmpty(
                    metadata["rollback_anchor_id"],
                    metadata["rollback_ref"],
                    stablePointID.isEmpty ? nil : "rollback-anchor-for-\(stablePointID)"
                )

                let precheckPassed = boolMetadata(metadata, keys: ["precheck_passed"]) ?? inferPrecheckPassed(
                    laneID: laneID,
                    runtimeState: runtimeState,
                    taskState: taskState,
                    hasPromptContract: contractsByLaneID[laneID] != nil
                )
                let mergeSucceeded = boolMetadata(metadata, keys: ["merge_succeeded"]) ?? inferMergeSucceeded(
                    runtimeState: runtimeState,
                    taskState: taskState
                )
                let verifyPassed = boolMetadata(metadata, keys: ["verify_passed"]) ?? inferVerifyPassed(
                    runtimeState: runtimeState,
                    taskState: taskState,
                    incidents: laneIncidents
                )
                let rolledBackToStablePoint = boolMetadata(
                    metadata,
                    keys: ["rolled_back_to_stable_point", "rolled_back", "auto_rollback_executed"]
                ) ?? inferRolledBackToStablePoint(
                    runtimeState: runtimeState,
                    taskState: taskState,
                    stablePointID: stablePointID,
                    rollbackAnchorID: rollbackAnchorID,
                    mergeSucceeded: mergeSucceeded,
                    verifyPassed: verifyPassed
                )
                let committed = boolMetadata(metadata, keys: ["mergeback_committed", "committed"]) ?? (
                    runtimeState?.status == .completed && !rolledBackToStablePoint
                )
                let qualityGateBlockedOnFailure = boolMetadata(
                    metadata,
                    keys: ["quality_gate_block_on_failure", "quality_gate_blocked_on_failure"]
                ) ?? inferQualityGateBlockedOnFailure(
                    runtimeState: runtimeState,
                    taskState: taskState,
                    committed: committed,
                    rolledBackToStablePoint: rolledBackToStablePoint,
                    stablePointID: stablePointID,
                    rollbackAnchorID: rollbackAnchorID
                )

                return MergebackRunSnapshot(
                    runID: firstNonEmpty(
                        metadata["mergeback_run_id"],
                        metadata["run_id"],
                        "mergeback-run-\(laneID)"
                    ),
                    laneID: laneID,
                    poolID: firstNonEmpty(
                        metadata["pool_id"],
                        lane.targetProject.map { "project-\($0.id.uuidString.lowercased())" },
                        "pool-default"
                    ),
                    precheckPassed: precheckPassed,
                    mergeSucceeded: mergeSucceeded,
                    verifyPassed: verifyPassed,
                    committed: committed,
                    stablePointID: stablePointID,
                    rollbackAnchorID: rollbackAnchorID,
                    qualityGateBlockedOnFailure: qualityGateBlockedOnFailure,
                    rolledBackToStablePoint: rolledBackToStablePoint,
                    conflicts: (conflictsByLaneID[laneID] ?? []).map { conflict in
                        makeConflictRecord(conflict, poolID: firstNonEmpty(
                            metadata["pool_id"],
                            lane.targetProject.map { "project-\($0.id.uuidString.lowercased())" },
                            "pool-default"
                        ))
                    }
                )
            }
    }

    private func latestTaskStateByLaneID(_ taskStates: [UUID: TaskExecutionState]) -> [String: TaskExecutionState] {
        var result: [String: TaskExecutionState] = [:]
        for state in taskStates.values {
            guard let laneID = laneID(from: state.task.metadata) else { continue }
            if let existing = result[laneID], existing.lastUpdateAt >= state.lastUpdateAt {
                continue
            }
            result[laneID] = state
        }
        return result
    }

    private func laneID(from metadata: [String: String]) -> String? {
        let value = metadata["lane_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private func mergedMetadata(base: [String: String], override: [String: String]) -> [String: String] {
        base.merging(override) { _, new in new }
    }

    private func boolMetadata(_ metadata: [String: String], keys: [String]) -> Bool? {
        for key in keys {
            guard let raw = metadata[key]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                  !raw.isEmpty else {
                continue
            }
            switch raw {
            case "1", "true", "yes", "pass", "passed", "ready", "committed":
                return true
            case "0", "false", "no", "fail", "failed", "blocked", "rollback":
                return false
            default:
                continue
            }
        }
        return nil
    }

    private func inferPrecheckPassed(
        laneID: String,
        runtimeState: LaneRuntimeState?,
        taskState: TaskExecutionState?,
        hasPromptContract: Bool
    ) -> Bool {
        guard hasPromptContract else { return false }
        if runtimeState?.blockedReason == .skillPreflightFailed {
            return false
        }
        if taskState?.task.failureReason?.localizedCaseInsensitiveContains("precheck") == true {
            return false
        }
        if taskState?.errors.contains(where: { error in
            error.message.localizedCaseInsensitiveContains("precheck")
                || (error.code?.localizedCaseInsensitiveContains("precheck") == true)
        }) == true {
            return false
        }
        return !laneID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func inferMergeSucceeded(
        runtimeState: LaneRuntimeState?,
        taskState: TaskExecutionState?
    ) -> Bool {
        if runtimeState?.status == .completed {
            return true
        }
        if taskState?.currentStatus == .completed {
            return true
        }
        return false
    }

    private func inferVerifyPassed(
        runtimeState: LaneRuntimeState?,
        taskState: TaskExecutionState?,
        incidents: [SupervisorLaneIncident]
    ) -> Bool {
        guard inferMergeSucceeded(runtimeState: runtimeState, taskState: taskState) else { return false }
        let hasRuntimeFailure = incidents.contains { incident in
            incident.incidentCode == LaneBlockedReason.runtimeError.rawValue
                && incident.status == .handled
        }
        if hasRuntimeFailure {
            return false
        }
        if taskState?.errors.isEmpty == false {
            return false
        }
        return true
    }

    private func inferRolledBackToStablePoint(
        runtimeState: LaneRuntimeState?,
        taskState: TaskExecutionState?,
        stablePointID: String,
        rollbackAnchorID: String,
        mergeSucceeded: Bool,
        verifyPassed: Bool
    ) -> Bool {
        guard !stablePointID.isEmpty, !rollbackAnchorID.isEmpty else { return false }
        if mergeSucceeded && verifyPassed && runtimeState?.status == .completed {
            return false
        }
        if taskState?.currentStatus == .failed || runtimeState?.status == .failed || runtimeState?.status == .blocked {
            return true
        }
        return !verifyPassed
    }

    private func inferQualityGateBlockedOnFailure(
        runtimeState: LaneRuntimeState?,
        taskState: TaskExecutionState?,
        committed: Bool,
        rolledBackToStablePoint: Bool,
        stablePointID: String,
        rollbackAnchorID: String
    ) -> Bool {
        if committed {
            return true
        }
        if rolledBackToStablePoint {
            return !stablePointID.isEmpty && !rollbackAnchorID.isEmpty
        }
        if runtimeState?.status == .blocked || runtimeState?.status == .failed {
            return true
        }
        return taskState?.currentStatus == .blocked || taskState?.currentStatus == .failed
    }

    private func makeConflictRecord(_ conflict: AssemblyConflict, poolID: String) -> MergebackConflictTriageRecord {
        let autoTriaged = conflict.kind == .semantic && conflict.routeTarget == .lane
            || conflict.kind == .structural && conflict.routeTarget == .pool
        return MergebackConflictTriageRecord(
            id: conflict.id,
            laneID: conflict.laneID,
            poolID: poolID,
            kind: conflict.kind,
            routeTarget: conflict.routeTarget,
            autoTriaged: autoTriaged,
            fixSuggestion: fixSuggestion(for: conflict)
        )
    }

    private func fixSuggestion(for conflict: AssemblyConflict) -> String {
        var suggestion: String
        switch (conflict.kind, conflict.routeTarget) {
        case (.semantic, .lane):
            suggestion = "apply suggested lane patch and rerun semantic lane checks before commit"
        case (.semantic, .pool):
            suggestion = "route semantic drift to pool review, refresh merge inputs, and rerun lane verification before commit"
        case (.structural, .lane):
            suggestion = "split structural conflict into a dedicated lane repair patch before retrying mergeback"
        case (.structural, .pool):
            suggestion = "route structural conflict back to pool integration and regenerate merge plan"
        }

        if conflict.crossPool {
            suggestion += "; include cross-pool contract drift check"
        }
        if conflict.reopened {
            suggestion += "; require supervisor review before next commit"
        }
        return suggestion
    }

    private func firstNonEmpty(_ values: String?...) -> String {
        for value in values {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return ""
    }
}
