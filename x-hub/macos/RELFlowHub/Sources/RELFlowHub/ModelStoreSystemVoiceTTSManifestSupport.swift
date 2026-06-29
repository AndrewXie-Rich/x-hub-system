import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func systemVoiceTTSCatalogEntry(modelPath: String) -> ModelCatalogEntry {
        ModelCatalogEntry(
            id: systemVoiceTTSModelID,
            name: "macOS System Voice TTS",
            backend: "transformers",
            quant: "system",
            contextLength: 6000,
            maxContextLength: 6000,
            paramsB: 0.0,
            modelPath: modelPath,
            roles: ["tts", "voice"],
            note: systemVoiceTTSNote,
            modelFormat: "system_voice",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 6000),
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"],
            offlineReady: true,
            voiceProfile: ModelVoiceProfile(
                languageHints: ["multi", "zh", "en"],
                styleHints: ["neutral", "clear", "warm", "calm"],
                engineHints: ["system_voice"]
            ),
            resourceProfile: ModelResourceProfile(
                preferredDevice: "cpu",
                memoryFloorMB: 64,
                dtype: "system"
            ),
            trustProfile: ModelTrustProfile(
                allowSecretInput: false,
                allowRemoteExport: false
            ),
            processorRequirements: ModelProcessorRequirements(
                tokenizerRequired: false,
                processorRequired: false,
                featureExtractorRequired: false
            )
        )
    }

    nonisolated static func systemVoiceTTSStateModel(from entry: ModelCatalogEntry) -> HubModel {
        HubModel(
            id: entry.id,
            name: entry.name,
            backend: entry.backend,
            runtimeProviderID: entry.runtimeProviderID,
            quant: entry.quant,
            contextLength: entry.contextLength,
            maxContextLength: entry.maxContextLength,
            paramsB: entry.paramsB,
            roles: entry.roles,
            state: .available,
            modelPath: entry.modelPath,
            note: entry.note,
            modelFormat: entry.modelFormat,
            defaultLoadProfile: entry.defaultLoadProfile,
            taskKinds: entry.taskKinds,
            inputModalities: entry.inputModalities,
            outputModalities: entry.outputModalities,
            offlineReady: entry.offlineReady,
            voiceProfile: entry.voiceProfile,
            resourceProfile: entry.resourceProfile,
            trustProfile: entry.trustProfile,
            processorRequirements: entry.processorRequirements
        )
    }
}
