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
    func routeDecisionSnapshotInAutoModeUsesRemoteTruthWhenRemoteProfileExists() {
        let resolved = HubAIClient.resolveRouteDecisionModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: true,
            remoteSnapshot: nil,
            localSnapshot: ModelStateSnapshot(
                models: [
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
                updatedAt: 1_776_200_350
            )
        )

        #expect(resolved.models.isEmpty)
    }

    @Test
    func authoritativeSnapshotInAutoModeFailsClosedToRemoteTruthWhenRemoteProfileExists() {
        let resolved = HubAIClient.resolveAuthoritativeModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: true,
            remoteSnapshot: nil,
            localSnapshot: ModelStateSnapshot(
                models: [
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
                updatedAt: 1_776_200_351
            )
        )

        #expect(resolved.models.isEmpty)
    }

    @Test
    func routeDecisionSnapshotInAutoModePrefersLiveLocalHubWhenInventoryIsAvailable() {
        let localSnapshot = ModelStateSnapshot(
            models: [
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
            updatedAt: 1_776_200_352
        )

        let remoteSnapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
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
            ],
            updatedAt: 1_776_200_353
        )

        let resolved = HubAIClient.resolveRouteDecisionModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: true,
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot,
            localRuntimeAlive: true
        )

        #expect(resolved == localSnapshot)
    }

    @Test
    func authoritativeSnapshotInAutoModePrefersLiveLocalHubWhenInventoryIsAvailable() {
        let localSnapshot = ModelStateSnapshot(
            models: [
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
            updatedAt: 1_776_200_354
        )

        let remoteSnapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "GPT 5.4",
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
            ],
            updatedAt: 1_776_200_355
        )

        let resolved = HubAIClient.resolveAuthoritativeModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: true,
            remoteSnapshot: remoteSnapshot,
            localSnapshot: localSnapshot,
            localRuntimeAlive: true
        )

        #expect(resolved == localSnapshot)
    }

    @Test
    func routeDecisionSnapshotInAutoModeFallsBackToLocalOnlyWithoutRemoteProfile() {
        let localSnapshot = ModelStateSnapshot(
            models: [
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
            updatedAt: 1_776_200_360
        )

        let resolved = HubAIClient.resolveRouteDecisionModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: false,
            remoteSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "openai/gpt-5.4",
                        name: "GPT 5.4",
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
                ],
                updatedAt: 1_776_200_361
            ),
            localSnapshot: localSnapshot
        )

        #expect(resolved == localSnapshot)
    }

    @Test
    func authoritativeSnapshotInAutoModeUsesLocalOnlyWithoutRemoteProfile() {
        let localSnapshot = ModelStateSnapshot(
            models: [
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
            updatedAt: 1_776_200_364
        )

        let resolved = HubAIClient.resolveAuthoritativeModelsSnapshot(
            mode: .auto,
            hasRemoteProfile: false,
            remoteSnapshot: ModelStateSnapshot.empty(),
            localSnapshot: localSnapshot
        )

        #expect(resolved == localSnapshot)
    }

    @Test
    func routeDecisionSnapshotInGrpcModeFailsClosedWithoutRemoteProfile() {
        let resolved = HubAIClient.resolveRouteDecisionModelsSnapshot(
            mode: .grpc,
            hasRemoteProfile: false,
            remoteSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "openai/gpt-5.4",
                        name: "GPT 5.4",
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
                ],
                updatedAt: 1_776_200_362
            ),
            localSnapshot: ModelStateSnapshot(
                models: [
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
                updatedAt: 1_776_200_363
            )
        )

        #expect(resolved.models.isEmpty)
    }

    @Test
    func routeDecisionSnapshotInFileModeAlwaysUsesLocalInventory() {
        let localSnapshot = ModelStateSnapshot(
            models: [
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
            updatedAt: 1_776_200_370
        )

        let resolved = HubAIClient.resolveRouteDecisionModelsSnapshot(
            mode: .fileIPC,
            hasRemoteProfile: true,
            remoteSnapshot: ModelStateSnapshot(
                models: [
                    HubModel(
                        id: "openai/gpt-5.4",
                        name: "GPT 5.4",
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
                ],
                updatedAt: 1_776_200_371
            ),
            localSnapshot: localSnapshot
        )

        #expect(resolved == localSnapshot)
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
    func equivalentRemoteProviderBackupIsAvailableWithoutProjectContext() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "gpt-5.4",
                    name: "按量",
                    backend: "openai_compatible",
                    quant: "n/a",
                    contextLength: 200_000,
                    paramsB: 0,
                    roles: ["general", "paid"],
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: "MODEL_KIND_PAID_ONLINE | MODEL_VISIBILITY_REQUESTABLE"
                ),
                HubModel(
                    id: "openai/gpt-5.4",
                    name: "C 组",
                    backend: "openai",
                    quant: "n/a",
                    contextLength: 200_000,
                    paramsB: 0,
                    roles: ["general", "paid"],
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: "MODEL_KIND_PAID_ONLINE | MODEL_VISIBILITY_REQUESTABLE"
                ),
                HubModel(
                    id: "openai/gpt-4.1",
                    name: "GPT 4.1",
                    backend: "openai",
                    quant: "n/a",
                    contextLength: 128_000,
                    paramsB: 0,
                    roles: ["general", "paid"],
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: nil,
                    note: "MODEL_KIND_PAID_ONLINE | MODEL_VISIBILITY_REQUESTABLE"
                ),
            ],
            updatedAt: 1_776_200_425
        )

        let backup = HubAIClient.preferredRemoteRetryBackupModelID(
            requestedModelId: "gpt-5.4",
            snapshot: snapshot,
            transportMode: .auto,
            projectId: nil
        )

        #expect(backup == "openai/gpt-5.4")
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
    func interactiveGenerateSanitizerFallsBackFromVisionOnlyModelForAssistTask() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "qwen2-vl-ocr-only",
                    name: "Qwen2 VL OCR",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 7.0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen2-vl-ocr",
                    note: nil,
                    taskKinds: ["vision_understand", "ocr"],
                    inputModalities: ["image"],
                    outputModalities: ["text", "spans"]
                ),
                HubModel(
                    id: "qwen3-8b-4bit",
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
                    note: nil,
                    taskKinds: ["text_generate"]
                ),
            ],
            updatedAt: 1_776_200_470
        )

        let resolved = HubAIClient.sanitizedInteractiveGenerateModelID(
            "qwen2-vl-ocr-only",
            snapshot: snapshot,
            taskType: "assist"
        )

        #expect(resolved == "qwen3-8b-4bit")
    }

    @Test
    func interactiveGenerateSanitizerKeepsVisionOnlyModelForVisionTask() {
        let snapshot = ModelStateSnapshot(
            models: [
                HubModel(
                    id: "qwen2-vl-ocr-only",
                    name: "Qwen2 VL OCR",
                    backend: "transformers",
                    quant: "bf16",
                    contextLength: 32_768,
                    paramsB: 7.0,
                    roles: nil,
                    state: .loaded,
                    memoryBytes: nil,
                    tokensPerSec: nil,
                    modelPath: "/models/qwen2-vl-ocr",
                    note: nil,
                    taskKinds: ["vision_understand", "ocr"],
                    inputModalities: ["image"],
                    outputModalities: ["text", "spans"]
                )
            ],
            updatedAt: 1_776_200_480
        )

        let resolved = HubAIClient.sanitizedInteractiveGenerateModelID(
            "qwen2-vl-ocr-only",
            snapshot: snapshot,
            taskType: "vision_understand"
        )

        #expect(resolved == "qwen2-vl-ocr-only")
    }

    @Test
    func effectiveRemotePromptPrefersSanitizedOverrideWhenPresent() {
        let resolved = HubAIClient.effectiveRemotePrompt(
            prompt: "full local prompt with raw evidence",
            remotePromptOverride: " sanitized remote prompt "
        )

        #expect(resolved == "sanitized remote prompt")
    }

    @Test
    func effectiveRemotePromptFallsBackToOriginalPromptWhenOverrideEmpty() {
        let resolved = HubAIClient.effectiveRemotePrompt(
            prompt: "full local prompt with raw evidence",
            remotePromptOverride: "   "
        )

        #expect(resolved == "full local prompt with raw evidence")
    }

    @Test
    func remoteRetryResolutionUsesRemotePromptOverrideForInvocation() async {
        let recorder = StringRecorder()
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            await recorder.record(invocation.prompt)
            return HubRemoteGenerateResult(
                ok: true,
                text: "ok",
                modelId: invocation.modelId,
                requestedModelId: invocation.modelId,
                actualModelId: invocation.modelId,
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 8,
                completionTokens: 13,
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubAIClient.resetRemoteGenerateOverrideForTesting() }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            prompt: "full local prompt with raw evidence",
            remotePromptOverride: "sanitized remote prompt",
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: nil
        )
        let recorded = await recorder.values()

        #expect(resolution.ok)
        #expect(recorded == ["sanitized remote prompt"])
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
    func remoteRetryResolutionUsesEquivalentProviderAfterQuotaFailure() async {
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            if invocation.modelId == "gpt-5.4" {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: "gpt-5.4",
                    reasonCode: "用户额度不足, 剩余额度: ＄-0.499130",
                    logLines: []
                )
            }
            return HubRemoteGenerateResult(
                ok: true,
                text: "ok",
                modelId: "openai/gpt-5.4",
                requestedModelId: "openai/gpt-5.4",
                actualModelId: "openai/gpt-5.4",
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
            preferredModelId: "gpt-5.4",
            remoteBackupModelId: "openai/gpt-5.4",
            projectId: nil
        )

        #expect(resolution.ok)
        #expect(resolution.actualModelId == "openai/gpt-5.4")
        #expect(resolution.remoteRetryAttempted)
        #expect(resolution.remoteRetryFromModelId == "gpt-5.4")
        #expect(resolution.remoteRetryToModelId == "openai/gpt-5.4")
        #expect(resolution.remoteRetryReasonCode == "用户额度不足, 剩余额度: ＄-0.499130")
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

    @Test
    func remoteRetryResolutionReconnectsRouteAndRetriesSameModelAfterTransportFailure() async {
        let generateCounter = InvocationCounter()
        let reconnectCounter = InvocationCounter()

        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            let count = await generateCounter.incrementAndReturn()
            if count == 1 {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: invocation.modelId,
                    reasonCode: "14 UNAVAILABLE: No connection established. Last error: Failed to connect to all addresses",
                    logLines: []
                )
            }
            return HubRemoteGenerateResult(
                ok: true,
                text: "remote recovered",
                modelId: invocation.modelId,
                requestedModelId: invocation.modelId,
                actualModelId: invocation.modelId,
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 12,
                completionTokens: 18,
                reasonCode: nil,
                logLines: []
            )
        }
        HubAIClient.installRemoteReconnectOverrideForTesting { _, _ in
            await reconnectCounter.increment()
            return HubRemoteConnectReport(
                ok: true,
                route: .internet,
                summary: "connected_internet",
                logLines: [],
                reasonCode: nil
            )
        }
        defer {
            HubAIClient.resetRemoteGenerateOverrideForTesting()
            HubAIClient.resetRemoteReconnectOverrideForTesting()
        }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: nil,
            transportMode: .grpc
        )

        #expect(resolution.ok)
        #expect(resolution.actualModelId == "openai/gpt-5.4")
        #expect(await generateCounter.value() == 2)
        #expect(await reconnectCounter.value() == 1)
        #expect(!resolution.remoteRetryAttempted)
    }

    @Test
    func remoteRetryResolutionAttemptsFollowupReconnectOnPersistentTransportFailure() async {
        let generateCounter = InvocationCounter()
        let reconnectCounter = InvocationCounter()
        let recordedPlans = RemoteReconnectPlanRecorder()
        let primaryPlan = HubAIClient.RemoteReconnectPlan(
            preferredRoute: .stableNamedRemote,
            candidateRoutes: [.stableNamedRemote, .managedTunnelFallback],
            handoffReason: "remote_generate_reconnect_prefer_stable_remote"
        )

        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            let count = await generateCounter.incrementAndReturn()
            if count <= 2 {
                return HubRemoteGenerateResult(
                    ok: false,
                    text: "",
                    modelId: invocation.modelId,
                    reasonCode: "grpc_unavailable",
                    logLines: []
                )
            }
            return HubRemoteGenerateResult(
                ok: true,
                text: "remote recovered on followup route",
                modelId: invocation.modelId,
                requestedModelId: invocation.modelId,
                actualModelId: invocation.modelId,
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 12,
                completionTokens: 18,
                reasonCode: nil,
                logLines: []
            )
        }
        HubAIClient.installRemoteReconnectOverrideForTesting { _, plan in
            await reconnectCounter.increment()
            await recordedPlans.record(plan)
            let count = await reconnectCounter.value()
            if count == 1 {
                return HubRemoteConnectReport(
                    ok: true,
                    route: .internet,
                    summary: "connected_internet",
                    logLines: [],
                    reasonCode: nil,
                    selectedRoute: .stableNamedRemote,
                    attemptedRoutes: [.stableNamedRemote]
                )
            }
            return HubRemoteConnectReport(
                ok: true,
                route: .internetTunnel,
                summary: "connected_internet_tunnel",
                logLines: [],
                reasonCode: nil,
                selectedRoute: .managedTunnelFallback,
                attemptedRoutes: [.managedTunnelFallback]
            )
        }
        defer {
            HubAIClient.resetRemoteGenerateOverrideForTesting()
            HubAIClient.resetRemoteReconnectOverrideForTesting()
        }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: nil,
            transportMode: .grpc,
            reconnectPlanOverride: primaryPlan
        )
        let plans = await recordedPlans.values()

        #expect(resolution.ok)
        #expect(resolution.actualModelId == "openai/gpt-5.4")
        #expect(await generateCounter.value() == 3)
        #expect(await reconnectCounter.value() == 2)
        #expect(plans.count == 2)
        #expect(plans.first?.preferredRoute == .stableNamedRemote)
        #expect(plans.first?.candidateRoutes == [.stableNamedRemote, .managedTunnelFallback])
        #expect(plans.last?.preferredRoute == .managedTunnelFallback)
        #expect(plans.last?.candidateRoutes == [.managedTunnelFallback])
        #expect(!resolution.remoteRetryAttempted)
    }

    @Test
    func remoteRetryResolutionPropagatesTimeoutToRemoteInvocation() async {
        let recorder = TimeoutRecorder()
        HubAIClient.installRemoteGenerateOverrideForTesting { invocation in
            await recorder.record(invocation.timeoutSec)
            return HubRemoteGenerateResult(
                ok: true,
                text: "ok",
                modelId: invocation.modelId,
                requestedModelId: invocation.modelId,
                actualModelId: invocation.modelId,
                runtimeProvider: "Hub (Remote)",
                executionPath: "remote_model",
                fallbackReasonCode: nil,
                promptTokens: 8,
                completionTokens: 13,
                reasonCode: nil,
                logLines: []
            )
        }
        defer { HubAIClient.resetRemoteGenerateOverrideForTesting() }

        let resolution = await HubAIClient.shared.remoteRetryResolutionForTesting(
            preferredModelId: "openai/gpt-5.4",
            remoteBackupModelId: nil,
            timeoutSec: 37.5
        )
        let recorded = await recorder.values()

        #expect(resolution.ok)
        #expect(recorded == [37.5])
    }
}

private actor InvocationCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func incrementAndReturn() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private actor RemoteReconnectPlanRecorder {
    private var plans: [HubAIClient.RemoteReconnectPlan] = []

    func record(_ plan: HubAIClient.RemoteReconnectPlan) {
        plans.append(plan)
    }

    func values() -> [HubAIClient.RemoteReconnectPlan] {
        plans
    }
}

private actor TimeoutRecorder {
    private var store: [Double] = []

    func record(_ value: Double) {
        store.append(value)
    }

    func values() -> [Double] {
        store
    }
}

private actor StringRecorder {
    private var store: [String] = []

    func record(_ value: String) {
        store.append(value)
    }

    func values() -> [String] {
        store
    }
}
