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
    func visionOnlyModelIsNotSelectableForInteractiveRouting() {
        let model = HubModel(
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

        #expect(!model.supportsInteractiveTextGeneration)
        #expect(model.isNonInteractiveOnlyModel)
        #expect(!model.isSelectableForInteractiveRouting)
        #expect(model.interactiveRoutingDisabledReason?.contains("任务专用链路") == true)
    }

    @Test
    func speechToTextOnlyModelIsNotSelectableForInteractiveRouting() {
        let model = HubModel(
            id: "whisper-large-v3",
            name: "Whisper Large V3",
            backend: "transformers",
            quant: "bf16",
            contextLength: 8_192,
            paramsB: 1.5,
            roles: nil,
            state: .available,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: "/models/whisper-large-v3",
            note: nil,
            taskKinds: ["speech_to_text"],
            inputModalities: ["audio"],
            outputModalities: ["text", "segments"]
        )

        #expect(!model.supportsInteractiveTextGeneration)
        #expect(model.isNonInteractiveOnlyModel)
        #expect(!model.isSelectableForInteractiveRouting)
        #expect(model.interactiveRoutingDisabledReason?.contains("任务专用链路") == true)
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
