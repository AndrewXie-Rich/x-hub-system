import Foundation
import Testing
@testable import XTerminal

struct XTModelCatalogTests {

    @Test
    func curatedClaudeOpusIncludesReasoningVisionAndCodingMarkers() {
        let model = XTModelCatalog.modelInfo(for: "claude-opus-4.6")
        let markerIDs = Set(model.capabilityMarkers.map(\.id))

        #expect(model.displayName == "Claude Opus 4.6")
        #expect(markerIDs.contains("type_hubPaid"))
        #expect(markerIDs.contains("trait_reasoning"))
        #expect(markerIDs.contains("trait_vision"))
        #expect(markerIDs.contains("trait_coding"))
    }

    @Test
    func curatedLocalLlamaMarksLocalAndCodingWithoutVision() {
        let model = XTModelCatalog.modelInfo(for: "llama-3-70b-local")
        let markerIDs = Set(model.capabilityMarkers.map(\.id))

        #expect(model.isLocal)
        #expect(markerIDs.contains("type_local"))
        #expect(markerIDs.contains("trait_coding"))
        #expect(!markerIDs.contains("trait_vision"))
    }

    @Test
    func fallbackUnknownLocalModelStillGetsLocalMarkerAndReadableDisplayName() {
        let model = XTModelCatalog.modelInfo(for: "custom-model-local", preferLocalHint: true)
        let markerIDs = Set(model.capabilityMarkers.map(\.id))

        #expect(model.displayName == "custom model Local")
        #expect(model.isLocal)
        #expect(markerIDs.contains("type_local"))
    }

    @Test
    func hubModelAdapterPrefersActualLocalRuntimeTraits() {
        let hubModel = HubModel(
            id: "custom-runtime-model",
            name: "Custom Runtime",
            backend: "transformers",
            quant: "4bit",
            contextLength: 131_072,
            maxContextLength: 200_000,
            paramsB: 34,
            roles: ["coder"],
            state: .loaded,
            memoryBytes: 42_000_000_000,
            tokensPerSec: 52,
            modelPath: "/models/claude-sonnet",
            note: nil,
            modelFormat: "hf_transformers",
            defaultLoadProfile: HubLocalModelLoadProfile(contextLength: 16_384),
            taskKinds: ["vision_understand", "ocr"],
            inputModalities: ["image"],
            outputModalities: ["text", "spans"]
        )

        let presentation = XTModelCatalog.modelInfo(for: hubModel)
        let markerIDs = Set(presentation.capabilityMarkers.map(\.id))

        #expect(presentation.displayName == "Custom Runtime")
        #expect(presentation.isLocal)
        #expect(presentation.speed == .fast)
        #expect(markerIDs.contains("type_local"))
        #expect(markerIDs.contains("trait_vision"))
        #expect(markerIDs.contains("trait_coding"))
        #expect(presentation.suitableFor.contains("图像理解"))
        #expect(presentation.suitableFor.contains("OCR"))
    }

    @Test
    func hubModelAdapterFallsBackToCatalogNameWhenHubNameMissing() {
        let hubModel = HubModel(
            id: "claude-haiku-4.5",
            name: "",
            backend: "anthropic",
            quant: "",
            contextLength: 200_000,
            maxContextLength: nil,
            paramsB: 0,
            roles: nil,
            state: .available,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: nil,
            note: nil,
            defaultLoadProfile: nil
        )

        let presentation = XTModelCatalog.modelInfo(for: hubModel)

        #expect(presentation.displayName == "Claude Haiku 4.5")
        #expect(!presentation.isLocal)
    }

    @Test
    func hubModelAdapterMarksVoiceModelsAsSupervisorVoice() {
        let hubModel = HubModel(
            id: "hexgrad/kokoro-82m",
            name: "Kokoro 82M",
            backend: "transformers",
            quant: "bf16",
            contextLength: 8_192,
            maxContextLength: 8_192,
            paramsB: 0.08,
            roles: nil,
            state: .loaded,
            memoryBytes: 2_000_000_000,
            tokensPerSec: nil,
            modelPath: "/models/kokoro-82m",
            note: nil,
            modelFormat: "hf_transformers",
            defaultLoadProfile: HubLocalModelLoadProfile(contextLength: 2_048),
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"]
        )

        let presentation = XTModelCatalog.modelInfo(for: hubModel)

        #expect(presentation.suitableFor.contains("Supervisor 语音"))
        #expect(presentation.suitableFor.contains("语音合成"))
    }

    @Test
    func hubModelDecodesSnakeCaseCapabilityFields() throws {
        let json = """
        {
          "models": [
            {
              "id": "glm46v_flash_local",
              "name": "GLM 4.6V Flash",
              "backend": "transformers",
              "quant": "4bit",
              "context_length": 8192,
              "max_context_length": 65536,
              "params_b": 30,
              "state": "available",
              "model_path": "/models/glm",
              "model_format": "hf_transformers",
              "default_load_profile": {
                "context_length": 4096
              },
              "task_kinds": ["vision_understand", "ocr"],
              "input_modalities": ["image"],
              "output_modalities": ["text", "spans"],
              "offline_ready": true,
              "resource_profile": {
                "preferred_device": "mps",
                "memory_floor_mb": 20000,
                "dtype": "int4"
              },
              "trust_profile": {
                "allow_secret_input": false,
                "allow_remote_export": false
              },
              "processor_requirements": {
                "tokenizer_required": false,
                "processor_required": true,
                "feature_extractor_required": true
              }
            }
          ],
          "updatedAt": 1
        }
        """
        let data = Data(json.utf8)
        let snapshot = try JSONDecoder().decode(ModelStateSnapshot.self, from: data)
        let model = try #require(snapshot.models.first)

        #expect(model.modelFormat == "hf_transformers")
        #expect(model.hubDefaultContextLength == 4096)
        #expect(model.hubMaxContextLength == 65536)
        #expect(model.taskKinds == ["vision_understand", "ocr"])
        #expect(model.inputModalities == ["image"])
        #expect(model.outputModalities == ["text", "spans"])
        #expect(model.offlineReady)
        #expect(model.resourceProfile.preferredDevice == "mps")
        #expect(model.processorRequirements.processorRequired)
        #expect(model.capabilitySummaryLine?.contains("图像理解") == true)
    }
}
