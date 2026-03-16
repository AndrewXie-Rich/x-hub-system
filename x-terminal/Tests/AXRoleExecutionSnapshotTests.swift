import Foundation
import Testing
@testable import XTerminal

struct AXRoleExecutionSnapshotTests {
    @Test
    func latestSnapshotPrefersNewestExecutionMetadata() throws {
        let usageText = """
        {"type":"ai_usage","created_at":10,"role":"coder","requested_model_id":"openai/gpt-5.2","actual_model_id":"qwen3-17b-mlx-bf16","runtime_provider":"Hub (Local)","execution_path":"local_fallback_after_remote_error","fallback_reason_code":"model_not_found"}
        {"type":"ai_usage","created_at":20,"role":"coder","requested_model_id":"openai/gpt-5.4","actual_model_id":"openai/gpt-5.4","runtime_provider":"Hub (Remote)","execution_path":"remote_model"}
        {"type":"ai_usage","created_at":15,"role":"reviewer","requested_model_id":"openai/gpt-5.2","actual_model_id":"openai/gpt-5.2","runtime_provider":"Hub (Remote)","execution_path":"remote_model"}
        """

        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(fromUsageText: usageText)
        let coder = try #require(snapshots[.coder])
        let reviewer = try #require(snapshots[.reviewer])

        #expect(coder.requestedModelId == "openai/gpt-5.4")
        #expect(coder.actualModelId == "openai/gpt-5.4")
        #expect(coder.runtimeProvider == "Hub (Remote)")
        #expect(coder.executionPath == "remote_model")

        #expect(reviewer.requestedModelId == "openai/gpt-5.2")
        #expect(reviewer.actualModelId == "openai/gpt-5.2")
    }

    @Test
    func latestSnapshotPreservesHubDowngradedToLocalPath() throws {
        let usageText = """
        {"type":"ai_usage","created_at":42,"role":"coder","requested_model_id":"gpt-5.4","actual_model_id":"qwen3-17b-mlx-bf16","runtime_provider":"Hub (Local)","execution_path":"hub_downgraded_to_local","fallback_reason_code":"downgrade_to_local"}
        """

        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(fromUsageText: usageText)
        let coder = try #require(snapshots[.coder])

        #expect(coder.executionPath == "hub_downgraded_to_local")
        #expect(coder.statusLabel == "Downgraded")
        #expect(coder.compactSummary.contains("requested=gpt-5.4"))
        #expect(coder.compactSummary.contains("actual=qwen3-17b-mlx-bf16"))
    }

    @Test
    func latestSnapshotPreservesRemoteRetryMetadata() throws {
        let usageText = """
        {"type":"ai_usage","created_at":50,"role":"coder","requested_model_id":"openai/gpt-5.4","actual_model_id":"openai/gpt-4.1","runtime_provider":"Hub (Remote)","execution_path":"remote_model","remote_retry_attempted":true,"remote_retry_from_model_id":"openai/gpt-5.4","remote_retry_to_model_id":"openai/gpt-4.1","remote_retry_reason_code":"model_not_found"}
        """

        let snapshots = AXRoleExecutionSnapshots.latestSnapshots(fromUsageText: usageText)
        let coder = try #require(snapshots[.coder])

        #expect(coder.remoteRetryAttempted)
        #expect(coder.remoteRetryFromModelId == "openai/gpt-5.4")
        #expect(coder.remoteRetryToModelId == "openai/gpt-4.1")
        #expect(coder.remoteRetryReasonCode == "model_not_found")
        #expect(coder.compactSummary.contains("remote_retry=openai/gpt-5.4->openai/gpt-4.1"))
        #expect(coder.detailedSummary.contains("remote_retry_attempted=true"))
    }
}
