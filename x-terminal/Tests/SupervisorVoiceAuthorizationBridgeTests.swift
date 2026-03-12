import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoiceAuthorizationBridgeTests {

    @Test
    func digestMaterialIsStableAcrossWhitespaceAndCase() {
        let lhs = SupervisorVoiceAuthorizationBridge.makeDigests(
            actionText: "Approve   Release   Payment",
            scopeText: " Project   Atlas ",
            amountText: " USD 500 "
        )
        let rhs = SupervisorVoiceAuthorizationBridge.makeDigests(
            actionText: "approve release payment",
            scopeText: "project atlas",
            amountText: "usd 500"
        )

        #expect(lhs == rhs)
        #expect(lhs.actionDigest.hasPrefix("action:sha256:"))
        #expect(lhs.scopeDigest.hasPrefix("scope:sha256:"))
        #expect(lhs.amountDigest?.hasPrefix("amount:sha256:") == true)
    }

    @Test
    func highRiskBeginAuthorizationEscalatesToMobile() async {
        var verifyCalled = false
        let challenge = makeChallenge(
            challengeId: "voice_chal_high",
            requiresMobileConfirm: true,
            allowVoiceOnly: false,
            riskLevel: "high"
        )

        let bridge = SupervisorVoiceAuthorizationBridge(
            issueHandler: { payload in
                #expect(payload.riskLevel == "high")
                #expect(payload.allowVoiceOnly == false)
                #expect(payload.requiresMobileConfirm == true)
                return HubIPCClient.VoiceGrantChallengeResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    challenge: challenge,
                    reasonCode: nil
                )
            },
            verifyHandler: { _ in
                verifyCalled = true
                return makeVerifyFailure(reasonCode: "unexpected_verify")
            }
        )

        let resolution = await bridge.beginAuthorization(
            SupervisorVoiceAuthorizationRequest(
                requestId: "voice-auth-begin-high",
                projectId: "project-atlas",
                actionText: "Approve treasury transfer",
                scopeText: "Atlas release wallet",
                amountText: "USD 5000",
                riskTier: .high,
                boundDeviceId: "bt-headset-1",
                mobileTerminalId: "mobile-1"
            )
        )

        #expect(resolution.state == .escalatedToMobile)
        #expect(resolution.challenge?.challengeId == "voice_chal_high")
        #expect(resolution.requiresMobileConfirm == true)
        #expect(resolution.allowVoiceOnly == false)
        #expect(resolution.nextAction.contains("mobile confirmation"))
        #expect(verifyCalled == false)
    }

    @Test
    func authorizeWithVerificationMapsVerifiedSuccess() async {
        var capturedIssuePayload: HubIPCClient.VoiceGrantChallengeRequestPayload?
        var capturedVerifyPayload: HubIPCClient.VoiceGrantVerificationPayload?

        let bridge = SupervisorVoiceAuthorizationBridge(
            issueHandler: { payload in
                capturedIssuePayload = payload
                return HubIPCClient.VoiceGrantChallengeResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    challenge: makeChallenge(
                        challengeId: "voice_chal_low",
                        templateId: payload.templateId,
                        actionDigest: payload.actionDigest,
                        scopeDigest: payload.scopeDigest,
                        amountDigest: payload.amountDigest ?? "",
                        challengeCode: "123456",
                        requiresMobileConfirm: false,
                        allowVoiceOnly: true,
                        riskLevel: payload.riskLevel,
                        boundDeviceId: payload.boundDeviceId ?? "",
                        mobileTerminalId: payload.mobileTerminalId ?? ""
                    ),
                    reasonCode: nil
                )
            },
            verifyHandler: { payload in
                capturedVerifyPayload = payload
                return HubIPCClient.VoiceGrantVerificationResult(
                    ok: true,
                    verified: true,
                    decision: .allow,
                    source: "hub_memory_v1_grpc",
                    denyCode: nil,
                    challengeId: payload.challengeId,
                    transcriptHash: "sha256:verified-transcript",
                    semanticMatchScore: payload.semanticMatchScore ?? 0,
                    challengeMatch: true,
                    deviceBindingOK: true,
                    mobileConfirmed: payload.mobileConfirmed,
                    reasonCode: nil
                )
            }
        )

        let request = SupervisorVoiceAuthorizationRequest(
            requestId: "voice-auth-low",
            projectId: "project-atlas",
            actionText: "Approve deploy",
            scopeText: "Atlas production rollout",
            amountText: nil,
            riskTier: .medium,
            boundDeviceId: "bt-headset-1",
            mobileTerminalId: "mobile-1"
        )
        let verification = SupervisorVoiceAuthorizationVerificationInput(
            requestId: "voice-auth-low-verify",
            challengeCode: "123456",
            transcript: "Approve deploy for Atlas production rollout",
            semanticMatchScore: 0.99,
            actionText: "Approve deploy",
            scopeText: "Atlas production rollout",
            verifyNonce: "nonce-voice-auth-low",
            boundDeviceId: "bt-headset-1",
            mobileConfirmed: false
        )

        let resolution = await bridge.authorize(request: request, verification: verification)

        #expect(resolution.state == .verified)
        #expect(resolution.verified == true)
        #expect(resolution.challengeId == "voice_chal_low")
        #expect(resolution.transcriptHash == "sha256:verified-transcript")
        #expect(capturedIssuePayload?.actionDigest == capturedVerifyPayload?.parsedActionDigest)
        #expect(capturedIssuePayload?.scopeDigest == capturedVerifyPayload?.parsedScopeDigest)
        #expect(capturedVerifyPayload?.verifyNonce == "nonce-voice-auth-low")
    }

    @Test
    func verifyDenialMapsToDeniedResolution() async {
        let challenge = makeChallenge(
            challengeId: "voice_chal_denied",
            requiresMobileConfirm: false,
            allowVoiceOnly: true,
            riskLevel: "medium"
        )

        let bridge = SupervisorVoiceAuthorizationBridge(
            issueHandler: { _ in
                HubIPCClient.VoiceGrantChallengeResult(
                    ok: true,
                    source: "hub_memory_v1_grpc",
                    challenge: challenge,
                    reasonCode: nil
                )
            },
            verifyHandler: { payload in
                HubIPCClient.VoiceGrantVerificationResult(
                    ok: true,
                    verified: false,
                    decision: .deny,
                    source: "hub_memory_v1_grpc",
                    denyCode: "semantic_ambiguous",
                    challengeId: payload.challengeId,
                    transcriptHash: "sha256:denied-transcript",
                    semanticMatchScore: 0.61,
                    challengeMatch: true,
                    deviceBindingOK: true,
                    mobileConfirmed: false,
                    reasonCode: nil
                )
            }
        )

        let resolution = await bridge.authorize(
            request: SupervisorVoiceAuthorizationRequest(
                requestId: "voice-auth-denied",
                projectId: "project-atlas",
                actionText: "Approve payment",
                scopeText: "Atlas vendor settlement",
                amountText: "USD 500",
                riskTier: .medium
            ),
            verification: SupervisorVoiceAuthorizationVerificationInput(
                requestId: "voice-auth-denied-verify",
                challengeCode: "123456",
                transcript: "Something unclear",
                semanticMatchScore: 0.61,
                actionText: "Approve payment",
                scopeText: "Atlas vendor settlement",
                amountText: "USD 500",
                verifyNonce: "nonce-denied"
            )
        )

        #expect(resolution.state == .denied)
        #expect(resolution.denyCode == "semantic_ambiguous")
        #expect(resolution.nextAction.contains("retry verify"))
    }

    @Test
    func transportFailureMapsToFailClosedResolution() async {
        let bridge = SupervisorVoiceAuthorizationBridge(
            issueHandler: { _ in
                HubIPCClient.VoiceGrantChallengeResult(
                    ok: false,
                    source: "hub_memory_v1_grpc",
                    challenge: nil,
                    reasonCode: "hub_env_missing"
                )
            },
            verifyHandler: { _ in
                makeVerifyFailure(reasonCode: "unexpected_verify")
            }
        )

        let resolution = await bridge.beginAuthorization(
            SupervisorVoiceAuthorizationRequest(
                requestId: "voice-auth-fail-closed",
                projectId: "project-atlas",
                actionText: "Approve remote spend",
                scopeText: "Atlas ops budget",
                amountText: "USD 200",
                riskTier: .high
            )
        )

        #expect(resolution.state == .failClosed)
        #expect(resolution.reasonCode == "hub_env_missing")
        #expect(resolution.nextAction.contains("repair Hub pairing"))
    }

    private func makeChallenge(
        challengeId: String,
        templateId: String = "voice.grant.v1",
        actionDigest: String = "action:sha256:test",
        scopeDigest: String = "scope:sha256:test",
        amountDigest: String = "",
        challengeCode: String = "123456",
        requiresMobileConfirm: Bool,
        allowVoiceOnly: Bool,
        riskLevel: String,
        boundDeviceId: String = "bt-headset-1",
        mobileTerminalId: String = "mobile-1"
    ) -> HubIPCClient.VoiceGrantChallengeSnapshot {
        HubIPCClient.VoiceGrantChallengeSnapshot(
            challengeId: challengeId,
            templateId: templateId,
            actionDigest: actionDigest,
            scopeDigest: scopeDigest,
            amountDigest: amountDigest,
            challengeCode: challengeCode,
            riskLevel: riskLevel,
            requiresMobileConfirm: requiresMobileConfirm,
            allowVoiceOnly: allowVoiceOnly,
            boundDeviceId: boundDeviceId,
            mobileTerminalId: mobileTerminalId,
            issuedAtMs: 1_730_000_000_000,
            expiresAtMs: 1_730_000_120_000
        )
    }

    private func makeVerifyFailure(reasonCode: String) -> HubIPCClient.VoiceGrantVerificationResult {
        HubIPCClient.VoiceGrantVerificationResult(
            ok: false,
            verified: false,
            decision: .failed,
            source: "hub_memory_v1_grpc",
            denyCode: nil,
            challengeId: nil,
            transcriptHash: nil,
            semanticMatchScore: 0,
            challengeMatch: false,
            deviceBindingOK: false,
            mobileConfirmed: false,
            reasonCode: reasonCode
        )
    }
}
