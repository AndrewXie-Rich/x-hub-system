import Foundation

struct LaneAllocationFactors {
    let riskFit: Double
    let budgetFit: Double
    let loadFit: Double
    let skillFit: Double
    let reliabilityFit: Double
    let total: Double
}

struct LaneAssignment {
    let laneID: String
    let task: DecomposedTask
    let project: ProjectModel
    let agentProfile: String
    let factors: LaneAllocationFactors
    let explain: String
}

struct LaneAllocationBlockedLane {
    let laneID: String
    let task: DecomposedTask
    let reason: String
    let explain: String
}

struct LaneAllocationResult {
    let assignments: [LaneAssignment]
    let blockedLanes: [LaneAllocationBlockedLane]
    let reproducibilitySignature: String

    var explainByLaneID: [String: String] {
        var result: [String: String] = [:]
        for assignment in assignments {
            result[assignment.laneID] = assignment.explain
        }
        for blocked in blockedLanes {
            result[blocked.laneID] = blocked.explain
        }
        return result
    }
}

private struct LaneScoreCandidate {
    let project: ProjectModel
    let factors: LaneAllocationFactors
    let agentProfile: String
    let explain: String
    let eligible: Bool
    let rejectionReason: String?
}

/// XT-W2-12 多泳道自动分配（risk/budget/load + explain）
@MainActor
final class LaneAllocator {
    private let riskWeight = 0.35
    private let budgetWeight = 0.20
    private let loadWeight = 0.15
    private let skillWeight = 0.15
    private let reliabilityWeight = 0.15

    func allocate(
        lanes: [MaterializedLane],
        projects: [ProjectModel]
    ) -> LaneAllocationResult {
        let candidateProjects = projects
            .filter { $0.status != .completed && $0.status != .archived }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority {
                    return lhs.priority > rhs.priority
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let sortedLanes = lanes.sorted { lhs, rhs in
            if lhs.plan.riskTier != rhs.plan.riskTier {
                return lhs.plan.riskTier > rhs.plan.riskTier
            }
            if lhs.task.priority != rhs.task.priority {
                return lhs.task.priority > rhs.task.priority
            }
            return lhs.plan.laneID < rhs.plan.laneID
        }

        guard !candidateProjects.isEmpty else {
            let blocked = sortedLanes.map {
                LaneAllocationBlockedLane(
                    laneID: $0.plan.laneID,
                    task: $0.task,
                    reason: "no_project_available",
                    explain: "lane=\($0.plan.laneID), blocked=no_project_available"
                )
            }
            return LaneAllocationResult(
                assignments: [],
                blockedLanes: blocked,
                reproducibilitySignature: buildSignature(assignments: [], blocked: blocked)
            )
        }

        var projectedLoad: [UUID: Int] = [:]
        var projectedCost: [UUID: Double] = [:]

        for project in candidateProjects {
            projectedLoad[project.id] = currentProjectLoad(project)
            projectedCost[project.id] = 0
        }

        var assignments: [LaneAssignment] = []
        var blockedLanes: [LaneAllocationBlockedLane] = []

        for lane in sortedLanes {
            var scoredCandidates: [LaneScoreCandidate] = []
            var rejections: [String] = []

            for project in candidateProjects {
                let scored = score(
                    lane: lane,
                    project: project,
                    projectedLoad: projectedLoad[project.id] ?? 0,
                    projectedCost: projectedCost[project.id] ?? 0
                )
                scoredCandidates.append(scored)
                if let reason = scored.rejectionReason {
                    rejections.append("\(project.name):\(reason)")
                }
            }

            let eligible = scoredCandidates
                .filter { $0.eligible }
                .sorted { lhs, rhs in
                    if abs(lhs.factors.total - rhs.factors.total) > 0.0001 {
                        return lhs.factors.total > rhs.factors.total
                    }
                    return lhs.project.id.uuidString < rhs.project.id.uuidString
                }

            guard let best = eligible.first else {
                let reason = rejections.isEmpty ? "no_eligible_candidate" : rejections.joined(separator: ";")
                blockedLanes.append(
                    LaneAllocationBlockedLane(
                        laneID: lane.plan.laneID,
                        task: lane.task,
                        reason: "allocation_blocked",
                        explain: "lane=\(lane.plan.laneID), blocked=allocation_blocked, reason=\(reason)"
                    )
                )
                continue
            }

            let estimatedCost = estimateLaneCost(lane: lane, project: best.project)
            projectedLoad[best.project.id, default: 0] += 1
            projectedCost[best.project.id, default: 0] += estimatedCost

            let assignment = LaneAssignment(
                laneID: lane.plan.laneID,
                task: lane.task,
                project: best.project,
                agentProfile: best.agentProfile,
                factors: best.factors,
                explain: best.explain
            )
            assignments.append(assignment)
        }

        return LaneAllocationResult(
            assignments: assignments,
            blockedLanes: blockedLanes,
            reproducibilitySignature: buildSignature(assignments: assignments, blocked: blockedLanes)
        )
    }

    // MARK: - Private

    private func score(
        lane: MaterializedLane,
        project: ProjectModel,
        projectedLoad: Int,
        projectedCost: Double
    ) -> LaneScoreCandidate {
        if lane.mode == .hardSplit,
           let pinned = lane.targetProject,
           pinned.id != project.id {
            return LaneScoreCandidate(
                project: project,
                factors: LaneAllocationFactors(
                    riskFit: 0,
                    budgetFit: 0,
                    loadFit: 0,
                    skillFit: 0,
                    reliabilityFit: 0,
                    total: 0
                ),
                agentProfile: "none",
                explain: "lane=\(lane.plan.laneID), project=\(project.name), reject=pinned_to_child_project",
                eligible: false,
                rejectionReason: "pinned_to_child_project"
            )
        }

        let risk = evaluateRiskFit(lane: lane, project: project)
        let budget = evaluateBudgetFit(lane: lane, project: project, projectedExtraCost: projectedCost)
        let load = evaluateLoadFit(project: project, projectedLoad: projectedLoad)
        let skill = evaluateSkillFit(lane: lane, project: project)
        let reliability = evaluateReliabilityFit(lane: lane, project: project)

        let total = risk.fit * riskWeight
            + budget.fit * budgetWeight
            + load * loadWeight
            + skill.fit * skillWeight
            + reliability.fit * reliabilityWeight
        let profile = chooseAgentProfile(lane: lane, project: project)

        var reasons: [String] = []
        var eligible = true

        if risk.hardBlocked {
            eligible = false
            reasons.append("risk_profile_mismatch")
        }
        if budget.hardBlocked {
            eligible = false
            reasons.append("budget_exhausted")
        }
        if skill.hardBlocked {
            eligible = false
            reasons.append("skill_profile_mismatch")
        }
        if reliability.hardBlocked {
            eligible = false
            reasons.append("reliability_history_insufficient")
        }

        let explain = String(
            format: "lane=%@,project=%@,risk_fit=%.2f,budget_fit=%.2f,load_fit=%.2f,skill_fit=%.2f,reliability_fit=%.2f,total=%.2f,profile=%@,weights=%.2f/%.2f/%.2f/%.2f/%.2f,skill_required=%d,skill_match=%d,reliability_samples=%d,projected_load=%d",
            lane.plan.laneID,
            project.name,
            risk.fit,
            budget.fit,
            load,
            skill.fit,
            reliability.fit,
            total,
            profile,
            riskWeight,
            budgetWeight,
            loadWeight,
            skillWeight,
            reliabilityWeight,
            skill.requiredCount,
            skill.matchedCount,
            reliability.samples,
            projectedLoad
        )

        return LaneScoreCandidate(
            project: project,
            factors: LaneAllocationFactors(
                riskFit: risk.fit,
                budgetFit: budget.fit,
                loadFit: load,
                skillFit: skill.fit,
                reliabilityFit: reliability.fit,
                total: total
            ),
            agentProfile: profile,
            explain: explain,
            eligible: eligible,
            rejectionReason: reasons.isEmpty ? nil : reasons.joined(separator: ",")
        )
    }

    private func evaluateRiskFit(lane: MaterializedLane, project: ProjectModel) -> (fit: Double, hardBlocked: Bool) {
        let capabilityRange = Double(ModelCapability.expert.rawValue - ModelCapability.basic.rawValue)
        let capabilityScore = Double(project.currentModel.capability.rawValue - ModelCapability.basic.rawValue) / max(1, capabilityRange)
        let executionScore = project.governanceSchedulingAutonomyScore
        let supervisionScore = project.governanceSchedulingRiskSupportScore

        let trustScore = capabilityScore * 0.60 + executionScore * 0.25 + supervisionScore * 0.15
        let requiredTrust: Double

        switch lane.plan.riskTier {
        case .low:
            requiredTrust = 0.20
        case .medium:
            requiredTrust = 0.40
        case .high:
            requiredTrust = 0.65
        case .critical:
            requiredTrust = 0.82
        }

        let gap = max(0, requiredTrust - trustScore)
        let fit = max(0, min(1, 1 - gap * 1.8))
        let hardBlocked = lane.plan.riskTier >= .high && trustScore + 0.05 < requiredTrust

        return (fit, hardBlocked)
    }

    private func evaluateBudgetFit(
        lane: MaterializedLane,
        project: ProjectModel,
        projectedExtraCost: Double
    ) -> (fit: Double, hardBlocked: Bool) {
        let estimatedLaneCost = estimateLaneCost(lane: lane, project: project)
        let remainingBudget = max(0, project.budget.daily - project.costTracker.totalCost - projectedExtraCost)

        let normalizedFit = remainingBudget / max(estimatedLaneCost, 0.05)
        var fit = max(0, min(1, normalizedFit))

        switch lane.plan.budgetClass {
        case .economy:
            if (project.currentModel.costPerMillionTokens ?? 0) > 5 {
                fit *= 0.7
            }
        case .premium:
            if project.currentModel.capability.rawValue < ModelCapability.advanced.rawValue {
                fit *= 0.75
            }
        case .balanced:
            break
        }

        let hardBlocked = remainingBudget <= 0.01
        return (fit, hardBlocked)
    }

    private func evaluateLoadFit(project: ProjectModel, projectedLoad: Int) -> Double {
        let capacity = project.governanceParallelCapacity
        let ratio = Double(projectedLoad) / Double(capacity)
        return max(0, min(1, 1 - ratio))
    }

    private func evaluateSkillFit(
        lane: MaterializedLane,
        project: ProjectModel
    ) -> (fit: Double, hardBlocked: Bool, requiredCount: Int, matchedCount: Int) {
        let requiredSkills = laneRequiredSkills(lane: lane)
        let hasExplicitRequirements = hasExplicitSkillRequirements(lane: lane)
        let projectSkills = projectSkillProfile(project: project)

        let requiredCount = requiredSkills.count
        let matchedCount = requiredSkills.intersection(projectSkills).count
        let overlapFit: Double
        if requiredCount == 0 {
            overlapFit = 0.75
        } else {
            overlapFit = Double(matchedCount) / Double(requiredCount)
        }

        // High capability models can compensate partially for sparse history tags.
        let capabilityBoost = min(
            0.20,
            Double(project.currentModel.capability.rawValue - ModelCapability.basic.rawValue) * 0.05
        )
        let fit = max(0, min(1, overlapFit + capabilityBoost))
        let hardBlocked = hasExplicitRequirements
            && lane.plan.riskTier >= .high
            && requiredCount > 0
            && fit < 0.45
        return (fit, hardBlocked, requiredCount, matchedCount)
    }

    private func evaluateReliabilityFit(
        lane: MaterializedLane,
        project: ProjectModel
    ) -> (fit: Double, hardBlocked: Bool, samples: Int) {
        let historical = project.taskQueue.filter { candidate in
            candidate.type == lane.task.type
                && (candidate.status == .completed || candidate.status == .failed || candidate.status == .cancelled)
        }

        let fallbackHistorical = historical.isEmpty
            ? project.taskQueue.filter { candidate in
                candidate.status == .completed || candidate.status == .failed || candidate.status == .cancelled
            }
            : historical

        let samples = fallbackHistorical.count
        guard samples > 0 else {
            // Unknown history is tolerated, but not treated as fully reliable.
            return (fit: 0.70, hardBlocked: false, samples: 0)
        }

        let success = fallbackHistorical.filter { $0.status == .completed }.count
        let successRate = Double(success) / Double(samples)
        let fit = max(0, min(1, successRate))

        let minRequired: Double
        switch lane.plan.riskTier {
        case .low:
            minRequired = 0.35
        case .medium:
            minRequired = 0.50
        case .high:
            minRequired = 0.70
        case .critical:
            minRequired = 0.80
        }

        let hardBlocked = lane.plan.riskTier >= .high && samples >= 3 && successRate < minRequired
        return (fit: fit, hardBlocked: hardBlocked, samples: samples)
    }

    private func currentProjectLoad(_ project: ProjectModel) -> Int {
        project.taskQueue.filter { task in
            task.status == .inProgress || task.status == .assigned || task.status == .pending || task.status == .blocked
        }.count
    }

    private func estimateLaneCost(lane: MaterializedLane, project: ProjectModel) -> Double {
        let hours = max(0.25, lane.task.estimatedEffort / 3600.0)
        let tokensPerHour = 50_000.0
        let tokenMillions = (hours * tokensPerHour) / 1_000_000.0
        let unitCost = project.currentModel.costPerMillionTokens ?? 0.05

        var cost = tokenMillions * unitCost
        switch lane.plan.budgetClass {
        case .economy:
            cost *= 0.8
        case .balanced:
            break
        case .premium:
            cost *= 1.2
        }

        return max(0.01, cost)
    }

    private func chooseAgentProfile(lane: MaterializedLane, project: ProjectModel) -> String {
        let skillToken = primarySkillToken(for: lane)
        if lane.plan.riskTier >= .high {
            let trustProfile = project.currentModel.capability.rawValue >= ModelCapability.advanced.rawValue
                ? "trusted_high"
                : "trusted_medium"
            return "\(trustProfile)_skill_\(skillToken)"
        }

        switch lane.plan.budgetClass {
        case .economy:
            return project.currentModel.isLocal
                ? "cost_optimized_local_skill_\(skillToken)"
                : "cost_optimized_remote_skill_\(skillToken)"
        case .balanced:
            return "balanced_general_skill_\(skillToken)"
        case .premium:
            return "quality_first_skill_\(skillToken)"
        }
    }

    private func laneRequiredSkills(lane: MaterializedLane) -> Set<String> {
        var tokens: [String] = []
        let metadataKeys = ["required_skills", "skill_tags", "skills"]
        for key in metadataKeys {
            guard let raw = lane.task.metadata[key], !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            tokens.append(contentsOf: raw.split(whereSeparator: { $0 == "," || $0 == "|" || $0 == ";" }).map(String.init))
        }

        if tokens.isEmpty {
            tokens.append(lane.task.type.rawValue)
            tokens.append(lane.task.description)
        }

        return Set(tokens.compactMap(normalizedSkillToken(raw:)))
    }

    private func hasExplicitSkillRequirements(lane: MaterializedLane) -> Bool {
        let metadataKeys = ["required_skills", "skill_tags", "skills"]
        return metadataKeys.contains { key in
            guard let raw = lane.task.metadata[key] else { return false }
            return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func projectSkillProfile(project: ProjectModel) -> Set<String> {
        var tokens: [String] = []
        tokens.append(contentsOf: project.currentModel.suitableFor)
        tokens.append(project.taskDescription)
        tokens.append(contentsOf: project.taskQueue.map(\.description))

        for task in project.taskQueue {
            tokens.append(task.type.rawValue)
            if let raw = task.metadata["required_skills"] {
                tokens.append(raw)
            }
            if let raw = task.metadata["skill_tags"] {
                tokens.append(raw)
            }
        }

        return Set(tokens.compactMap(normalizedSkillToken(raw:)))
    }

    private func primarySkillToken(for lane: MaterializedLane) -> String {
        laneRequiredSkills(lane: lane)
            .sorted()
            .first ?? "general"
    }

    private func normalizedSkillToken(raw: String) -> String? {
        let lowered = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lowered.isEmpty else { return nil }

        if lowered.contains("deploy") || lowered.contains("release") || lowered.contains("运维") || lowered.contains("部署") {
            return "deployment"
        }
        if lowered.contains("test") || lowered.contains("qa") || lowered.contains("验证") || lowered.contains("测试") {
            return "testing"
        }
        if lowered.contains("doc") || lowered.contains("文档") {
            return "documentation"
        }
        if lowered.contains("research") || lowered.contains("analysis") || lowered.contains("调研") || lowered.contains("研究") {
            return "research"
        }
        if lowered.contains("debug") || lowered.contains("bug") || lowered.contains("修复") || lowered.contains("故障") {
            return "debugging"
        }
        if lowered.contains("refactor") || lowered.contains("重构") {
            return "refactoring"
        }
        if lowered.contains("review") || lowered.contains("审查") {
            return "review"
        }
        if lowered.contains("design") || lowered.contains("架构") || lowered.contains("设计") {
            return "design"
        }
        if lowered.contains("plan") || lowered.contains("项目管理") || lowered.contains("规划") {
            return "planning"
        }
        if lowered.contains("code") || lowered.contains("develop") || lowered.contains("编程") || lowered.contains("开发") {
            return "development"
        }

        let ascii = lowered.filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        return ascii.isEmpty ? nil : ascii
    }

    private func buildSignature(assignments: [LaneAssignment], blocked: [LaneAllocationBlockedLane]) -> String {
        let assignmentPart = assignments
            .sorted { $0.laneID < $1.laneID }
            .map { "\($0.laneID)->\($0.project.id.uuidString)" }
            .joined(separator: "|")

        let blockedPart = blocked
            .sorted { $0.laneID < $1.laneID }
            .map { "\($0.laneID):\($0.reason)" }
            .joined(separator: "|")

        return "assign:[\(assignmentPart)]::blocked:[\(blockedPart)]"
    }
}
