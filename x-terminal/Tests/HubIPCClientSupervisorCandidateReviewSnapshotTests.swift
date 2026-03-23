import Foundation
import Testing
@testable import XTerminal

struct HubIPCClientSupervisorCandidateReviewSnapshotTests {
    @Test
    func requestSupervisorCandidateReviewSnapshotReadsLocalSnapshotAndFiltersProject() async throws {
        let originalMode = HubAIClient.transportMode()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt_hub_supervisor_candidate_review_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        HubAIClient.setTransportMode(.fileIPC)
        HubPaths.setPinnedBaseDirOverride(base)
        defer {
            HubAIClient.setTransportMode(originalMode)
            HubPaths.clearPinnedBaseDirOverride()
            try? FileManager.default.removeItem(at: base)
        }

        let payload: [String: Any] = [
            "schema_version": "supervisor_candidate_review_status.v1",
            "updated_at_ms": 1_773_420_090_000,
            "items": [
                [
                    "schema_version": "xhub.supervisor_candidate_review_item.v1",
                    "review_id": "sup_cand_review:device:x_terminal:req-older",
                    "request_id": "req-older",
                    "evidence_ref": "candidate_carrier_request:req-older",
                    "review_state": "pending_review",
                    "durable_promotion_state": "not_promoted",
                    "promotion_boundary": "candidate_carrier_only",
                    "device_id": "device-a",
                    "user_id": "user-a",
                    "app_id": "x_terminal",
                    "thread_id": "thread-1",
                    "thread_key": "shadow-thread-1",
                    "project_id": "project-a",
                    "project_ids": ["project-a"],
                    "scopes": ["project_scope"],
                    "record_types": ["project_blocker"],
                    "audit_refs": ["audit-older"],
                    "idempotency_keys": ["sha256:older"],
                    "candidate_count": 1,
                    "summary_line": "single blocker handoff",
                    "mirror_target": "hub_candidate_carrier_shadow_thread",
                    "local_store_role": "cache|fallback|edit_buffer",
                    "carrier_kind": "supervisor_after_turn_durable_candidate_shadow_write",
                    "carrier_schema_version": "xt.supervisor.durable_candidate_mirror.v1",
                    "pending_change_id": "",
                    "pending_change_status": "",
                    "edit_session_id": "",
                    "doc_id": "",
                    "writeback_ref": "",
                    "stage_created_at_ms": 0,
                    "stage_updated_at_ms": 0,
                    "latest_emitted_at_ms": 1_773_420_010_000,
                    "created_at_ms": 1_773_420_009_000,
                    "updated_at_ms": 1_773_420_010_500,
                ],
                [
                    "schema_version": "xhub.supervisor_candidate_review_item.v1",
                    "review_id": "sup_cand_review:device:x_terminal:req-mixed",
                    "request_id": "req-mixed",
                    "evidence_ref": "candidate_carrier_request:req-mixed",
                    "review_state": "draft_staged",
                    "durable_promotion_state": "not_promoted",
                    "promotion_boundary": "longterm_markdown_pending_change",
                    "device_id": "device-a",
                    "user_id": "user-a",
                    "app_id": "x_terminal",
                    "thread_id": "thread-2",
                    "thread_key": "shadow-thread-2",
                    "project_id": "",
                    "project_ids": ["project-a", "project-b"],
                    "scopes": ["user_scope", "project_scope"],
                    "record_types": ["preferred_name", "project_blocker"],
                    "audit_refs": ["audit-mixed-a", "audit-mixed-b"],
                    "idempotency_keys": ["sha256:mixed-a", "sha256:mixed-b"],
                    "candidate_count": 2,
                    "summary_line": "user_scope, project_scope",
                    "mirror_target": "hub_candidate_carrier_shadow_thread",
                    "local_store_role": "cache|fallback|edit_buffer",
                    "carrier_kind": "supervisor_after_turn_durable_candidate_shadow_write",
                    "carrier_schema_version": "xt.supervisor.durable_candidate_mirror.v1",
                    "pending_change_id": "chg-1",
                    "pending_change_status": "draft",
                    "edit_session_id": "edit-1",
                    "doc_id": "longterm:project-a",
                    "writeback_ref": "",
                    "stage_created_at_ms": 1_773_420_070_000,
                    "stage_updated_at_ms": 1_773_420_071_000,
                    "latest_emitted_at_ms": 1_773_420_080_000,
                    "created_at_ms": 1_773_420_060_000,
                    "updated_at_ms": 1_773_420_081_000,
                ],
                [
                    "schema_version": "xhub.supervisor_candidate_review_item.v1",
                    "review_id": "sup_cand_review:device:x_terminal:req-other",
                    "request_id": "req-other",
                    "evidence_ref": "candidate_carrier_request:req-other",
                    "review_state": "pending_review",
                    "durable_promotion_state": "not_promoted",
                    "promotion_boundary": "candidate_carrier_only",
                    "device_id": "device-a",
                    "user_id": "user-a",
                    "app_id": "x_terminal",
                    "thread_id": "thread-3",
                    "thread_key": "shadow-thread-3",
                    "project_id": "project-b",
                    "project_ids": ["project-b"],
                    "scopes": ["project_scope"],
                    "record_types": ["project_blocker"],
                    "audit_refs": ["audit-other"],
                    "idempotency_keys": ["sha256:other"],
                    "candidate_count": 1,
                    "summary_line": "other project",
                    "mirror_target": "hub_candidate_carrier_shadow_thread",
                    "local_store_role": "cache|fallback|edit_buffer",
                    "carrier_kind": "supervisor_after_turn_durable_candidate_shadow_write",
                    "carrier_schema_version": "xt.supervisor.durable_candidate_mirror.v1",
                    "pending_change_id": "",
                    "pending_change_status": "",
                    "edit_session_id": "",
                    "doc_id": "",
                    "writeback_ref": "",
                    "stage_created_at_ms": 0,
                    "stage_updated_at_ms": 0,
                    "latest_emitted_at_ms": 1_773_420_085_000,
                    "created_at_ms": 1_773_420_084_000,
                    "updated_at_ms": 1_773_420_086_000,
                ],
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        try data.write(to: base.appendingPathComponent("supervisor_candidate_review_status.json"), options: .atomic)

        let snapshot = await HubIPCClient.requestSupervisorCandidateReviewSnapshot(projectId: "project-a", limit: 10)
        let resolved = try #require(snapshot)

        #expect(resolved.source == "hub_supervisor_candidate_review_file")
        #expect(resolved.updatedAtMs == 1_773_420_090_000)
        #expect(resolved.items.count == 2)
        #expect(resolved.items.map(\.requestId) == ["req-mixed", "req-older"])
        #expect(resolved.items.first?.projectIds == ["project-a", "project-b"])
        #expect(resolved.items.first?.reviewState == "draft_staged")
        #expect(resolved.items.first?.pendingChangeId == "chg-1")
        #expect(resolved.items.first?.candidateCount == 2)
        #expect(resolved.items.last?.projectId == "project-a")
    }
}
