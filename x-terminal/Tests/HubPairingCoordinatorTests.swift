import Foundation
import Testing
@testable import XTerminal

struct HubPairingCoordinatorTests {
    @Test
    func normalizedRemoteReasonCodeCollapsesRawGRPCUnavailable() {
        let reason = HubPairingCoordinator.normalizedRemoteReasonCodeForTesting(
            "14_UNAVAILABLE:_No_connection_established._Last_error:_null._Resolution_note:"
        )

        #expect(reason == "grpc_unavailable")
    }

    @Test
    func normalizedRemoteReasonCodePreservesCanonicalTokens() {
        let reason = HubPairingCoordinator.normalizedRemoteReasonCodeForTesting("grant_required")
        #expect(reason == "grant_required")
    }

    @Test
    func reusableInternetHostSkipsCorporateLanAddressWhenHubIdentityIsKnown() {
        let host = HubPairingCoordinator.inferredReusableInternetHostForTesting(
            "17.81.12.12",
            hubInstanceID: "hub_deadbeefcafefeed00",
            lanDiscoveryName: "axhub-edge-bj"
        )

        #expect(host == nil)
    }

    @Test
    func remoteGenerateSuccessPreservesReturnedModelId() {
        let json = """
        {"ok":true,"text":"hello","model_id":"openai/gpt-5.3-codex","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "openai/gpt-4.1"
        )

        #expect(result?.ok == true)
        #expect(result?.text == "hello")
        #expect(result?.modelId == "openai/gpt-5.3-codex")
    }

    @Test
    func remoteGenerateSuccessFallsBackToRequestedModelIdWhenPayloadOmitsIt() {
        let json = """
        {"ok":true,"text":"hello","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "openai/gpt-5.3-codex"
        )

        #expect(result?.ok == true)
        #expect(result?.text == "hello")
        #expect(result?.modelId == "openai/gpt-5.3-codex")
    }

    @Test
    func remoteGenerateSuccessPreservesExecutionMetadata() {
        let json = """
        {"ok":true,"text":"hello","model_id":"qwen3-17b-mlx-bf16","requested_model_id":"gpt-5.4","actual_model_id":"qwen3-17b-mlx-bf16","runtime_provider":"Hub (Local)","execution_path":"hub_downgraded_to_local","fallback_reason_code":"downgrade_to_local","audit_ref":"audit-route-1","deny_code":"credential_finding","reason":"eos"}
        """

        let result = HubPairingCoordinator.remoteGenerateResultForTesting(
            jsonLine: json,
            requestedModelId: "gpt-5.4"
        )

        #expect(result?.ok == true)
        #expect(result?.requestedModelId == "gpt-5.4")
        #expect(result?.actualModelId == "qwen3-17b-mlx-bf16")
        #expect(result?.runtimeProvider == "Hub (Local)")
        #expect(result?.executionPath == "hub_downgraded_to_local")
        #expect(result?.fallbackReasonCode == "downgrade_to_local")
        #expect(result?.auditRef == "audit-route-1")
        #expect(result?.denyCode == "credential_finding")
    }

    @Test
    func remoteSupervisorCandidateReviewQueueResultParsesRequestLevelSnapshot() {
        let json = """
        {"ok":true,"source":"hub_runtime_grpc","updated_at_ms":1773420090000,"items":[{"schema_version":"xhub.supervisor_candidate_review_item.v1","review_id":"sup_cand_review:device:x_terminal:req-1","request_id":"req-1","evidence_ref":"candidate_carrier_request:req-1","review_state":"pending_review","durable_promotion_state":"not_promoted","promotion_boundary":"candidate_carrier_only","device_id":"device-a","user_id":"user-a","app_id":"x_terminal","thread_id":"thread-1","thread_key":"shadow-thread","project_id":"project-a","project_ids":["project-a"],"scopes":["project_scope"],"record_types":["project_blocker"],"audit_refs":["audit-1"],"idempotency_keys":["sha256:req-1"],"candidate_count":2,"summary_line":"project_scope","mirror_target":"hub_candidate_carrier_shadow_thread","local_store_role":"cache|fallback|edit_buffer","carrier_kind":"supervisor_after_turn_durable_candidate_shadow_write","carrier_schema_version":"xt.supervisor.durable_candidate_mirror.v1","pending_change_id":"","pending_change_status":"","edit_session_id":"","doc_id":"","writeback_ref":"","stage_created_at_ms":0,"stage_updated_at_ms":0,"latest_emitted_at_ms":1773420080000,"created_at_ms":1773420079000,"updated_at_ms":1773420081000}]}
        """

        let result = HubPairingCoordinator.remoteSupervisorCandidateReviewQueueResultForTesting(jsonLine: json)

        #expect(result?.ok == true)
        #expect(result?.updatedAtMs == 1_773_420_090_000)
        #expect(result?.items.count == 1)
        #expect(result?.items.first?.requestId == "req-1")
        #expect(result?.items.first?.reviewState == "pending_review")
        #expect(result?.items.first?.candidateCount == 2)
        #expect(result?.items.first?.projectIds == ["project-a"])
    }

    @Test
    func remoteSupervisorCandidateReviewStageResultParsesDraftMetadata() {
        let json = """
        {"ok":true,"source":"hub_memory_v1_grpc","staged":true,"idempotent":false,"review_state":"draft_staged","durable_promotion_state":"not_promoted","promotion_boundary":"longterm_markdown_pending_change","candidate_request_id":"req-1","evidence_ref":"candidate_carrier_request:req-1","edit_session_id":"edit-1","pending_change_id":"chg-1","doc_id":"longterm:project-a","base_version":"v1","working_version":"v2","session_revision":3,"status":"draft","markdown":"# Supervisor Candidate Review Handoff","created_at_ms":1773420082000,"updated_at_ms":1773420083000,"expires_at_ms":1773423683000}
        """

        let result = HubPairingCoordinator.remoteSupervisorCandidateReviewStageResultForTesting(jsonLine: json)

        #expect(result?.ok == true)
        #expect(result?.staged == true)
        #expect(result?.idempotent == false)
        #expect(result?.reviewState == "draft_staged")
        #expect(result?.promotionBoundary == "longterm_markdown_pending_change")
        #expect(result?.pendingChangeId == "chg-1")
        #expect(result?.sessionRevision == 3)
        #expect(result?.status == "draft")
    }
}
