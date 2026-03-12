import Foundation

enum SupervisorArchiveRollupError: Error, Equatable, Sendable {
    case failClosed([String])
}

struct SupervisorMemoryCompactionRollup: Equatable, Codable, Sendable {
    static let schemaVersion = "xt.supervisor_memory_compaction_rollup.v1"

    var schemaVersion: String
    var projectId: String
    var periodStartMs: Int64
    var periodEndMs: Int64
    var rollupSummary: String
    var rolledUpNodeIds: [String]
    var archivedNodeIds: [String]
    var keptDecisionIds: [String]
    var keptMilestoneIds: [String]
    var keptAuditRefs: [String]
    var keptReleaseGateRefs: [String]
    var archivedRefs: [String]
    var archiveCandidate: Bool
    var policyReasons: [String]
    var decisionNodeLoss: Int
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case projectId = "project_id"
        case periodStartMs = "period_start_ms"
        case periodEndMs = "period_end_ms"
        case rollupSummary = "rollup_summary"
        case rolledUpNodeIds = "rolled_up_node_ids"
        case archivedNodeIds = "archived_node_ids"
        case keptDecisionIds = "kept_decision_ids"
        case keptMilestoneIds = "kept_milestone_ids"
        case keptAuditRefs = "kept_audit_refs"
        case keptReleaseGateRefs = "kept_release_gate_refs"
        case archivedRefs = "archived_refs"
        case archiveCandidate = "archive_candidate"
        case policyReasons = "policy_reasons"
        case decisionNodeLoss = "decision_node_loss"
        case updatedAtMs = "updated_at_ms"
    }
}

enum SupervisorArchiveRollup {
    static func build(
        from plan: SupervisorMemoryCompactionPlan,
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) throws -> SupervisorMemoryCompactionRollup {
        let validationErrors = validate(plan)
        guard validationErrors.isEmpty else {
            throw SupervisorArchiveRollupError.failClosed(validationErrors)
        }

        let keptDecisionIds = SupervisorMemoryCompactionPolicy.decisionIDs(in: plan.keepNodes)
        let keptMilestoneIds = SupervisorMemoryCompactionPolicy.milestoneIDs(in: plan.keepNodes)
        let keptAuditRefs = SupervisorMemoryCompactionPolicy.auditRefs(in: plan.keepNodes)
        let keptReleaseGateRefs = SupervisorMemoryCompactionPolicy.releaseGateRefs(in: plan.keepNodes)
        let archivedRefs = dedupe(
            SupervisorMemoryCompactionPolicy.requiredSurvivingRefs(in: plan.rollupNodes + plan.archiveNodes)
                + keptAuditRefs
                + keptReleaseGateRefs
        )

        let rollupSummary = summary(
            plan: plan,
            keptDecisionIds: keptDecisionIds,
            keptMilestoneIds: keptMilestoneIds,
            archivedRefs: archivedRefs
        )

        return SupervisorMemoryCompactionRollup(
            schemaVersion: SupervisorMemoryCompactionRollup.schemaVersion,
            projectId: plan.projectId,
            periodStartMs: plan.periodStartMs,
            periodEndMs: plan.periodEndMs,
            rollupSummary: rollupSummary,
            rolledUpNodeIds: plan.rollupNodes.map(\.id),
            archivedNodeIds: plan.archiveNodes.map(\.id),
            keptDecisionIds: keptDecisionIds,
            keptMilestoneIds: keptMilestoneIds,
            keptAuditRefs: keptAuditRefs,
            keptReleaseGateRefs: keptReleaseGateRefs,
            archivedRefs: archivedRefs,
            archiveCandidate: plan.archiveCandidate,
            policyReasons: plan.policyReasons,
            decisionNodeLoss: 0,
            updatedAtMs: max(updatedAtMs, plan.periodEndMs)
        )
    }

    static func validate(_ plan: SupervisorMemoryCompactionPlan) -> [String] {
        let originalProtectedIDs = Set(plan.sourceNodes.filter(SupervisorMemoryCompactionPolicy.isProtected).map(\.id))
        let keptIDs = Set(plan.keepNodes.map(\.id))
        let missingProtectedIDs = originalProtectedIDs.subtracting(keptIDs)

        let originalDecisionIDs = Set(SupervisorMemoryCompactionPolicy.decisionIDs(in: plan.sourceNodes))
        let keptDecisionIDs = Set(SupervisorMemoryCompactionPolicy.decisionIDs(in: plan.keepNodes))
        let lostDecisionIDs = originalDecisionIDs.subtracting(keptDecisionIDs)

        let requiredRefs = Set(SupervisorMemoryCompactionPolicy.requiredSurvivingRefs(in: plan.sourceNodes))
        let survivingRefs = Set(
            SupervisorMemoryCompactionPolicy.requiredSurvivingRefs(in: plan.keepNodes + plan.rollupNodes + plan.archiveNodes)
        )
        let missingRefs = requiredRefs.subtracting(survivingRefs)

        var errors: [String] = []
        if !missingProtectedIDs.isEmpty {
            errors.append("protected_node_loss:\(missingProtectedIDs.sorted().joined(separator: ","))")
        }
        if !lostDecisionIDs.isEmpty {
            errors.append("decision_node_loss:\(lostDecisionIDs.sorted().joined(separator: ","))")
        }
        if !missingRefs.isEmpty {
            errors.append("traceability_ref_loss:\(missingRefs.sorted().joined(separator: ","))")
        }
        return errors
    }

    private static func summary(
        plan: SupervisorMemoryCompactionPlan,
        keptDecisionIds: [String],
        keptMilestoneIds: [String],
        archivedRefs: [String]
    ) -> String {
        [
            "rolled_up=\(plan.rollupNodes.count)",
            "archived=\(plan.archiveNodes.count)",
            "kept_decisions=\(keptDecisionIds.count)",
            "kept_milestones=\(keptMilestoneIds.count)",
            "traceable_refs=\(archivedRefs.count)",
            "archive_candidate=\(plan.archiveCandidate)"
        ].joined(separator: "; ")
    }

    private static func dedupe(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                continue
            }
            ordered.append(trimmed)
        }
        return ordered
    }
}
