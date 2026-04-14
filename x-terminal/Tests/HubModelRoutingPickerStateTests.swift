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
    func supplementaryPresentationSeparatesEvidenceBadgesFromPrimaryBadges() {
        let presentation = HubModelRoutingSupplementaryPresentation(
            badges: [
                HubModelRoutingBadgePresentation(
                    text: "项目 Override",
                    tone: .neutral,
                    kind: .source
                ),
                HubModelRoutingBadgePresentation(
                    text: "Fallback",
                    tone: .warning,
                    kind: .status
                ),
                HubModelRoutingBadgePresentation(
                    text: "Local qwen3-14b-mlx",
                    tone: .warning,
                    kind: .detail
                ),
                HubModelRoutingBadgePresentation(
                    text: "Deny 当前设备不允许远端 export",
                    tone: .danger,
                    kind: .evidence
                )
            ],
            summaryText: "summary"
        )

        #expect(presentation.primaryBadges.map(\.text) == ["项目 Override", "Fallback", "Local qwen3-14b-mlx"])
        #expect(presentation.evidenceBadges.map(\.text) == ["Deny 当前设备不允许远端 export"])
    }

    @Test
    func supplementaryPresentationHasEmptyEvidenceSliceWhenNoEvidenceBadgeExists() {
        let presentation = HubModelRoutingSupplementaryPresentation(
            badges: [
                HubModelRoutingBadgePresentation(
                    text: "继承全局",
                    tone: .neutral,
                    kind: .source
                ),
                HubModelRoutingBadgePresentation(
                    text: "Pending",
                    tone: .neutral,
                    kind: .status
                )
            ],
            summaryText: "summary"
        )

        #expect(presentation.primaryBadges.map(\.text) == ["继承全局", "Pending"])
        #expect(presentation.evidenceBadges.isEmpty)
    }

    @Test
    func remoteSourceBadgesUseIconsForKeyAndHost() {
        let model = makeModel(
            id: "openai/gpt-5.4",
            name: "GPT 5.4",
            state: .loaded,
            backend: "openai",
            remoteGroupDisplayName: "Team Pro",
            remoteProviderModelID: "gpt-5.4",
            remoteKeyReference: "crs",
            remoteEndpointHost: "aispeed.store"
        )

        let badges = model.routingSourceBadges(language: .defaultPreference)

        #expect(badges.map(\.text) == ["crs", "aispeed.store"])
        #expect(badges.map(\.iconName) == ["key.fill", "network"])
    }

    @Test
    func explicitRecommendationWinsOverAutomaticFallbackRecommendation() throws {
        let recommendation = try #require(
            HubModelPickerRecommendationState.resolved(
                explicitModelId: "openai/gpt-4.1",
                explicitMessage: "直接切这个。",
                explicitKind: .continueWithoutSwitch,
                selectedModelId: "openai/gpt-5.4",
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ]
            )
        )

        #expect(recommendation.modelId == "openai/gpt-4.1")
        #expect(recommendation.message == "直接切这个。")
        #expect(recommendation.kind == .continueWithoutSwitch)
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
        #expect(recommendation.kind == .switchRecommended)
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
        #expect(recommendation.kind == .switchRecommended)
        #expect(recommendation.message.contains("检索专用"))
        #expect(recommendation.message.contains("做检索"))
    }

    @Test
    func automaticRecommendationCanRenderInEnglish() throws {
        let recommendation = try #require(
            HubModelPickerRecommendationState.resolved(
                explicitModelId: nil,
                explicitMessage: nil,
                selectedModelId: "openai/gpt-5.4",
                models: [
                    makeModel(id: "openai/gpt-5.4", name: "GPT 5.4", state: .available),
                    makeModel(id: "openai/gpt-4.1", name: "GPT 4.1", state: .loaded)
                ],
                language: .english
            )
        )

        #expect(recommendation.kind == .switchRecommended)
        #expect(recommendation.message.contains("openai/gpt-5.4"))
        #expect(recommendation.message.contains("openai/gpt-4.1"))
        #expect(recommendation.message.contains("switch to the loaded model"))
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
        taskKinds: [String]? = nil,
        remoteGroupDisplayName: String? = nil,
        remoteProviderModelID: String? = nil,
        remoteKeyReference: String? = nil,
        remoteEndpointHost: String? = nil
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
            remoteGroupDisplayName: remoteGroupDisplayName,
            remoteProviderModelID: remoteProviderModelID,
            remoteKeyReference: remoteKeyReference,
            remoteEndpointHost: remoteEndpointHost
        )
    }
}
