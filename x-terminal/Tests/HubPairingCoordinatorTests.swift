import Foundation
import Testing
@testable import XTerminal

struct HubPairingCoordinatorTests {
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
        {"ok":true,"text":"hello","model_id":"qwen3-17b-mlx-bf16","requested_model_id":"gpt-5.4","actual_model_id":"qwen3-17b-mlx-bf16","runtime_provider":"Hub (Local)","execution_path":"hub_downgraded_to_local","fallback_reason_code":"downgrade_to_local","reason":"eos"}
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
    }
}
