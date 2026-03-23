import Foundation
import Testing
@testable import XTerminal

struct HubModelInteractiveRoutingEligibilityTests {

    @Test
    func embeddingOnlyModelIsNotSelectableForInteractiveRouting() {
        let model = HubModel(
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

        #expect(model.isEmbeddingModel)
        #expect(model.isEmbeddingOnlyModel)
        #expect(!model.isSelectableForInteractiveRouting)
        #expect(model.interactiveRoutingDisabledReason?.contains("Supervisor") == true)
    }

    @Test
    func multimodalAssistantModelRemainsSelectable() {
        let model = HubModel(
            id: "glm-4.6v-flash",
            name: "GLM 4.6V Flash",
            backend: "transformers",
            quant: "bf16",
            contextLength: 32_768,
            paramsB: 9.0,
            roles: nil,
            state: .available,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: "/models/glm-4.6v-flash",
            note: nil,
            taskKinds: ["vision_understand", "text_generate"]
        )

        #expect(!model.isEmbeddingOnlyModel)
        #expect(model.isSelectableForInteractiveRouting)
        #expect(model.interactiveRoutingDisabledReason == nil)
    }

    @Test
    func voiceOnlyModelIsNotSelectableForInteractiveRouting() {
        let model = HubModel(
            id: "hexgrad/kokoro-82m",
            name: "Kokoro 82M",
            backend: "transformers",
            quant: "bf16",
            contextLength: 8_192,
            paramsB: 0.08,
            roles: nil,
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: "/models/kokoro-82m",
            note: nil,
            taskKinds: ["text_to_speech"],
            outputModalities: ["audio"]
        )

        #expect(model.isTextToSpeechModel)
        #expect(model.isTextToSpeechOnlyModel)
        #expect(!model.isSelectableForInteractiveRouting)
        #expect(model.interactiveRoutingDisabledReason?.contains("Supervisor Voice") == true)
    }
}
