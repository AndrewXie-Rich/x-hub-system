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

    @MainActor
    @Test
    func orchestratorProductionPathBuildsAndExportsMergebackQualityReport() throws {
        let supervisor = SupervisorModel()
        let orchestrator = SupervisorOrchestrator(runtimeHost: supervisor)
        let splitPlanID = "split-xt-w3-11-production-pass"
        let taskIDs = [
            "lane-clean": UUID(),
            "lane-semantic": UUID(),
            "lane-structural": UUID(),
            "lane-verify-fail": UUID()
        ]
        let materialization = MaterializationResult(
            splitPlanID: splitPlanID,
            rootProjectID: UUID(),
            lanes: [
                materializedLane(laneID: "lane-clean", taskID: taskIDs["lane-clean"]!, poolID: "pool-a"),
                materializedLane(laneID: "lane-semantic", taskID: taskIDs["lane-semantic"]!, poolID: "pool-a"),
                materializedLane(laneID: "lane-structural", taskID: taskIDs["lane-structural"]!, poolID: "pool-b"),
                materializedLane(
                    laneID: "lane-verify-fail",
                    taskID: taskIDs["lane-verify-fail"]!,
                    poolID: "pool-b",
                    metadata: [
                        "merge_succeeded": "true",
                        "verify_passed": "false",
                        "mergeback_committed": "false",
                        "quality_gate_block_on_failure": "true",
                        "rolled_back_to_stable_point": "true",
                        "stable_point_id": "stable-lane-verify-fail",
                        "rollback_anchor_id": "rollback-lane-verify-fail"
                    ]
                )
            ],
            lineageOperations: [],
            auditEvents: [],
            hardSplitWithoutChildProject: 0,
            softSplitLineagePollution: 0
        )
        let promptCompilation = promptCompilationResult(
            laneIDs: ["lane-clean", "lane-semantic", "lane-structural", "lane-verify-fail"]
        )
        let taskStates = makeTaskStates(
            materialization.lanes,
            projectID: UUID(),
            now: Date(timeIntervalSince1970: 1_730_300_300)
        )
        let laneStates = makeLaneStates(taskIDs: taskIDs)
        let gateReport = mergebackGateReport(
            splitPlanID: splitPlanID,
            rollbackPoints: [
                rollbackPoint(laneID: "lane-clean", taskID: taskIDs["lane-clean"]!, stablePointID: "stable-lane-clean"),
                rollbackPoint(laneID: "lane-semantic", taskID: taskIDs["lane-semantic"]!, stablePointID: "stable-lane-semantic"),
                rollbackPoint(laneID: "lane-structural", taskID: taskIDs["lane-structural"]!, stablePointID: "stable-lane-structural"),
                rollbackPoint(laneID: "lane-verify-fail", taskID: taskIDs["lane-verify-fail"]!, stablePointID: "stable-lane-verify-fail")
            ]
        )
        let report = orchestrator.evaluateMergebackQuality(
            gateReport: gateReport,
            materialization: materialization,
            promptCompilationResult: promptCompilation,
            taskStates: taskStates,
            laneStates: laneStates,
            incidents: [],
            conflicts: [
                AssemblyConflict(
                    id: "conflict-semantic-1",
                    laneID: "lane-semantic",
                    poolID: "pool-a",
                    kind: .semantic,
                    routeTarget: .lane,
                    crossPool: false,
                    reopened: false
                ),
                AssemblyConflict(
                    id: "conflict-structural-1",
                    laneID: "lane-structural",
                    poolID: "pool-b",
                    kind: .structural,
                    routeTarget: .pool,
                    crossPool: true,
                    reopened: false
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_300_300)
        )

        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let reportURL = workspace.appendingPathComponent("xt_w3_11_mergeback_quality_report.v2.json")
        try orchestrator.exportMergebackQualityReport(report, to: reportURL)

        let data = try Data(contentsOf: reportURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(report.pass)
        #expect(report.sampleCount == 4)
        #expect(report.mergebackFirstPassRate == 0.75)
        #expect(report.laneRollbackPointCoverage == 1.0)
        #expect(report.conflictAutoTriageRate == 1.0)
        #expect(report.mergeFailureAutoRollbackCoverage == 1.0)
        #expect(report.runAudits.contains(where: {
            $0.laneID == "lane-verify-fail"
                && $0.rollbackAnchorID == "rollback-lane-verify-fail"
                && $0.rolledBackToStablePoint
        }))
        #expect(report.runAudits.flatMap(\.conflicts).contains(where: {
            $0.laneID == "lane-structural"
                && $0.fixSuggestion.contains("cross-pool contract drift check")
        }))
        #expect((json?["schema_version"] as? String) == "xterminal.xt_w3_11.mergeback_quality_gate.v1")
        #expect((json?["sample_count"] as? Int) == 4)
    }

    @MainActor
    @Test
    func orchestratorProductionPathFailsClosedWhenContractsRollbackOrAutoTriageAreMissing() {
        let supervisor = SupervisorModel()
        let orchestrator = SupervisorOrchestrator(runtimeHost: supervisor)
        let taskID = UUID()
        let materialization = MaterializationResult(
            splitPlanID: "split-xt-w3-11-production-fail",
            rootProjectID: UUID(),
            lanes: [
                materializedLane(
                    laneID: "lane-fail",
                    taskID: taskID,
                    poolID: "pool-a",
                    status: .failed,
                    metadata: [
                        "merge_succeeded": "false",
                        "verify_passed": "false",
                        "mergeback_committed": "false",
                        "quality_gate_block_on_failure": "false"
                    ]
                )
            ],
            lineageOperations: [],
            auditEvents: [],
            hardSplitWithoutChildProject: 0,
            softSplitLineagePollution: 0
        )
        let taskStates = makeTaskStates(
            materialization.lanes,
            projectID: UUID(),
            now: Date(timeIntervalSince1970: 1_730_300_400)
        )
        let laneStates = [
            "lane-fail": laneState(
                laneID: "lane-fail",
                taskID: taskID,
                status: .failed,
                blockedReason: .runtimeError,
                updatedAtMs: 1_730_300_400_000
            )
        ]
        let report = orchestrator.evaluateMergebackQuality(
            gateReport: mergebackGateReport(splitPlanID: "split-xt-w3-11-production-fail", rollbackPoints: []),
            materialization: materialization,
            promptCompilationResult: promptCompilationResult(laneIDs: []),
            taskStates: taskStates,
            laneStates: laneStates,
            incidents: [],
            conflicts: [
                AssemblyConflict(
                    id: "conflict-fail-1",
                    laneID: "lane-fail",
                    poolID: "pool-a",
                    kind: .semantic,
                    routeTarget: .pool,
                    crossPool: false,
                    reopened: true
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_300_400)
        )

        #expect(report.pass == false)
        #expect(report.minimalGaps.contains("mergeback_first_pass_rate_below_0_70"))
        #expect(report.minimalGaps.contains("lane_rollback_point_coverage_incomplete"))
        #expect(report.minimalGaps.contains("conflict_auto_triage_rate_incomplete"))
        #expect(report.minimalGaps.contains("quality_gate_did_not_block_and_rollback_merge_failure"))
        #expect(report.runAudits.first?.precheckPassed == false)
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

    private func materializedLane(
        laneID: String,
        taskID: UUID,
        poolID: String,
        status: DecomposedTaskStatus = .completed,
        metadata: [String: String] = [:]
    ) -> MaterializedLane {
        let mergedMetadata = [
            "lane_id": laneID,
            "pool_id": poolID
        ].merging(metadata) { _, new in new }
        let task = DecomposedTask(
            id: taskID,
            description: "mergeback \(laneID)",
            status: status,
            metadata: mergedMetadata
        )
        let plan = SupervisorLanePlan(
            laneID: laneID,
            goal: "mergeback \(laneID)",
            dependsOn: [],
            riskTier: .medium,
            budgetClass: .balanced,
            createChildProject: false,
            expectedArtifacts: ["patch"],
            dodChecklist: ["verify"],
            source: .inferred,
            metadata: ["pool_id": poolID],
            task: task
        )
        return MaterializedLane(
            plan: plan,
            mode: .softSplit,
            task: task,
            targetProject: nil,
            lineageOperations: [],
            decisionReasons: [],
            explain: "test"
        )
    }

    private func promptCompilationResult(laneIDs: [String]) -> PromptCompilationResult {
        PromptCompilationResult(
            splitPlanId: UUID(),
            expectedLaneCount: laneIDs.count,
            contracts: laneIDs.map { laneID in
                PromptContract(
                    laneId: laneID,
                    goal: "goal \(laneID)",
                    boundaries: [],
                    inputs: [],
                    outputs: [],
                    dodChecklist: ["verify"],
                    riskBoundaries: [],
                    rollbackPoints: ["restore \(laneID)"],
                    refusalSemantics: ["fail_closed"],
                    compiledPrompt: "prompt \(laneID)",
                    tokenBudget: 2_048
                )
            },
            lintResult: PromptLintResult(issues: []),
            status: .ready,
            compiledAt: Date(timeIntervalSince1970: 1_730_300_000)
        )
    }

    private func makeTaskStates(
        _ lanes: [MaterializedLane],
        projectID: UUID,
        now: Date
    ) -> [UUID: TaskExecutionState] {
        Dictionary(uniqueKeysWithValues: lanes.map { lane in
            let currentStatus = lane.task.status
            let progress = currentStatus == .completed ? 1.0 : 0.5
            return (
                lane.task.id,
                TaskExecutionState(
                    task: lane.task,
                    projectId: projectID,
                    startedAt: now,
                    lastUpdateAt: now,
                    progress: progress,
                    currentStatus: currentStatus,
                    attempts: 1,
                    errors: [],
                    logs: []
                )
            )
        })
    }

    private func makeLaneStates(taskIDs: [String: UUID]) -> [String: LaneRuntimeState] {
        [
            "lane-clean": laneState(
                laneID: "lane-clean",
                taskID: taskIDs["lane-clean"]!,
                status: .completed,
                updatedAtMs: 1_730_300_300_000
            ),
            "lane-semantic": laneState(
                laneID: "lane-semantic",
                taskID: taskIDs["lane-semantic"]!,
                status: .completed,
                updatedAtMs: 1_730_300_301_000
            ),
            "lane-structural": laneState(
                laneID: "lane-structural",
                taskID: taskIDs["lane-structural"]!,
                status: .completed,
                updatedAtMs: 1_730_300_302_000
            ),
            "lane-verify-fail": laneState(
                laneID: "lane-verify-fail",
                taskID: taskIDs["lane-verify-fail"]!,
                status: .failed,
                blockedReason: .runtimeError,
                updatedAtMs: 1_730_300_303_000
            )
        ]
    }

    private func laneState(
        laneID: String,
        taskID: UUID,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason? = nil,
        updatedAtMs: Int64
    ) -> LaneRuntimeState {
        var state = LaneRuntimeState(
            laneID: laneID,
            taskId: taskID,
            projectId: UUID(),
            agentProfile: "test-agent",
            status: status,
            blockedReason: blockedReason,
            nextActionRecommendation: "continue"
        )
        state.heartbeatSeq = 4
        state.lastHeartbeatAtMs = updatedAtMs
        state.updatedAtMs = updatedAtMs
        state.oldestWaitMs = status == .blocked || status == .failed ? updatedAtMs - 500 : 0
        state.lastNote = blockedReason?.rawValue
        return state
    }

    private func mergebackGateReport(
        splitPlanID: String,
        rollbackPoints: [LaneMergebackRollbackPoint]
    ) -> LaneMergebackGateReport {
        LaneMergebackGateReport(
            schemaVersion: "xterminal.mergeback_gate.v1",
            generatedAtMs: 1_730_300_300_000,
            splitPlanID: splitPlanID,
            pass: true,
            assertions: [
                LaneMergebackGateAssertion(
                    id: "mergeback_rollback_points_ready",
                    ok: !rollbackPoints.isEmpty,
                    detail: "rollback_points=\(rollbackPoints.count)"
                )
            ],
            rollbackPoints: rollbackPoints,
            kpi: LaneMergebackKPISnapshot(
                laneStallDetectP95Ms: 0,
                supervisorActionLatencyP95Ms: 0,
                highRiskLaneWithoutGrant: 0,
                unauditedAutoResolution: 0,
                mergebackRollbackReadyRate: rollbackPoints.isEmpty ? 0 : 1.0
            )
        )
    }

    private func rollbackPoint(
        laneID: String,
        taskID: UUID,
        stablePointID: String
    ) -> LaneMergebackRollbackPoint {
        LaneMergebackRollbackPoint(
            laneID: laneID,
            taskID: taskID,
            projectID: UUID(),
            status: .completed,
            heartbeatSeq: 4,
            stablePointID: stablePointID,
            assignmentSnapshotRef: "assign:\(laneID)",
            incidentPolicyVersion: "incident_arbiter.skill_takeover.v1",
            mergePolicyVersion: "mergeback_gate.v1",
            rollbackHints: ["restore \(laneID)"],
            capturedAtMs: 1_730_300_300_000
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
