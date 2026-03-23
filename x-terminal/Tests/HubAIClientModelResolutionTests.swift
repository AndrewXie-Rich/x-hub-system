import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
struct HubAIClientModelResolutionTests {
    @Test
    func bareConfiguredModelIdResolvesToUniqueSuffixMatch() {
        let models = [
            HubModel(
                id: "openai/gpt-5.3-codex",
                name: "GPT 5.3 Codex",
                backend: "openai",
                quant: "n/a",
                contextLength: 200_000,
                paramsB: 0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: nil
            ),
        ]

        let resolved = HubAIClient.normalizeConfiguredModelID("gpt-5.3-codex", availableModels: models)
        #expect(resolved == "openai/gpt-5.3-codex")
    }

    @Test
    func exactConfiguredModelIdIsKept() {
        let models = [
            HubModel(
                id: "openai/gpt-5-low",
                name: "gpt-5-low",
                backend: "openai",
                quant: "n/a",
                contextLength: 200_000,
                paramsB: 0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: nil
            ),
        ]

        let resolved = HubAIClient.normalizeConfiguredModelID("openai/gpt-5-low", availableModels: models)
        #expect(resolved == "openai/gpt-5-low")
    }

    @Test
    func ambiguousBareConfiguredModelIdStaysUnchanged() {
        let models = [
            HubModel(
                id: "openai/gpt-5-low",
                name: "gpt-5-low",
                backend: "openai",
                quant: "n/a",
                contextLength: 200_000,
                paramsB: 0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: nil
            ),
            HubModel(
                id: "custom/gpt-5-low",
                name: "custom gpt-5-low",
                backend: "custom_openai",
                quant: "n/a",
                contextLength: 128_000,
                paramsB: 0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: nil
            ),
        ]

        let resolved = HubAIClient.normalizeConfiguredModelID("gpt-5-low", availableModels: models)
        #expect(resolved == "gpt-5-low")
    }

    @Test
    func projectAutoRouteGetsRemoteBackupModelWhenFamilyFallbackIsLoaded() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
                    backend: "openai",
                    quant: "n/a",
                    contextLength: 200_000,
                    paramsB: 0,
                    roles: nil,
                    state: .available,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: nil
                ),
                HubModel(
                    id: "openai/gpt-4.1",
                    name: "GPT 4.1",
                    backend: "openai",
                    quant: "n/a",
                    contextLength: 200_000,
                    paramsB: 0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: nil
                ),
                HubModel(
                    id: "qwen3-14b-mlx",
                    name: "Qwen 14B",
                    backend: "mlx",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 14,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen3",
                    note: nil
                ),
            ],
            updatedAt: 1_776_200_400
        )

        let backup = HubAIClient.preferredRemoteRetryBackupModelID(
            requestedModelId: "openai/gpt-5.4",
            snapshot: snapshot,
            transportMode: .auto,
            projectId: "project-1"
        )

        #expect(backup == "openai/gpt-4.1")
    }

    @Test
    func interactiveGenerateSanitizerDropsEmbeddingOnlyModelToLoadedChatFallback() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "mlx-community/qwen3-embedding-0.6b-4bit",
                    name: "Qwen3 Embedding 0.6B",
                    backend: "mlx",
                    quant: "4bit",
                    contextLength: 32_768,
                    paramsB: 0.6,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen3-embedding",
                    note: nil,
                    taskKinds: ["embedding"]
                ),
                HubModel(
                    id: "mlx-community/qwen3-8b-4bit",
                    name: "Qwen3 8B",
                    backend: "mlx",
                    quant: "4bit",
                    contextLength: 32_768,
                    paramsB: 8.0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen3-8b",
                    note: nil
                ),
            ],
            updatedAt: 1_776_200_450
        )

        let resolved = HubAIClient.sanitizedInteractiveGenerateModelID(
            "mlx-community/qwen3-embedding-0.6b-4bit",
            snapshot: snapshot,
            taskType: "assist"
        )

        #expect(resolved == "mlx-community/qwen3-8b-4bit")
    }

    @Test
    func interactiveGenerateSanitizerKeepsEmbeddingModelForEmbeddingTask() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "mlx-community/qwen3-embedding-0.6b-4bit",
                    name: "Qwen3 Embedding 0.6B",
                    backend: "mlx",
                    quant: "4bit",
                    contextLength: 32_768,
                    paramsB: 0.6,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen3-embedding",
                    note: nil,
                    taskKinds: ["embedding"]
                )
            ],
            updatedAt: 1_776_200_460
        )

        let resolved = HubAIClient.sanitizedInteractiveGenerateModelID(
            "mlx-community/qwen3-embedding-0.6b-4bit",
            snapshot: snapshot,
            taskType: "embedding"
        )

        #expect(resolved == "mlx-community/qwen3-embedding-0.6b-4bit")
    }

    @Test
    func remoteRetryResolutionUsesBackupModelAfterRetryableModelFailure() async {
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            if invocation.modelId == "openai/gpt-5.4" {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: "openai/gpt-5.4",
                    reasonCode: "model_not_found",
                    logLines: []
                )
            }
            return HubRemoteGenerateResult(
                ok: true,
                text: "ok",
                modelId: "openai/gpt-4.1",
                requestedModelId: "openai/gpt-4.1",
                actualModelId: "openai/gpt-4.1",
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 10,
                completionTokens: 20,
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubAIClient.resetRemoteGenerateOverrideForTesting() }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: "openai/gpt-4.1"
        )

        #expect(resolution.ok)
        #expect(resolution.actualModelId == "openai/gpt-4.1")
        #expect(resolution.remoteRetryAttempted)
        #expect(resolution.remoteRetryFromModelId == "openai/gpt-5.4")
        #expect(resolution.remoteRetryToModelId == "openai/gpt-4.1")
        #expect(resolution.remoteRetryReasonCode == "model_not_found")
    }

    @Test
    func remoteRetryResolutionRetriesAfterSuccessfulDowngradeToLocal() async {
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            if invocation.modelId == "openai/gpt-5.4" {
                return HubRemoteGenerateResult(
                    ok: true,
                    text: "local fallback",
                    modelId: "qwen3-14b-mlx",
                    requestedModelId: "openai/gpt-5.4",
                    actualModelId: "qwen3-14b-mlx",
                    runtimeProvider: "Hub (Local)",
                    executionPath: "hub_downgraded_to_local",
                    fallbackReasonCode: "downgrade_to_local",
                    promptTokens: 10,
                    completionTokens: 20,
                    reasonCode: nil,
                    logLines: []
                )
            }
            return HubRemoteGenerateResult(
                ok: true,
                text: "remote retry ok",
                modelId: "openai/gpt-4.1",
                requestedModelId: "openai/gpt-4.1",
                actualModelId: "openai/gpt-4.1",
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 11,
                completionTokens: 21,
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubAIClient.resetRemoteGenerateOverrideForTesting() }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: "openai/gpt-4.1"
        )

        #expect(resolution.ok)
        #expect(resolution.actualModelId == "openai/gpt-4.1")
        #expect(resolution.remoteRetryAttempted)
        #expect(resolution.remoteRetryFromModelId == "openai/gpt-5.4")
        #expect(resolution.remoteRetryToModelId == "openai/gpt-4.1")
        #expect(resolution.remoteRetryReasonCode == "downgrade_to_local")
    }

    @Test
    func remoteRetryResolutionDoesNotRetryOnNonRetryableFailure() async {
        let counter = InvocationCounter()
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            await counter.increment()
            return HubRemoteGenerateResult(
                ok: false,
                text: "",
                modelId: invocation.modelId,
                reasonCode: "api_key_missing",
                logLines: []
            )
        }
        defer { HubAIClient.resetRemoteGenerateOverrideForTesting() }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: "openai/gpt-4.1"
        )
        let invocationCount = await counter.value()

        #expect(!resolution.ok)
        #expect(invocationCount == 1)
        #expect(!resolution.remoteRetryAttempted)
        #expect(resolution.reasonCode == "api_key_missing")
    }
}

private actor InvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}
