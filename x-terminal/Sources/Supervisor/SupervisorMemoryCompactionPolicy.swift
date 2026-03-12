import Foundation

enum SupervisorMemoryNodeKind: String, Codable, Sendable, CaseIterable {
    case observation
    case workingSet = "working_set"
    case actionLog = "action_log"
    case decision
    case approval
    case milestone
    case audit
    case releaseGate = "release_gate"
}

struct SupervisorMemoryNode: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var kind: SupervisorMemoryNodeKind
    var createdAtMs: Int64
    var lastTouchedAtMs: Int64
    var summary: String
    var refs: [String]
    var decisionId: String?
    var milestoneId: String?
    var pinned: Bool
    var active: Bool

    init(
        id: String,
        kind: SupervisorMemoryNodeKind,
        createdAtMs: Int64,
        lastTouchedAtMs: Int64,
        summary: String,
        refs: [String] = [],
        decisionId: String? = nil,
        milestoneId: String? = nil,
        pinned: Bool = false,
        active: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.createdAtMs = createdAtMs
        self.lastTouchedAtMs = lastTouchedAtMs
        self.summary = summary
        self.refs = refs
        self.decisionId = decisionId
        self.milestoneId = milestoneId
        self.pinned = pinned
        self.active = active
    }
}

struct SupervisorMemoryCompactionPolicyInput: Equatable, Sendable {
    var projectId: String
    var projectState: SupervisorProjectCapsuleState
    var nowMs: Int64
    var nodes: [SupervisorMemoryNode]
    var rollupObservationAgeMs: Int64
    var archiveNoiseAgeMs: Int64

    init(
        projectId: String,
        projectState: SupervisorProjectCapsuleState,
        nowMs: Int64,
        nodes: [SupervisorMemoryNode],
        rollupObservationAgeMs: Int64 = SupervisorMemoryCompactionPolicy.defaultObservationRollupAgeMs,
        archiveNoiseAgeMs: Int64 = SupervisorMemoryCompactionPolicy.defaultArchiveNoiseAgeMs
    ) {
        self.projectId = projectId
        self.projectState = projectState
        self.nowMs = nowMs
        self.nodes = nodes
        self.rollupObservationAgeMs = rollupObservationAgeMs
        self.archiveNoiseAgeMs = archiveNoiseAgeMs
    }
}

struct SupervisorMemoryCompactionPlan: Equatable, Sendable {
    var projectId: String
    var projectState: SupervisorProjectCapsuleState
    var periodStartMs: Int64
    var periodEndMs: Int64
    var sourceNodes: [SupervisorMemoryNode]
    var keepNodes: [SupervisorMemoryNode]
    var rollupNodes: [SupervisorMemoryNode]
    var archiveNodes: [SupervisorMemoryNode]
    var protectedNodes: [SupervisorMemoryNode]
    var archiveCandidate: Bool
    var policyReasons: [String]
}

enum SupervisorMemoryCompactionPolicy {
    static let defaultObservationRollupAgeMs: Int64 = 7 * 24 * 60 * 60 * 1_000
    static let defaultArchiveNoiseAgeMs: Int64 = 24 * 60 * 60 * 1_000

    static func makePlan(_ input: SupervisorMemoryCompactionPolicyInput) -> SupervisorMemoryCompactionPlan {
        let archiveCandidate = input.projectState == .completed || input.projectState == .archived
        var keepNodes: [SupervisorMemoryNode] = []
        var rollupNodes: [SupervisorMemoryNode] = []
        var archiveNodes: [SupervisorMemoryNode] = []
        var policyReasons: [String] = []

        if archiveCandidate {
            policyReasons.append("completed_project_is_archive_candidate")
        } else {
            policyReasons.append("active_project_rolls_up_only_stale_noise")
        }

        for node in input.nodes.sorted(by: nodeOrder) {
            if shouldKeep(node) {
                keepNodes.append(node)
                if isProtected(node) {
                    policyReasons.append("protected_fact_kept:\(node.id)")
                } else if node.active || node.pinned {
                    policyReasons.append("active_or_pinned_fact_kept:\(node.id)")
                }
                continue
            }

            let age = max(input.nowMs - node.lastTouchedAtMs, 0)
            if archiveCandidate && isNoise(node) && age >= input.archiveNoiseAgeMs {
                archiveNodes.append(node)
                policyReasons.append("completed_project_noise_archived:\(node.id)")
                continue
            }

            if isRollupEligible(node, age: age, rollupObservationAgeMs: input.rollupObservationAgeMs) {
                rollupNodes.append(node)
                policyReasons.append("stale_noise_rolled_up:\(node.id)")
                continue
            }

            keepNodes.append(node)
            policyReasons.append("fact_kept_by_default:\(node.id)")
        }

        let protectedNodes = keepNodes.filter(isProtected)
        let startMs = input.nodes.map(\.createdAtMs).min() ?? input.nowMs

        return SupervisorMemoryCompactionPlan(
            projectId: input.projectId,
            projectState: input.projectState,
            periodStartMs: startMs,
            periodEndMs: input.nowMs,
            sourceNodes: input.nodes.sorted(by: nodeOrder),
            keepNodes: keepNodes.sorted(by: nodeOrder),
            rollupNodes: rollupNodes.sorted(by: nodeOrder),
            archiveNodes: archiveNodes.sorted(by: nodeOrder),
            protectedNodes: protectedNodes.sorted(by: nodeOrder),
            archiveCandidate: archiveCandidate,
            policyReasons: dedupe(policyReasons)
        )
    }

    static func isProtected(_ node: SupervisorMemoryNode) -> Bool {
        switch node.kind {
        case .decision, .approval, .milestone, .audit, .releaseGate:
            return true
        case .observation, .workingSet, .actionLog:
            return false
        }
    }

    static func decisionIDs(in nodes: [SupervisorMemoryNode]) -> [String] {
        dedupe(nodes.compactMap(\.decisionId))
    }

    static func milestoneIDs(in nodes: [SupervisorMemoryNode]) -> [String] {
        dedupe(nodes.compactMap(\.milestoneId))
    }

    static func requiredSurvivingRefs(in nodes: [SupervisorMemoryNode]) -> [String] {
        let refs = nodes.flatMap { node in
            if isProtected(node) {
                return node.refs
            }
            return node.refs.filter { isAuditLikeRef($0) || isReleaseGateRef($0) }
        }
        return dedupe(refs)
    }

    static func auditRefs(in nodes: [SupervisorMemoryNode]) -> [String] {
        dedupe(nodes.flatMap(\.refs).filter(isAuditLikeRef))
    }

    static func releaseGateRefs(in nodes: [SupervisorMemoryNode]) -> [String] {
        dedupe(nodes.flatMap(\.refs).filter(isReleaseGateRef))
    }

    private static func isNoise(_ node: SupervisorMemoryNode) -> Bool {
        switch node.kind {
        case .observation, .workingSet, .actionLog:
            return true
        case .decision, .approval, .milestone, .audit, .releaseGate:
            return false
        }
    }

    private static func shouldKeep(_ node: SupervisorMemoryNode) -> Bool {
        isProtected(node) || node.active || node.pinned
    }

    private static func isRollupEligible(
        _ node: SupervisorMemoryNode,
        age: Int64,
        rollupObservationAgeMs: Int64
    ) -> Bool {
        guard isNoise(node) else {
            return false
        }
        return age >= rollupObservationAgeMs
    }

    private static func isAuditLikeRef(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.contains("audit") || lowered.contains("decision") || lowered.contains("approval")
    }

    private static func isReleaseGateRef(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.contains("release") || lowered.contains("gate")
    }

    private static func nodeOrder(lhs: SupervisorMemoryNode, rhs: SupervisorMemoryNode) -> Bool {
        if lhs.lastTouchedAtMs == rhs.lastTouchedAtMs {
            return lhs.id < rhs.id
        }
        return lhs.lastTouchedAtMs < rhs.lastTouchedAtMs
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
