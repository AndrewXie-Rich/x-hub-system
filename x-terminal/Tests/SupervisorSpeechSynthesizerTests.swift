import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorSpeechSynthesizerTests {

    @Test
    func dedupeSuppressesImmediateRepeat() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
            speakSink: { spoken.append($0) }
        )
        let job = SupervisorVoiceTTSJob(
            trigger: .authorization,
            script: ["Voice authorization verified."],
            dedupeKey: "voice-auth-verified"
        )

        let first = synthesizer.speak(
            job: job,
            preferences: .default(),
            now: Date(timeIntervalSince1970: 1_000)
        )
        let second = synthesizer.speak(
            job: job,
            preferences: .default(),
            now: Date(timeIntervalSince1970: 1_010)
        )

        #expect(first == .spoken)
        #expect(second == .suppressed("duplicate_suppressed"))
        #expect(spoken.count == 1)
    }

    @Test
    func quietHoursSuppressSpeech() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) }
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.quietHours = VoiceQuietHours(
            enabled: true,
            fromLocal: "22:00",
            toLocal: "08:00"
        )
        let components = DateComponents(
            calendar: .current,
            timeZone: .current,
            year: 2026,
            month: 3,
            day: 10,
            hour: 23,
            minute: 15
        )
        let outcome = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .authorization,
                script: ["Voice authorization verified."],
                dedupeKey: "voice-auth-verified"
            ),
            preferences: preferences,
            now: components.date ?? Date(timeIntervalSince1970: 0)
        )

        #expect(outcome == .suppressed("quiet_hours_suppressed"))
        #expect(spoken.isEmpty)
    }

    @Test
    func blockersOnlyModeStillAllowsExplicitVoiceReplies() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) }
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.autoReportMode = .blockersOnly

        let outcome = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["自动化执行命令"],
                dedupeKey: "voice-reply-automation-help"
            ),
            preferences: preferences,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(outcome == .spoken)
        #expect(spoken == ["自动化执行命令"])
    }

    @Test
    func inFlightDuplicateContentIsSuppressedEvenWithDifferentDedupeKeys() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) }
        )
        let first = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["请继续汇总当前项目进度。"],
                dedupeKey: "voice-reply-a"
            ),
            preferences: .default(),
            now: Date(timeIntervalSince1970: 1_000)
        )
        let second = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .completed,
                script: ["请继续汇总当前项目进度。"],
                dedupeKey: "heartbeat-b"
            ),
            preferences: .default(),
            now: Date(timeIntervalSince1970: 1_001)
        )

        #expect(first == .spoken)
        #expect(second == .suppressed("inflight_duplicate_suppressed"))
        #expect(spoken == ["请继续汇总当前项目进度。"])
    }

    @Test
    func interruptCurrentPlaybackUsesInjectedInterruptSink() {
        var interruptCount = 0
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { _ in },
            interruptSink: {
                interruptCount += 1
                return true
            }
        )

        let interrupted = synthesizer.interruptCurrentPlayback()

        #expect(interrupted)
        #expect(interruptCount == 1)
    }

    @Test
    func interruptCurrentPlaybackStopsHubVoicePackAndSystemPlayback() {
        var systemInterruptCount = 0
        var hubInterruptCount = 0
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { _ in },
            interruptSink: {
                systemInterruptCount += 1
                return true
            },
            hubVoicePackSpeakSink: { _, _, _ in
                .unavailable(reasonCode: "disabled", detail: "")
            },
            hubVoicePackInterruptSink: {
                hubInterruptCount += 1
                return true
            }
        )

        let interrupted = synthesizer.interruptCurrentPlayback()

        #expect(interrupted)
        #expect(systemInterruptCount == 1)
        #expect(hubInterruptCount == 1)
    }

    @Test
    func interruptCurrentPlaybackClearsActiveDuplicateSuppressionState() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) },
            interruptSink: { true }
        )
        let job = SupervisorVoiceTTSJob(
            trigger: .userQueryReply,
            script: ["Atlas 项目已恢复执行。"],
            dedupeKey: "voice-reply-atlas"
        )

        let first = synthesizer.speak(
            job: job,
            preferences: .default(),
            now: Date(timeIntervalSince1970: 2_000)
        )
        let interrupted = synthesizer.interruptCurrentPlayback()
        let second = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["Atlas 项目已恢复执行。"],
                dedupeKey: "voice-reply-atlas-retry"
            ),
            preferences: .default(),
            now: Date(timeIntervalSince1970: 2_001)
        )

        #expect(first == .spoken)
        #expect(interrupted)
        #expect(second == .spoken)
        #expect(spoken == ["Atlas 项目已恢复执行。", "Atlas 项目已恢复执行。"])
    }

    @Test
    func distinctInFlightPlaybackPreemptsExistingAudioBeforeSpeakingAgain() {
        var spoken: [String] = []
        var interruptCount = 0
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) },
            interruptSink: {
                interruptCount += 1
                return true
            }
        )

        let first = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["Atlas 项目已恢复执行。"],
                dedupeKey: "voice-reply-atlas"
            ),
            preferences: .default(),
            now: Date(timeIntervalSince1970: 2_000)
        )
        let second = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .completed,
                script: ["Phoenix 项目等待授权。"],
                dedupeKey: "heartbeat-phoenix"
            ),
            preferences: .default(),
            now: Date(timeIntervalSince1970: 2_001)
        )

        #expect(first == .spoken)
        #expect(second == .spoken)
        #expect(interruptCount == 1)
        #expect(spoken == ["Atlas 项目已恢复执行。", "Phoenix 项目等待授权。"])
    }

    @Test
    func legacyVoiceRuntimePreferencesDecodeUsesPersonaAndInterruptDefaults() throws {
        let payload = """
        {
          "preferredRoute": "automatic",
          "wakeMode": "push_to_talk",
          "autoReportMode": "summary",
          "quietHours": {
            "enabled": false,
            "fromLocal": "22:00",
            "toLocal": "08:00"
          },
          "localeIdentifier": "zh-CN",
          "funASR": {
            "enabled": false,
            "transport": "websocket",
            "webSocketURL": "ws://127.0.0.1:10096",
            "wakeEnabled": true,
            "partialsEnabled": true
          }
        }
        """.data(using: .utf8) ?? Data()

        let decoded = try JSONDecoder().decode(VoiceRuntimePreferences.self, from: payload)

        #expect(decoded.playbackPreference == .automatic)
        #expect(decoded.persona == .conversational)
        #expect(decoded.timbre == .neutral)
        #expect(decoded.preferredHubVoicePackID.isEmpty)
        #expect(decoded.speechRateMultiplier == 1.0)
        #expect(decoded.interruptOnSpeech)
    }

    @Test
    func playbackResolutionFallsBackToSystemSpeechWhenHubVoicePackIsPreferredButUnavailable() {
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { _ in }
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub_voice_zh_warm_v1"

        let resolution = synthesizer.playbackResolution(for: preferences)

        #expect(resolution.resolvedSource == .systemSpeech)
        #expect(resolution.reasonCode == "preferred_hub_voice_pack_unavailable")
        #expect(resolution.fallbackFrom == .hubVoicePack)
    }

    @Test
    func automaticPlaybackResolutionUsesRecommendedHubVoicePackWhenReady() {
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .automatic
        preferences.preferredHubVoicePackID = ""
        preferences.localeIdentifier = "zh-CN"
        preferences.timbre = .warm

        let models = [
            HubModel(
                id: "voice.zh.warm",
                name: "Chinese Warm",
                backend: "transformers",
                quant: "fp16",
                contextLength: 4096,
                paramsB: 0.08,
                state: .loaded,
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

        let resolution = SupervisorSpeechPlaybackRouting.resolve(
            preferences: preferences,
            availableModels: models,
            voicePackReadyEvaluator: { $0 == "voice.zh.warm" }
        )

        #expect(resolution.resolvedSource == .hubVoicePack)
        #expect(resolution.resolvedHubVoicePackID == "voice.zh.warm")
        #expect(resolution.reasonCode == "automatic_hub_voice_pack_recommended")
    }

    @Test
    func systemVoiceRankingPenalizesEloquenceAndNoveltyVoices() {
        let locale = "zh-cn"
        let tingtingScore = SupervisorSpeechSynthesizer.voiceRank(
            language: "zh-CN",
            name: "Tingting",
            identifier: "com.apple.voice.compact.zh-CN.Tingting",
            normalizedLocale: locale,
            persona: .conversational,
            timbre: .neutral
        )
        let eloquenceScore = SupervisorSpeechSynthesizer.voiceRank(
            language: "zh-CN",
            name: "Eddy",
            identifier: "com.apple.eloquence.zh-CN.Eddy",
            normalizedLocale: locale,
            persona: .conversational,
            timbre: .neutral
        )
        let noveltyScore = SupervisorSpeechSynthesizer.voiceRank(
            language: "en-US",
            name: "Bad News",
            identifier: "com.apple.speech.synthesis.voice.BadNews",
            normalizedLocale: "en-us",
            persona: .conversational,
            timbre: .neutral
        )
        let samanthaScore = SupervisorSpeechSynthesizer.voiceRank(
            language: "en-US",
            name: "Samantha",
            identifier: "com.apple.voice.compact.en-US.Samantha",
            normalizedLocale: "en-us",
            persona: .conversational,
            timbre: .neutral
        )

        #expect(tingtingScore > eloquenceScore)
        #expect(samanthaScore > noveltyScore)
    }

    @Test
    func speakUsesHubVoicePackSinkWhenConfigured() {
        var systemSpoken: [String] = []
        var hubSpoken: [[String]] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { systemSpoken.append($0) },
            hubVoicePackSpeakSink: { script, _, resolution in
                #expect(resolution.resolvedSource == .hubVoicePack)
                #expect(resolution.resolvedHubVoicePackID == "hub_voice_zh_warm_v1")
                hubSpoken.append(script)
                return .spoken(
                    VoicePlaybackDeliveryMetadata(
                        actualSource: .hubVoicePack,
                        provider: "transformers",
                        modelID: "hub_voice_zh_warm_v1",
                        engineName: "kokoro",
                        speakerId: "zh_warm_f1",
                        deviceBackend: "system_voice_compatibility",
                        nativeTTSUsed: false,
                        fallbackMode: "system_voice_compatibility",
                        fallbackReasonCode: "native_dependency_error",
                        audioFormat: "aiff",
                        voiceName: "Eddy (Chinese (China mainland))",
                        reasonCode: "hub_voice_pack_played",
                        detail: ""
                    )
                )
            }
        )
        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub_voice_zh_warm_v1"

        let outcome = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["Phoenix 项目目前卡在授权。"],
                dedupeKey: "voice-hub-pack-1"
            ),
            preferences: preferences,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(outcome == .spoken)
        #expect(systemSpoken.isEmpty)
        #expect(hubSpoken == [["Phoenix 项目目前卡在授权。"]])
    }

    @Test
    func failedHubVoicePackPlaybackFallsBackToSystemSpeechAndPublishesActivity() {
        var systemSpoken: [String] = []
        var playbackActivities: [VoicePlaybackActivity] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { systemSpoken.append($0) },
            hubVoicePackSpeakSink: { _, _, _ in
                .unavailable(reasonCode: "hub_voice_pack_runtime_failed", detail: "tts failed")
            }
        )
        synthesizer.playbackActivitySink = { playbackActivities.append($0) }

        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub_voice_zh_warm_v1"

        let outcome = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["请继续汇报当前项目进度。"],
                dedupeKey: "voice-hub-pack-fallback"
            ),
            preferences: preferences,
            now: Date(timeIntervalSince1970: 2_000)
        )

        #expect(outcome == .spoken)
        #expect(systemSpoken == ["请继续汇报当前项目进度。"])
        #expect(playbackActivities.count == 1)
        #expect(playbackActivities[0].state == .fallbackPlayed)
        #expect(playbackActivities[0].actualSource == .systemSpeech)
        #expect(playbackActivities[0].reasonCode == "hub_voice_pack_runtime_failed")
        #expect(playbackActivities[0].fallbackMode == "hub_voice_pack_unavailable")
        #expect(playbackActivities[0].fallbackReasonCode == "hub_voice_pack_runtime_failed")
        #expect(playbackActivities[0].shouldDisplayExecutionMode)
        #expect(playbackActivities[0].executionModeDisplayName == "系统语音回退")
        #expect(playbackActivities[0].compactRailSummaryLine == "tts=system mode=system_speech_fallback why=hub_voice_pack_runtime_failed")
        #expect(
            playbackActivities[0].runtimeLogSummaryLine
            == "voice_playback state=fallback_played output=system_speech tts=system mode=system_speech_fallback why=hub_voice_pack_runtime_failed fallback_from=hub_voice_pack model=hub_voice_zh_warm_v1 provider=hub_voice_pack"
        )
    }

    @Test
    func successfulHubVoicePackPlaybackPublishesEngineSpeakerAndNativeTruth() {
        var playbackActivities: [VoicePlaybackActivity] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { _ in },
            hubVoicePackSpeakSink: { _, _, _ in
                .spoken(
                    VoicePlaybackDeliveryMetadata(
                        actualSource: .hubVoicePack,
                        provider: "transformers",
                        modelID: "hub_voice_en_calm_v1",
                        engineName: "kokoro",
                        speakerId: "bf_emma",
                        deviceBackend: "cpu",
                        nativeTTSUsed: true,
                        fallbackMode: "",
                        fallbackReasonCode: "",
                        audioFormat: "wav",
                        voiceName: "Emma",
                        reasonCode: "hub_voice_pack_played",
                        detail: "",
                        auditLine: "tts_audit status=ok provider=transformers model=hub_voice_en_calm_v1 source=native_tts route=local_runtime_command output=audio_path fallback=none deny=none"
                    )
                )
            }
        )
        synthesizer.playbackActivitySink = { playbackActivities.append($0) }

        var preferences = VoiceRuntimePreferences.default()
        preferences.playbackPreference = .hubVoicePack
        preferences.preferredHubVoicePackID = "hub_voice_en_calm_v1"

        let outcome = synthesizer.speak(
            job: SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                script: ["The build is green."],
                dedupeKey: "voice-hub-pack-truth"
            ),
            preferences: preferences,
            now: Date(timeIntervalSince1970: 3_000)
        )

        #expect(outcome == .spoken)
        #expect(playbackActivities.count == 1)
        #expect(playbackActivities[0].engineName == "kokoro")
        #expect(playbackActivities[0].speakerId == "bf_emma")
        #expect(playbackActivities[0].nativeTTSUsed == true)
        #expect(playbackActivities[0].fallbackReasonCode.isEmpty)
        #expect(playbackActivities[0].auditLine == "tts_audit status=ok provider=transformers model=hub_voice_en_calm_v1 source=native_tts route=local_runtime_command output=audio_path fallback=none deny=none")
        #expect(playbackActivities[0].summaryLine.contains("native synthesis"))
        #expect(playbackActivities[0].compactRailSummaryLine == "tts=kokoro spk=bf_emma mode=native_tts")
        #expect(
            playbackActivities[0].runtimeLogSummaryLine
            == "voice_playback state=played output=hub_voice_pack tts=kokoro spk=bf_emma mode=native_tts model=hub_voice_en_calm_v1 provider=transformers"
        )
    }

    @Test
    func fasterSpeechRateShortensEstimatedPlaybackDuration() {
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { _ in }
        )
        let job = SupervisorVoiceTTSJob(
            trigger: .userQueryReply,
            script: ["请汇总 Phoenix 项目和 Atlas 项目的当前阻塞。"],
            dedupeKey: "voice-rate-duration"
        )

        var slowPreferences = VoiceRuntimePreferences.default()
        slowPreferences.speechRateMultiplier = 0.8

        var fastPreferences = VoiceRuntimePreferences.default()
        fastPreferences.speechRateMultiplier = 1.2

        let slowDuration = synthesizer.estimatedPlaybackDuration(
            job: job,
            preferences: slowPreferences
        )
        let fastDuration = synthesizer.estimatedPlaybackDuration(
            job: job,
            preferences: fastPreferences
        )

        #expect(fastDuration < slowDuration)
    }
}
