import Foundation
import Testing
@testable import XTerminal

struct HubVoicePackCatalogTests {
    @Test
    func eligibleModelsPreferBestLocalTTSSnapshotAndSortLoadedFirst() {
        let models = [
            HubModel(
                id: "hub.voice.zh.warm",
                name: "Warm Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .available,
                modelPath: "/models/warm",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
            HubModel(
                id: "hub.voice.en.clear",
                name: "Clear Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/clear",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
            HubModel(
                id: "hub.voice.zh.warm",
                name: "Warm Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/warm",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
            HubModel(
                id: "hub.embedding.zh",
                name: "Embedding",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.4,
                state: .loaded,
                modelPath: "/models/embed",
                modelFormat: "safetensors",
                taskKinds: ["embedding"],
                inputModalities: ["text"],
                outputModalities: ["embedding"]
            ),
            HubModel(
                id: "remote.voice.only",
                name: "Remote Voice",
                backend: "openai",
                quant: "n/a",
                contextLength: 4096,
                paramsB: 0.1,
                state: .loaded,
                modelPath: nil,
                modelFormat: "api",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
        ]

        let eligible = HubVoicePackCatalog.eligibleModels(from: models)

        #expect(eligible.map(\.id) == ["hub.voice.en.clear", "hub.voice.zh.warm"])
        #expect(eligible.allSatisfy { $0.isEligibleHubVoicePackModel })
        #expect(eligible[1].state == .loaded)
    }

    @Test
    func pickerOptionsIncludeUnavailableConfiguredSelection() {
        let models = [
            HubModel(
                id: "hub.voice.zh.warm",
                name: "Warm Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/warm",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
        ]

        let options = HubVoicePackCatalog.pickerOptions(
            models: models,
            selectedModelID: "missing.voice.pack"
        )

        #expect(options.map(\.id) == ["", "missing.voice.pack", "hub.voice.zh.warm"])
        #expect(options[1].isUnavailableSelection)
        #expect(options[1].title == "Hub 清单中不可用")
        #expect(options[1].detail == "missing.voice.pack")
    }

    @Test
    func selectionPresentationUsesFriendlyLabelForKnownModel() {
        let models = [
            HubModel(
                id: "hub.voice.zh.warm",
                name: "Warm Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/warm",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
        ]

        #expect(
            HubVoicePackCatalog.selectionTitle(
                preferredModelID: "hub.voice.zh.warm",
                models: models
            ) == "Warm Voice"
        )
        #expect(
            HubVoicePackCatalog.selectionDetail(
                preferredModelID: "hub.voice.zh.warm",
                models: models
            ) == "已加载 · 特征：中文偏好、温暖风格 · hub.voice.zh.warm"
        )
        #expect(
            HubVoicePackCatalog.selectionTitle(
                preferredModelID: "",
                models: models
            ) == HubVoicePackCatalog.automaticSelectionTitle
        )
    }

    @Test
    func automaticPickerOptionExplainsBestMatchBehavior() {
        let options = HubVoicePackCatalog.pickerOptions(
            models: [],
            selectedModelID: ""
        )

        #expect(options.count == 1)
        #expect(options[0].title == HubVoicePackCatalog.automaticSelectionTitle)
        #expect(options[0].detail == HubVoicePackCatalog.automaticSelectionDetail)
    }

    @Test
    func pickerMenuLabelIncludesCompactSignalsWhenTheyCanBeInferred() {
        let models = [
            HubModel(
                id: "kokoro.zh.warm",
                name: "Kokoro Warm Voice",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/kokoro.zh.warm",
                note: "bilingual preview pack",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"]
            ),
        ]

        let options = HubVoicePackCatalog.pickerOptions(
            models: models,
            selectedModelID: "kokoro.zh.warm"
        )

        #expect(options[1].menuLabel == "Kokoro Warm Voice · 多语种 · 温暖风格 · 已加载")
        #expect(options[1].detail == "已加载 · 特征：多语种、温暖风格、Kokoro · kokoro.zh.warm")
    }

    @Test
    func pickerUsesStructuredVoiceProfileFromHubWhenPresent() {
        let models = [
            HubModel(
                id: "voice.pack.alpha",
                name: "Voice Pack Alpha",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/voice.pack.alpha",
                note: "generic note",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                voiceProfile: HubModelVoiceProfile(
                    languageHints: ["en"],
                    styleHints: ["clear"],
                    engineHints: ["parler"]
                )
            ),
        ]

        let options = HubVoicePackCatalog.pickerOptions(
            models: models,
            selectedModelID: "voice.pack.alpha"
        )

        #expect(options[1].menuLabel == "Voice Pack Alpha · 英文偏好 · 清晰风格 · 已加载")
        #expect(options[1].detail == "已加载 · 特征：英文偏好、清晰风格、Parler · voice.pack.alpha")
    }

    @Test
    func recommendedModelPrefersLocaleAndTimbreMatch() {
        let models = [
            HubModel(
                id: "voice.en.clear",
                name: "English Clear",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/voice.en.clear",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                voiceProfile: HubModelVoiceProfile(
                    languageHints: ["en"],
                    styleHints: ["clear"],
                    engineHints: ["parler"]
                )
            ),
            HubModel(
                id: "voice.zh.warm",
                name: "Chinese Warm",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .available,
                modelPath: "/models/voice.zh.warm",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                voiceProfile: HubModelVoiceProfile(
                    languageHints: ["zh"],
                    styleHints: ["warm"],
                    engineHints: ["kokoro"]
                )
            ),
        ]

        let recommended = HubVoicePackCatalog.recommendedModel(
            localeIdentifier: "zh-CN",
            timbre: .warm,
            models: models
        )

        #expect(recommended?.id == "voice.zh.warm")
    }

    @Test
    func recommendedModelPrefersKokoroWhenRequestedRouteMatchesNativeSpeakerMap() {
        let models = [
            HubModel(
                id: "voice.melo.zh.clear",
                name: "A Melo Chinese",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/voice.melo.zh.clear",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                voiceProfile: HubModelVoiceProfile(
                    languageHints: ["zh"],
                    styleHints: ["clear"],
                    engineHints: ["melotts"]
                )
            ),
            HubModel(
                id: "voice.kokoro.zh.clear",
                name: "Z Kokoro Chinese",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
                modelPath: "/models/voice.kokoro.zh.clear",
                modelFormat: "safetensors",
                taskKinds: ["text_to_speech"],
                inputModalities: ["text"],
                outputModalities: ["audio"],
                voiceProfile: HubModelVoiceProfile(
                    languageHints: ["zh"],
                    styleHints: ["clear"],
                    engineHints: ["kokoro"]
                )
            ),
        ]

        let recommended = HubVoicePackCatalog.recommendedModel(
            localeIdentifier: "zh-CN",
            timbre: .bright,
            models: models
        )

        #expect(recommended?.id == "voice.kokoro.zh.clear")
    }
}
