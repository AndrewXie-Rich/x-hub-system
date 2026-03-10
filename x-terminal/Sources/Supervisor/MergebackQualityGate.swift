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
