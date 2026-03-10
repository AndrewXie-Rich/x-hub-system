import Foundation

enum AssemblyArtifactScope: String, Codable, Equatable {
    case lane
    case pool
}

struct AssemblyArtifact: Codable, Equatable, Identifiable {
    let artifactID: String
    let scope: AssemblyArtifactScope
    let poolID: String
    let laneID: String?
    let schemaHash: String
    let lineageRef: String
    let contractInterfaceID: String
    let contractHash: String
    let stablePointID: String
    let rollbackAnchorID: String

    var id: String { artifactID }

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case scope
        case poolID = "pool_id"
        case laneID = "lane_id"
        case schemaHash = "schema_hash"
        case lineageRef = "lineage_ref"
        case contractInterfaceID = "contract_interface_id"
        case contractHash = "contract_hash"
        case stablePointID = "stable_point_id"
        case rollbackAnchorID = "rollback_anchor_id"
    }
}

enum AssemblyConflictKind: String, Codable, Equatable {
    case semantic
    case structural
}

enum AssemblyConflictRoute: String, Codable, Equatable {
    case lane
    case pool
}

struct AssemblyConflict: Codable, Equatable, Identifiable {
    let id: String
    let laneID: String
    let poolID: String
    let kind: AssemblyConflictKind
    let routeTarget: AssemblyConflictRoute
    let crossPool: Bool
    let reopened: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case laneID = "lane_id"
        case poolID = "pool_id"
        case kind
        case routeTarget = "route_target"
        case crossPool = "cross_pool"
        case reopened
    }
}

struct AssemblyWave: Codable, Equatable, Identifiable {
    let waveIndex: Int
    let laneIDs: [String]
    let poolIDs: [String]
    let mergeChunk: Int
    let waveStablePointID: String
    let rollbackAnchorID: String

    var id: String { "wave-\(waveIndex)" }

    enum CodingKeys: String, CodingKey {
        case waveIndex = "wave_index"
        case laneIDs = "lane_ids"
        case poolIDs = "pool_ids"
        case mergeChunk = "merge_chunk"
        case waveStablePointID = "stable_point_id"
        case rollbackAnchorID = "rollback_anchor_id"
    }
}

struct ContractFreezeGateResult: Codable, Equatable {
    let result: String
    let driftDetected: Bool
    let blockedInterfaceIDs: [String]
    let blockedLaneIDs: [String]

    enum CodingKeys: String, CodingKey {
        case result
        case driftDetected = "drift_detected"
        case blockedInterfaceIDs = "blocked_interface_ids"
        case blockedLaneIDs = "blocked_lane_ids"
    }
}

struct AssemblyConflictRoutingSummary: Codable, Equatable {
    let semanticConflictCount: Int
    let structuralConflictCount: Int
    let semanticConflictRouteBackToLane: Bool
    let structuralConflictRouteBackToPool: Bool

    enum CodingKeys: String, CodingKey {
        case semanticConflictCount = "semantic_conflict_count"
        case structuralConflictCount = "structural_conflict_count"
        case semanticConflictRouteBackToLane = "semantic_conflict_route_back_to_lane"
        case structuralConflictRouteBackToPool = "structural_conflict_route_back_to_pool"
    }
}

struct AssemblyConvergenceReport: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let laneArtifactCount: Int
    let poolArtifactCount: Int
    let waveCount: Int
    let mergeChunkMax: Int
    let mergeTaxRatio: Double
    let crossPoolConflictReopenRate: Double
    let schemaHashCoverage: Double
    let lineageReferenceCoverage: Double
    let stablePointIDCoverage: Double
    let rollbackAnchorCoverage: Double
    let contractFreezeGateResult: ContractFreezeGateResult
    let conflictRouting: AssemblyConflictRoutingSummary
    let waves: [AssemblyWave]
    let minimalGaps: [String]

    var pass: Bool { minimalGaps.isEmpty }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case laneArtifactCount = "lane_artifact_count"
        case poolArtifactCount = "pool_artifact_count"
        case waveCount = "wave_count"
        case mergeChunkMax = "merge_chunk_max"
        case mergeTaxRatio = "merge_tax_ratio"
        case crossPoolConflictReopenRate = "cross_pool_conflict_reopen_rate"
        case schemaHashCoverage = "schema_hash_coverage"
        case lineageReferenceCoverage = "lineage_reference_coverage"
        case stablePointIDCoverage = "stable_point_id_coverage"
        case rollbackAnchorCoverage = "rollback_anchor_coverage"
        case contractFreezeGateResult = "contract_freeze_gate_result"
        case conflictRouting = "conflict_routing"
        case waves
        case minimalGaps = "minimal_gaps"
    }
}

/// XT-W3-18-S1: converge multi-pool assembly in bounded merge waves.
final class AssemblyWavePlanner {
    func plan(artifacts: [AssemblyArtifact], maxMergeChunk: Int = 6) -> [AssemblyWave] {
        let laneArtifacts = artifacts
            .filter { $0.scope == .lane }
            .sorted { lhs, rhs in
                if lhs.poolID != rhs.poolID { return lhs.poolID < rhs.poolID }
                return (lhs.laneID ?? lhs.artifactID) < (rhs.laneID ?? rhs.artifactID)
            }
        guard maxMergeChunk > 0 else { return [] }

        var waves: [AssemblyWave] = []
        var start = 0
        var waveIndex = 1
        while start < laneArtifacts.count {
            let end = min(start + maxMergeChunk, laneArtifacts.count)
            let chunk = Array(laneArtifacts[start..<end])
            let laneIDs = chunk.compactMap(\.laneID)
            let poolIDs = Array(Set(chunk.map(\.poolID))).sorted()
            waves.append(
                AssemblyWave(
                    waveIndex: waveIndex,
                    laneIDs: laneIDs,
                    poolIDs: poolIDs,
                    mergeChunk: laneIDs.count,
                    waveStablePointID: "assembly-wave-\(waveIndex)-stable",
                    rollbackAnchorID: "assembly-wave-\(waveIndex)-rollback"
                )
            )
            waveIndex += 1
            start = end
        }
        return waves
    }
}

final class ContractFreezeGate {
    func evaluate(artifacts: [AssemblyArtifact]) -> ContractFreezeGateResult {
        var blockedInterfaceIDs: [String] = []
        var blockedLaneIDs: [String] = []

        let grouped = Dictionary(grouping: artifacts, by: \.contractInterfaceID)
        for (interfaceID, members) in grouped {
            let hashes = Set(members.map(\.contractHash))
            if hashes.count > 1 {
                blockedInterfaceIDs.append(interfaceID)
                blockedLaneIDs.append(contentsOf: members.compactMap(\.laneID))
            }
        }

        blockedInterfaceIDs.sort()
        blockedLaneIDs = Array(Set(blockedLaneIDs)).sorted()
        return ContractFreezeGateResult(
            result: blockedInterfaceIDs.isEmpty ? "pass" : "blocked",
            driftDetected: !blockedInterfaceIDs.isEmpty,
            blockedInterfaceIDs: blockedInterfaceIDs,
            blockedLaneIDs: blockedLaneIDs
        )
    }
}

final class AssemblyConvergenceEvaluator {
    private let wavePlanner = AssemblyWavePlanner()
    private let freezeGate = ContractFreezeGate()
    private let schemaVersion = "xterminal.assembly_convergence_report.v1"

    func evaluate(
        artifacts: [AssemblyArtifact],
        conflicts: [AssemblyConflict],
        maxMergeChunk: Int = 6,
        now: Date = Date()
    ) -> AssemblyConvergenceReport {
        let laneArtifacts = artifacts.filter { $0.scope == .lane }
        let poolArtifacts = artifacts.filter { $0.scope == .pool }
        let waves = wavePlanner.plan(artifacts: artifacts, maxMergeChunk: maxMergeChunk)
        let contractResult = freezeGate.evaluate(artifacts: artifacts)

        let schemaHashCoverage = coverage(of: artifacts) { !$0.schemaHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let lineageReferenceCoverage = coverage(of: artifacts) { !$0.lineageRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let stablePointIDCoverage = coverage(of: laneArtifacts) { !$0.stablePointID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let rollbackAnchorCoverage = coverage(of: laneArtifacts) { !$0.rollbackAnchorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let mergeChunkMax = waves.map(\.mergeChunk).max() ?? 0
        let mergeTaxRatio = laneArtifacts.isEmpty ? 0 : Double(max(0, waves.count - 1)) / Double(laneArtifacts.count)
        let reopenedCrossPoolConflicts = conflicts.filter { $0.kind == .structural && $0.crossPool && $0.reopened }.count
        let crossPoolConflictReopenRate = laneArtifacts.isEmpty ? 0 : Double(reopenedCrossPoolConflicts) / Double(laneArtifacts.count)

        let semanticConflicts = conflicts.filter { $0.kind == .semantic }
        let structuralConflicts = conflicts.filter { $0.kind == .structural }
        let routing = AssemblyConflictRoutingSummary(
            semanticConflictCount: semanticConflicts.count,
            structuralConflictCount: structuralConflicts.count,
            semanticConflictRouteBackToLane: semanticConflicts.allSatisfy { $0.routeTarget == .lane },
            structuralConflictRouteBackToPool: structuralConflicts.allSatisfy { $0.routeTarget == .pool }
        )

        var minimalGaps: [String] = []
        if schemaHashCoverage < 1.0 { minimalGaps.append("schema_hash_coverage_incomplete") }
        if lineageReferenceCoverage < 1.0 { minimalGaps.append("lineage_reference_coverage_incomplete") }
        if stablePointIDCoverage < 1.0 { minimalGaps.append("stable_point_id_coverage_incomplete") }
        if rollbackAnchorCoverage < 1.0 { minimalGaps.append("rollback_anchor_coverage_incomplete") }
        if mergeChunkMax > maxMergeChunk { minimalGaps.append("merge_chunk_exceeds_\(maxMergeChunk)") }
        if mergeTaxRatio > 0.30 { minimalGaps.append("merge_tax_ratio_exceeds_0_30") }
        if crossPoolConflictReopenRate > 0.08 { minimalGaps.append("cross_pool_conflict_reopen_rate_exceeds_0_08") }
        if contractResult.driftDetected { minimalGaps.append("contract_hash_drift_detected") }
        if !routing.semanticConflictRouteBackToLane { minimalGaps.append("semantic_conflict_not_routed_back_to_lane") }
        if !routing.structuralConflictRouteBackToPool { minimalGaps.append("structural_conflict_not_routed_back_to_pool") }

        return AssemblyConvergenceReport(
            schemaVersion: schemaVersion,
            generatedAtMs: Int64((now.timeIntervalSince1970 * 1000.0).rounded()),
            laneArtifactCount: laneArtifacts.count,
            poolArtifactCount: poolArtifacts.count,
            waveCount: waves.count,
            mergeChunkMax: mergeChunkMax,
            mergeTaxRatio: mergeTaxRatio,
            crossPoolConflictReopenRate: crossPoolConflictReopenRate,
            schemaHashCoverage: schemaHashCoverage,
            lineageReferenceCoverage: lineageReferenceCoverage,
            stablePointIDCoverage: stablePointIDCoverage,
            rollbackAnchorCoverage: rollbackAnchorCoverage,
            contractFreezeGateResult: contractResult,
            conflictRouting: routing,
            waves: waves,
            minimalGaps: minimalGaps
        )
    }

    private func coverage<T>(of values: [T], predicate: (T) -> Bool) -> Double {
        guard !values.isEmpty else { return 0 }
        let covered = values.filter(predicate).count
        return Double(covered) / Double(values.count)
    }
}
