import Foundation
import Testing
@testable import XTerminal

struct LaneWinnerScoringTests {
    @Test
    func scorerPrefersReviewerApprovedEligibleLaneOverChangesRequestedLane() {
        let outputA = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: "lane-a",
            role: "coder",
            projectID: "project",
            changedFiles: ["Sources/A.swift"],
            diffRef: ".xterminal/diffs/lane-a.patch",
            diagnosticsRunIDs: ["diag-a"],
            artifactRefs: [],
            summary: "Small implementation.",
            outputRef: ".xterminal/lane-output/lane-a.json",
            auditRef: "audit-output-a",
            createdAtMs: 1
        )
        let outputB = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: "lane-b",
            role: "coder",
            projectID: "project",
            changedFiles: ["Sources/B.swift", "Tests/BTests.swift"],
            diffRef: ".xterminal/diffs/lane-b.patch",
            diagnosticsRunIDs: ["diag-b-1", "diag-b-2"],
            artifactRefs: [],
            summary: "Reviewed implementation.",
            outputRef: ".xterminal/lane-output/lane-b.json",
            auditRef: "audit-output-b",
            createdAtMs: 2
        )
        let reviewA = LaneReviewReport(
            schemaVersion: LaneReviewReport.currentSchemaVersion,
            laneID: "lane-a",
            role: "reviewer",
            reviewerID: "reviewer",
            verdict: .changesRequested,
            summary: "Needs changes.",
            issues: ["coverage_gap"],
            recommendedActions: ["repair"],
            residualRisks: ["medium"],
            evidenceRefs: [outputA.outputRef, outputA.diffRef],
            coderOutputRef: outputA.outputRef,
            reviewRef: ".xterminal/lane-review/lane-a.json",
            auditRef: "audit-review-a",
            createdAtMs: 3
        )
        let reviewB = LaneReviewReport(
            schemaVersion: LaneReviewReport.currentSchemaVersion,
            laneID: "lane-b",
            role: "reviewer",
            reviewerID: "reviewer",
            verdict: .approved,
            summary: "Approved for mergeback.",
            issues: [],
            recommendedActions: ["mergeback"],
            residualRisks: ["low"],
            evidenceRefs: [outputB.outputRef, outputB.diffRef],
            coderOutputRef: outputB.outputRef,
            reviewRef: ".xterminal/lane-review/lane-b.json",
            auditRef: "audit-review-b",
            createdAtMs: 4
        )
        let allowA = OneShotLaunchDecision(
            laneID: "lane-a",
            decision: .allow,
            denyCode: "none",
            blockedReason: nil,
            note: "allowed",
            autoLaunchAllowed: true,
            failClosed: false,
            requiresHumanTouch: false
        )
        let allowB = OneShotLaunchDecision(
            laneID: "lane-b",
            decision: .allow,
            denyCode: "none",
            blockedReason: nil,
            note: "allowed",
            autoLaunchAllowed: true,
            failClosed: false,
            requiresHumanTouch: false
        )

        let report = LaneWinnerScorer.score(
            input: LaneWinnerScoringInput(
                splitPlanID: "split-plan",
                launchedLaneIDs: ["lane-a", "lane-b"],
                worktreeLaneIDs: ["lane-a", "lane-b"],
                completedLaneIDs: ["lane-a", "lane-b"],
                lanePlansByID: [:],
                laneLaunchDecisions: [
                    "lane-a": allowA,
                    "lane-b": allowB,
                ],
                coderLaneOutputs: [
                    "lane-a": outputA,
                    "lane-b": outputB,
                ],
                laneReviewReports: [
                    "lane-a": reviewA,
                    "lane-b": reviewB,
                ],
                laneWorktreeMergebackReports: [:],
                reportRef: ".xterminal/lane-winner/split-plan.json",
                auditRef: "audit-score",
                createdAtMs: 5
            )
        )

        #expect(report.schemaVersion == LaneWinnerScoreReport.currentSchemaVersion)
        #expect(report.recommendedLaneID == "lane-b")
        #expect(report.automaticRecommendedLaneID == "lane-b")
        #expect(report.selectionSource == "auto_score")
        #expect(report.manualOverrideLaneID == "")
        #expect(report.selectionBlockers.isEmpty)
        #expect(report.eligibleCount == 1)
        #expect(report.candidates.first?.laneID == "lane-b")
        #expect(report.candidates.first?.selected == true)
        #expect(report.candidates.first?.reviewVerdict == "approved")
        #expect(report.candidates.first(where: { $0.laneID == "lane-a" })?.blockers.contains("reviewer_changes_requested") == true)
    }

    @Test
    func scorerHonorsEligibleManualOverrideWithoutBypassingReviewerGate() {
        let outputA = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: "lane-a",
            role: "coder",
            projectID: "project",
            changedFiles: ["Sources/A.swift"],
            diffRef: ".xterminal/diffs/lane-a.patch",
            diagnosticsRunIDs: ["diag-a"],
            artifactRefs: [],
            summary: "Smaller approved implementation.",
            outputRef: ".xterminal/lane-output/lane-a.json",
            auditRef: "audit-output-a",
            createdAtMs: 1
        )
        let outputB = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: "lane-b",
            role: "coder",
            projectID: "project",
            changedFiles: ["Sources/B.swift"],
            diffRef: ".xterminal/diffs/lane-b.patch",
            diagnosticsRunIDs: ["diag-b", "diag-b-2"],
            artifactRefs: [],
            summary: "Higher score approved implementation.",
            outputRef: ".xterminal/lane-output/lane-b.json",
            auditRef: "audit-output-b",
            createdAtMs: 2
        )
        let reviewA = approvedReview(laneID: "lane-a", output: outputA, createdAtMs: 3)
        let reviewB = approvedReview(laneID: "lane-b", output: outputB, createdAtMs: 4)
        let allowA = allowedLaunch(laneID: "lane-a")
        let allowB = allowedLaunch(laneID: "lane-b")

        let report = LaneWinnerScorer.score(
            input: LaneWinnerScoringInput(
                splitPlanID: "split-plan",
                launchedLaneIDs: ["lane-a", "lane-b"],
                worktreeLaneIDs: ["lane-a", "lane-b"],
                completedLaneIDs: ["lane-a", "lane-b"],
                lanePlansByID: [:],
                laneLaunchDecisions: [
                    "lane-a": allowA,
                    "lane-b": allowB,
                ],
                coderLaneOutputs: [
                    "lane-a": outputA,
                    "lane-b": outputB,
                ],
                laneReviewReports: [
                    "lane-a": reviewA,
                    "lane-b": reviewB,
                ],
                laneWorktreeMergebackReports: [:],
                manualOverrideLaneID: "lane-a",
                manualOverrideReason: "operator_selected_smaller_diff",
                reportRef: ".xterminal/lane-winner/split-plan.json",
                auditRef: "audit-score",
                createdAtMs: 5
            )
        )

        #expect(report.automaticRecommendedLaneID == "lane-b")
        #expect(report.recommendedLaneID == "lane-a")
        #expect(report.manualOverrideLaneID == "lane-a")
        #expect(report.manualOverrideReason == "operator_selected_smaller_diff")
        #expect(report.selectionSource == "manual_override")
        #expect(report.selectionBlockers.isEmpty)
        #expect(report.candidates.first(where: { $0.laneID == "lane-a" })?.selected == true)
    }

    @Test
    func scorerFailClosesIneligibleManualOverride() {
        let output = CoderLaneOutput(
            schemaVersion: CoderLaneOutput.currentSchemaVersion,
            laneID: "lane-a",
            role: "coder",
            projectID: "project",
            changedFiles: ["Sources/A.swift"],
            diffRef: ".xterminal/diffs/lane-a.patch",
            diagnosticsRunIDs: ["diag-a"],
            artifactRefs: [],
            summary: "Needs review changes.",
            outputRef: ".xterminal/lane-output/lane-a.json",
            auditRef: "audit-output-a",
            createdAtMs: 1
        )
        let review = LaneReviewReport(
            schemaVersion: LaneReviewReport.currentSchemaVersion,
            laneID: "lane-a",
            role: "reviewer",
            reviewerID: "reviewer",
            verdict: .changesRequested,
            summary: "Needs changes.",
            issues: ["coverage_gap"],
            recommendedActions: ["repair"],
            residualRisks: ["medium"],
            evidenceRefs: [output.outputRef, output.diffRef],
            coderOutputRef: output.outputRef,
            reviewRef: ".xterminal/lane-review/lane-a.json",
            auditRef: "audit-review-a",
            createdAtMs: 2
        )

        let report = LaneWinnerScorer.score(
            input: LaneWinnerScoringInput(
                splitPlanID: "split-plan",
                launchedLaneIDs: ["lane-a"],
                worktreeLaneIDs: ["lane-a"],
                completedLaneIDs: ["lane-a"],
                lanePlansByID: [:],
                laneLaunchDecisions: ["lane-a": allowedLaunch(laneID: "lane-a")],
                coderLaneOutputs: ["lane-a": output],
                laneReviewReports: ["lane-a": review],
                laneWorktreeMergebackReports: [:],
                manualOverrideLaneID: "lane-a",
                manualOverrideReason: "operator_requested",
                reportRef: ".xterminal/lane-winner/split-plan.json",
                auditRef: "audit-score",
                createdAtMs: 3
            )
        )

        #expect(report.recommendedLaneID == "")
        #expect(report.automaticRecommendedLaneID == "")
        #expect(report.selectionSource == "manual_override_blocked")
        #expect(report.selectionBlockers.contains("manual_override_ineligible"))
        #expect(report.selectionBlockers.contains("reviewer_changes_requested"))
        #expect(report.candidates.first?.selected == true)
    }

    private func allowedLaunch(laneID: String) -> OneShotLaunchDecision {
        OneShotLaunchDecision(
            laneID: laneID,
            decision: .allow,
            denyCode: "none",
            blockedReason: nil,
            note: "allowed",
            autoLaunchAllowed: true,
            failClosed: false,
            requiresHumanTouch: false
        )
    }

    private func approvedReview(
        laneID: String,
        output: CoderLaneOutput,
        createdAtMs: Int64
    ) -> LaneReviewReport {
        LaneReviewReport(
            schemaVersion: LaneReviewReport.currentSchemaVersion,
            laneID: laneID,
            role: "reviewer",
            reviewerID: "reviewer",
            verdict: .approved,
            summary: "Approved.",
            issues: [],
            recommendedActions: ["mergeback"],
            residualRisks: ["low"],
            evidenceRefs: [output.outputRef, output.diffRef],
            coderOutputRef: output.outputRef,
            reviewRef: ".xterminal/lane-review/\(laneID).json",
            auditRef: "audit-review-\(laneID)",
            createdAtMs: createdAtMs
        )
    }
}
