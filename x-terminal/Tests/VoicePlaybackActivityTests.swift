import Foundation
import Testing
@testable import XTerminal

struct VoicePlaybackActivityTests {

    @Test
    func fallbackPlayedWithoutDetailUsesHubRepairHint() {
        let activity = VoicePlaybackActivity(
            state: .fallbackPlayed,
            configuredResolution: VoicePlaybackResolution(
                requestedPreference: .hubVoicePack,
                resolvedSource: .systemSpeech,
                preferredHubVoicePackID: "hub.voice.zh.warm",
                resolvedHubVoicePackID: "",
                reasonCode: "preferred_hub_voice_pack_unavailable",
                fallbackFrom: .hubVoicePack
            ),
            actualSource: .systemSpeech,
            reasonCode: "hub_voice_pack_runtime_failed",
            detail: "",
            provider: "hub_voice_pack",
            modelID: "hub.voice.zh.warm",
            engineName: "",
            speakerId: "",
            deviceBackend: "system_speech",
            nativeTTSUsed: nil,
            fallbackMode: "hub_voice_pack_unavailable",
            fallbackReasonCode: "hub_voice_pack_runtime_failed",
            audioFormat: "",
            voiceName: "",
            updatedAt: 42
        )

        #expect(
            activity.recommendedNextStep
                == "如果你想恢复 Hub 语音包，请打开 Supervisor 设置，检查语音包是否仍在 Hub Library，且本机 Hub IPC 已报告 ready。"
        )
    }

    @Test
    func failedPlaybackWithoutDetailUsesDiagnosticsHint() {
        let activity = VoicePlaybackActivity(
            state: .failed,
            configuredResolution: nil,
            actualSource: .systemSpeech,
            reasonCode: "tts_output_device_unavailable",
            detail: "",
            provider: "",
            modelID: "",
            engineName: "",
            speakerId: "",
            deviceBackend: "",
            nativeTTSUsed: nil,
            fallbackMode: "",
            fallbackReasonCode: "",
            audioFormat: "",
            voiceName: "",
            updatedAt: 7
        )

        #expect(activity.recommendedNextStep == "打开 Supervisor 设置，确认当前播放输出链路。")
    }
}
