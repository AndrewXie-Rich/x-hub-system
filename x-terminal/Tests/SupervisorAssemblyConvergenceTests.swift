import Foundation
import Testing
@testable import XTerminal

struct SupervisorAssemblyConvergenceTests {

    @Test
    func assemblyConvergencePassesAtScaleAndRoutesConflicts() {
        let evaluator = AssemblyConvergenceEvaluator()
        let artifacts = makeArtifacts(laneCount: 50, poolCount: 4)
        let conflicts = [
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

        let report = evaluator.evaluate(
            artifacts: artifacts,
            conflicts: conflicts,
            maxMergeChunk: 6,
            now: Date(timeIntervalSince1970: 1_730_200_000)
        )

        #expect(report.pass)
        #expect(report.laneArtifactCount == 50)
        #expect(report.poolArtifactCount == 4)
        #expect(report.waveCount == 9)
        #expect(report.mergeChunkMax == 6)
        #expect(report.mergeTaxRatio <= 0.30)
        #expect(report.crossPoolConflictReopenRate <= 0.08)
        #expect(report.stablePointIDCoverage == 1.0)
        #expect(report.rollbackAnchorCoverage == 1.0)
        #expect(report.schemaHashCoverage == 1.0)
        #expect(report.lineageReferenceCoverage == 1.0)
        #expect(report.contractFreezeGateResult.result == "pass")
        #expect(report.conflictRouting.semanticConflictRouteBackToLane)
        #expect(report.conflictRouting.structuralConflictRouteBackToPool)
    }

    @Test
    func contractFreezeGateBlocksHashDrift() {
        let evaluator = AssemblyConvergenceEvaluator()
        var artifacts = makeArtifacts(laneCount: 12, poolCount: 2)
        artifacts[3] = AssemblyArtifact(
            artifactID: artifacts[3].artifactID,
            scope: artifacts[3].scope,
            poolID: artifacts[3].poolID,
            laneID: artifacts[3].laneID,
            schemaHash: artifacts[3].schemaHash,
            lineageRef: artifacts[3].lineageRef,
            contractInterfaceID: artifacts[3].contractInterfaceID,
            contractHash: "dispatch-contract-drifted",
            stablePointID: artifacts[3].stablePointID,
            rollbackAnchorID: artifacts[3].rollbackAnchorID
        )

        let report = evaluator.evaluate(
            artifacts: artifacts,
            conflicts: [],
            maxMergeChunk: 6,
            now: Date(timeIntervalSince1970: 1_730_200_100)
        )

        #expect(report.pass == false)
        #expect(report.contractFreezeGateResult.result == "blocked")
        #expect(report.contractFreezeGateResult.driftDetected)
        #expect(report.minimalGaps.contains("contract_hash_drift_detected"))
    }

    @Test
    func missingStablePointOrRollbackAnchorFailsClosed() {
        let evaluator = AssemblyConvergenceEvaluator()
        var artifacts = makeArtifacts(laneCount: 8, poolCount: 2)
        artifacts[2] = AssemblyArtifact(
            artifactID: artifacts[2].artifactID,
            scope: artifacts[2].scope,
            poolID: artifacts[2].poolID,
            laneID: artifacts[2].laneID,
            schemaHash: artifacts[2].schemaHash,
            lineageRef: artifacts[2].lineageRef,
            contractInterfaceID: artifacts[2].contractInterfaceID,
            contractHash: artifacts[2].contractHash,
            stablePointID: "",
            rollbackAnchorID: artifacts[2].rollbackAnchorID
        )
        artifacts[3] = AssemblyArtifact(
            artifactID: artifacts[3].artifactID,
            scope: artifacts[3].scope,
            poolID: artifacts[3].poolID,
            laneID: artifacts[3].laneID,
            schemaHash: artifacts[3].schemaHash,
            lineageRef: artifacts[3].lineageRef,
            contractInterfaceID: artifacts[3].contractInterfaceID,
            contractHash: artifacts[3].contractHash,
            stablePointID: artifacts[3].stablePointID,
            rollbackAnchorID: ""
        )

        let report = evaluator.evaluate(
            artifacts: artifacts,
            conflicts: [],
            maxMergeChunk: 6,
            now: Date(timeIntervalSince1970: 1_730_200_200)
        )

        #expect(report.pass == false)
        #expect(report.stablePointIDCoverage < 1.0)
        #expect(report.rollbackAnchorCoverage < 1.0)
        #expect(report.minimalGaps.contains("stable_point_id_coverage_incomplete"))
        #expect(report.minimalGaps.contains("rollback_anchor_coverage_incomplete"))
    }

    private func makeArtifacts(laneCount: Int, poolCount: Int) -> [AssemblyArtifact] {
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
}
