import Foundation

struct PoolIntegrationGlobalAssertion: Codable, Equatable, Identifiable {
    var id: String
    let ok: Bool
    let detail: String
}

struct PoolIntegrationFailureAttributionReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let splitPlanID: String
    let failureScope: String
    let failedStage: String
    let rootCauseHypothesis: String
    let rollbackPoint: String
    let repairSuggestions: [String]
    let poolLevelPass: Bool
    let globalLevelExecuted: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case splitPlanID = "split_plan_id"
        case failureScope = "failure_scope"
        case failedStage = "failed_stage"
        case rootCauseHypothesis = "root_cause_hypothesis"
        case rollbackPoint = "rollback_point"
        case repairSuggestions = "repair_suggestions"
        case poolLevelPass = "pool_level_pass"
        case globalLevelExecuted = "global_level_executed"
    }
}

struct PoolIntegrationRunReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let splitPlanID: String
    let poolLevelPass: Bool
    let globalLevelExecuted: Bool
    let globalLevelPass: Bool
    let rollbackConsistencyCheck: Bool
    let rollbackPoint: String
    let failureAttributionReady: Bool
    let failureAttribution: PoolIntegrationFailureAttributionReport?
    let globalAssertions: [PoolIntegrationGlobalAssertion]

    var pass: Bool {
        poolLevelPass && globalLevelExecuted && globalLevelPass && rollbackConsistencyCheck
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case splitPlanID = "split_plan_id"
        case poolLevelPass = "pool_level_pass"
        case globalLevelExecuted = "global_level_executed"
        case globalLevelPass = "global_level_pass"
        case rollbackConsistencyCheck = "rollback_consistency_check"
        case rollbackPoint = "rollback_point"
        case failureAttributionReady = "failure_attribution_ready"
        case failureAttribution = "failure_attribution"
        case globalAssertions = "global_assertions"
    }
}

/// XT-W3-18: run pool integration first, only then allow global integration.
@MainActor
final class PoolIntegrationOrchestrator {
    private let schemaVersion = "xterminal.pool_integration_orchestrator.v1"
    private let failureSchemaVersion = "xterminal.pool_integration_failure_attribution.v1"

    func orchestrate(
        splitPlanID: String,
        poolGateReport: LaneMergebackGateReport,
        globalAssertions: [PoolIntegrationGlobalAssertion],
        now: Date = Date()
    ) -> PoolIntegrationRunReport {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let rollbackPoint = poolGateReport.rollbackPoints.first?.stablePointID ?? ""
        let rollbackConsistencyCheck = !rollbackPoint.isEmpty && poolGateReport.kpi.mergebackRollbackReadyRate >= 1.0

        guard poolGateReport.pass else {
            let failure = buildFailureAttribution(
                splitPlanID: splitPlanID,
                failureScope: "pool-level",
                failedStage: "pool_integration",
                rootCause: failingPoolRootCause(from: poolGateReport),
                rollbackPoint: rollbackPoint,
                poolLevelPass: false,
                globalLevelExecuted: false,
                nowMs: nowMs
            )
            return PoolIntegrationRunReport(
                schemaVersion: schemaVersion,
                generatedAtMs: nowMs,
                splitPlanID: splitPlanID,
                poolLevelPass: false,
                globalLevelExecuted: false,
                globalLevelPass: false,
                rollbackConsistencyCheck: rollbackConsistencyCheck,
                rollbackPoint: rollbackPoint,
                failureAttributionReady: true,
                failureAttribution: failure,
                globalAssertions: []
            )
        }

        let globalLevelPass = globalAssertions.allSatisfy(\.ok)
        guard globalLevelPass else {
            let failure = buildFailureAttribution(
                splitPlanID: splitPlanID,
                failureScope: "global-level",
                failedStage: "global_integration",
                rootCause: failingGlobalRootCause(from: globalAssertions),
                rollbackPoint: rollbackPoint,
                poolLevelPass: true,
                globalLevelExecuted: true,
                nowMs: nowMs
            )
            return PoolIntegrationRunReport(
                schemaVersion: schemaVersion,
                generatedAtMs: nowMs,
                splitPlanID: splitPlanID,
                poolLevelPass: true,
                globalLevelExecuted: true,
                globalLevelPass: false,
                rollbackConsistencyCheck: rollbackConsistencyCheck,
                rollbackPoint: rollbackPoint,
                failureAttributionReady: true,
                failureAttribution: failure,
                globalAssertions: globalAssertions
            )
        }

        return PoolIntegrationRunReport(
            schemaVersion: schemaVersion,
            generatedAtMs: nowMs,
            splitPlanID: splitPlanID,
            poolLevelPass: true,
            globalLevelExecuted: true,
            globalLevelPass: true,
            rollbackConsistencyCheck: rollbackConsistencyCheck,
            rollbackPoint: rollbackPoint,
            failureAttributionReady: false,
            failureAttribution: nil,
            globalAssertions: globalAssertions
        )
    }

    func exportFailureAttribution(
        _ report: PoolIntegrationFailureAttributionReport,
        to url: URL
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func failingPoolRootCause(from report: LaneMergebackGateReport) -> String {
        report.assertions.first(where: { !$0.ok })?.detail ?? "pool gate failed without explicit failing assertion"
    }

    private func failingGlobalRootCause(from assertions: [PoolIntegrationGlobalAssertion]) -> String {
        assertions.first(where: { !$0.ok })?.detail ?? "global integration failed without explicit failing assertion"
    }

    private func buildFailureAttribution(
        splitPlanID: String,
        failureScope: String,
        failedStage: String,
        rootCause: String,
        rollbackPoint: String,
        poolLevelPass: Bool,
        globalLevelExecuted: Bool,
        nowMs: Int64
    ) -> PoolIntegrationFailureAttributionReport {
        PoolIntegrationFailureAttributionReport(
            schemaVersion: failureSchemaVersion,
            generatedAtMs: nowMs,
            splitPlanID: splitPlanID,
            failureScope: failureScope,
            failedStage: failedStage,
            rootCauseHypothesis: rootCause,
            rollbackPoint: rollbackPoint,
            repairSuggestions: repairSuggestions(for: failureScope, rootCause: rootCause),
            poolLevelPass: poolLevelPass,
            globalLevelExecuted: globalLevelExecuted
        )
    }

    private func repairSuggestions(for failureScope: String, rootCause: String) -> [String] {
        var suggestions: [String] = []
        if failureScope == "pool-level" {
            suggestions.append("repair pool-level gate inputs before allowing global integration")
            suggestions.append("re-run pool integration until rollback points are complete for every lane")
        } else {
            suggestions.append("rollback global integration to the latest pool stable point before retry")
            suggestions.append("export a fresh failure attribution report before any next global merge attempt")
        }
        if rootCause.localizedCaseInsensitiveContains("rollback") {
            suggestions.append("rebuild rollback hints and stable point metadata for every completed lane")
        }
        if rootCause.localizedCaseInsensitiveContains("incident") {
            suggestions.append("restore handled incident coverage before retrying integration")
        }
        return Array(NSOrderedSet(array: suggestions)) as? [String] ?? suggestions
    }
}
