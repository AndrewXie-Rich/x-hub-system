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
                script: ["Automation Runtime 命令"],
                dedupeKey: "voice-reply-automation-help"
            ),
            preferences: preferences,
            now: Date(timeIntervalSince1970: 1_000)
        )

        #expect(outcome == .spoken)
        #expect(spoken == ["Automation Runtime 命令"])
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

        #expect(decoded.persona == .conversational)
        #expect(decoded.interruptOnSpeech)
    }
}
