import Foundation

struct VoicePlaybackResolution: Equatable, Sendable {
    var requestedPreference: VoicePlaybackPreference
    var resolvedSource: VoicePlaybackSource
    var preferredHubVoicePackID: String
    var resolvedHubVoicePackID: String
    var reasonCode: String
    var fallbackFrom: VoicePlaybackSource?
}

enum SupervisorSpeechPlaybackRouting {
    static func resolve(
        preferences: VoiceRuntimePreferences,
        availableModels: [HubModel],
        voicePackReadyEvaluator: (String) -> Bool
    ) -> VoicePlaybackResolution {
        let preferredPackID = preferences.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitSelectedModel = HubVoicePackCatalog.selectedModel(
            preferredModelID: preferredPackID,
            models: availableModels
        )
        let recommendedModel = preferredPackID.isEmpty && preferences.playbackPreference == .automatic
            ? HubVoicePackCatalog.recommendedModel(
                localeIdentifier: preferences.localeIdentifier,
                timbre: preferences.timbre,
                models: availableModels
            )
            : nil
        let resolvedHubVoicePackID = explicitSelectedModel?.id
            ?? recommendedModel?.id
            ?? ""
        let hubVoicePackReady = !resolvedHubVoicePackID.isEmpty
            && voicePackReadyEvaluator(resolvedHubVoicePackID)

        return resolve(
            preferences: preferences,
            preferredHubVoicePackID: preferredPackID,
            resolvedHubVoicePackID: resolvedHubVoicePackID,
            hubVoicePackReady: hubVoicePackReady
        )
    }

    static func resolve(
        preferences: VoiceRuntimePreferences,
        hubVoicePackReady: Bool
    ) -> VoicePlaybackResolution {
        let preferredPackID = preferences.preferredHubVoicePackID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return resolve(
            preferences: preferences,
            preferredHubVoicePackID: preferredPackID,
            resolvedHubVoicePackID: preferredPackID,
            hubVoicePackReady: hubVoicePackReady
        )
    }

    private static func resolve(
        preferences: VoiceRuntimePreferences,
        preferredHubVoicePackID preferredPackID: String,
        resolvedHubVoicePackID: String,
        hubVoicePackReady: Bool
    ) -> VoicePlaybackResolution {
        switch preferences.playbackPreference {
        case .automatic:
            if hubVoicePackReady, !resolvedHubVoicePackID.isEmpty {
                return VoicePlaybackResolution(
                    requestedPreference: .automatic,
                    resolvedSource: .hubVoicePack,
                    preferredHubVoicePackID: preferredPackID,
                    resolvedHubVoicePackID: resolvedHubVoicePackID,
                    reasonCode: preferredPackID.isEmpty
                        ? "automatic_hub_voice_pack_recommended"
                        : "automatic_hub_voice_pack_ready",
                    fallbackFrom: nil
                )
            }
            return VoicePlaybackResolution(
                requestedPreference: .automatic,
                resolvedSource: .systemSpeech,
                preferredHubVoicePackID: preferredPackID,
                resolvedHubVoicePackID: resolvedHubVoicePackID,
                reasonCode: !preferredPackID.isEmpty
                    ? "automatic_hub_voice_pack_unavailable"
                    : (resolvedHubVoicePackID.isEmpty
                        ? "automatic_system_speech_default"
                        : "automatic_hub_voice_pack_recommended_unavailable"),
                fallbackFrom: (!preferredPackID.isEmpty || !resolvedHubVoicePackID.isEmpty) ? .hubVoicePack : nil
            )
        case .hubVoicePack:
            if hubVoicePackReady, !preferredPackID.isEmpty {
                return VoicePlaybackResolution(
                    requestedPreference: .hubVoicePack,
                    resolvedSource: .hubVoicePack,
                    preferredHubVoicePackID: preferredPackID,
                    resolvedHubVoicePackID: resolvedHubVoicePackID,
                    reasonCode: "preferred_hub_voice_pack_ready",
                    fallbackFrom: nil
                )
            }
            return VoicePlaybackResolution(
                requestedPreference: .hubVoicePack,
                resolvedSource: .systemSpeech,
                preferredHubVoicePackID: preferredPackID,
                resolvedHubVoicePackID: "",
                reasonCode: preferredPackID.isEmpty
                    ? "preferred_hub_voice_pack_missing_id"
                    : "preferred_hub_voice_pack_unavailable",
                fallbackFrom: .hubVoicePack
            )
        case .systemSpeech:
            return VoicePlaybackResolution(
                requestedPreference: .systemSpeech,
                resolvedSource: .systemSpeech,
                preferredHubVoicePackID: preferredPackID,
                resolvedHubVoicePackID: "",
                reasonCode: "preferred_system_speech",
                fallbackFrom: nil
            )
        }
    }
}
