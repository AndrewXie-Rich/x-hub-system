import Foundation

struct SupervisorUIReviewRepairGuidance: Equatable, Sendable {
    var actionCode: String
    var focusArea: String
    var summary: String
    var prompt: String
}

enum SupervisorUIReviewRepairPlanner {
    static func guidance(
        for snapshot: XTUIReviewAgentEvidenceSnapshot
    ) -> SupervisorUIReviewRepairGuidance? {
        guidance(
            verdict: snapshot.verdict,
            sufficientEvidence: snapshot.sufficientEvidence,
            objectiveReady: snapshot.objectiveReady,
            issueCodes: snapshot.issueCodes,
            trend: snapshot.trend
        )
    }

    static func guidance(
        verdict: XTUIReviewVerdict?,
        sufficientEvidence: Bool?,
        objectiveReady: Bool?,
        issueCodes: [String],
        trend: [String] = []
    ) -> SupervisorUIReviewRepairGuidance? {
        let normalizedIssues = Set(
            issueCodes.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }.filter { !$0.isEmpty && $0 != "(none)" }
        )
        let hasRegression = trend.contains {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .contains("status=regressed")
        }

        if normalizedIssues.contains("critical_action_not_visible") {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "repair_primary_cta_visibility",
                focusArea: "critical_action",
                summary: "Repair primary CTA visibility before continuing browser automation.",
                prompt: "Restore a visible primary CTA for the current objective, rerun UI review, then resume automation."
            )
        }

        if normalizedIssues.contains("interactive_target_missing") {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "repair_interactive_target_exposure",
                focusArea: "interactive_target",
                summary: "Expose the missing interactive target before continuing browser automation.",
                prompt: "Restore the missing button, link, or input needed for the next step, rerun UI review, then resume automation."
            )
        }

        if verdict == .insufficientEvidence || sufficientEvidence == false {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "stabilize_ui_review_evidence",
                focusArea: "ui_probe",
                summary: "Stabilize the page and gather stronger UI evidence before continuing automation.",
                prompt: "Wait for the target page to fully render or adjust the probe path, rerun UI review, then continue only when evidence is sufficient."
            )
        }

        if objectiveReady == false {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "repair_objective_path",
                focusArea: "objective_path",
                summary: "Repair the current objective path before continuing browser automation.",
                prompt: "Fix the current UI flow so the intended task can be completed end-to-end, rerun UI review, then resume automation."
            )
        }

        if hasRegression {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "review_recent_ui_regression",
                focusArea: "regression",
                summary: "Investigate the recent UI regression before continuing browser automation.",
                prompt: "Compare the last good UI state with the current regressed state, repair the regression, rerun UI review, then resume automation."
            )
        }

        if verdict == .attentionNeeded {
            return SupervisorUIReviewRepairGuidance(
                actionCode: "repair_ui_flow_before_resume",
                focusArea: "ui_flow",
                summary: "Repair the current UI flow before continuing browser automation.",
                prompt: "Resolve the blocking UI issue for the current task, rerun UI review, then continue automation."
            )
        }

        return nil
    }
}
