import XCTest
@testable import RELFlowHubCore

final class LocalModelCapabilityDefaultsTests: XCTestCase {
    func testTextToSpeechDefaultsResolveTextInAndAudioOut() {
        XCTAssertEqual(
            LocalModelCapabilityDefaults.defaultInputModalities(forTaskKinds: ["text_to_speech"]),
            ["text"]
        )
        XCTAssertEqual(
            LocalModelCapabilityDefaults.defaultOutputModalities(forTaskKinds: ["text_to_speech"]),
            ["audio"]
        )

        let requirements = LocalModelCapabilityDefaults.defaultProcessorRequirements(
            backend: "transformers",
            modelFormat: "hf_transformers",
            taskKinds: ["text_to_speech"]
        )

        XCTAssertTrue(requirements.tokenizerRequired)
        XCTAssertFalse(requirements.processorRequired)
        XCTAssertFalse(requirements.featureExtractorRequired)
    }

    func testVoiceProfileInferenceCapturesLanguageStyleAndEngineHints() {
        let profile = LocalModelCapabilityDefaults.defaultVoiceProfile(
            modelID: "kokoro.zh.warm",
            name: "Kokoro Warm Voice",
            note: "bilingual preview pack",
            taskKinds: ["text_to_speech"],
            outputModalities: ["audio"]
        )

        XCTAssertEqual(profile?.languageHints, ["multi"])
        XCTAssertEqual(profile?.styleHints, ["warm"])
        XCTAssertEqual(profile?.engineHints, ["kokoro"])
    }

    func testVoiceProfileStaysNilForNonVoiceModels() {
        let profile = LocalModelCapabilityDefaults.defaultVoiceProfile(
            modelID: "embed.zh",
            name: "Embedding",
            note: nil,
            taskKinds: ["embedding"],
            outputModalities: ["embedding"]
        )

        XCTAssertNil(profile)
    }

    func testVoiceProfileInferenceNormalizesImportedStyleAliases() {
        let profile = LocalModelCapabilityDefaults.defaultVoiceProfile(
            modelID: "voice.pack.studio",
            name: "Studio Gentle Voice",
            note: "soft bilingual preview pack",
            taskKinds: ["text_to_speech"],
            outputModalities: ["audio"]
        )

        XCTAssertEqual(profile?.languageHints, ["multi"])
        XCTAssertEqual(Set(profile?.styleHints ?? []), Set(["clear", "calm"]))
    }
}
