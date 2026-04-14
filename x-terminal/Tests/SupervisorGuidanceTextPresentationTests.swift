import Testing
@testable import XTerminal

struct SupervisorGuidanceTextPresentationTests {

    @Test
    func summaryExtractsWrappedSummaryFromConcatenatedStructuredFields() {
        let text = "收到，我会按《Release Runtime》这条指导继续推进：verdict=watchsummary=当前没有待处理的 Hub 授权。effective_supervisor_tier=s3_strategic_coacheffective_work_order_depth=execution_readywork_order_ref=plan:plan-release-runtime-v1"

        let summary = SupervisorGuidanceTextPresentation.summary(
            text,
            maxChars: 200
        )

        #expect(summary == "当前没有待处理的 Hub 授权。")
    }

    @Test
    func fieldsParseWrappedStructuredUIReviewContractKeys() {
        let text = """
收到，我会按《Landing Repair》这条指导继续推进：source=ui_review_repair
ui_review_summary=Primary CTA is missing from the current screen.
repair_action=Expose the primary CTA
repair_focus=Landing hero actions
next_safe_action=repair_before_execution
"""

        let fields = SupervisorGuidanceTextPresentation.fields(text)

        #expect(fields["source"] == "ui_review_repair")
        #expect(fields["ui_review_summary"] == "Primary CTA is missing from the current screen.")
        #expect(fields["repair_action"] == "Expose the primary CTA")
        #expect(fields["repair_focus"] == "Landing hero actions")
        #expect(fields["next_safe_action"] == "repair_before_execution")
    }

    @Test
    func summaryHumanizesNextSafeActionWhenStructuredGuidanceOmitsSummary() {
        let text = """
verdict=watch
next_safe_action=repair_before_execution
effective_supervisor_tier=s3_strategic_coach
"""

        let summary = SupervisorGuidanceTextPresentation.summary(
            text,
            maxChars: 200
        )

        #expect(summary == "先完成当前修复，再继续执行")
    }

    @Test
    func actionDisplayTextHumanizesStructuredTokensForFrontstageSurfaces() {
        #expect(
            SupervisorGuidanceTextPresentation.actionDisplayText("open_candidate_review_board")
                == "打开候选记忆审查面板"
        )
        #expect(
            SupervisorGuidanceTextPresentation.actionDisplayText("approve hub grant")
                == "处理当前 Hub 授权"
        )
        #expect(
            SupervisorGuidanceTextPresentation.actionDisplayText("pause_lane")
                == "暂停当前泳道"
        )
    }

    @Test
    func actionDisplayTextCanIncludeRawTokenForChatAndLaneSummaries() {
        #expect(
            SupervisorGuidanceTextPresentation.actionDisplayText(
                "apply_supervisor_replan",
                includeRawToken: true
            ) == "先按当前重规划处理（apply_supervisor_replan）"
        )
        #expect(
            SupervisorGuidanceTextPresentation.actionDisplayText(
                "sync_remote_context",
                includeRawToken: true
            ) == "sync remote context（sync_remote_context）"
        )
    }

    @Test
    func actionsDisplayTextHumanizesMixedRecommendedActions() {
        let rendered = SupervisorGuidanceTextPresentation.actionsDisplayText([
            "stage_to_review",
            "Approve the pending hub grant"
        ])

        #expect(rendered == "转入审查 | Approve the pending hub grant")
    }
}
