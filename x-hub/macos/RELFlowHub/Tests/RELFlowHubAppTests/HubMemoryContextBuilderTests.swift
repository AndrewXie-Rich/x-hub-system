import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubMemoryContextBuilderTests: XCTestCase {
    func testProjectChatMarksProgressiveDisclosureAndRetrievalAvailability() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "project_chat",
                projectId: "project-ctx",
                projectRoot: "/tmp/project-ctx",
                displayName: "Project Context",
                latestUser: "你之前怎么定 tech stack 的",
                constitutionHint: "真实透明",
                canonicalText: "goal: keep current project memory thin",
                observationsText: "decision track landed",
                workingSetText: "ask for history if summary is insufficient",
                rawEvidenceText: "build/reports/example.json",
                servingProfile: "m2_plan_review",
                budgets: nil
            )
        )

        XCTAssertEqual(response.longtermMode, "progressive_disclosure")
        XCTAssertEqual(response.retrievalAvailable, true)
        XCTAssertEqual(response.fulltextNotLoaded, true)
        XCTAssertTrue(response.text.contains("[LONGTERM_MEMORY]"))
        XCTAssertTrue(response.text.contains("longterm_mode=progressive_disclosure"))
        XCTAssertTrue(response.text.contains("retrieval_available=true"))
        XCTAssertTrue(response.text.contains("fulltext_not_loaded=true"))
    }

    func testSupervisorSectionsAreElevatedIntoTopLevelMemoryObjects() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "supervisor_orchestration",
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "审查这个项目并给我下一步",
                constitutionHint: "真实透明",
                dialogueWindowText: """
                window_profile: standard_12_pairs
                raw_window_floor_pairs: 8
                raw_window_ceiling_pairs: 12
                raw_window_selected_pairs: 9
                eligible_messages: 18
                low_signal_dropped_messages: 0
                raw_window_source: xt_cache
                continuity_floor_satisfied: true
                truncation_after_floor: false
                raw_messages:
                - user: 继续推进当前项目
                - assistant: 收到，我先看 blocker
                """,
                portfolioBriefText: "managed_projects: 2\nfocus_candidate_project: 项目A",
                focusedProjectAnchorPackText: "project_id: project-a\ngoal: 把核心链路走通\ndone_definition: 主链可验证",
                longtermOutlineText: "project: 项目A (project-a)\nstrategic_milestones:\n- active: 打通主链",
                deltaFeedText: "material_change_flags: focused_project, action_ledger",
                conflictSetText: "- conflict_id: conflict-1\n  conflict_kind: decision_vs_guidance\n  summary: 决策与新 guidance 存在冲突",
                contextRefsText: "- ref_id=review:1 ref_kind=observation_ref title=latest review source_scope=review_note token_cost_hint=medium freshness_hint=fresh",
                evidencePackText: "evidence_goal: verify latest guidance before replan\nselected_items:\n- ref_id=review:1 title=latest review source_scope=review_note freshness=fresh why_included=latest_supervisor_verdict excerpt=verdict=better_path_found",
                canonicalText: "stable_scope: repo-bound",
                observationsText: "recent_event: plan updated",
                workingSetText: "recent_message: fix compile error",
                rawEvidenceText: "build/reports/supervisor.json",
                servingProfile: "m2_plan_review",
                budgets: nil
            )
        )

        XCTAssertTrue(response.text.contains("[DIALOGUE_WINDOW]"))
        XCTAssertTrue(response.text.contains("raw_window_selected_pairs: 9"))
        XCTAssertTrue(response.text.contains("raw_messages:"))
        XCTAssertTrue(response.text.contains("- assistant: 收到，我先看 blocker"))
        XCTAssertTrue(response.text.contains("[PORTFOLIO_BRIEF]"))
        XCTAssertTrue(response.text.contains("focus_candidate_project: 项目A"))
        XCTAssertTrue(response.text.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        XCTAssertTrue(response.text.contains("done_definition: 主链可验证"))
        XCTAssertTrue(response.text.contains("[LONGTERM_OUTLINE]"))
        XCTAssertTrue(response.text.contains("strategic_milestones:"))
        XCTAssertTrue(response.text.contains("[DELTA_FEED]"))
        XCTAssertTrue(response.text.contains("material_change_flags: focused_project, action_ledger"))
        XCTAssertTrue(response.text.contains("[CONFLICT_SET]"))
        XCTAssertTrue(response.text.contains("decision_vs_guidance"))
        XCTAssertTrue(response.text.contains("[CONTEXT_REFS]"))
        XCTAssertTrue(response.text.contains("source_scope=review_note"))
        XCTAssertTrue(response.text.contains("[EVIDENCE_PACK]"))
        XCTAssertTrue(response.text.contains("why_included=latest_supervisor_verdict"))
        XCTAssertTrue(response.text.contains("[L1_CANONICAL]"))
        XCTAssertTrue(response.text.contains("stable_scope: repo-bound"))
    }

    func testSupervisorServingGovernorAlignsMinimumPackWithStrategicReviewLevel() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "supervisor_orchestration",
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "请做战略纠偏，确认是不是该改路",
                reviewLevelHint: "r2_strategic",
                constitutionHint: "真实透明",
                portfolioBriefText: "managed_projects: 2\nfocus_candidate_project: 项目A",
                focusedProjectAnchorPackText: "project_id: project-a\ngoal: 稳定推进主链\ndone_definition: 主链验证通过",
                longtermOutlineText: "project: 项目A (project-a)\nstrategic_milestones:\n- active: 稳定主链",
                deltaFeedText: "material_change_flags: focused_project, blocker_delta",
                conflictSetText: "- conflict_id: conflict-1\n  conflict_kind: decision_vs_guidance\n  summary: 当前 guidance 建议改路",
                contextRefsText: "- ref_id=review:1 ref_kind=observation_ref title=latest review source_scope=review_note token_cost_hint=medium freshness_hint=fresh",
                evidencePackText: "evidence_goal: verify latest review\nselected_items:\n- ref_id=review:1 title=latest review source_scope=review_note freshness=fresh why_included=latest_supervisor_verdict excerpt=verdict=better_path_found",
                canonicalText: "stable_scope: repo-bound",
                observationsText: "recent_event: plan updated",
                workingSetText: "recent_message: check drift",
                rawEvidenceText: "build/reports/supervisor-governor.json",
                servingProfile: "m1_execute",
                budgets: nil
            )
        )

        XCTAssertTrue(response.text.contains("[SERVING_GOVERNOR]"))
        XCTAssertTrue(response.text.contains("review_level_hint: r2_strategic"))
        XCTAssertTrue(response.text.contains("profile_floor: m3_deep_dive"))
        XCTAssertTrue(
            response.text.contains(
                "minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs, evidence_pack"
            )
        )
        XCTAssertTrue(response.text.contains("[LONGTERM_OUTLINE]"))
        XCTAssertTrue(response.text.contains("[CONFLICT_SET]"))
        XCTAssertTrue(response.text.contains("[CONTEXT_REFS]"))
        XCTAssertTrue(response.text.contains("[EVIDENCE_PACK]"))
    }

    func testSupervisorStrategicReviewWithoutFocusedAnchorKeepsM2Floor() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "supervisor_orchestration",
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "请做战略纠偏，先看整体上下文再定下一步",
                reviewLevelHint: "r2_strategic",
                constitutionHint: "真实透明",
                portfolioBriefText: "managed_projects: 2\nfocus_candidate_project: (none)",
                focusedProjectAnchorPackText: "",
                longtermOutlineText: "project: (none)\nstrategic_milestones:\n- active: review portfolio state",
                deltaFeedText: "material_change_flags: portfolio_review",
                conflictSetText: "- conflict_id: conflict-portfolio-1\n  conflict_kind: runtime_vs_memory\n  summary: 需要先确认 portfolio 级冲突",
                contextRefsText: "- ref_id=portfolio:1 ref_kind=canonical_ref title=portfolio snapshot source_scope=portfolio_brief token_cost_hint=low freshness_hint=fresh",
                evidencePackText: "",
                canonicalText: "stable_scope: portfolio",
                observationsText: "recent_event: strategic review requested",
                workingSetText: "recent_message: check overall drift",
                rawEvidenceText: "build/reports/supervisor-governor-m2.json",
                servingProfile: "m1_execute",
                budgets: nil
            )
        )

        XCTAssertTrue(response.text.contains("[SERVING_GOVERNOR]"))
        XCTAssertTrue(response.text.contains("review_level_hint: r2_strategic"))
        XCTAssertTrue(response.text.contains("profile_floor: m2_plan_review"))
        XCTAssertTrue(
            response.text.contains(
                "minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs"
            )
        )
        XCTAssertFalse(response.text.contains("minimum_pack: portfolio_brief, focused_project_anchor_pack, longterm_outline, delta_feed, conflict_set, context_refs, evidence_pack"))
        XCTAssertTrue(response.text.contains("compression_policy: protect_anchor_conflict_longterm_then_refs"))
    }

    func testSupervisorServingObjectsUseObjectAwareCompressionMetadataWhenBudgetsAreTight() {
        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "supervisor_orchestration",
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "review and decide next step",
                constitutionHint: "真实透明",
                portfolioBriefText: """
                managed_projects: 6
                active_projects: 4
                blocked_projects: 3
                focus_candidate_project: project-a
                priority_order:
                1. project-a runtime=running next=finish verification matrix blocker=external dependency outage
                2. project-b runtime=running next=stabilize cache invalidation blocker=qa signal drift
                3. project-c runtime=paused next=prepare migration rollback blocker=release cut window
                4. project-d runtime=running next=finish operator docs blocker=staffing
                5. project-e runtime=running next=close onboarding audit blocker=feishu review queue
                6. project-f runtime=paused next=prepare smoke report blocker=budget cap
                top_blocked_projects:
                - project-a blocker=external dependency outage next=finish verification matrix
                - project-b blocker=qa signal drift next=stabilize cache invalidation
                - project-c blocker=release cut window next=prepare migration rollback
                - project-f blocker=budget cap next=prepare smoke report
                """,
                focusedProjectAnchorPackText: """
                focus_source: explicit_user_mention
                project: project-a (project-a-id)
                memory_source: local_project_memory
                runtime_state: running
                goal: keep the release train stable while preserving the approved migration boundary
                done_definition: pass the release gate before any phase-two migration change enters execution
                constraints:
                - non_goals: do not expand scope into phase-two migration before the release gate is green
                - approved_tech_stack: swiftui | hub memory | governed operator channels
                - autonomy_guard: configured=assisted, effective=assisted, override=none, kill_switch=no
                approved_decisions:
                - scope_freeze=keep migration order unchanged until release verification completes
                - architecture=operator channels stay hub-side and do not bypass governance
                longterm_outline:
                project: project-a (project-a-id)
                goal: keep the release train stable while preserving the approved migration boundary
                done_definition: pass the release gate before any phase-two migration change enters execution
                stable_constraints:
                - non_goals: do not expand scope
                - approved_tech_stack: swiftui | hub memory
                strategic_milestones:
                - active: finish release hardening
                - queued: prepare migration resumption plan
                durable_decisions:
                - scope_freeze=keep migration order unchanged until release verification completes
                background_memory:
                keep the release track boring, verified, and reversible
                source_tags: spec, review, governance
                background_hints:
                migration remains strategically valid, but only after release verification closes the current risk window
                governance:
                configured=assisted effective=assisted override=none ttl_remaining_sec=1200
                latest_review_note:
                review_id: review-1
                memory_cursor: review:review-1@1773720000000
                project_state_hash: sha256:before
                portfolio_state_hash: sha256:portfolio-before
                trigger: manual_request
                review_level: r2_strategic
                verdict: better_path_found
                delivery: coder/replan_request ack_required=true
                summary: keep verification first and delay migration reordering until the gate is green
                recommended_actions: finish verification matrix | re-open migration sequence only after blocker clears
                latest_guidance_injection:
                injection_id: guidance-1
                review_id: review-1
                delivery: coder/replan_request
                intervention_mode: replan_next_safe_point
                safe_point_policy: next_step_boundary
                ack_status: pending
                ack_required: true
                ack_note: (none)
                guidance_text: hold migration change until release verification clears
                pending_ack_guidance:
                injection_id: guidance-1
                review_id: review-1
                delivery: coder/replan_request
                intervention_mode: replan_next_safe_point
                safe_point_policy: next_step_boundary
                ack_status: pending
                ack_required: true
                ack_note: (none)
                guidance_text: hold migration change until release verification clears
                missing_anchor_fields: (none)
                current_state: verification is running but blocked by external dependency outage
                next_step: finish verification matrix and clear dependency outage
                blocker: external dependency outage
                active_job_id: job-release-hardening
                active_job_goal: keep the release train stable
                active_job_status: running
                active_plan_id: plan-release-hardening
                active_plan_status: running
                active_plan_steps:
                - step-001 finish verification matrix
                - step-002 confirm rollback package
                - step-003 re-evaluate migration sequence
                next_pending_steps:
                - step-002 confirm rollback package
                - step-003 re-evaluate migration sequence
                attention_steps:
                - step-001 finish verification matrix
                - step-004 clear dependency outage
                active_skill_request_id: skill-call-1
                active_skill_id: governed.browser.read
                active_skill_status: awaiting_authorization
                active_skill_result_summary: waiting for authorization to read external runbook
                recent_relevant_messages:
                - user: keep the release safe and do not let migration noise take over
                - assistant: verification must stay first until the dependency outage is cleared
                - user: if there is a better plan, explain the switching cost
                - assistant: hold the migration order and close verification first
                """,
                longtermOutlineText: """
                project: project-a (project-a-id)
                goal: keep the release train stable while preserving the approved migration boundary
                done_definition: pass the release gate before any phase-two migration change enters execution
                stable_constraints:
                - non_goals: do not expand scope into phase-two migration before the release gate is green
                - approved_tech_stack: swiftui | hub memory | governed operator channels
                - tech_stack_blacklist: direct uncontrolled external calls
                strategic_milestones:
                - active: finish release hardening
                - queued: prepare migration resumption plan
                - queued: re-open operator-channel expansion after release gate
                durable_decisions:
                - scope_freeze=keep migration order unchanged until release verification completes
                - review_style=prefer low churn unless evidence forces replan
                background_memory:
                longterm strategy is to reopen migration only after release verification proves the system is boring and reversible again
                source_tags: spec, review, governance, release
                """,
                deltaFeedText: """
                cursor_from: review:review-1@1773720000000
                cursor_to: memory_build:1773723600000
                focus_project: project-a
                focus_project_id: project-a-id
                project_state_hash_before: sha256:before
                project_state_hash_after: sha256:after
                portfolio_state_hash_before: sha256:portfolio-before
                portfolio_state_hash_after: sha256:portfolio-after
                material_change_flags: focused_project, workflow, guidance, blocker_delta, recent_events
                user_intent_hint: review and decide whether the project needs strategic correction or should keep the current strategy
                delta_items:
                - [progress_delta] current_state: before=verification planned after=verification running but blocked by dependency outage
                - [progress_delta] next_step: before=prepare verification matrix after=finish verification matrix and clear dependency outage
                - [blocker_delta] blocker: before=(none) after=external dependency outage
                - [guidance_delta] guidance updated: ack_status=pending delivery=replan_request intervention=replan_next_safe_point
                - [progress_delta] plan focus narrowed: verification stays first and migration sequence remains frozen
                focused_project_delta:
                focused_project_anchor_pack: source=explicit_user_mention project=project-a-id job=job-release-hardening plan=plan-release-hardening blocker=external dependency outage next=finish verification matrix and clear dependency outage
                workflow_delta:
                workflow currently reports running, but safe-point guidance says migration sequence changes must wait until verification closes
                recent_project_actions:
                - [progress_delta] finish verification matrix -> confirm rollback package
                - [blocker_delta] dependency outage escalated -> wait for external service recovery
                - [guidance_delta] pending ack remains open -> replan at next safe point
                recent_events:
                review cursor advanced after latest strategic note
                guidance ack remains pending in project lane
                external dependency outage reopened verification risk
                recent_actions:
                - [progress_delta] plan_update target=project-a status=running reason=workflow_sync
                - [grant_delta] browser_read target=project-a status=awaiting_authorization reason=authorization_required
                - [verification_delta] release_gate target=project-a status=running reason=verification_window_open
                """,
                conflictSetText: """
                - conflict_id: conflict-1
                  conflict_kind: decision_vs_guidance
                  summary: latest guidance asks for a replan while the approved decision still says keep the migration order unchanged until release verification completes
                  side_a: approved_decision=keep migration order unchanged until release verification completes
                  side_b: guidance=replan the migration order immediately before full release verification
                  resolution_status: open
                  refs: decision://1 | guidance://1
                - conflict_id: conflict-2
                  conflict_kind: runtime_vs_memory
                  summary: workflow still reports running while the latest blocker says the external dependency is unavailable and retry should pause
                  side_a: runtime_state=running
                  side_b: blocker=external dependency unavailable and retry should pause
                  resolution_status: watch
                  refs: workflow://1 | blocker://1
                - conflict_id: conflict-3
                  conflict_kind: longterm_vs_recent_execution
                  summary: recent execution notes propose a new done definition that is wider than the approved longterm objective for this release
                  side_a: longterm_done_definition=pass release gate
                  side_b: execution_done_definition=finish release plus begin migration phase two
                  resolution_status: open
                  refs: longterm://1 | execution://1
                """,
                contextRefsText: """
                - ref_id=spec://project-a ref_kind=canonical_ref title=spec capsule for release hardening and migration boundary freeze source_scope=spec_capsule token_cost_hint=medium freshness_hint=fresh
                - ref_id=decision://1 ref_kind=canonical_ref title=approved decision about migration order and release verification source_scope=decision_track token_cost_hint=medium freshness_hint=fresh
                - ref_id=review://1 ref_kind=observation_ref title=latest strategic review with next correction path source_scope=review_note token_cost_hint=medium freshness_hint=recent
                - ref_id=guidance://1 ref_kind=workflow_ref title=latest guidance injection pending acknowledgement from project lane source_scope=guidance_injection token_cost_hint=medium freshness_hint=recent
                - ref_id=workflow://1 ref_kind=workflow_ref title=active workflow plan and pending steps for release hardening source_scope=workflow_plan token_cost_hint=low freshness_hint=recent
                """,
                evidencePackText: """
                evidence_goal: verify the approved release anchor, latest strategic review, and pending guidance before changing the project strategy
                selected_items:
                - ref_id=spec://project-a title=spec capsule source_scope=spec_capsule freshness=fresh why_included=stable_goal_and_done_definition excerpt=goal=keep release train stable | done_definition=pass release gate | non_goals=do not begin phase two migration before release verification completes
                - ref_id=review://1 title=latest review source_scope=review_note freshness=recent why_included=latest_supervisor_verdict excerpt=verdict=better_path_found | summary=re-sequence the work so verification stays first and migration changes happen only after the gate is green
                - ref_id=guidance://1 title=latest guidance source_scope=guidance_injection freshness=recent why_included=active_guidance_guardrail_pending_ack excerpt=ack_status=pending | delivery=replan_request | guidance=hold the migration change until the current blocker is cleared and the release gate is green
                - ref_id=workflow://1 title=active workflow source_scope=workflow_plan freshness=recent why_included=active_workflow_state excerpt=job=release-hardening | goal=keep the release train stable | next_pending=finish verification matrix | attention=external dependency outage
                truncated_items: 0
                redacted_items: 0
                audit_ref: audit://supervisor-evidence-project-a
                """,
                canonicalText: "stable_scope: repo-bound",
                observationsText: "recent_event: plan updated",
                workingSetText: "recent_message: fix compile error",
                rawEvidenceText: "build/reports/supervisor-tight-budget.json",
                servingProfile: "m1_execute",
                budgets: IPCMemoryContextBudgets(
                    totalTokens: 1_000,
                    l0Tokens: 60,
                    l1Tokens: 220,
                    l2Tokens: 140,
                    l3Tokens: 260,
                    l4Tokens: 180
                )
            )
        )

        XCTAssertTrue(response.text.contains("[PORTFOLIO_BRIEF]\ncompression_reason:"))
        XCTAssertTrue(response.text.contains("priority_order_items="))
        XCTAssertTrue(response.text.contains("[FOCUSED_PROJECT_ANCHOR_PACK]\ncompression_reason:"))
        XCTAssertTrue(response.text.contains("recent_relevant_messages"))
        XCTAssertTrue(response.text.contains("[LONGTERM_OUTLINE]\ncompression_reason:"))
        XCTAssertTrue(response.text.contains("strategic_milestones_items=") || response.text.contains("source_tags=1"))
        XCTAssertTrue(response.text.contains("[DELTA_FEED]\ncompression_reason:"))
        XCTAssertTrue(response.text.contains("delta_items=") || response.text.contains("recent_events=1"))
        XCTAssertTrue(response.text.contains("[CONFLICT_SET]"))
        XCTAssertTrue(response.text.contains("compression_reason:"))
        XCTAssertTrue(response.text.contains("drop_tail_conflicts"))
        XCTAssertTrue(response.text.contains("dropped_items:"))
        XCTAssertTrue(response.text.contains("dropped_fields: 0"))
        XCTAssertTrue(response.text.contains("[CONTEXT_REFS]"))
        XCTAssertTrue(response.text.contains("drop_low_priority_fields"))
        XCTAssertTrue(response.text.contains("dropped_fields: freshness_hint="))
        XCTAssertTrue(response.text.contains("[EVIDENCE_PACK]"))
        XCTAssertTrue(response.text.contains("drop_low_priority_fields"))
        XCTAssertTrue(response.text.contains("dropped_fields: excerpt="))
    }

    func testDialogueWindowCompressionPreservesRecentRawFloorBeforeDroppingToClipFallback() {
        func makeDialogueLine(_ role: String, turn: Int) -> String {
            let payload = String(repeating: "\(role)-\(turn)-continuity ", count: 2)
            return "- \(role): \(payload)"
        }

        let rawMessages = (1...12).flatMap { turn in
            [
                makeDialogueLine("user", turn: turn),
                makeDialogueLine("assistant", turn: turn)
            ]
        }.joined(separator: "\n")

        let response = HubMemoryContextBuilder.build(
            from: IPCMemoryContextRequestPayload(
                mode: "supervisor_orchestration",
                projectId: nil,
                projectRoot: nil,
                displayName: "Supervisor",
                latestUser: "继续推进当前项目",
                constitutionHint: "真实透明",
                dialogueWindowText: """
                window_profile: standard_12_pairs
                raw_window_floor_pairs: 8
                raw_window_ceiling_pairs: 12
                raw_window_selected_pairs: 12
                eligible_messages: 24
                low_signal_dropped_messages: 0
                raw_window_source: mixed
                continuity_floor_satisfied: true
                truncation_after_floor: false
                current_turn_refs:
                - turn_mode=project_first
                - focused_project=项目A
                - focused_project_id=project-a
                recent_user_intent:
                - 继续推进当前项目
                - 先看 blocker，再决定是否重排
                recent_assistant_commitments:
                - 我会先看 blocker，再决定下一步
                - 如果需要改路，我会先解释切换成本
                raw_messages:
                \(rawMessages)
                rolling_dialogue_digest:
                source_eligible_messages: 8
                source_pairs: 4
                continuity_points:
                - user -> earlier-turn
                - assistant -> earlier-commitment
                - user -> switch-cost-question
                focused_project_recent_dialogue_recovery:
                - user: earlier project recovery
                - assistant: earlier project recovery acknowledgement
                """,
                portfolioBriefText: "managed_projects: 1\nfocus_candidate_project: 项目A",
                focusedProjectAnchorPackText: "project: 项目A (project-a)\ngoal: keep the current execution aligned",
                longtermOutlineText: "",
                deltaFeedText: "material_change_flags: focused_project",
                conflictSetText: "",
                contextRefsText: "",
                evidencePackText: "",
                canonicalText: "stable_scope: repo-bound",
                observationsText: "recent_event: plan updated",
                workingSetText: "recent_message: keep recent raw first",
                rawEvidenceText: "build/reports/supervisor-dialogue-floor.json",
                servingProfile: "m1_execute",
                budgets: nil
            )
        )

        let dialogueWindow = try! XCTUnwrap(
            Self.extractSection("DIALOGUE_WINDOW", from: response.text)
        )
        let rawMessageLines = dialogueWindow
            .split(separator: "\n")
            .map(String.init)
            .filter { $0.hasPrefix("- user: ") || $0.hasPrefix("- assistant: ") }

        XCTAssertTrue(dialogueWindow.contains("compression_reason:"))
        XCTAssertTrue(dialogueWindow.contains("raw_window_floor_pairs: 8"))
        XCTAssertTrue(dialogueWindow.contains("raw_window_selected_pairs: 8"))
        XCTAssertTrue(dialogueWindow.contains("continuity_floor_satisfied: true"))
        XCTAssertTrue(dialogueWindow.contains("truncation_after_floor: true"))
        XCTAssertEqual(rawMessageLines.count, 16)
        XCTAssertFalse(dialogueWindow.contains("rolling_dialogue_digest:"))
        XCTAssertFalse(dialogueWindow.contains("focused_project_recent_dialogue_recovery:"))
        XCTAssertFalse(dialogueWindow.contains("user-1-continuity"))
        XCTAssertTrue(dialogueWindow.contains("user-5-continuity"))
        XCTAssertTrue(dialogueWindow.contains("assistant-12-continuity"))
    }

    private static func extractSection(_ tag: String, from text: String) -> String? {
        guard let start = text.range(of: "[\(tag)]") else { return nil }
        guard let end = text.range(of: "[/\(tag)]", range: start.upperBound..<text.endIndex) else {
            return nil
        }
        return String(text[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
