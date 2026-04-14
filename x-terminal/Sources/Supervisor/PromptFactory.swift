import Foundation

/// PromptFactory：把 split proposal 编译成每条 lane 的 Prompt Contract，并执行 lint
@MainActor
final class PromptFactory {

    func compileContracts(for proposal: SplitProposal, globalContext: String = "") -> PromptCompilationResult {
        var contracts: [PromptContract] = []
        var issues: [PromptLintIssue] = []

        for lane in proposal.lanes {
            let contract = compileContract(for: lane, proposal: proposal, globalContext: globalContext)
            contracts.append(contract)
            issues.append(contentsOf: lint(contract))

            if lane.riskTier >= .high && !contract.riskBoundaries.contains(where: { $0.lowercased().contains("grant") }) {
                issues.append(
                    PromptLintIssue(
                        laneId: lane.laneId,
                        severity: .error,
                        code: "high_risk_missing_grant_boundary",
                        message: "High-risk lane requires grant boundary in prompt contract."
                    )
                )
            }
        }

        if contracts.count != proposal.lanes.count {
            issues.append(
                PromptLintIssue(
                    laneId: "__all__",
                    severity: .error,
                    code: "prompt_coverage_gap",
                    message: "Prompt contract coverage does not match lane count."
                )
            )
        }

        let lintResult = PromptLintResult(issues: issues)
        let status: PromptCompilationStatus = lintResult.hasBlockingErrors ? .rejected : .ready

        return PromptCompilationResult(
            splitPlanId: proposal.splitPlanId,
            expectedLaneCount: proposal.lanes.count,
            contracts: contracts,
            lintResult: lintResult,
            status: status,
            compiledAt: Date()
        )
    }

    func compileContract(for lane: SplitLaneProposal, proposal: SplitProposal, globalContext: String) -> PromptContract {
        let boundaries = buildBoundaries(for: lane)
        let inputs = buildInputs(for: lane, proposal: proposal, globalContext: globalContext)
        let outputs = sanitizeEntries(lane.expectedArtifacts)
        let dodChecklist = sanitizeEntries(lane.dodChecklist)
        let riskBoundaries = sanitizeEntries(buildRiskBoundaries(for: lane))
        let prohibitions = sanitizeEntries(buildProhibitions(for: lane))
        let rollbackPoints = sanitizeEntries(buildRollbackPoints(for: lane))
        let refusalSemantics = sanitizeEntries(buildRefusalSemantics(for: lane))
        let verificationContract = lane.verificationContract ?? fallbackVerificationContract(for: lane)

        let compiledPrompt = renderPrompt(
            lane: lane,
            boundaries: boundaries,
            inputs: inputs,
            outputs: outputs,
            dodChecklist: dodChecklist,
            verificationContract: verificationContract,
            riskBoundaries: riskBoundaries,
            prohibitions: prohibitions,
            rollbackPoints: rollbackPoints,
            refusalSemantics: refusalSemantics
        )

        return PromptContract(
            laneId: lane.laneId,
            goal: lane.goal,
            boundaries: boundaries,
            inputs: inputs,
            outputs: outputs,
            dodChecklist: dodChecklist,
            riskBoundaries: riskBoundaries,
            prohibitions: prohibitions,
            rollbackPoints: rollbackPoints,
            refusalSemantics: refusalSemantics,
            verificationContract: verificationContract,
            compiledPrompt: compiledPrompt,
            tokenBudget: lane.tokenBudget
        )
    }

    func lint(_ contract: PromptContract) -> [PromptLintIssue] {
        var issues: [PromptLintIssue] = []
        let dod = sanitizeEntries(contract.dodChecklist)
        let riskBoundaries = sanitizeEntries(contract.riskBoundaries)
        let prohibitions = sanitizeEntries(contract.prohibitions)
        let refusalSemantics = sanitizeEntries(contract.refusalSemantics)
        let rollbackPoints = sanitizeEntries(contract.rollbackPoints)

        if contract.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_goal",
                    message: "Prompt contract must include lane goal."
                )
            )
        }

        if dod.isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_dod",
                    message: "Prompt contract is missing DoD checklist."
                )
            )
        }

        if riskBoundaries.isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_risk_boundary",
                    message: "Prompt contract is missing risk boundary section."
                )
            )
        }

        if prohibitions.isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_prohibitions",
                    message: "Prompt contract is missing prohibition section."
                )
            )
        }

        if refusalSemantics.isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_refusal_semantics",
                    message: "Prompt contract is missing refusal semantics."
                )
            )
        }

        if rollbackPoints.isEmpty {
            issues.append(
                PromptLintIssue(
                    laneId: contract.laneId,
                    severity: .error,
                    code: "missing_rollback_points",
                    message: "Prompt contract is missing rollback points."
                )
            )
        }

        return issues
    }

    // MARK: - Private

    private func buildBoundaries(for lane: SplitLaneProposal) -> [String] {
        var boundaries = [
            "Only execute within lane scope: \(lane.goal)",
            "Do not modify artifacts owned by other lanes without dependency handoff.",
            "Report blockers immediately instead of guessing requirements."
        ]

        if lane.createChildProject {
            boundaries.append("Use isolated child project workspace for side-effecting changes.")
        } else {
            boundaries.append("Operate as soft split in parent project and avoid broad refactors.")
        }

        return boundaries
    }

    private func buildInputs(for lane: SplitLaneProposal, proposal: SplitProposal, globalContext: String) -> [String] {
        var inputs = [
            "split_plan_id=\(proposal.splitPlanId.uuidString)",
            "lane_id=\(lane.laneId)",
            "depends_on=\(lane.dependsOn.joined(separator: ","))",
            "budget_class=\(lane.budgetClass.rawValue)",
            "token_budget=\(lane.tokenBudget)"
        ]

        let cleanedContext = globalContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanedContext.isEmpty {
            inputs.append("global_context=\(cleanedContext)")
        }

        return inputs
    }

    private func buildRiskBoundaries(for lane: SplitLaneProposal) -> [String] {
        switch lane.riskTier {
        case .critical:
            return [
                "Critical risk lane: require explicit grant_id before any external side effects.",
                "If grant is missing, refuse and emit deny_code=grant_pending."
            ]
        case .high:
            return [
                "High risk lane: execute only with confirmed grant boundary.",
                "Any ambiguous requirement must be escalated to Supervisor before execution."
            ]
        case .medium:
            return [
                "Medium risk lane: keep changes scoped and reversible.",
                "Pause and ask Supervisor when constraints conflict."
            ]
        case .low:
            return [
                "Low risk lane: stay inside declared artifacts and avoid hidden side effects."
            ]
        }
    }

    private func buildProhibitions(for lane: SplitLaneProposal) -> [String] {
        var prohibitions = [
            "Do not execute work outside the declared lane outputs and DoD.",
            "Do not bypass lane dependencies; blocked dependency must be escalated.",
            "Do not fabricate grant_id, audit_ref, or completion evidence."
        ]

        if lane.riskTier >= .high {
            prohibitions.append("Do not perform external side effects without explicit grant_id.")
        }
        if lane.createChildProject == false {
            prohibitions.append("Do not perform broad repository rewrites under soft split mode.")
        }

        return prohibitions
    }

    private func buildRollbackPoints(for lane: SplitLaneProposal) -> [String] {
        var points = [
            "checkpoint_before_execution",
            "checkpoint_after_primary_artifact"
        ]

        if lane.riskTier >= .high {
            points.append("checkpoint_before_external_side_effect")
        }

        return points
    }

    private func buildRefusalSemantics(for lane: SplitLaneProposal) -> [String] {
        var semantics = [
            "Refuse execution when required inputs are missing.",
            "Refuse execution when DoD cannot be satisfied.",
            "Return explicit deny_code for grant-related blocks."
        ]

        if lane.createChildProject == false && lane.riskTier >= .high {
            semantics.append("Refuse side-effecting operations under soft split for high-risk lane.")
        }

        return semantics
    }

    private func renderPrompt(
        lane: SplitLaneProposal,
        boundaries: [String],
        inputs: [String],
        outputs: [String],
        dodChecklist: [String],
        verificationContract: LaneVerificationContract?,
        riskBoundaries: [String],
        prohibitions: [String],
        rollbackPoints: [String],
        refusalSemantics: [String]
    ) -> String {
        let boundaryText = boundaries.map { "- \($0)" }.joined(separator: "\n")
        let inputText = inputs.map { "- \($0)" }.joined(separator: "\n")
        let outputText = outputs.map { "- \($0)" }.joined(separator: "\n")
        let dodText = dodChecklist.map { "- \($0)" }.joined(separator: "\n")
        let verificationText = renderVerificationSection(verificationContract)
        let riskText = riskBoundaries.map { "- \($0)" }.joined(separator: "\n")
        let prohibitionText = prohibitions.map { "- \($0)" }.joined(separator: "\n")
        let rollbackText = rollbackPoints.map { "- \($0)" }.joined(separator: "\n")
        let refusalText = refusalSemantics.map { "- \($0)" }.joined(separator: "\n")

        return """
[Lane Goal]
\(lane.goal)

[Boundaries]
\(boundaryText)

[Inputs]
\(inputText)

[Outputs]
\(outputText)

[DoD]
\(dodText)

[Verification Contract]
\(verificationText)

[Risk Boundaries]
\(riskText)

[Prohibitions]
\(prohibitionText)

[Rollback Points]
\(rollbackText)

[Refusal Semantics]
\(refusalText)
"""
    }

    private func renderVerificationSection(_ contract: LaneVerificationContract?) -> String {
        guard let contract else {
            return "- No explicit verification contract was attached."
        }

        let evidenceText = sanitizeEntries(contract.evidenceRequired)
            .map { "- \($0)" }
            .joined(separator: "\n")
        let checklistText = sanitizeEntries(contract.verificationChecklist)
            .map { "- \($0)" }
            .joined(separator: "\n")

        return """
- Expected state: \(contract.expectedState)
- Verify method: \(contract.verifyMethod.promptLabel)
- Retry policy: \(contract.retryPolicy.promptLabel)
- Hold policy: \(contract.holdPolicy.promptLabel)
- Evidence required:
\(evidenceText)
- Verification checklist:
\(checklistText)
"""
    }

    private func fallbackVerificationContract(for lane: SplitLaneProposal) -> LaneVerificationContract {
        let text = ([lane.goal] + lane.expectedArtifacts + lane.dodChecklist)
            .joined(separator: " ")
            .lowercased()

        if text.contains("deploy") || text.contains("release") || text.contains("rollback") ||
            text.contains("部署") || text.contains("发布") {
            return LaneVerificationContract(
                expectedState: "Change is ready to ship, smoke checks are green, and rollback readiness is documented.",
                verifyMethod: .preflightAndSmoke,
                retryPolicy: lane.riskTier >= .high ? .noAutoRetry : .singleRetryThenEscalate,
                holdPolicy: .holdUntilEvidence,
                evidenceRequired: sanitizeEntries(lane.expectedArtifacts + ["preflight_result", "smoke_result", "rollback_readiness"]),
                verificationChecklist: sanitizeEntries(["expected_state_confirmed", "evidence_attached"] + lane.dodChecklist)
            )
        }

        if text.contains("doc") || text.contains("design") || text.contains("research") || text.contains("plan") ||
            text.contains("文档") || text.contains("设计") || text.contains("研究") || text.contains("计划") {
            return LaneVerificationContract(
                expectedState: "Artifacts are internally consistent and ready for handoff.",
                verifyMethod: .artifactConsistencyReview,
                retryPolicy: .noAutoRetry,
                holdPolicy: .advisoryOnly,
                evidenceRequired: sanitizeEntries(lane.expectedArtifacts + ["artifact_review_note", "consistency_summary"]),
                verificationChecklist: sanitizeEntries(["expected_state_confirmed", "evidence_attached"] + lane.dodChecklist)
            )
        }

        return LaneVerificationContract(
            expectedState: "Lane goal is satisfied and targeted checks confirm the intended change.",
            verifyMethod: .targetedChecksAndDiffReview,
            retryPolicy: lane.riskTier >= .high ? .singleRetryThenEscalate : .boundedRetryThenHold,
            holdPolicy: .holdOnMismatch,
            evidenceRequired: sanitizeEntries(lane.expectedArtifacts + ["diff_summary", "targeted_check_result"]),
            verificationChecklist: sanitizeEntries(["expected_state_confirmed", "evidence_attached"] + lane.dodChecklist)
        )
    }

    private func sanitizeEntries(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
