import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorManagerVoicePlaybackRuntimeTests {

    @Test
    func speakSupervisorVoiceTextWritesPlaybackTruthIntoRuntimeLog() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 1),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )

        let outcome = manager.speakSupervisorVoiceText("请继续汇总当前项目进度。")

        #expect(outcome == .spoken)
        #expect(spoken == ["请继续汇总当前项目进度。"])
        #expect(manager.voicePlaybackActivity.state == .played)
        #expect(manager.latestRuntimeActivity?.text.contains("voice_playback") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("state=played") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("output=system_speech") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("tts=system") == true)
    }

    @Test
    func upstreamVoiceDispatchSuppressesRapidSameSourceRepeat() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        let job = SupervisorVoiceTTSJob(
            trigger: .completed,
            priority: .normal,
            script: ["Atlas 项目状态稳定。"],
            dedupeKey: "heartbeat-atlas-1"
        )

        let first = manager.dispatchSupervisorVoiceJobForTesting(
            job,
            source: "heartbeat",
            suppressRapidSameSourceRepeat: true,
            now: Date(timeIntervalSince1970: 10)
        )
        let second = manager.dispatchSupervisorVoiceJobForTesting(
            SupervisorVoiceTTSJob(
                trigger: .completed,
                priority: .normal,
                script: ["Atlas 项目状态稳定。"],
                dedupeKey: "heartbeat-atlas-2"
            ),
            source: "heartbeat",
            suppressRapidSameSourceRepeat: true,
            now: Date(timeIntervalSince1970: 10.2)
        )

        #expect(first == .spoken)
        #expect(second == .suppressed("source_duplicate_suppressed"))
        #expect(spoken == ["Atlas 项目状态稳定。"])
        #expect(manager.latestRuntimeActivity?.text.contains("voice_dispatch") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("state=suppressed") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("reason=source_duplicate_suppressed") == true)
    }

    @Test
    func explicitVoiceReplyCancelsPendingHeartbeatVoiceDispatch() async throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )

        manager.scheduleHeartbeatVoiceJobForTesting(
            SupervisorVoiceTTSJob(
                trigger: .completed,
                priority: .normal,
                script: ["后台心跳：Atlas 项目状态稳定。"],
                dedupeKey: "heartbeat-delayed"
            ),
            delaySec: 0.05
        )

        let outcome = manager.speakSupervisorVoiceText("用户显式回复：请继续汇总当前项目进度。")
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(outcome == .spoken)
        #expect(spoken == ["用户显式回复：请继续汇总当前项目进度。"])
        #expect(manager.runtimeActivityEntries.contains(where: {
            $0.text.contains("voice_dispatch state=cancelled source=heartbeat")
                && $0.text.contains("reason=preempted_by_voice_skill")
        }))
    }

    @Test
    func upstreamVoiceDispatchSuppressesRapidCrossSourceRepeatWithNormalizedFingerprint() {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )

        let first = manager.dispatchSupervisorVoiceJobForTesting(
            SupervisorVoiceTTSJob(
                trigger: .completed,
                priority: .normal,
                script: ["🫀 Atlas 项目状态稳定。"],
                dedupeKey: "heartbeat-atlas-voice"
            ),
            source: "heartbeat",
            suppressRapidSameSourceRepeat: true,
            now: Date(timeIntervalSince1970: 10)
        )
        let second = manager.dispatchSupervisorVoiceJobForTesting(
            SupervisorVoiceTTSJob(
                trigger: .userQueryReply,
                priority: .normal,
                script: ["Atlas 项目状态稳定"],
                dedupeKey: "voice-skill-atlas-voice"
            ),
            source: "voice_skill",
            suppressRapidSameSourceRepeat: true,
            now: Date(timeIntervalSince1970: 10.9)
        )

        #expect(first == .spoken)
        #expect(second == .suppressed("cross_source_duplicate_suppressed"))
        #expect(spoken == ["🫀 Atlas 项目状态稳定。"])
        #expect(manager.latestRuntimeActivity?.text.contains("voice_dispatch") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("reason=cross_source_duplicate_suppressed") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("detail=heartbeat") == true)
        #expect(manager.voiceDispatchAuditEntries.count >= 2)
        #expect(manager.voiceDispatchAuditEntries[0].source == "voice_skill")
        #expect(manager.voiceDispatchAuditEntries[0].reasonCode == "cross_source_duplicate_suppressed")
        #expect(manager.voiceDispatchAuditEntries[0].detail == "heartbeat")
        #expect(manager.voiceDispatchAuditEntries[1].source == "heartbeat")
        #expect(manager.voiceDispatchAuditEntries[1].state == "spoken")
    }
}
