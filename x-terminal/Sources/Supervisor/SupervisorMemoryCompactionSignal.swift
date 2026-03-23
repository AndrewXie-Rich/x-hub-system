import Foundation

struct SupervisorMemoryCompactionSignal: Equatable, Codable, Sendable {
    var rollupSummary: String
    var rolledUpCount: Int
    var archivedCount: Int
    var keptDecisionCount: Int
    var keptMilestoneCount: Int
    var archiveCandidate: Bool

    enum CodingKeys: String, CodingKey {
        case rollupSummary = "rollup_summary"
        case rolledUpCount = "rolled_up_count"
        case archivedCount = "archived_count"
        case keptDecisionCount = "kept_decision_count"
        case keptMilestoneCount = "kept_milestone_count"
        case archiveCandidate = "archive_candidate"
    }
}

enum SupervisorMemoryCompactionSignalBuilder {
    static func build(
        from rollup: SupervisorMemoryCompactionRollup
    ) -> SupervisorMemoryCompactionSignal {
        SupervisorMemoryCompactionSignal(
            rollupSummary: rollup.rollupSummary,
            rolledUpCount: rollup.rolledUpNodeIds.count,
            archivedCount: rollup.archivedNodeIds.count,
            keptDecisionCount: rollup.keptDecisionIds.count,
            keptMilestoneCount: rollup.keptMilestoneIds.count,
            archiveCandidate: rollup.archiveCandidate
        )
    }
}
