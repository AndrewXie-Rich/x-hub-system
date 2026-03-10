import Foundation

enum DirectedResumeScope: String, Codable, Equatable {
    case continueCurrentTaskOnly = "continue_current_task_only"
}

struct DirectedUnblockBaton: Codable, Equatable, Identifiable {
    var id: String { edgeID }

    let schemaVersion: String
    let projectID: String
    let edgeID: String
    let blockedLane: String
    let resolvedBy: String
    let resolvedFact: String
    let resumeScope: DirectedResumeScope
    let deadlineHintUTC: String
    let mustNotDo: [String]
    let evidenceRefs: [String]
    let emittedAtMs: Int64
    let nextAction: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectID = "project_id"
        case edgeID = "edge_id"
        case blockedLane = "blocked_lane"
        case resolvedBy = "resolved_by"
        case resolvedFact = "resolved_fact"
        case resumeScope = "resume_scope"
        case deadlineHintUTC = "deadline_hint_utc"
        case mustNotDo = "must_not_do"
        case evidenceRefs = "evidence_refs"
        case emittedAtMs = "emitted_at_ms"
        case nextAction = "next_action"
    }
}

struct DirectedUnblockEvidence: Codable, Equatable {
    let schemaVersion: String
    let generatedAtMs: Int64
    let blockedToDirectedResumeP95Ms: Int64
    let emittedBatonCount: Int
    let directedOnly: Bool
    let batons: [DirectedUnblockBaton]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAtMs = "generated_at_ms"
        case blockedToDirectedResumeP95Ms = "blocked_to_directed_resume_p95_ms"
        case emittedBatonCount = "emitted_baton_count"
        case directedOnly = "directed_only"
        case batons
    }
}

@MainActor
final class DirectedUnblockRouter {
    private var batonLedger: [DirectedUnblockBaton] = []
    private var dedupeKeys: Set<String> = []
    private var blockedToResumeLatencySamplesMs: [Int64] = []

    @discardableResult
    func routeResolvedDependency(
        completedLaneID: String,
        resolvedBy: String,
        resolvedFact: String = "dependency_resolved",
        taskStates: [UUID: TaskExecutionState],
        laneStates: [String: LaneRuntimeState],
        evidenceRefs: [String] = [],
        now: Date = Date()
    ) -> [DirectedUnblockBaton] {
        let normalizedCompletedLaneID = completedLaneID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCompletedLaneID.isEmpty == false else { return [] }

        let currentProjectIDs = Set(
            taskStates.values
                .filter { laneID(for: $0.task) == normalizedCompletedLaneID }
                .map(\.projectId)
        )

        var emitted: [DirectedUnblockBaton] = []
        let nowMs = now.millisecondsSinceEpoch

        for state in taskStates.values.sorted(by: orderedStateComparator) {
            let blockedLaneID = laneID(for: state.task)
            guard blockedLaneID.isEmpty == false else { continue }
            guard blockedLaneID != normalizedCompletedLaneID else { continue }
            guard dependencyLaneIDs(from: state.task).contains(normalizedCompletedLaneID) else { continue }
            guard state.currentStatus == .blocked else { continue }
            if currentProjectIDs.isEmpty == false, currentProjectIDs.contains(state.projectId) == false {
                continue
            }

            let currentLaneState = laneStates[blockedLaneID]
            let blockedReason = currentLaneState?.blockedReason ?? LaneBlockedReason(metadataValue: state.task.metadata["blocked_reason"])
            guard blockedReason == .dependencyBlocked else { continue }

            let edgeID = "EDGE-\(sanitize(normalizedCompletedLaneID))-\(sanitize(blockedLaneID))"
            let dedupeKey = "\(edgeID)|\(resolvedFact.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            guard dedupeKeys.insert(dedupeKey).inserted else { continue }

            let baton = DirectedUnblockBaton(
                schemaVersion: "xt.unblock_baton.v1",
                projectID: state.projectId.uuidString.lowercased(),
                edgeID: edgeID,
                blockedLane: blockedLaneID,
                resolvedBy: resolvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Supervisor" : resolvedBy,
                resolvedFact: resolvedFact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "dependency_resolved" : resolvedFact,
                resumeScope: .continueCurrentTaskOnly,
                deadlineHintUTC: ISO8601DateFormatter().string(from: now.addingTimeInterval(300)),
                mustNotDo: ["scope_expand", "parallel_claim_new_lane"],
                evidenceRefs: orderedUnique(evidenceRefs + metadataList(state.task.metadata["evidence_refs"])),
                emittedAtMs: nowMs,
                nextAction: "continue_current_task_only"
            )

            batonLedger.append(baton)
            blockedToResumeLatencySamplesMs.append(0)
            emitted.append(baton)
        }

        if batonLedger.count > 60 {
            batonLedger.removeFirst(batonLedger.count - 60)
        }

        return emitted
    }

    func ledger(limit: Int = 40) -> [DirectedUnblockBaton] {
        Array(batonLedger.suffix(max(1, limit)))
    }

    func snapshot(now: Date = Date()) -> DirectedUnblockEvidence {
        DirectedUnblockEvidence(
            schemaVersion: "xt.w3_26.directed_unblock_evidence.v1",
            generatedAtMs: now.millisecondsSinceEpoch,
            blockedToDirectedResumeP95Ms: percentile95(blockedToResumeLatencySamplesMs),
            emittedBatonCount: batonLedger.count,
            directedOnly: true,
            batons: ledger(limit: 40)
        )
    }

    private func orderedStateComparator(lhs: TaskExecutionState, rhs: TaskExecutionState) -> Bool {
        let leftLane = laneID(for: lhs.task)
        let rightLane = laneID(for: rhs.task)
        if leftLane != rightLane {
            return leftLane < rightLane
        }
        return lhs.projectId.uuidString < rhs.projectId.uuidString
    }

    private func laneID(for task: DecomposedTask) -> String {
        task.metadata["lane_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? task.description.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func dependencyLaneIDs(from task: DecomposedTask) -> [String] {
        metadataList(task.metadata["depends_on"])
    }

    private func orderedUnique(_ entries: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for entry in entries {
            let token = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard token.isEmpty == false else { continue }
            if seen.insert(token).inserted {
                ordered.append(token)
            }
        }
        return ordered
    }

    private func metadataList(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw
            .replacingOccurrences(of: "\n", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == "|" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func sanitize(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar))
            }
            return "-"
        }
        return String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
    }

    private func percentile95(_ samples: [Int64]) -> Int64 {
        guard samples.isEmpty == false else { return 0 }
        let sorted = samples.sorted()
        let rawIndex = Int((Double(sorted.count - 1) * 0.95).rounded(.up))
        let index = max(0, min(sorted.count - 1, rawIndex))
        return sorted[index]
    }
}

private extension Date {
    var millisecondsSinceEpoch: Int64 {
        Int64((timeIntervalSince1970 * 1000.0).rounded())
    }
}
