import XCTest
@testable import RELFlowHub
@testable import RELFlowHubCore

final class HubMemoryRetrievalBuilderTests: XCTestCase {
    func testBuildReturnsRecentContextAndDecisionSnippetsForCurrentProject() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w335_memory_retrieval_\(UUID().uuidString)", isDirectory: true)
        let stateDir = projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try writeJSON(
            [
                "schema_version": 1,
                "updated_at": 123.0,
                "messages": [
                    ["role": "user", "content": "我们之前说过要先修付费模型 grant", "created_at": 1.0],
                    ["role": "assistant", "content": "你还提到 supervisor 默认只有最近几轮上下文", "created_at": 2.0],
                    ["role": "user", "content": "新的消息 1", "created_at": 3.0],
                    ["role": "assistant", "content": "新的消息 2", "created_at": 4.0],
                    ["role": "user", "content": "新的消息 3", "created_at": 5.0],
                    ["role": "assistant", "content": "新的消息 4", "created_at": 6.0],
                    ["role": "user", "content": "新的消息 5", "created_at": 7.0],
                    ["role": "assistant", "content": "新的消息 6", "created_at": 8.0],
                    ["role": "user", "content": "新的消息 7", "created_at": 9.0],
                    ["role": "assistant", "content": "新的消息 8", "created_at": 10.0],
                    ["role": "user", "content": "新的消息 9", "created_at": 11.0],
                    ["role": "assistant", "content": "新的消息 10", "created_at": 12.0],
                    ["role": "user", "content": "新的消息 11", "created_at": 13.0],
                    ["role": "assistant", "content": "新的消息 12", "created_at": 14.0],
                    ["role": "user", "content": "新的消息 13", "created_at": 15.0],
                    ["role": "assistant", "content": "新的消息 14", "created_at": 16.0],
                    ["role": "user", "content": "新的消息 15", "created_at": 17.0],
                    ["role": "assistant", "content": "新的消息 16", "created_at": 18.0]
                ]
            ],
            to: stateDir.appendingPathComponent("recent_context.json")
        )

        try writeJSON(
            [
                "schema_version": "xt.supervisor_decision_track.v1",
                "updated_at_ms": 456,
                "events": [
                    [
                        "schema_version": "xt.supervisor_decision_track_event.v1",
                        "decision_id": "decision-1",
                        "project_id": "project-1",
                        "category": "tech_stack",
                        "status": "approved",
                        "statement": "技术栈固定为 Swift + SwiftUI",
                        "source": "owner",
                        "reversible": true,
                        "approval_required": false,
                        "approved_by": "owner",
                        "audit_ref": "audit-1",
                        "evidence_refs": [],
                        "created_at_ms": 100,
                        "updated_at_ms": 200
                    ]
                ]
            ],
            to: stateDir.appendingPathComponent("supervisor_decision_track.json")
        )

        let response = HubMemoryRetrievalBuilder.build(
            from: IPCMemoryRetrievalRequestPayload(
                requestId: "memreq-xt-w335-1",
                scope: "current_project",
                requesterRole: "chat",
                mode: "project_chat",
                projectId: "project-1",
                projectRoot: projectRoot.path,
                displayName: "Project One",
                query: "你之前说过的 tech stack 决策是什么",
                latestUser: "你之前说过的 tech stack 决策是什么",
                allowedLayers: ["l1_canonical", "l2_observations"],
                retrievalKind: "search",
                maxResults: 3,
                reason: "project_chat_progressive_disclosure_seed",
                requireExplainability: true,
                requestedKinds: ["recent_context", "decision_track"],
                explicitRefs: [],
                maxSnippets: 3,
                maxSnippetChars: 240,
                auditRef: "audit-xt-memory-retrieval-1"
            )
        )

        XCTAssertNil(response.denyCode)
        XCTAssertEqual(response.schemaVersion, "xt.memory_retrieval_result.v1")
        XCTAssertEqual(response.requestId, "memreq-xt-w335-1")
        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.resolvedScope, "current_project")
        XCTAssertEqual(response.auditRef, "audit-xt-memory-retrieval-1")
        XCTAssertNotNil(response.budgetUsedChars)
        XCTAssertFalse(response.truncated ?? true)
        XCTAssertFalse(response.snippets.isEmpty)
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "recent_context" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "decision_track" }))
        XCTAssertEqual(response.results?.count, response.snippets.count)
        XCTAssertTrue(response.results?.contains(where: { $0.sourceKind == "decision_track" }) == true)
    }

    func testBuildHonorsAllowedLayersAndGetRefMode() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w335_memory_retrieval_layers_\(UUID().uuidString)", isDirectory: true)
        let stateDir = projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        try writeJSON(
            [
                "schema_version": 1,
                "updated_at": 123.0,
                "messages": [
                    ["role": "user", "content": "我们之前说过 grant", "created_at": 1.0]
                ]
            ],
            to: stateDir.appendingPathComponent("recent_context.json")
        )
        try writeJSON(
            [
                "schema_version": "xt.supervisor_decision_track.v1",
                "updated_at_ms": 456,
                "events": [
                    [
                        "schema_version": "xt.supervisor_decision_track_event.v1",
                        "decision_id": "decision-1",
                        "project_id": "project-1",
                        "category": "tech_stack",
                        "status": "approved",
                        "statement": "技术栈固定为 Swift + SwiftUI",
                        "source": "owner",
                        "reversible": true,
                        "approval_required": false,
                        "approved_by": "owner",
                        "audit_ref": "audit-1",
                        "evidence_refs": [],
                        "created_at_ms": 100,
                        "updated_at_ms": 200
                    ]
                ]
            ],
            to: stateDir.appendingPathComponent("supervisor_decision_track.json")
        )

        let response = HubMemoryRetrievalBuilder.build(
            from: IPCMemoryRetrievalRequestPayload(
                requestId: "memreq-xt-w335-2",
                scope: "current_project",
                requesterRole: "supervisor",
                mode: "supervisor_orchestration",
                projectId: "project-1",
                projectRoot: projectRoot.path,
                displayName: "Project One",
                query: "展开最近批准的决策",
                latestUser: "展开最近批准的决策",
                allowedLayers: ["l1_canonical"],
                retrievalKind: "get_ref",
                maxResults: 2,
                reason: "supervisor_focused_project_review",
                requireExplainability: true,
                requestedKinds: ["recent_context", "decision_track"],
                explicitRefs: [stateDir.appendingPathComponent("supervisor_decision_track.json").path],
                maxSnippets: 2,
                maxSnippetChars: 240,
                auditRef: "audit-xt-memory-retrieval-2"
            )
        )

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.requestId, "memreq-xt-w335-2")
        XCTAssertEqual(response.resolvedScope, "current_project")
        XCTAssertEqual(response.snippets.count, 1)
        XCTAssertEqual(response.snippets.first?.sourceKind, "decision_track")
        XCTAssertFalse(response.snippets.contains(where: { $0.sourceKind == "recent_context" }))
        XCTAssertEqual(response.results?.first?.sourceKind, "decision_track")
    }

    func testBuildReturnsGovernedCodingRuntimeTruthSnippetsForCurrentProject() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w4_memory_runtime_truth_\(UUID().uuidString)", isDirectory: true)
        let stateDir = projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
        let reportsDir = projectRoot.appendingPathComponent("build/reports", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let checkpointURL = reportsDir.appendingPathComponent("xt_w3_25_run_checkpoint_2.v1.json")
        let handoffURL = reportsDir.appendingPathComponent("xt_automation_run_handoff_run-1.v1.json")
        let retryURL = reportsDir.appendingPathComponent("xt_automation_retry_package_run-1-retry.v1.json")
        let guidanceURL = stateDir.appendingPathComponent("supervisor_guidance_injections.json")
        let heartbeatURL = stateDir.appendingPathComponent("heartbeat_memory_projection.json")

        try writeJSON(
            [
                "schema_version": "xt.automation_run_checkpoint.v1",
                "run_id": "run-1",
                "recipe_id": "recipe-1",
                "state": "blocked",
                "attempt": 2,
                "last_transition": "blocked",
                "retry_after_seconds": 120,
                "resume_token": "resume-1",
                "checkpoint_ref": checkpointURL.path,
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "audit_ref": "audit-checkpoint-1"
            ],
            to: checkpointURL
        )
        try writeJSON(
            [
                "schema_version": "xt.automation_run_handoff.v1",
                "generated_at": 123.0,
                "run_id": "run-1",
                "recipe_ref": "recipe://run-1",
                "delivery_ref": "build/reports/delivery-card.v1.json",
                "final_state": "blocked",
                "hold_reason": "automation_verify_failed",
                "detail": "Smoke tests are still red.",
                "action_results": [],
                "verification_report": [
                    "required": true,
                    "executed": true,
                    "command_count": 3,
                    "passed_command_count": 1,
                    "hold_reason": "automation_verify_failed"
                ],
                "suggested_next_actions": [
                    "shrink verify scope",
                    "re-run smoke tests"
                ],
                "structured_blocker": [
                    "code": "automation_verify_failed",
                    "summary": "Smoke tests are still red.",
                    "stage": "verification",
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ],
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting before retrying the reduced verify set."
            ],
            to: handoffURL
        )
        try writeJSON(
            [
                "schema_version": "xt.automation_retry_package.v1",
                "generated_at": 124.0,
                "project_id": "project-runtime",
                "delivery_ref": "build/reports/delivery-card.v1.json",
                "source_run_id": "run-1",
                "source_final_state": "blocked",
                "source_hold_reason": "automation_verify_failed",
                "source_handoff_artifact_path": handoffURL.path,
                "source_blocker": [
                    "code": "automation_verify_failed",
                    "summary": "Smoke tests are still red.",
                    "stage": "verification",
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ],
                "retry_strategy": "shrink_verify_scope",
                "retry_reason": "automation_verify_failed",
                "retry_reason_descriptor": [
                    "code": "retry_verify_scope",
                    "summary": "Retry with a reduced verify set",
                    "strategy": "shrink_verify_scope",
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ],
                "planning_mode": "verification_recovery",
                "planning_summary": "Retry with a reduced verify scope before escalating.",
                "retry_run_id": "run-1-retry",
                "retry_artifact_path": retryURL.path
            ],
            to: retryURL
        )
        try writeJSON(
            [
                "schema_version": "xt.supervisor_guidance_injection_snapshot.v1",
                "updated_at_ms": 900,
                "items": [
                    [
                        "schema_version": "xt.supervisor_guidance_injection.v1",
                        "injection_id": "guidance-1",
                        "review_id": "review-1",
                        "project_id": "project-runtime",
                        "target_role": "coder",
                        "delivery_mode": "priority_insert",
                        "intervention_mode": "replan_next_safe_point",
                        "safe_point_policy": "next_step_boundary",
                        "guidance_text": "Pause the broader rollout and reduce the verify scope before the next retry.",
                        "ack_status": "pending",
                        "ack_required": true,
                        "effective_supervisor_tier": "s3_strategic_coach",
                        "work_order_ref": "xt-w4-guidance",
                        "ack_note": "",
                        "injected_at_ms": 880,
                        "ack_updated_at_ms": 880,
                        "audit_ref": "audit-guidance-1"
                    ]
                ]
            ],
            to: guidanceURL
        )
        try writeJSON(
            [
                "schema_version": "xt.heartbeat_memory_projection.v1",
                "project_id": "project-runtime",
                "project_root": projectRoot.path,
                "project_name": "Runtime Project",
                "created_at_ms": 950,
                "raw_vault_ref": stateDir.appendingPathComponent("raw_log.jsonl").path,
                "raw_payload": [
                    "status_digest": "Blocked on smoke tests",
                    "current_state_summary": "Verification failed after patch",
                    "next_step_summary": "Retry with reduced verify scope",
                    "blocker_summary": "Smoke tests are still red.",
                    "latest_quality_band": "medium",
                    "latest_quality_score": 62,
                    "execution_status": "blocked",
                    "risk_tier": "medium",
                    "recovery_decision": [
                        "action": "queue_strategic_review",
                        "urgency": "active",
                        "reason_code": "blocker_detected",
                        "summary": "Queue a strategic review before retrying.",
                        "queued_review_trigger": "blocker_detected",
                        "queued_review_level": "r2_strategic",
                        "queued_review_run_kind": "event_driven"
                    ]
                ],
                "canonical_projection": [
                    "audit_ref": "audit-heartbeat-canonical-1"
                ]
            ],
            to: heartbeatURL
        )

        let response = HubMemoryRetrievalBuilder.build(
            from: IPCMemoryRetrievalRequestPayload(
                requestId: "memreq-xt-w4-runtime",
                scope: "current_project",
                requesterRole: "supervisor",
                mode: "supervisor_orchestration",
                projectId: "project-runtime",
                projectRoot: projectRoot.path,
                displayName: "Runtime Project",
                query: "当前 blocker、retry plan、latest guidance 和 heartbeat 是什么",
                latestUser: "当前 blocker、retry plan、latest guidance 和 heartbeat 是什么",
                allowedLayers: ["l1_canonical", "l2_observations"],
                retrievalKind: "search",
                maxResults: 6,
                reason: "supervisor_runtime_truth_review",
                requireExplainability: true,
                requestedKinds: [
                    "automation_execution_report",
                    "automation_checkpoint",
                    "automation_retry_package",
                    "guidance_injection",
                    "heartbeat_projection"
                ],
                explicitRefs: [],
                maxSnippets: 6,
                maxSnippetChars: 1200,
                auditRef: "audit-xt-memory-runtime-1"
            )
        )

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.requestId, "memreq-xt-w4-runtime")
        XCTAssertEqual(response.resolvedScope, "current_project")
        XCTAssertEqual(response.auditRef, "audit-xt-memory-runtime-1")
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "automation_execution_report" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "automation_checkpoint" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "automation_retry_package" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "guidance_injection" }))
        XCTAssertTrue(response.snippets.contains(where: { $0.sourceKind == "heartbeat_projection" }))
        XCTAssertTrue(response.results?.contains(where: { $0.sourceKind == "guidance_injection" && $0.ref.contains("supervisor_guidance_injections.json") }) == true)
        XCTAssertTrue(response.results?.contains(where: { $0.sourceKind == "automation_execution_report" && $0.ref.contains("xt_automation_run_handoff_run-1.v1.json") }) == true)
    }

    func testBuildSupportsExplicitGovernedCodingArtifactRefsWithFragments() throws {
        let projectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_w4_memory_runtime_ref_\(UUID().uuidString)", isDirectory: true)
        let reportsDir = projectRoot.appendingPathComponent("build/reports", isDirectory: true)
        try FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: projectRoot) }

        let checkpointURL = reportsDir.appendingPathComponent("xt_w3_25_run_checkpoint_3.v1.json")
        try writeJSON(
            [
                "schema_version": "xt.automation_run_checkpoint.v1",
                "run_id": "run-explicit",
                "recipe_id": "recipe-explicit",
                "state": "retry_wait",
                "attempt": 3,
                "last_transition": "retry_wait",
                "retry_after_seconds": 45,
                "resume_token": "resume-explicit",
                "checkpoint_ref": checkpointURL.path,
                "stable_identity": true,
                "current_step_id": "step-explicit",
                "current_step_title": "Wait for retry window",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting for retry_after to elapse.",
                "audit_ref": "audit-checkpoint-explicit"
            ],
            to: checkpointURL
        )

        let response = HubMemoryRetrievalBuilder.build(
            from: IPCMemoryRetrievalRequestPayload(
                requestId: "memreq-xt-w4-explicit",
                scope: "current_project",
                requesterRole: "supervisor",
                mode: "supervisor_orchestration",
                projectId: "project-runtime",
                projectRoot: projectRoot.path,
                displayName: "Runtime Project",
                query: "展开 checkpoint ref",
                latestUser: "展开 checkpoint ref",
                allowedLayers: ["l1_canonical", "l2_observations"],
                retrievalKind: "get_ref",
                maxResults: 1,
                reason: "supervisor_runtime_truth_ref_read",
                requireExplainability: true,
                requestedKinds: ["automation_checkpoint"],
                explicitRefs: [checkpointURL.path + "#run:run-explicit"],
                maxSnippets: 1,
                maxSnippetChars: 480,
                auditRef: "audit-xt-memory-runtime-2"
            )
        )

        XCTAssertEqual(response.status, "ok")
        XCTAssertEqual(response.snippets.count, 1)
        XCTAssertEqual(response.snippets.first?.sourceKind, "automation_checkpoint")
        XCTAssertEqual(response.results?.first?.sourceKind, "automation_checkpoint")
        XCTAssertTrue(response.results?.first?.ref.contains("xt_w3_25_run_checkpoint_3.v1.json") == true)
    }

    private func writeJSON(_ object: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
