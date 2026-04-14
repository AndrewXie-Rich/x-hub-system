import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoiceSafetyInvariantTests {
    @Test
    func replaySummaryBuildsCompactTimeline() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .wake,
            state: .hit,
            summary: "唤醒命中",
            createdAt: 10
        )
        store.append(
            category: .authorization,
            state: .pending,
            summary: "授权挑战已发起",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 20
        )
        store.append(
            category: .playback,
            state: .interrupted,
            summary: "播报被打断",
            metadata: ["challenge_id": "chal-1"],
            createdAt: 30
        )
        store.append(
            category: .authorization,
            state: .preserved,
            summary: "待决挑战保持不变",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 40
        )

        let summary = store.buildSummary()

        #expect(summary.overallState == .attention)
        #expect(summary.headline == "待决挑战保持不变")
        #expect(summary.compactTimelineText.contains("唤醒命中"))
        #expect(summary.compactTimelineText.contains("授权挑战已发起"))
        #expect(summary.compactTimelineText.contains("播报被打断"))
        #expect(summary.compactTimelineText.contains("待决挑战保持不变"))
    }

    @Test
    func wakeRequiresChallengeEvidenceBeforeVerified() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .wake,
            state: .hit,
            summary: "唤醒命中",
            createdAt: 10
        )
        store.append(
            category: .authorization,
            state: .pending,
            summary: "授权挑战已发起",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 20
        )
        store.append(
            category: .authorization,
            state: .verified,
            summary: "口头授权已验证通过",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 30
        )

        let report = VoiceSafetyInvariantChecker.evaluate(
            VoiceSafetyInvariantContext(
                replayEvents: store.events
            )
        )

        #expect(report.overallState == .ready)
        #expect(check(report, .wakeDoesNotImplyAuthorization)?.status == .pass)
    }

    @Test
    func verifiedWithoutChallengeEvidenceFailsInvariant() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .wake,
            state: .hit,
            summary: "唤醒命中",
            createdAt: 10
        )
        store.append(
            category: .authorization,
            state: .verified,
            summary: "口头授权已验证通过",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 20
        )

        let report = VoiceSafetyInvariantChecker.evaluate(
            VoiceSafetyInvariantContext(
                replayEvents: store.events
            )
        )

        #expect(report.overallState == .failed)
        #expect(check(report, .wakeDoesNotImplyAuthorization)?.status == .fail)
    }

    @Test
    func talkLoopForwardingKeepsSupervisorGate() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .utterance,
            state: .forwarded,
            summary: "语音转入 Supervisor：talk_loop",
            metadata: [
                "capture_source": VoiceCaptureSource.talkLoop.rawValue,
                "path": "send_message",
            ],
            createdAt: 10
        )

        let report = VoiceSafetyInvariantChecker.evaluate(
            VoiceSafetyInvariantContext(
                replayEvents: store.events
            )
        )

        #expect(check(report, .talkLoopDoesNotBypassToolGates)?.status == .pass)
    }

    @Test
    func fallbackWithoutAuditFailsInvariant() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .playback,
            state: .fallback,
            summary: "语音已回退播放",
            createdAt: 10
        )

        let report = VoiceSafetyInvariantChecker.evaluate(
            VoiceSafetyInvariantContext(
                replayEvents: store.events,
                playbackActivity: makePlaybackActivity(
                    state: .fallbackPlayed,
                    auditLine: ""
                )
            )
        )

        #expect(report.overallState == .failed)
        #expect(check(report, .providerFallbackDoesNotDropAudit)?.status == .fail)
    }

    @Test
    func interruptedChallengePreservedPassesInvariant() {
        var store = VoiceReplayEventStore(maxEntries: 8)
        store.append(
            category: .playback,
            state: .interrupted,
            summary: "播报被打断",
            metadata: ["challenge_id": "chal-1"],
            createdAt: 10
        )
        store.append(
            category: .authorization,
            state: .preserved,
            summary: "待决挑战保持不变",
            metadata: ["challenge_id": "chal-1", "request_id": "req-1"],
            createdAt: 20
        )

        let report = VoiceSafetyInvariantChecker.evaluate(
            VoiceSafetyInvariantContext(
                replayEvents: store.events,
                activeChallenge: makeChallenge(challengeId: "chal-1")
            )
        )

        #expect(report.overallState == .ready)
        #expect(check(report, .interruptDoesNotCorruptPendingAuthorizationChallenge)?.status == .pass)
    }

    private func check(
        _ report: VoiceSafetyInvariantReport,
        _ kind: VoiceSafetyInvariantKind
    ) -> VoiceSafetyInvariantCheck? {
        report.checks.first { $0.kind == kind }
    }

    private func makePlaybackActivity(
        state: VoicePlaybackActivityState,
        auditLine: String
    ) -> VoicePlaybackActivity {
        VoicePlaybackActivity(
            state: state,
            configuredResolution: nil,
            actualSource: nil,
            reasonCode: "test_reason",
            detail: "",
            provider: "test_provider",
            modelID: "test_model",
            engineName: "test_engine",
            speakerId: "speaker-1",
            deviceBackend: "system_speech",
            nativeTTSUsed: true,
            fallbackMode: "system_voice_compatibility",
            fallbackReasonCode: "provider_failed",
            audioFormat: "wav",
            voiceName: "test_voice",
            auditLine: auditLine,
            updatedAt: 42
        )
    }

    private func makeChallenge(
        challengeId: String
    ) -> HubIPCClient.VoiceGrantChallengeSnapshot {
        HubIPCClient.VoiceGrantChallengeSnapshot(
            challengeId: challengeId,
            templateId: "voice.grant.v1",
            actionDigest: "action",
            scopeDigest: "scope",
            amountDigest: "amount",
            challengeCode: "123456",
            riskLevel: "high",
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            boundDeviceId: "bt-headset-1",
            mobileTerminalId: "mobile-1",
            issuedAtMs: 1000,
            expiresAtMs: 2000
        )
    }
}
