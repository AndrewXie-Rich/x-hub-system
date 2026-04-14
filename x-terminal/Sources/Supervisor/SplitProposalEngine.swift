import Foundation

/// 拆分提案构建结果
struct SplitProposalBuildResult {
    var decomposition: DecompositionResult
    var proposal: SplitProposal
    var validation: SplitProposalValidationResult
}

/// 覆盖后提案结果
struct SplitProposalOverrideResult {
    var proposal: SplitProposal
    var validation: SplitProposalValidationResult
    var appliedOverrides: [SplitLaneOverrideRecord]
}

/// 拆分提案引擎：负责把任务分解结果转换成可审阅提案
@MainActor
final class SplitProposalEngine {

    func buildProposal(
        from decomposition: DecompositionResult,
        rootProjectId: UUID,
        planVersion: Int = 1
    ) -> SplitProposalBuildResult {
        let laneTasks = decomposition.subtasks.isEmpty ? [decomposition.rootTask] : decomposition.subtasks
        let laneIdByTaskId: [UUID: String] = Dictionary(
            uniqueKeysWithValues: laneTasks.enumerated().map { index, task in
                (task.id, "lane-\(index + 1)")
            }
        )

        let lanes = laneTasks.enumerated().map { index, task -> SplitLaneProposal in
            let laneId = laneIdByTaskId[task.id] ?? "lane-\(index + 1)"
            let riskTier = inferRiskTier(for: task, analysis: decomposition.analysis)
            let budgetClass = inferBudgetClass(for: task, riskTier: riskTier)
            let dependencies = decomposition.dependencyGraph.getDependencies(task.id)
                .compactMap { laneIdByTaskId[$0] }
                .sorted()
            let createChildProject = shouldCreateChildProject(task: task, riskTier: riskTier)
            let artifacts = expectedArtifacts(for: task)
            let dodChecklist = buildDoDChecklist(for: task, riskTier: riskTier)
            let verificationContract = buildVerificationContract(
                for: task,
                riskTier: riskTier,
                expectedArtifacts: artifacts,
                dodChecklist: dodChecklist
            )

            return SplitLaneProposal(
                laneId: laneId,
                goal: task.description,
                dependsOn: dependencies,
                riskTier: riskTier,
                budgetClass: budgetClass,
                createChildProject: createChildProject,
                expectedArtifacts: artifacts,
                dodChecklist: dodChecklist,
                verificationContract: verificationContract,
                estimatedEffortMs: Int(task.estimatedEffort * 1_000),
                tokenBudget: budgetClass.tokenBudget,
                sourceTaskId: task.id,
                notes: []
            )
        }

        let proposal = SplitProposal(
            splitPlanId: UUID(),
            rootProjectId: rootProjectId,
            planVersion: max(1, planVersion),
            complexityScore: computeComplexityScore(
                analysis: decomposition.analysis,
                laneCount: lanes.count,
                dependencyCount: lanes.reduce(0) { $0 + $1.dependsOn.count },
                lanes: lanes
            ),
            lanes: lanes,
            recommendedConcurrency: recommendedConcurrency(for: lanes),
            tokenBudgetTotal: lanes.reduce(0) { $0 + $1.tokenBudget },
            estimatedWallTimeMs: estimatedWallTimeMs(for: lanes),
            sourceTaskDescription: decomposition.rootTask.description,
            createdAt: Date()
        )

        let validation = validate(proposal)
        return SplitProposalBuildResult(
            decomposition: decomposition,
            proposal: proposal,
            validation: validation
        )
    }

    func applyOverrides(
        _ overrides: [SplitLaneOverride],
        to proposal: SplitProposal,
        reason: String = "user_override"
    ) -> SplitProposalOverrideResult {
        guard !overrides.isEmpty else {
            return SplitProposalOverrideResult(
                proposal: proposal,
                validation: validate(proposal),
                appliedOverrides: []
            )
        }

        var updated = proposal
        var overrideIssues: [SplitProposalValidationIssue] = []
        var appliedOverrides: [SplitLaneOverrideRecord] = []

        for override in overrides {
            guard let laneIndex = updated.lanes.firstIndex(where: { $0.laneId == override.laneId }) else {
                overrideIssues.append(
                    SplitProposalValidationIssue(
                        code: "override_lane_not_found",
                        message: "Override lane not found: \(override.laneId)",
                        severity: .warning,
                        laneId: override.laneId
                    )
                )
                continue
            }

            var lane = updated.lanes[laneIndex]
            let beforeSnapshot = snapshot(for: lane)
            let oldCreateChildProject = lane.createChildProject
            let normalizedDoD = override.dodChecklist.map(normalizeChecklist)
            let normalizedNote = override.note?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if let createChildProject = override.createChildProject {
                lane.createChildProject = createChildProject
            }
            if let budgetClass = override.budgetClass {
                lane.budgetClass = budgetClass
                lane.tokenBudget = budgetClass.tokenBudget
            }
            if let riskTier = override.riskTier {
                lane.riskTier = riskTier
            }
            if let dodChecklist = normalizedDoD {
                lane.dodChecklist = dodChecklist
            }
            if let note = normalizedNote, !note.isEmpty {
                lane.notes.append("override: \(note)")
            }

            var issueCodes: [String] = []
            let isHighRiskHardToSoft = oldCreateChildProject &&
                lane.createChildProject == false &&
                lane.riskTier >= .high

            if isHighRiskHardToSoft, override.confirmHighRiskHardToSoft != true {
                lane.createChildProject = oldCreateChildProject
                issueCodes.append("high_risk_hard_to_soft_confirmation_required")
                overrideIssues.append(
                    SplitProposalValidationIssue(
                        code: "high_risk_hard_to_soft_confirmation_required",
                        message: "High-risk lane \(lane.laneId) requires explicit confirmation before overriding hard_split to soft_split.",
                        severity: .blocking,
                        laneId: lane.laneId
                    )
                )
            } else if isHighRiskHardToSoft {
                issueCodes.append("high_risk_hard_to_soft_override")
                overrideIssues.append(
                    SplitProposalValidationIssue(
                        code: "high_risk_hard_to_soft_override",
                        message: "High-risk lane \(lane.laneId) overridden from hard_split to soft_split; explicit user confirmation is required.",
                        severity: .warning,
                        laneId: lane.laneId
                    )
                )
            }

            updated.lanes[laneIndex] = lane
            let normalizedOverride = SplitLaneOverride(
                id: override.id,
                laneId: override.laneId,
                createChildProject: override.createChildProject,
                budgetClass: override.budgetClass,
                riskTier: override.riskTier,
                dodChecklist: normalizedDoD,
                note: normalizedNote,
                confirmHighRiskHardToSoft: override.confirmHighRiskHardToSoft
            )
            appliedOverrides.append(
                SplitLaneOverrideRecord(
                    id: override.id,
                    laneId: lane.laneId,
                    reason: reason,
                    override: normalizedOverride,
                    before: beforeSnapshot,
                    after: snapshot(for: lane),
                    appliedAt: Date(),
                    issueCodes: issueCodes
                )
            )
        }

        updated.tokenBudgetTotal = updated.lanes.reduce(0) { $0 + $1.tokenBudget }
        updated.recommendedConcurrency = recommendedConcurrency(for: updated.lanes)
        updated.estimatedWallTimeMs = estimatedWallTimeMs(for: updated.lanes)

        let validation = validate(updated)
        let mergedValidation = SplitProposalValidationResult(issues: validation.issues + overrideIssues)
        return SplitProposalOverrideResult(
            proposal: updated,
            validation: mergedValidation,
            appliedOverrides: appliedOverrides
        )
    }

    func replayOverrides(
        _ records: [SplitLaneOverrideRecord],
        baseProposal: SplitProposal
    ) -> SplitProposalOverrideResult {
        let overrides = records
            .sorted {
                if $0.appliedAt != $1.appliedAt {
                    return $0.appliedAt < $1.appliedAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .map(\.override)
        return applyOverrides(overrides, to: baseProposal, reason: "override_replay")
    }

    func validate(_ proposal: SplitProposal) -> SplitProposalValidationResult {
        var issues: [SplitProposalValidationIssue] = []

        if proposal.lanes.isEmpty {
            issues.append(
                SplitProposalValidationIssue(
                    code: "empty_lanes",
                    message: "Split proposal must contain at least one lane.",
                    severity: .blocking
                )
            )
            return SplitProposalValidationResult(issues: issues)
        }

        let laneIds = proposal.lanes.map { $0.laneId }
        let uniqueLaneIds = Set(laneIds)
        if laneIds.count != uniqueLaneIds.count {
            issues.append(
                SplitProposalValidationIssue(
                    code: "duplicate_lane_id",
                    message: "Lane IDs must be unique.",
                    severity: .blocking
                )
            )
        }

        let existingLaneIds = Set(laneIds)
        for lane in proposal.lanes {
            if lane.dodChecklist.isEmpty {
                issues.append(
                    SplitProposalValidationIssue(
                        code: "lane_missing_dod",
                        message: "Lane \(lane.laneId) is missing DoD checklist.",
                        severity: .blocking,
                        laneId: lane.laneId
                    )
                )
            }

            if lane.expectedArtifacts.isEmpty {
                issues.append(
                    SplitProposalValidationIssue(
                        code: "lane_missing_artifact",
                        message: "Lane \(lane.laneId) is missing expected artifacts.",
                        severity: .warning,
                        laneId: lane.laneId
                    )
                )
            }

            for dependency in lane.dependsOn where !existingLaneIds.contains(dependency) {
                issues.append(
                    SplitProposalValidationIssue(
                        code: "lane_dependency_not_found",
                        message: "Lane \(lane.laneId) depends on unknown lane \(dependency).",
                        severity: .blocking,
                        laneId: lane.laneId
                    )
                )
            }

            if lane.riskTier >= .high && lane.createChildProject == false {
                issues.append(
                    SplitProposalValidationIssue(
                        code: "high_risk_soft_split",
                        message: "High-risk lane \(lane.laneId) is configured as soft split; this requires explicit user awareness.",
                        severity: .warning,
                        laneId: lane.laneId
                    )
                )
            }
        }

        if topologicalSort(lanes: proposal.lanes) == nil {
            issues.append(
                SplitProposalValidationIssue(
                    code: "dag_cycle_detected",
                    message: "Split proposal DAG contains a cycle.",
                    severity: .blocking
                )
            )
        }

        let computedBudget = proposal.lanes.reduce(0) { $0 + $1.tokenBudget }
        if computedBudget != proposal.tokenBudgetTotal {
            issues.append(
                SplitProposalValidationIssue(
                    code: "token_budget_mismatch",
                    message: "token_budget_total does not match lane budgets; value will be recalculated.",
                    severity: .warning
                )
            )
        }

        return SplitProposalValidationResult(issues: issues)
    }

    // MARK: - Private

    private func inferRiskTier(for task: DecomposedTask, analysis: TaskAnalysis) -> SplitRiskTier {
        if task.type == .deployment {
            return .critical
        }
        if task.type == .bugfix && task.complexity >= .complex {
            return .high
        }
        if task.complexity >= .veryComplex {
            return .critical
        }
        if task.complexity >= .complex {
            return .high
        }
        if analysis.riskLevel >= .high {
            return .high
        }
        if analysis.riskLevel == .medium || task.complexity == .moderate {
            return .medium
        }
        return .low
    }

    private func snapshot(for lane: SplitLaneProposal) -> SplitLaneSnapshot {
        SplitLaneSnapshot(
            laneId: lane.laneId,
            createChildProject: lane.createChildProject,
            riskTier: lane.riskTier,
            budgetClass: lane.budgetClass,
            tokenBudget: lane.tokenBudget,
            dodChecklist: lane.dodChecklist
        )
    }

    private func normalizeChecklist(_ checklist: [String]) -> [String] {
        checklist
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeUniqueEntries(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for value in values.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !value.isEmpty {
            if seen.insert(value).inserted {
                ordered.append(value)
            }
        }
        return ordered
    }

    private func inferBudgetClass(for task: DecomposedTask, riskTier: SplitRiskTier) -> SplitBudgetClass {
        if riskTier == .critical {
            return .burst
        }
        if riskTier == .high {
            return .premium
        }
        if task.complexity >= .complex {
            return .premium
        }
        if task.complexity == .moderate {
            return .standard
        }
        return .compact
    }

    private func shouldCreateChildProject(task: DecomposedTask, riskTier: SplitRiskTier) -> Bool {
        if riskTier >= .high {
            return true
        }
        if task.complexity >= .complex {
            return true
        }
        if task.estimatedEffort > 45 * 60 {
            return true
        }
        return false
    }

    private func expectedArtifacts(for task: DecomposedTask) -> [String] {
        switch task.type {
        case .development:
            return ["implemented_changes", "verification_notes"]
        case .testing:
            return ["test_cases", "test_report"]
        case .documentation:
            return ["documentation_update"]
        case .research:
            return ["research_notes", "decision_summary"]
        case .bugfix:
            return ["fix_patch", "regression_proof"]
        case .refactoring:
            return ["refactor_patch", "compatibility_validation"]
        case .deployment:
            return ["release_plan", "rollback_instructions"]
        case .review:
            return ["review_findings"]
        case .design:
            return ["design_spec", "acceptance_criteria"]
        case .planning:
            return ["execution_plan"]
        }
    }

    private func buildDoDChecklist(for task: DecomposedTask, riskTier: SplitRiskTier) -> [String] {
        var checklist = [
            "goal_complete: \(task.description)",
            "artifacts_uploaded",
            "self_check_passed"
        ]

        switch task.type {
        case .development, .bugfix, .refactoring:
            checklist.append("tests_or_checks_passed")
        case .testing:
            checklist.append("failing_cases_explained")
        case .documentation:
            checklist.append("doc_reviewed_for_accuracy")
        case .deployment:
            checklist.append("release_and_rollback_steps_recorded")
        default:
            checklist.append("handoff_notes_ready")
        }

        if riskTier >= .high {
            checklist.append("grant_or_risk_exception_recorded")
        }

        return checklist
    }

    private func buildVerificationContract(
        for task: DecomposedTask,
        riskTier: SplitRiskTier,
        expectedArtifacts: [String],
        dodChecklist: [String]
    ) -> LaneVerificationContract {
        let method: LaneVerificationMethod
        let retryPolicy: LaneVerificationRetryPolicy
        let holdPolicy: LaneVerificationHoldPolicy
        let expectedState: String
        var evidenceRequired = expectedArtifacts

        switch task.type {
        case .development, .bugfix, .refactoring, .testing:
            method = .targetedChecksAndDiffReview
            retryPolicy = riskTier >= .high ? .singleRetryThenEscalate : .boundedRetryThenHold
            holdPolicy = .holdOnMismatch
            expectedState = "Lane goal is satisfied, artifacts are updated, and targeted checks confirm no obvious regression."
            evidenceRequired.append(contentsOf: ["diff_summary", "targeted_check_result"])
        case .deployment:
            method = .preflightAndSmoke
            retryPolicy = riskTier >= .high ? .noAutoRetry : .singleRetryThenEscalate
            holdPolicy = .holdUntilEvidence
            expectedState = "Change is ready to ship, post-change smoke checks pass, and rollback readiness is recorded."
            evidenceRequired.append(contentsOf: ["preflight_result", "smoke_result", "rollback_readiness"])
        case .documentation, .research, .review, .design, .planning:
            method = .artifactConsistencyReview
            retryPolicy = .noAutoRetry
            holdPolicy = .advisoryOnly
            expectedState = "Produced artifacts are internally consistent, scoped correctly, and ready for handoff."
            evidenceRequired.append(contentsOf: ["artifact_review_note", "consistency_summary"])
        }

        if riskTier >= .high {
            evidenceRequired.append("grant_or_risk_exception_reference")
        }

        return LaneVerificationContract(
            expectedState: expectedState,
            verifyMethod: method,
            retryPolicy: retryPolicy,
            holdPolicy: holdPolicy,
            evidenceRequired: normalizeUniqueEntries(evidenceRequired),
            verificationChecklist: normalizeUniqueEntries(
                [
                    "expected_state_confirmed",
                    "evidence_attached"
                ] + dodChecklist
            )
        )
    }

    private func computeComplexityScore(
        analysis: TaskAnalysis,
        laneCount: Int,
        dependencyCount: Int,
        lanes: [SplitLaneProposal]
    ) -> Double {
        let baseByComplexity: Double
        switch analysis.complexity {
        case .trivial:
            baseByComplexity = 10
        case .simple:
            baseByComplexity = 25
        case .moderate:
            baseByComplexity = 45
        case .complex:
            baseByComplexity = 70
        case .veryComplex:
            baseByComplexity = 85
        }

        let laneBonus = min(20.0, Double(laneCount * 3))
        let dependencyBonus = min(15.0, Double(dependencyCount * 2))
        let riskBonus = lanes.reduce(0.0) { partial, lane in
            switch lane.riskTier {
            case .critical:
                return partial + 4.0
            case .high:
                return partial + 2.0
            case .medium:
                return partial + 1.0
            case .low:
                return partial
            }
        }

        return min(100.0, baseByComplexity + laneBonus + dependencyBonus + riskBonus)
    }

    private func recommendedConcurrency(for lanes: [SplitLaneProposal]) -> Int {
        guard !lanes.isEmpty else { return 1 }
        let width = maxConcurrencyWidth(lanes: lanes)
        guard width > 0 else {
            return 1
        }
        return max(1, min(4, width))
    }

    private func estimatedWallTimeMs(for lanes: [SplitLaneProposal]) -> Int {
        guard !lanes.isEmpty else { return 0 }
        guard let orderedLaneIds = topologicalSort(lanes: lanes) else {
            return lanes.reduce(0) { $0 + $1.estimatedEffortMs }
        }

        let laneById = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0) })
        var completion: [String: Int] = [:]

        for laneId in orderedLaneIds {
            guard let lane = laneById[laneId] else { continue }
            let dependencyFinish = lane.dependsOn.compactMap { completion[$0] }.max() ?? 0
            completion[laneId] = dependencyFinish + lane.estimatedEffortMs
        }

        return completion.values.max() ?? lanes.reduce(0) { $0 + $1.estimatedEffortMs }
    }

    private func maxConcurrencyWidth(lanes: [SplitLaneProposal]) -> Int {
        guard let ordered = topologicalSort(lanes: lanes) else {
            return 1
        }

        let laneById = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0) })
        var levels: [String: Int] = [:]
        var levelWidth: [Int: Int] = [:]

        for laneId in ordered {
            guard let lane = laneById[laneId] else { continue }
            let level = (lane.dependsOn.compactMap { levels[$0] }.max() ?? -1) + 1
            levels[laneId] = level
            levelWidth[level, default: 0] += 1
        }

        return levelWidth.values.max() ?? 1
    }

    private func topologicalSort(lanes: [SplitLaneProposal]) -> [String]? {
        let laneIds = lanes.map { $0.laneId }
        let laneById = Dictionary(uniqueKeysWithValues: lanes.map { ($0.laneId, $0) })
        var inDegree: [String: Int] = Dictionary(uniqueKeysWithValues: laneIds.map { ($0, 0) })
        var reverseEdges: [String: [String]] = Dictionary(uniqueKeysWithValues: laneIds.map { ($0, []) })

        for lane in lanes {
            for dependency in lane.dependsOn {
                guard laneById[dependency] != nil else { continue }
                inDegree[lane.laneId, default: 0] += 1
                reverseEdges[dependency, default: []].append(lane.laneId)
            }
        }

        var queue = inDegree.filter { $0.value == 0 }.map { $0.key }
        queue.sort()
        var ordered: [String] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()
            ordered.append(current)

            for dependent in reverseEdges[current] ?? [] {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                    queue.sort()
                }
            }
        }

        return ordered.count == laneIds.count ? ordered : nil
    }
}
