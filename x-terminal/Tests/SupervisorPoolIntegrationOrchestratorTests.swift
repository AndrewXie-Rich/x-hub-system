import Foundation
import Testing
@testable import XTerminal

struct SupervisorPoolIntegrationOrchestratorTests {

    @MainActor
    @Test
    func poolFailureBlocksGlobalExecution() {
        let orchestrator = PoolIntegrationOrchestrator()
        let report = orchestrator.orchestrate(
            splitPlanID: "split-pool-fail",
            poolGateReport: makePoolGateReport(pass: false, rollbackReadyRate: 0, rollbackPoint: ""),
            globalAssertions: [
                PoolIntegrationGlobalAssertion(id: "global_merge_quality_gate", ok: true, detail: "should not run")
            ],
            now: Date(timeIntervalSince1970: 1_730_100_000)
        )

        #expect(report.pass == false)
        #expect(report.poolLevelPass == false)
        #expect(report.globalLevelExecuted == false)
        #expect(report.failureAttributionReady == true)
        #expect(report.failureAttribution?.failureScope == "pool-level")
        #expect(report.failureAttribution?.repairSuggestions.isEmpty == false)
    }

    @MainActor
    @Test
    func globalFailureRollsBackToPoolStablePointAndExportsAttribution() throws {
        let orchestrator = PoolIntegrationOrchestrator()
        let report = orchestrator.orchestrate(
            splitPlanID: "split-global-fail",
            poolGateReport: makePoolGateReport(
                pass: true,
                rollbackReadyRate: 1.0,
                rollbackPoint: "stable-lane-2-hb8-1730000200"
            ),
            globalAssertions: [
                PoolIntegrationGlobalAssertion(
                    id: "failure_attribution_report_export",
                    ok: false,
                    detail: "failure attribution export missing repair suggestions"
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_100_100)
        )

        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reportURL = workspace.appendingPathComponent("xt_w3_18_failure_attribution_report.v1.json")
        try orchestrator.exportFailureAttribution(try #require(report.failureAttribution), to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(report.pass == false)
        #expect(report.poolLevelPass == true)
        #expect(report.globalLevelExecuted == true)
        #expect(report.rollbackConsistencyCheck == true)
        #expect(report.rollbackPoint == "stable-lane-2-hb8-1730000200")
        #expect(report.failureAttribution?.failureScope == "global-level")
        #expect((json?["schema_version"] as? String) == "xterminal.pool_integration_failure_attribution.v1")
        #expect((json?["rollback_point"] as? String) == "stable-lane-2-hb8-1730000200")
    }

    @MainActor
    @Test
    func poolAndGlobalPassProduceRunnableReport() {
        let orchestrator = PoolIntegrationOrchestrator()
        let report = orchestrator.orchestrate(
            splitPlanID: "split-pass",
            poolGateReport: makePoolGateReport(
                pass: true,
                rollbackReadyRate: 1.0,
                rollbackPoint: "stable-lane-3-hb6-1730000300"
            ),
            globalAssertions: [
                PoolIntegrationGlobalAssertion(id: "global_merge_quality_gate", ok: true, detail: "rollback ready"),
                PoolIntegrationGlobalAssertion(id: "failure_attribution_report_export", ok: true, detail: "export path ready")
            ],
            now: Date(timeIntervalSince1970: 1_730_100_200)
        )

        #expect(report.pass)
        #expect(report.poolLevelPass)
        #expect(report.globalLevelExecuted)
        #expect(report.globalLevelPass)
        #expect(report.rollbackConsistencyCheck)
        #expect(report.failureAttributionReady == false)
        #expect(report.failureAttribution == nil)
    }

    private func makePoolGateReport(
        pass: Bool,
        rollbackReadyRate: Double,
        rollbackPoint: String
    ) -> LaneMergebackGateReport {
        let assertions = [
            LaneMergebackGateAssertion(
                id: pass ? "mergeback_rollback_points_ready" : "mergeback_only_completed_lanes",
                ok: pass,
                detail: pass ? "rollback_points_ready" : "missing completed stable point"
            )
        ]

        let rollbackPoints = rollbackPoint.isEmpty ? [] : [
            LaneMergebackRollbackPoint(
                laneID: "lane-2",
                taskID: UUID(),
                projectID: UUID(),
                status: .completed,
                heartbeatSeq: 8,
                stablePointID: rollbackPoint,
                assignmentSnapshotRef: "assign:[lane-2->projectA]",
                incidentPolicyVersion: "incident_arbiter.skill_takeover.v1",
                mergePolicyVersion: "mergeback_gate.v1",
                rollbackHints: ["restore snapshot lane-2"],
                capturedAtMs: 1_730_000_400
            )
        ]

        return LaneMergebackGateReport(
            schemaVersion: "xterminal.mergeback_gate.v1",
            generatedAtMs: 1_730_000_400,
            splitPlanID: pass ? "split-mergeback-pass" : "split-mergeback-fail",
            pass: pass,
            assertions: assertions,
            rollbackPoints: rollbackPoints,
            kpi: LaneMergebackKPISnapshot(
                laneStallDetectP95Ms: 0,
                supervisorActionLatencyP95Ms: 900,
                highRiskLaneWithoutGrant: 0,
                unauditedAutoResolution: 0,
                mergebackRollbackReadyRate: rollbackReadyRate
            )
        )
    }
}
