import Foundation
import Testing
@testable import XTerminal

struct SupervisorMergebackQualityGateTests {

    @Test
    func mergebackQualityGatePassesWithRollbackCoverageAndAutoTriage() {
        let evaluator = MergebackQualityGateEvaluator()
        let report = evaluator.evaluate(
            runs: makePassingSampleRuns(),
            now: Date(timeIntervalSince1970: 1_730_300_000)
        )

        #expect(report.pass)
        #expect(report.mergebackFirstPassRate >= 0.70)
        #expect(report.laneRollbackPointCoverage == 1.0)
        #expect(report.conflictAutoTriageRate == 1.0)
        #expect(report.qualityGateBlockOnMergeFailure)
        #expect(report.laneConflictFixSuggestionCoverage == 1.0)
        #expect(report.mergeFailureAutoRollbackCoverage == 1.0)
        #expect(report.runAudits.contains(where: { $0.laneID == "lane-verify-fail" && $0.rolledBackToStablePoint }))
        #expect(report.runAudits.flatMap(\.conflicts).contains(where: { $0.laneID == "lane-semantic" && !$0.fixSuggestion.isEmpty }))
    }

    @Test
    func mergebackQualityGateFailsClosedWithoutRollbackPointOrAutoRollback() {
        let evaluator = MergebackQualityGateEvaluator()
        let report = evaluator.evaluate(
            runs: [
                MergebackRunSnapshot(
                    runID: "run-fail-1",
                    laneID: "lane-fail",
                    poolID: "pool-a",
                    precheckPassed: true,
                    mergeSucceeded: true,
                    verifyPassed: false,
                    committed: false,
                    stablePointID: "",
                    rollbackAnchorID: "",
                    qualityGateBlockedOnFailure: false,
                    rolledBackToStablePoint: false,
                    conflicts: [
                        conflict(
                            id: "conflict-fail-1",
                            laneID: "lane-fail",
                            poolID: "pool-a",
                            kind: .semantic,
                            routeTarget: .lane,
                            autoTriaged: false,
                            fixSuggestion: ""
                        )
                    ]
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_300_100)
        )

        #expect(report.pass == false)
        #expect(report.minimalGaps.contains("lane_rollback_point_coverage_incomplete"))
        #expect(report.minimalGaps.contains("conflict_auto_triage_rate_incomplete"))
        #expect(report.minimalGaps.contains("quality_gate_did_not_block_and_rollback_merge_failure"))
    }

    @Test
    func xtW311CaptureEmitsMachineReadableMergebackAudit() throws {
        let evaluator = MergebackQualityGateEvaluator()
        let report = evaluator.evaluate(
            runs: makePassingSampleRuns(),
            now: Date(timeIntervalSince1970: 1_730_300_200)
        )

        #expect(report.pass)

        if ProcessInfo.processInfo.environment["XT_W3_11_CAPTURE"] == "1" {
            let payload = XTW311MergebackCapture(
                schemaVersion: "xterminal.xt_w3_11.mergeback_capture.v1",
                sampleWindow: "xt_w3_11_g4_g5_first_probe_v1",
                mergebackQualityReport: report,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/MergebackQualityGate.swift",
                    "x-terminal/Tests/SupervisorMergebackQualityGateTests.swift",
                    "x-terminal/Sources/Supervisor/LaneMergebackGate.swift"
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = try String(decoding: encoder.encode(payload), as: UTF8.self)
            print("XT_W3_11_CAPTURE_JSON=\(json)")
        }
    }

    private func makePassingSampleRuns() -> [MergebackRunSnapshot] {
        [
            MergebackRunSnapshot(
                runID: "run-pass-1",
                laneID: "lane-clean",
                poolID: "pool-a",
                precheckPassed: true,
                mergeSucceeded: true,
                verifyPassed: true,
                committed: true,
                stablePointID: "stable-lane-clean",
                rollbackAnchorID: "rollback-lane-clean",
                qualityGateBlockedOnFailure: true,
                rolledBackToStablePoint: false,
                conflicts: []
            ),
            MergebackRunSnapshot(
                runID: "run-pass-2",
                laneID: "lane-semantic",
                poolID: "pool-a",
                precheckPassed: true,
                mergeSucceeded: true,
                verifyPassed: true,
                committed: true,
                stablePointID: "stable-lane-semantic",
                rollbackAnchorID: "rollback-lane-semantic",
                qualityGateBlockedOnFailure: true,
                rolledBackToStablePoint: false,
                conflicts: [
                    conflict(
                        id: "conflict-semantic-1",
                        laneID: "lane-semantic",
                        poolID: "pool-a",
                        kind: .semantic,
                        routeTarget: .lane,
                        autoTriaged: true,
                        fixSuggestion: "apply suggested lane patch and rerun semantic lane checks before commit"
                    )
                ]
            ),
            MergebackRunSnapshot(
                runID: "run-pass-3",
                laneID: "lane-structural",
                poolID: "pool-b",
                precheckPassed: true,
                mergeSucceeded: true,
                verifyPassed: true,
                committed: true,
                stablePointID: "stable-lane-structural",
                rollbackAnchorID: "rollback-lane-structural",
                qualityGateBlockedOnFailure: true,
                rolledBackToStablePoint: false,
                conflicts: [
                    conflict(
                        id: "conflict-structural-1",
                        laneID: "lane-structural",
                        poolID: "pool-b",
                        kind: .structural,
                        routeTarget: .pool,
                        autoTriaged: true,
                        fixSuggestion: "route structural conflict back to pool integration and regenerate merge plan"
                    )
                ]
            ),
            MergebackRunSnapshot(
                runID: "run-fail-rollback",
                laneID: "lane-verify-fail",
                poolID: "pool-b",
                precheckPassed: true,
                mergeSucceeded: true,
                verifyPassed: false,
                committed: false,
                stablePointID: "stable-lane-verify-fail",
                rollbackAnchorID: "rollback-lane-verify-fail",
                qualityGateBlockedOnFailure: true,
                rolledBackToStablePoint: true,
                conflicts: []
            )
        ]
    }

    private func conflict(
        id: String,
        laneID: String,
        poolID: String,
        kind: AssemblyConflictKind,
        routeTarget: AssemblyConflictRoute,
        autoTriaged: Bool,
        fixSuggestion: String
    ) -> MergebackConflictTriageRecord {
        MergebackConflictTriageRecord(
            id: id,
            laneID: laneID,
            poolID: poolID,
            kind: kind,
            routeTarget: routeTarget,
            autoTriaged: autoTriaged,
            fixSuggestion: fixSuggestion
        )
    }
}

private struct XTW311MergebackCapture: Codable {
    let schemaVersion: String
    let sampleWindow: String
    let mergebackQualityReport: MergebackQualityGateReport
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sampleWindow = "sample_window"
        case mergebackQualityReport = "mergeback_quality_report"
        case sourceRefs = "source_refs"
    }
}
