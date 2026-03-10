import Foundation
import Testing
@testable import XTerminal

struct SupervisorDeliveryEconomicsSnapshotTests {

    @Test
    func economicsSnapshotReturnsInsufficientEvidenceWhenRealSamplesAreIncomplete() {
        let evaluator = DeliveryEconomicsEvaluator()
        let snapshot = evaluator.evaluate(
            samples: [
                DeliveryEconomicsSample(
                    sampleID: "actual-1",
                    kind: .actual,
                    sourceRefs: ["build/reports/xt_w3_18_s1_assembly_convergence_evidence.v1.json"],
                    realSample: true,
                    wallTimeSeconds: 8.12,
                    tokenCount: nil,
                    costUSD: nil,
                    mergeTaxRatio: 0.16
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_400_000)
        )

        #expect(snapshot.recommendation == .insufficientEvidence)
        #expect(snapshot.sampleSufficiency.sufficient == false)
        #expect(snapshot.sampleSufficiency.blockedByInsufficientEvidence)
        #expect(snapshot.sampleSufficiency.missingFields.contains("missing_real_baseline_sample"))
        #expect(snapshot.sampleSufficiency.missingFields.contains("missing_actual_token_count"))
        #expect(snapshot.sampleSufficiency.missingFields.contains("missing_actual_cost_usd"))
        #expect(snapshot.roiFieldsComplete == false)
    }

    @Test
    func economicsSnapshotRecommendsKeepWhenCompleteRealSamplesMeetThresholds() {
        let evaluator = DeliveryEconomicsEvaluator()
        let snapshot = evaluator.evaluate(
            samples: [
                DeliveryEconomicsSample(
                    sampleID: "baseline-1",
                    kind: .baseline,
                    sourceRefs: ["build/reports/baseline.json"],
                    realSample: true,
                    wallTimeSeconds: 20.0,
                    tokenCount: 100_000,
                    costUSD: 1.00,
                    mergeTaxRatio: 0.22
                ),
                DeliveryEconomicsSample(
                    sampleID: "actual-1",
                    kind: .actual,
                    sourceRefs: ["build/reports/actual.json"],
                    realSample: true,
                    wallTimeSeconds: 16.0,
                    tokenCount: 105_000,
                    costUSD: 1.10,
                    mergeTaxRatio: 0.27
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_400_100)
        )

        #expect(snapshot.sampleSufficiency.sufficient)
        #expect(snapshot.roiFieldsComplete)
        #expect(snapshot.recommendation == .recommendKeep)
        #expect(snapshot.baselineVsActual.delta.speedupRatio == 1.25)
        #expect(abs((snapshot.baselineVsActual.delta.costDeltaRatio ?? 0) - 0.10) < 0.0001)
        #expect(abs((snapshot.baselineVsActual.delta.mergeTaxDelta ?? 0) - 0.05) < 0.0001)
    }

    @Test
    func economicsSnapshotTreatsMeasuredZeroUsageAsCompleteEvidence() {
        let evaluator = DeliveryEconomicsEvaluator()
        let snapshot = evaluator.evaluate(
            samples: [
                DeliveryEconomicsSample(
                    sampleID: "baseline-zero",
                    kind: .baseline,
                    sourceRefs: ["build/reports/baseline_zero.json"],
                    realSample: true,
                    wallTimeSeconds: 20.0,
                    tokenCount: 0,
                    costUSD: 0,
                    mergeTaxRatio: 0.22
                ),
                DeliveryEconomicsSample(
                    sampleID: "actual-zero",
                    kind: .actual,
                    sourceRefs: ["build/reports/actual_zero.json"],
                    realSample: true,
                    wallTimeSeconds: 16.0,
                    tokenCount: 0,
                    costUSD: 0,
                    mergeTaxRatio: 0.27
                )
            ],
            now: Date(timeIntervalSince1970: 1_730_400_150)
        )

        #expect(snapshot.sampleSufficiency.sufficient)
        #expect(snapshot.roiFieldsComplete)
        #expect(snapshot.recommendation == .recommendKeep)
        #expect(snapshot.baselineVsActual.delta.tokenDeltaRatio == 0)
        #expect(snapshot.baselineVsActual.delta.costDeltaRatio == 0)
    }

    @Test
    func economicsSnapshotCanParseRealBuildDurationFromRuntimeLog() {
        let evaluator = DeliveryEconomicsEvaluator()
        let log = """
        Build complete! (8.12s)
        ◇ Test run started.
        """

        #expect(evaluator.parseBuildDurationSeconds(from: log) == 8.12)
    }

    @Test
    func economicsCaptureEmitsCoherentSameWorkloadWindows() throws {
        let artifacts = makeCaptureArtifacts(laneCount: 50, poolCount: 4)
        let conflicts = makeCaptureConflicts()
        let workloadID = "xt_w3_19_s1_delivery_economics_same_workload_control_vs_actual"
        let probeScope = "xt_w3_19_s1_real_sample_capture_v1"
        let iterations = 20_000

        let baselineWindow = measureAssemblyWindow(
            workloadID: workloadID,
            probeScope: probeScope,
            artifacts: artifacts,
            conflicts: conflicts,
            maxMergeChunk: 1,
            iterations: iterations,
            sampleID: "baseline_control_window"
        )
        let actualWindow = measureAssemblyWindow(
            workloadID: workloadID,
            probeScope: probeScope,
            artifacts: artifacts,
            conflicts: conflicts,
            maxMergeChunk: 6,
            iterations: iterations,
            sampleID: "actual_runtime_window"
        )

        #expect(baselineWindow.window.sameWorkload)
        #expect(actualWindow.window.sameWorkload)
        #expect(baselineWindow.window.sameProbeScope)
        #expect(actualWindow.window.sameProbeScope)
        #expect(baselineWindow.window.realSample)
        #expect(actualWindow.window.realSample)
        #expect(abs(baselineWindow.window.mergeTaxRatio - 0.98) < 0.0001)
        #expect(abs(actualWindow.window.mergeTaxRatio - 0.16) < 0.0001)
        #expect(baselineWindow.window.wallTimeSeconds > 0)
        #expect(actualWindow.window.wallTimeSeconds > 0)

        if ProcessInfo.processInfo.environment["XT_W3_19_S1_CAPTURE"] == "1" {
            let payload = DeliveryEconomicsRuntimeCapture(
                schemaVersion: "xterminal.xt_w3_19_s1.real_sample_runtime_capture.v1",
                workloadID: workloadID,
                probeScope: probeScope,
                sameWorkload: true,
                sameProbeScope: true,
                realSample: true,
                iterationsPerWindow: iterations,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/AssemblyConvergencePlanner.swift",
                    "x-terminal/Tests/SupervisorAssemblyConvergenceTests.swift",
                    "x-terminal/Tests/SupervisorDeliveryEconomicsSnapshotTests.swift"
                ],
                baselineControlWindow: baselineWindow.window,
                actualRuntimeWindow: actualWindow.window
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = try String(decoding: encoder.encode(payload), as: UTF8.self)
            print("XT_W3_19_S1_CAPTURE_JSON=\(json)")
        }
    }

    private func measureAssemblyWindow(
        workloadID: String,
        probeScope: String,
        artifacts: [AssemblyArtifact],
        conflicts: [AssemblyConflict],
        maxMergeChunk: Int,
        iterations: Int,
        sampleID: String
    ) -> DeliveryEconomicsRuntimeCaptureWindowEnvelope {
        let evaluator = AssemblyConvergenceEvaluator()
        let startedAt = Date()
        let startedAtMS = Int64((startedAt.timeIntervalSince1970 * 1000.0).rounded())
        let monotonicStart = ProcessInfo.processInfo.systemUptime

        var report: AssemblyConvergenceReport?
        for _ in 0..<iterations {
            report = evaluator.evaluate(
                artifacts: artifacts,
                conflicts: conflicts,
                maxMergeChunk: maxMergeChunk,
                now: startedAt
            )
        }

        let wallTimeSeconds = ProcessInfo.processInfo.systemUptime - monotonicStart
        let finishedAtMS = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let measuredReport = try! #require(report)

        return DeliveryEconomicsRuntimeCaptureWindowEnvelope(
            window: DeliveryEconomicsRuntimeCaptureWindow(
                sampleID: sampleID,
                workloadID: workloadID,
                probeScope: probeScope,
                sameWorkload: true,
                sameProbeScope: true,
                realSample: true,
                startedAtMS: startedAtMS,
                finishedAtMS: finishedAtMS,
                wallTimeSeconds: wallTimeSeconds,
                mergeTaxRatio: measuredReport.mergeTaxRatio,
                mergeChunkMax: measuredReport.mergeChunkMax,
                waveCount: measuredReport.waveCount,
                iterations: iterations,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/AssemblyConvergencePlanner.swift",
                    "x-terminal/Tests/SupervisorAssemblyConvergenceTests.swift"
                ]
            )
        )
    }

    private func makeCaptureArtifacts(laneCount: Int, poolCount: Int) -> [AssemblyArtifact] {
        let poolArtifacts = (0..<poolCount).map { index in
            let poolID = "pool-\(index + 1)"
            return AssemblyArtifact(
                artifactID: "artifact-\(poolID)",
                scope: .pool,
                poolID: poolID,
                laneID: nil,
                schemaHash: "schema-\(poolID)-v1",
                lineageRef: "lineage://\(poolID)",
                contractInterfaceID: "dispatch-manifest",
                contractHash: "dispatch-contract-v1",
                stablePointID: "pool-stable-\(poolID)",
                rollbackAnchorID: "pool-rollback-\(poolID)"
            )
        }

        let laneArtifacts = (0..<laneCount).map { index in
            let laneNumber = index + 1
            let poolID = "pool-\((index % poolCount) + 1)"
            let laneID = String(format: "lane-%03d", laneNumber)
            return AssemblyArtifact(
                artifactID: "artifact-\(laneID)",
                scope: .lane,
                poolID: poolID,
                laneID: laneID,
                schemaHash: "schema-\(laneID)-v1",
                lineageRef: "lineage://\(poolID)/\(laneID)",
                contractInterfaceID: "dispatch-manifest",
                contractHash: "dispatch-contract-v1",
                stablePointID: "stable-\(laneID)",
                rollbackAnchorID: "rollback-\(laneID)"
            )
        }

        return poolArtifacts + laneArtifacts
    }

    private func makeCaptureConflicts() -> [AssemblyConflict] {
        [
            AssemblyConflict(
                id: "semantic-1",
                laneID: "lane-001",
                poolID: "pool-1",
                kind: .semantic,
                routeTarget: .lane,
                crossPool: false,
                reopened: false
            ),
            AssemblyConflict(
                id: "structural-1",
                laneID: "lane-017",
                poolID: "pool-2",
                kind: .structural,
                routeTarget: .pool,
                crossPool: true,
                reopened: true
            ),
            AssemblyConflict(
                id: "structural-2",
                laneID: "lane-033",
                poolID: "pool-3",
                kind: .structural,
                routeTarget: .pool,
                crossPool: true,
                reopened: true
            )
        ]
    }
}

private struct DeliveryEconomicsRuntimeCapture: Codable {
    let schemaVersion: String
    let workloadID: String
    let probeScope: String
    let sameWorkload: Bool
    let sameProbeScope: Bool
    let realSample: Bool
    let iterationsPerWindow: Int
    let sourceRefs: [String]
    let baselineControlWindow: DeliveryEconomicsRuntimeCaptureWindow
    let actualRuntimeWindow: DeliveryEconomicsRuntimeCaptureWindow

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case workloadID = "workload_id"
        case probeScope = "probe_scope"
        case sameWorkload = "same_workload"
        case sameProbeScope = "same_probe_scope"
        case realSample = "real_sample"
        case iterationsPerWindow = "iterations_per_window"
        case sourceRefs = "source_refs"
        case baselineControlWindow = "baseline_control_window"
        case actualRuntimeWindow = "actual_runtime_window"
    }
}

private struct DeliveryEconomicsRuntimeCaptureWindowEnvelope {
    let window: DeliveryEconomicsRuntimeCaptureWindow
}

private struct DeliveryEconomicsRuntimeCaptureWindow: Codable {
    let sampleID: String
    let workloadID: String
    let probeScope: String
    let sameWorkload: Bool
    let sameProbeScope: Bool
    let realSample: Bool
    let startedAtMS: Int64
    let finishedAtMS: Int64
    let wallTimeSeconds: Double
    let mergeTaxRatio: Double
    let mergeChunkMax: Int
    let waveCount: Int
    let iterations: Int
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case sampleID = "sample_id"
        case workloadID = "workload_id"
        case probeScope = "probe_scope"
        case sameWorkload = "same_workload"
        case sameProbeScope = "same_probe_scope"
        case realSample = "real_sample"
        case startedAtMS = "started_at_ms"
        case finishedAtMS = "finished_at_ms"
        case wallTimeSeconds = "wall_time_seconds"
        case mergeTaxRatio = "merge_tax_ratio"
        case mergeChunkMax = "merge_chunk_max"
        case waveCount = "wave_count"
        case iterations
        case sourceRefs = "source_refs"
    }
}
