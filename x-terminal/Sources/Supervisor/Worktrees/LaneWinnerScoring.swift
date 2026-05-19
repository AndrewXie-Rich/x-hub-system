import Foundation

struct LaneWinnerSelectionOverride: Codable, Equatable {
    let laneID: String
    let reason: String
    let auditRef: String
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case reason
        case auditRef = "audit_ref"
        case createdAtMs = "created_at_ms"
    }
}

struct LaneWinnerScoreCandidate: Codable, Equatable, Identifiable {
    var id: String { laneID }

    let laneID: String
    let rank: Int
    let score: Int
    let selected: Bool
    let eligibleForMergeback: Bool
    let reviewVerdict: String
    let riskTier: String
    let changedFileCount: Int
    let diagnosticsRunCount: Int
    let launchDenyCode: String
    let blockers: [String]
    let strengths: [String]
    let evidenceRefs: [String]
    let coderOutputRef: String
    let reviewReportRef: String
    let mergebackReportRef: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case rank
        case score
        case selected
        case eligibleForMergeback = "eligible_for_mergeback"
        case reviewVerdict = "review_verdict"
        case riskTier = "risk_tier"
        case changedFileCount = "changed_file_count"
        case diagnosticsRunCount = "diagnostics_run_count"
        case launchDenyCode = "launch_deny_code"
        case blockers
        case strengths
        case evidenceRefs = "evidence_refs"
        case coderOutputRef = "coder_output_ref"
        case reviewReportRef = "review_report_ref"
        case mergebackReportRef = "mergeback_report_ref"
        case summary
    }
}

struct LaneWinnerScoreReport: Codable, Equatable {
    static let currentSchemaVersion = "xt.lane_winner_score_report.v1"

    let schemaVersion: String
    let splitPlanID: String
    let recommendedLaneID: String
    let automaticRecommendedLaneID: String
    let manualOverrideLaneID: String
    let manualOverrideReason: String
    let selectionSource: String
    let selectionBlockers: [String]
    let candidateCount: Int
    let eligibleCount: Int
    let policySummary: String
    let candidates: [LaneWinnerScoreCandidate]
    let reportRef: String
    let auditRef: String
    let createdAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case splitPlanID = "split_plan_id"
        case recommendedLaneID = "recommended_lane_id"
        case automaticRecommendedLaneID = "automatic_recommended_lane_id"
        case manualOverrideLaneID = "manual_override_lane_id"
        case manualOverrideReason = "manual_override_reason"
        case selectionSource = "selection_source"
        case selectionBlockers = "selection_blockers"
        case candidateCount = "candidate_count"
        case eligibleCount = "eligible_count"
        case policySummary = "policy_summary"
        case candidates
        case reportRef = "report_ref"
        case auditRef = "audit_ref"
        case createdAtMs = "created_at_ms"
    }
}

struct LaneWinnerScoringInput {
    let splitPlanID: String
    let launchedLaneIDs: [String]
    let worktreeLaneIDs: Set<String>
    let completedLaneIDs: Set<String>
    let lanePlansByID: [String: SupervisorLanePlan]
    let laneLaunchDecisions: [String: OneShotLaunchDecision]
    let coderLaneOutputs: [String: CoderLaneOutput]
    let laneReviewReports: [String: LaneReviewReport]
    let laneWorktreeMergebackReports: [String: LaneWorktreeMergebackReport]
    let manualOverrideLaneID: String
    let manualOverrideReason: String
    let reportRef: String
    let auditRef: String
    let createdAtMs: Int64

    init(
        splitPlanID: String,
        launchedLaneIDs: [String],
        worktreeLaneIDs: Set<String>,
        completedLaneIDs: Set<String>,
        lanePlansByID: [String: SupervisorLanePlan],
        laneLaunchDecisions: [String: OneShotLaunchDecision],
        coderLaneOutputs: [String: CoderLaneOutput],
        laneReviewReports: [String: LaneReviewReport],
        laneWorktreeMergebackReports: [String: LaneWorktreeMergebackReport],
        manualOverrideLaneID: String = "",
        manualOverrideReason: String = "",
        reportRef: String,
        auditRef: String,
        createdAtMs: Int64
    ) {
        self.splitPlanID = splitPlanID
        self.launchedLaneIDs = launchedLaneIDs
        self.worktreeLaneIDs = worktreeLaneIDs
        self.completedLaneIDs = completedLaneIDs
        self.lanePlansByID = lanePlansByID
        self.laneLaunchDecisions = laneLaunchDecisions
        self.coderLaneOutputs = coderLaneOutputs
        self.laneReviewReports = laneReviewReports
        self.laneWorktreeMergebackReports = laneWorktreeMergebackReports
        self.manualOverrideLaneID = manualOverrideLaneID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.manualOverrideReason = manualOverrideReason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reportRef = reportRef
        self.auditRef = auditRef
        self.createdAtMs = createdAtMs
    }
}

enum LaneWinnerScorer {
    static func score(input: LaneWinnerScoringInput) -> LaneWinnerScoreReport {
        let rawCandidates = input.launchedLaneIDs.map { laneID in
            scoreCandidate(laneID: laneID, input: input)
        }
        let sorted = rawCandidates.sorted { lhs, rhs in
            if lhs.eligibleForMergeback != rhs.eligibleForMergeback {
                return lhs.eligibleForMergeback && !rhs.eligibleForMergeback
            }
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.laneID.localizedCaseInsensitiveCompare(rhs.laneID) == .orderedAscending
        }
        let automaticRecommendedLaneID = sorted.first(where: \.eligibleForMergeback)?.laneID ?? ""
        let selection = selectedLane(
            automaticRecommendedLaneID: automaticRecommendedLaneID,
            candidates: sorted,
            manualOverrideLaneID: input.manualOverrideLaneID
        )
        let ranked = sorted.enumerated().map { index, candidate in
            LaneWinnerScoreCandidate(
                laneID: candidate.laneID,
                rank: index + 1,
                score: candidate.score,
                selected: selection.selectedCandidateLaneID == candidate.laneID,
                eligibleForMergeback: candidate.eligibleForMergeback,
                reviewVerdict: candidate.reviewVerdict,
                riskTier: candidate.riskTier,
                changedFileCount: candidate.changedFileCount,
                diagnosticsRunCount: candidate.diagnosticsRunCount,
                launchDenyCode: candidate.launchDenyCode,
                blockers: candidate.blockers,
                strengths: candidate.strengths,
                evidenceRefs: candidate.evidenceRefs,
                coderOutputRef: candidate.coderOutputRef,
                reviewReportRef: candidate.reviewReportRef,
                mergebackReportRef: candidate.mergebackReportRef,
                summary: candidate.summary
            )
        }
        let eligibleCount = ranked.filter(\.eligibleForMergeback).count
        let policySummary = [
            "reviewer_approved_required",
            "completed_worktree_required",
            "coder_output_required",
            "launch_policy_fail_closed",
            "mergeback_failures_penalized",
            "diff_size_and_diagnostics_weighted"
        ].joined(separator: ",")
        return LaneWinnerScoreReport(
            schemaVersion: LaneWinnerScoreReport.currentSchemaVersion,
            splitPlanID: input.splitPlanID,
            recommendedLaneID: selection.recommendedLaneID,
            automaticRecommendedLaneID: automaticRecommendedLaneID,
            manualOverrideLaneID: input.manualOverrideLaneID,
            manualOverrideReason: input.manualOverrideReason,
            selectionSource: selection.source,
            selectionBlockers: selection.blockers,
            candidateCount: ranked.count,
            eligibleCount: eligibleCount,
            policySummary: policySummary,
            candidates: ranked,
            reportRef: input.reportRef,
            auditRef: input.auditRef,
            createdAtMs: input.createdAtMs
        )
    }

    private static func selectedLane(
        automaticRecommendedLaneID: String,
        candidates: [LaneWinnerScoreCandidate],
        manualOverrideLaneID: String
    ) -> (recommendedLaneID: String, selectedCandidateLaneID: String, source: String, blockers: [String]) {
        guard let overrideLaneID = normalized(manualOverrideLaneID) else {
            return (
                recommendedLaneID: automaticRecommendedLaneID,
                selectedCandidateLaneID: automaticRecommendedLaneID,
                source: "auto_score",
                blockers: []
            )
        }

        guard let overrideCandidate = candidates.first(where: { $0.laneID == overrideLaneID }) else {
            return (
                recommendedLaneID: "",
                selectedCandidateLaneID: "",
                source: "manual_override_blocked",
                blockers: ["manual_override_lane_not_found"]
            )
        }

        guard overrideCandidate.eligibleForMergeback else {
            return (
                recommendedLaneID: "",
                selectedCandidateLaneID: overrideLaneID,
                source: "manual_override_blocked",
                blockers: normalizedStrings(["manual_override_ineligible"] + overrideCandidate.blockers)
            )
        }

        return (
            recommendedLaneID: overrideLaneID,
            selectedCandidateLaneID: overrideLaneID,
            source: "manual_override",
            blockers: []
        )
    }

    private static func scoreCandidate(
        laneID: String,
        input: LaneWinnerScoringInput
    ) -> LaneWinnerScoreCandidate {
        var score = 0
        var blockers: [String] = []
        var strengths: [String] = []
        var evidenceRefs: [String] = []

        let hasWorktree = input.worktreeLaneIDs.contains(laneID)
        if hasWorktree {
            score += 100
            strengths.append("worktree_prepared")
        } else {
            score -= 400
            blockers.append("worktree_missing")
        }

        let completed = input.completedLaneIDs.contains(laneID)
        if completed {
            score += 120
            strengths.append("lane_completed")
        } else {
            score -= 120
            blockers.append("lane_not_completed")
        }

        let launchDecision = input.laneLaunchDecisions[laneID]
        let launchDenyCode = normalized(launchDecision?.denyCode) ?? ""
        if let launchDecision,
           launchDecision.autoLaunchAllowed == false || launchDecision.decision != .allow {
            score -= 300
            blockers.append("launch_denied:\(launchDenyCode.isEmpty ? "unknown" : launchDenyCode)")
        } else {
            score += 60
            strengths.append("launch_policy_allowed")
        }

        let output = input.coderLaneOutputs[laneID]
        let changedFileCount = output?.changedFiles.count ?? 0
        let diagnosticsRunCount = output?.diagnosticsRunIDs.count ?? 0
        let coderOutputRef = output?.outputRef ?? ""
        if let output {
            score += 160
            evidenceRefs.append(output.outputRef)
            evidenceRefs.append(output.diffRef)
            evidenceRefs.append(contentsOf: output.artifactRefs)
            if changedFileCount == 0 {
                score -= 60
                blockers.append("changed_files_empty")
            } else if changedFileCount <= 4 {
                score += 80
                strengths.append("small_diff")
            } else if changedFileCount <= 12 {
                score += 40
                strengths.append("moderate_diff")
            } else {
                score -= min(120, (changedFileCount - 12) * 8)
                blockers.append("large_diff")
            }
            if diagnosticsRunCount > 0 {
                score += min(60, diagnosticsRunCount * 20)
                strengths.append("diagnostics_recorded")
            } else {
                score -= 20
            }
        } else {
            score -= 220
            blockers.append("coder_lane_output_missing")
        }

        let review = input.laneReviewReports[laneID]
        let reviewVerdict = review?.verdict.rawValue ?? "missing"
        let reviewReportRef = review?.reviewRef ?? ""
        if let review {
            evidenceRefs.append(review.reviewRef)
            evidenceRefs.append(review.coderOutputRef)
            evidenceRefs.append(contentsOf: review.evidenceRefs)
            switch review.verdict {
            case .approved:
                score += 320
                strengths.append("reviewer_approved")
            case .changesRequested:
                score -= 260
                blockers.append("reviewer_changes_requested")
            case .blocked:
                score -= 420
                blockers.append("reviewer_blocked")
            case .needsHuman:
                score -= 220
                blockers.append("reviewer_needs_human")
            }
            score += residualRiskScore(review.residualRisks, blockers: &blockers, strengths: &strengths)
        } else {
            score -= 220
            blockers.append("reviewer_verdict_missing")
        }

        let mergebackReport = input.laneWorktreeMergebackReports[laneID]
        let mergebackReportRef = mergebackReport?.reportRef ?? ""
        if let mergebackReport {
            evidenceRefs.append(mergebackReport.reportRef)
            evidenceRefs.append(mergebackReport.diffRef)
            if mergebackReport.pass {
                score += 120
                strengths.append("mergeback_previously_passed")
            } else if priorContractBlockResolved(
                reason: mergebackReport.blockedReason,
                output: output,
                review: review
            ) {
                score -= 20
                strengths.append("prior_contract_block_resolved")
            } else {
                score -= 500
                let reason = normalized(mergebackReport.blockedReason) ?? "unknown"
                blockers.append("mergeback_blocked:\(reason)")
            }
        }

        let riskTier = input.lanePlansByID[laneID]?.riskTier.rawValue ?? "unknown"
        switch input.lanePlansByID[laneID]?.riskTier {
        case .low:
            score += 40
        case .medium:
            score += 20
        case .high:
            score -= 30
            strengths.append("high_risk_reviewed")
        case .critical:
            score -= 80
            blockers.append("critical_risk_requires_human_attention")
        case nil:
            score -= 10
        }

        let eligible = hasWorktree
            && completed
            && output != nil
            && review?.verdict.allowsMergeback == true
            && !(launchDecision?.autoLaunchAllowed == false || launchDecision?.decision != .allow)
            && !(mergebackReport?.pass == false && !priorContractBlockResolved(
                reason: mergebackReport?.blockedReason,
                output: output,
                review: review
            ))

        return LaneWinnerScoreCandidate(
            laneID: laneID,
            rank: 0,
            score: score,
            selected: false,
            eligibleForMergeback: eligible,
            reviewVerdict: reviewVerdict,
            riskTier: riskTier,
            changedFileCount: changedFileCount,
            diagnosticsRunCount: diagnosticsRunCount,
            launchDenyCode: launchDenyCode,
            blockers: normalizedStrings(blockers),
            strengths: normalizedStrings(strengths),
            evidenceRefs: normalizedStrings(evidenceRefs),
            coderOutputRef: coderOutputRef,
            reviewReportRef: reviewReportRef,
            mergebackReportRef: mergebackReportRef,
            summary: output?.summary ?? review?.summary ?? ""
        )
    }

    private static func residualRiskScore(
        _ risks: [String],
        blockers: inout [String],
        strengths: inout [String]
    ) -> Int {
        let joined = risks.joined(separator: " ").lowercased()
        if joined.contains("critical") {
            blockers.append("critical_residual_risk")
            return -140
        }
        if joined.contains("high") {
            blockers.append("high_residual_risk")
            return -80
        }
        if joined.contains("medium") {
            return -20
        }
        if joined.contains("low") || joined.contains("none") {
            strengths.append("low_residual_risk")
            return 30
        }
        return 0
    }

    private static func priorContractBlockResolved(
        reason: String?,
        output: CoderLaneOutput?,
        review: LaneReviewReport?
    ) -> Bool {
        guard output != nil, review?.verdict.allowsMergeback == true else { return false }
        switch normalized(reason) {
        case "coder_lane_output_missing",
            "reviewer_verdict_missing",
            "reviewer_verdict_not_approved":
            return true
        default:
            return false
        }
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "none" ? nil : trimmed
    }

    private static func normalizedStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            guard let normalized = normalized(value), !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            output.append(normalized)
        }
        return output
    }
}
