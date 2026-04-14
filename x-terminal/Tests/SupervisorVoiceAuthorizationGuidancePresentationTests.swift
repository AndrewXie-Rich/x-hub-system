import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoiceAuthorizationGuidancePresentationTests {

    @Test
    func escalatedPresentationRequiresMobileConfirmationBeforeVerify() {
        let challenge = makeChallenge(
            challengeId: "voice_chal_mobile",
            challengeCode: "442211",
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            riskLevel: "high"
        )
        let resolution = makeResolution(
            state: .escalatedToMobile,
            challenge: challenge,
            requiresMobileConfirm: true,
            allowVoiceOnly: false
        )

        let presentation = SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: challenge
        )

        #expect(presentation.summary.contains("配对手机确认"))
        #expect(presentation.instructions.contains { $0.contains("配对手机") })
        #expect(presentation.instructions.contains { $0.contains("442211") })
        #expect(presentation.caution?.contains("不会放行") == true)
    }

    @Test
    func deniedSemanticAmbiguousRequiresFreshChallenge() {
        let challenge = makeChallenge(
            challengeId: "voice_chal_denied_semantic",
            challengeCode: "118822",
            requiresMobileConfirm: false,
            allowVoiceOnly: true,
            riskLevel: "medium"
        )
        let resolution = makeResolution(
            state: .denied,
            challenge: challenge,
            denyCode: "semantic_ambiguous"
        )

        let presentation = SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: challenge
        )

        #expect(presentation.summary.contains("语义摘要"))
        #expect(presentation.instructions.contains { $0.contains("重新发起新的 challenge") })
        #expect(presentation.caution?.contains("旧 challenge") == true)
    }

    @Test
    func failClosedChallengeExpiredMarksChallengeStale() {
        let challenge = makeChallenge(
            challengeId: "voice_chal_expired",
            challengeCode: "554400",
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            riskLevel: "high"
        )
        let resolution = makeResolution(
            state: .failClosed,
            challenge: challenge,
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            reasonCode: "challenge_expired"
        )

        let presentation = SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: challenge
        )

        #expect(presentation.summary.contains("已过期"))
        #expect(presentation.instructions.contains { $0.contains("重新发起新的 challenge") })
        #expect(presentation.caution?.contains("不要再复用") == true)
    }

    @Test
    func failClosedMobileConfirmationMissingKeepsCurrentChallengeUsable() {
        let challenge = makeChallenge(
            challengeId: "voice_chal_mobile_missing",
            challengeCode: "118822",
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            riskLevel: "high"
        )
        let resolution = makeResolution(
            state: .failClosed,
            challenge: challenge,
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            reasonCode: "mobile_confirmation_missing"
        )

        let presentation = SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: challenge
        )

        #expect(presentation.summary.contains("移动端确认"))
        #expect(presentation.instructions.contains { $0.contains("配对手机") })
        #expect(presentation.instructions.contains { $0.contains("118822") })
        #expect(presentation.caution?.contains("当前 challenge 仍保留") == true)
    }

    private func makeResolution(
        state: SupervisorVoiceAuthorizationResolution.State,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot,
        requiresMobileConfirm: Bool? = nil,
        allowVoiceOnly: Bool? = nil,
        denyCode: String? = nil,
        reasonCode: String? = nil
    ) -> SupervisorVoiceAuthorizationResolution {
        SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: state,
            ok: state != .failClosed,
            requestId: "voice-auth-presentation",
            projectId: "project-atlas",
            templateId: "voice.grant.v1",
            riskTier: challenge.riskLevel,
            challengeId: challenge.challengeId,
            challenge: challenge,
            verified: state == .verified,
            requiresMobileConfirm: requiresMobileConfirm ?? challenge.requiresMobileConfirm,
            allowVoiceOnly: allowVoiceOnly ?? challenge.allowVoiceOnly,
            denyCode: denyCode,
            reasonCode: reasonCode,
            transcriptHash: nil,
            semanticMatchScore: nil,
            policyRef: "schema=test",
            nextAction: "next"
        )
    }

    private func makeChallenge(
        challengeId: String,
        challengeCode: String,
        requiresMobileConfirm: Bool,
        allowVoiceOnly: Bool,
        riskLevel: String
    ) -> HubIPCClient.VoiceGrantChallengeSnapshot {
        HubIPCClient.VoiceGrantChallengeSnapshot(
            challengeId: challengeId,
            templateId: "voice.grant.v1",
            actionDigest: "action:sha256:test",
            scopeDigest: "scope:sha256:test",
            amountDigest: "",
            challengeCode: challengeCode,
            riskLevel: riskLevel,
            requiresMobileConfirm: requiresMobileConfirm,
            allowVoiceOnly: allowVoiceOnly,
            boundDeviceId: "bt-headset-1",
            mobileTerminalId: "mobile-1",
            issuedAtMs: 1_730_000_000_000,
            expiresAtMs: 1_730_000_120_000
        )
    }
}
