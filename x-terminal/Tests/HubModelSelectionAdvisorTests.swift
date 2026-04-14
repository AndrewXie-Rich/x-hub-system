import Foundation
import Testing
@testable import XTerminal

struct HubModelSelectionAdvisorTests {
    @Test
    func exactLoadedMatchIsRecognizedEvenWhenConfiguredWithBareSuffix() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .loaded),
                makeModel(id: "qwen3-14b-mlx", name: "Qwen 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen")
            ],
            updatedAt: 1_776_200_000
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(requestedId: "gpt-5.4", snapshot: snapshot)
        )

        #expect(assessment.exactMatch?.id == "openai/gpt-5.4")
        #expect(assessment.isExactMatchLoaded)
    }

    @Test
    func knownButNotLoadedModelReturnsLoadedFallbackCandidates() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                makeModel(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4", state: .loaded)
            ],
            updatedAt: 1_776_200_100
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(requestedId: "openai/gpt-5.4", snapshot: snapshot)
        )

        #expect(assessment.exactMatch?.state == .available)
        #expect(!assessment.isExactMatchLoaded)
        #expect(assessment.loadedCandidates.map(\.id) == ["openai/gpt-4.1"])
    }

    @Test
    func unavailableRemoteModelPrefersRemoteFallbackOverLoadedLocalModel() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                makeModel(
                    id: "mlx-community/qwen3-14b-4bit",
                    name: "Qwen3 14B",
                    state: .loaded,
                    backend: "mlx",
                    modelPath: "/models/qwen3-14b"
                )
            ],
            updatedAt: 1_776_200_150
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(
                requestedId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(assessment.loadedCandidates.map(\.id) == ["openai/gpt-4.1"])
    }

    @Test
    func missingModelFallsBackToClosestInventoryMatches() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                makeModel(id: "openai/gpt-4.1-mini", name: "GPT 4.1 Mini", state: .loaded),
                makeModel(id: "anthropic/claude-sonnet-4", name: "Claude Sonnet 4", state: .available)
            ],
            updatedAt: 1_776_200_200
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(requestedId: "gpt-4.5", snapshot: snapshot)
        )

        #expect(assessment.exactMatch == nil)
        #expect(assessment.loadedCandidates.map(\.id) == ["openai/gpt-4.1", "openai/gpt-4.1-mini"])
        #expect(assessment.inventoryCandidates.first?.id == "openai/gpt-4.1")
    }

    @Test
    func brokenLocalCandidatesAreExcludedFromInventorySuggestions() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "qwen3-1.7b-mlx",
                    name: "Qwen 3 1.7B",
                    state: .available,
                    backend: "mlx",
                    modelPath: "/models/qwen3-1.7b",
                    offlineReady: false
                ),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
            ],
            updatedAt: 1_776_200_225
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(
                requestedId: "qwen3-1.7b-mlx",
                snapshot: snapshot
            )
        )

        #expect(assessment.exactMatch?.id == "qwen3-1.7b-mlx")
        #expect(assessment.inventoryCandidates.isEmpty)
        #expect(assessment.loadedCandidates.map(\.id) == ["openai/gpt-4.1"])
        #expect(HubModelSelectionAdvisor.suggestedModelIDs(from: assessment) == ["openai/gpt-4.1"])
    }

    @Test
    func localTaskResolutionAutoSelectsRunnableTaskCompatibleLocalModel() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "nomic-embed-text-v1",
                    name: "Nomic Embed Text",
                    state: .available,
                    backend: "transformers",
                    modelPath: "/models/nomic-embed-text-v1",
                    offlineReady: true,
                    taskKinds: ["embedding"]
                )
            ],
            updatedAt: 1_776_200_240
        )

        let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
            taskKind: "embedding",
            snapshot: snapshot
        )

        #expect(resolution.resolvedModel?.id == "nomic-embed-text-v1")
        #expect(resolution.reasonCode == "task_kind_auto")
        #expect(resolution.fallbackUsed == false)
    }

    @Test
    func localTaskResolutionFallsBackFromBrokenPreferredModelToRunnableCandidate() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "qwen-ocr-broken",
                    name: "Qwen OCR Broken",
                    state: .available,
                    backend: "mlx",
                    modelPath: "/models/qwen-ocr-broken",
                    offlineReady: false,
                    taskKinds: ["ocr"]
                ),
                makeModel(
                    id: "qwen-ocr-ready",
                    name: "Qwen OCR Ready",
                    state: .loaded,
                    backend: "mlx",
                    modelPath: "/models/qwen-ocr-ready",
                    offlineReady: true,
                    taskKinds: ["ocr"]
                )
            ],
            updatedAt: 1_776_200_245
        )

        let resolution = HubModelSelectionAdvisor.resolveLocalTaskModel(
            taskKind: "ocr",
            preferredModelId: "qwen-ocr-broken",
            snapshot: snapshot
        )

        #expect(resolution.resolvedModel?.id == "qwen-ocr-ready")
        #expect(resolution.reasonCode == "preferred_model_fallback_task_kind")
        #expect(resolution.fallbackUsed == true)
    }

    @Test
    func embeddingOnlyExactMatchIsMarkedAsNonInteractiveAndSuggestsChatFallback() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "mlx-community/qwen3-embedding-0.6b-4bit",
                    name: "Qwen3 Embedding 0.6B",
                    state: .loaded,
                    backend: "mlx",
                    modelPath: "/models/qwen3-embedding",
                    taskKinds: ["embedding"]
                ),
                makeModel(
                    id: "mlx-community/qwen3-8b-4bit",
                    name: "Qwen3 8B",
                    state: .loaded,
                    backend: "mlx",
                    modelPath: "/models/qwen3-8b"
                )
            ],
            updatedAt: 1_776_200_250
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(
                requestedId: "mlx-community/qwen3-embedding-0.6b-4bit",
                snapshot: snapshot
            )
        )

        #expect(assessment.exactMatch == nil)
        #expect(assessment.nonInteractiveExactMatch?.id == "mlx-community/qwen3-embedding-0.6b-4bit")
        #expect(assessment.interactiveRoutingBlockedReason?.contains("Supervisor") == true)
        #expect(assessment.loadedCandidates.map(\.id) == ["mlx-community/qwen3-8b-4bit"])
    }

    @Test
    func remoteLoadedFallbackCandidatesPreferRemoteFamilyAndSkipLocalModels() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded),
                makeModel(id: "custom/gpt-4.1", name: "Custom GPT 4.1", state: .loaded, backend: "custom_openai"),
                makeModel(id: "qwen3-14b-mlx", name: "Qwen 14B", state: .loaded, backend: "mlx", modelPath: "/models/qwen3")
            ],
            updatedAt: 1_776_200_300
        )

        let candidates = HubModelSelectionAdvisor.remoteLoadedFallbackCandidates(
            requestedId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(candidates.map(\.id) == ["openai/gpt-4.1"])
    }

    @Test
    func remoteLoadedFallbackCandidatesSkipEmbeddingOnlyModels() {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                makeModel(
                    id: "openai/text-embedding-3-large",
                    name: "Embedding 3 Large",
                    state: .loaded,
                    taskKinds: ["embedding"]
                ),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
            ],
            updatedAt: 1_776_200_320
        )

        let candidates = HubModelSelectionAdvisor.remoteLoadedFallbackCandidates(
            requestedId: "openai/gpt-5.4",
            snapshot: snapshot
        )

        #expect(candidates.map(\.id) == ["openai/gpt-4.1"])
    }

    @Test
    func globalAssignmentIssueSuggestsLoadedFallbackForUnavailableRoleModel() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
            ],
            updatedAt: 1_776_200_325
        )

        let issue = try #require(
            HubModelSelectionAdvisor.globalAssignmentIssue(
                for: .coder,
                configuredModelId: "openai/gpt-5.4",
                snapshot: snapshot
            )
        )

        #expect(issue.role == .coder)
        #expect(issue.suggestedModelId == "openai/gpt-4.1")
        #expect(issue.message.contains("回退到本地"))
    }

    @Test
    func voiceOnlyExactMatchIsMarkedAsNonInteractiveAndSuggestsChatFallback() throws {
        let snapshot = ModelStateSnapshot(
            models: [
                makeModel(
                    id: "hexgrad/kokoro-82m",
                    name: "Kokoro 82M",
                    state: .loaded,
                    backend: "transformers",
                    modelPath: "/models/kokoro-82m",
                    taskKinds: ["text_to_speech"]
                ),
                makeModel(
                    id: "mlx-community/qwen3-8b-4bit",
                    name: "Qwen3 8B",
                    state: .loaded,
                    backend: "mlx",
                    modelPath: "/models/qwen3-8b"
                )
            ],
            updatedAt: 1_776_200_330
        )

        let assessment = try #require(
            HubModelSelectionAdvisor.assess(
                requestedId: "hexgrad/kokoro-82m",
                snapshot: snapshot
            )
        )

        #expect(assessment.exactMatch == nil)
        #expect(assessment.nonInteractiveExactMatch?.id == "hexgrad/kokoro-82m")
        #expect(assessment.interactiveRoutingBlockedReason?.contains("Supervisor Voice") == true)
        #expect(assessment.loadedCandidates.map(\.id) == ["mlx-community/qwen3-8b-4bit"])
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil,
        offlineReady: Bool? = nil,
        taskKinds: [String]? = nil
    ) -> HubModel {
        HubModel(
            id: id,
            name: name,
            backend: backend,
            quant: "",
            contextLength: 128_000,
            paramsB: 0,
            roles: nil,
            state: state,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: modelPath,
            note: nil,
            taskKinds: taskKinds,
            offlineReady: offlineReady
        )
    }
}
