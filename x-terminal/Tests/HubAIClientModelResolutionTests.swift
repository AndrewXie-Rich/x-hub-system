import Foundation
import Testing
@testable import XTerminal

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
}
