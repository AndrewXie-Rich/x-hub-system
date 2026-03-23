import Foundation
import Testing
@testable import XTerminal

struct HubModelRoutingPickerStateTests {

    @Test
    func explicitSelectionUsesExplicitPresentationAndSourceLabel() {
        let explicit = XTModelCatalog.modelInfo(for: "claude-sonnet-4.6")
        let inherited = XTModelCatalog.modelInfo(for: "claude-haiku-4.5")
        let state = HubModelRoutingSelectionState(
            explicitModelId: "claude-sonnet-4.6",
            inheritedModelId: "claude-haiku-4.5",
            explicitPresentation: explicit,
            inheritedPresentation: inherited,
            explicitSourceLabel: "项目覆盖",
            inheritedSourceLabel: "继承全局",
            automaticTitle: "使用全局设置"
        )

        #expect(state.title == explicit.displayName)
        #expect(state.identifier == "claude-sonnet-4.6")
        #expect(state.sourceLabel == "项目覆盖")
        #expect(state.effectivePresentation?.id == explicit.id)
    }

    @Test
    func inheritedSelectionUsesInheritedPresentationWhenExplicitMissing() {
        let inherited = XTModelCatalog.modelInfo(for: "llama-3-70b-local")
        let state = HubModelRoutingSelectionState(
            explicitModelId: nil,
            inheritedModelId: "llama-3-70b-local",
            explicitPresentation: nil,
            inheritedPresentation: inherited,
            explicitSourceLabel: "当前绑定",
            inheritedSourceLabel: "Hub 默认",
            automaticTitle: "使用 Hub 默认设置"
        )

        #expect(state.title == inherited.displayName)
        #expect(state.identifier == "llama-3-70b-local")
        #expect(state.sourceLabel == "Hub 默认")
        #expect(state.effectivePresentation?.isLocal == true)
    }

    @Test
    func automaticSelectionFallsBackToAutomaticTitle() {
        let state = HubModelRoutingSelectionState(
            explicitModelId: nil,
            inheritedModelId: nil,
            explicitPresentation: nil,
            inheritedPresentation: nil,
            explicitSourceLabel: "当前绑定",
            inheritedSourceLabel: "Hub 默认",
            automaticTitle: "使用 Hub 默认设置"
        )

        #expect(state.title == "使用 Hub 默认设置")
        #expect(state.identifier == nil)
        #expect(state.sourceLabel == "Hub 默认")
        #expect(state.effectivePresentation == nil)
    }

    @Test
    func resolvedStateFallsBackToCatalogWhenInventoryMatchIsMissing() {
        let state = HubModelRoutingSelectionState.resolved(
            explicitModelId: "claude-sonnet-4.6",
            inheritedModelId: "llama-3-70b-local",
            models: [],
            explicitSourceLabel: "项目覆盖",
            inheritedSourceLabel: "继承全局",
            automaticTitle: "Auto"
        )

        #expect(state.title == "Claude Sonnet 4.6")
        #expect(state.identifier == "claude-sonnet-4.6")
        #expect(state.effectivePresentation?.id == "claude-sonnet-4.6")
        #expect(state.inheritedPresentation?.id == "llama-3-70b-local")
    }

    @Test
    func resolvedStateNormalizesBlankIdsToAutomaticRoute() {
        let state = HubModelRoutingSelectionState.resolved(
            explicitModelId: "   ",
            inheritedModelId: "\n",
            models: [],
            explicitSourceLabel: "项目覆盖",
            inheritedSourceLabel: "自动路由",
            automaticTitle: "Auto"
        )

        #expect(state.title == "Auto")
        #expect(state.identifier == nil)
        #expect(state.sourceLabel == "自动路由")
        #expect(state.effectivePresentation == nil)
    }

    @Test
    func explicitRecommendationWinsOverAutomaticFallbackRecommendation() throws {
        let recommendation = try #require(
            HubModelPickerRecommendationState.resolved(
                explicitModelId: "openai/gpt-4.1",
                explicitMessage: "直接切这个。",
                selectedModelId: "openai/gpt-5.4",
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ]
            )
        )

        #expect(recommendation.modelId == "openai/gpt-4.1")
        #expect(recommendation.message == "直接切这个。")
    }

    @Test
    func automaticRecommendationSuggestsLoadedFallbackForUnavailableSelectedModel() throws {
        let recommendation = try #require(
            HubModelPickerRecommendationState.resolved(
                explicitModelId: nil,
                explicitMessage: nil,
                selectedModelId: "openai/gpt-5.4",
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ]
            )
        )

        #expect(recommendation.modelId == "openai/gpt-4.1")
        #expect(recommendation.message.contains("openai/gpt-4.1"))
        #expect(recommendation.message.contains("openai/gpt-5.4"))
    }

    @Test
    func automaticRecommendationExplainsRetrievalOnlyModelFallback() throws {
        let recommendation = try #require(
            HubModelPickerRecommendationState.resolved(
                explicitModelId: nil,
                explicitMessage: nil,
                selectedModelId: "mlx-community/qwen3-embedding-0.6b-4bit",
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
                ]
            )
        )

        #expect(recommendation.modelId == "mlx-community/qwen3-8b-4bit")
        #expect(recommendation.message.contains("检索专用"))
        #expect(recommendation.message.contains("retrieval"))
    }

    @Test
    func automaticRecommendationIsNilWhenSelectedModelIsAlreadyLoaded() {
        let recommendation = HubModelPickerRecommendationState.resolved(
            explicitModelId: nil,
            explicitMessage: nil,
            selectedModelId: "openai/gpt-5.4",
            models: [
                makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .loaded),
                makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
            ]
        )

        #expect(recommendation == nil)
    }

    private func makeModel(
        id: String,
        name: String,
        state: HubModelState,
        backend: String = "openai",
        modelPath: String? = nil,
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
            taskKinds: taskKinds
        )
    }
}
