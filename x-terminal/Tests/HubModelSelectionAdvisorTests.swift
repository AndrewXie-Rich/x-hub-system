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

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil
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
            note: nil
        )
    }
}
