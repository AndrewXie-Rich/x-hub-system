import Foundation
import Testing
@testable import XTerminal

private actor SupervisorManagerVoiceAuthorizationTestGate {
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !locked {
            locked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            locked = false
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }

    func run(_ operation: @MainActor () async throws -> Void) async rethrows {
        await acquire()
        defer { release() }
        try await operation()
    }
}

private actor SupervisorVoiceAuthorizationIssueProbe {
    private var payloads: [HubIPCClient.VoiceGrantChallengeRequestPayload] = []

    func record(_ payload: HubIPCClient.VoiceGrantChallengeRequestPayload) {
        payloads.append(payload)
    }

    func count() -> Int {
        payloads.count
    }

    func first() -> HubIPCClient.VoiceGrantChallengeRequestPayload? {
        payloads.first
    }
}

@MainActor
struct SupervisorManagerVoiceAuthorizationTests {
    private static let gate = SupervisorManagerVoiceAuthorizationTestGate()

    @Test
    func managerStartVoiceAuthorizationPublishesChallengeState() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let challenge = makeChallenge(
                challengeId: "voice_chal_manager_start",
                requiresMobileConfirm: true,
                allowVoiceOnly: false,
                riskLevel: "high"
            )
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { _ in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: challenge,
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { _ in
                        makeVerifyFailure(reasonCode: "unexpected_verify")
                    }
                )
            )

            let resolution = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-manager-start",
                    projectId: "project-atlas",
                    actionText: "Approve production payment",
                    scopeText: "Atlas treasury",
                    amountText: "USD 8000",
                    riskTier: .high,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1"
                )
            )

            #expect(resolution.state == .escalatedToMobile)
            #expect(manager.voiceAuthorizationResolution?.state == .escalatedToMobile)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_manager_start")
            #expect(manager.messages.last?.content.contains("移动端确认") == true)
        }
    }

    @Test
    func managerConfirmVoiceAuthorizationClearsChallengeAfterVerified() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_manager_verify",
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
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "hub_memory_v1_grpc",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:manager-verified",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-manager-verify-start",
                    projectId: "project-atlas",
                    actionText: "Approve deploy",
                    scopeText: "Atlas production rollout",
                    riskTier: .medium,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1"
                )
            )

            let resolution = await manager.confirmVoiceAuthorization(
                SupervisorVoiceAuthorizationVerificationInput(
                    requestId: "voice-manager-verify-confirm",
                    challengeCode: "123456",
                    transcript: "Approve deploy for Atlas production rollout",
                    semanticMatchScore: 0.99,
                    actionText: "Approve deploy",
                    scopeText: "Atlas production rollout",
                    verifyNonce: "nonce-manager-verify",
                    boundDeviceId: "bt-headset-1",
                    mobileConfirmed: false
                )
            )

            #expect(resolution.state == .verified)
            #expect(manager.voiceAuthorizationResolution?.state == .verified)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.messages.last?.content.contains("验证通过") == true)
        }
    }

    @Test
    func managerCancelVoiceAuthorizationClearsChallengeAndMarksFailClosed() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { _ in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_manager_cancel",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
                                riskLevel: "high"
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { _ in
                        makeVerifyFailure(reasonCode: "unexpected_verify")
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-manager-cancel-start",
                    projectId: "project-atlas",
                    actionText: "Approve payout",
                    scopeText: "Atlas payroll",
                    amountText: "USD 1000",
                    riskTier: .high
                )
            )
            manager.cancelVoiceAuthorization()

            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.voiceAuthorizationResolution?.state == .failClosed)
            #expect(manager.voiceAuthorizationResolution?.reasonCode == "user_cancelled")
            #expect(manager.messages.last?.content.contains("已取消语音授权挑战") == true)
        }
    }

    @Test
    func managerRetryVoiceAuthorizationVerificationUsesStoredRequestAndChallenge() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let request = SupervisorVoiceAuthorizationRequest(
                requestId: "voice-manager-retry-start",
                projectId: "project-atlas",
                actionText: "Approve deploy",
                scopeText: "Atlas production rollout",
                riskTier: .medium,
                boundDeviceId: "bt-headset-1",
                mobileTerminalId: "mobile-1"
            )
            let digests = SupervisorVoiceAuthorizationBridge.makeDigests(
                actionText: request.actionText,
                scopeText: request.scopeText,
                amountText: request.amountText
            )

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_manager_retry",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "246810",
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
                        #expect(payload.requestId == request.requestId)
                        #expect(payload.challengeId == "voice_chal_manager_retry")
                        #expect(payload.challengeCode == "246810")
                        #expect(payload.transcript == "Approve deploy for Atlas production rollout")
                        #expect(payload.parsedActionDigest == digests.actionDigest)
                        #expect(payload.parsedScopeDigest == digests.scopeDigest)
                        #expect(payload.boundDeviceId == "bt-headset-1")
                        #expect(payload.verifyNonce.isEmpty == false)

                        return HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "hub_memory_v1_grpc",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:manager-retry",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(request)

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve deploy for Atlas production rollout",
                semanticMatchScore: 0.98,
                mobileConfirmed: false
            )

            #expect(resolution.state == .verified)
            #expect(manager.voiceAuthorizationResolution?.state == .verified)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.messages.last?.content.contains("验证通过") == true)
        }
    }

    @Test
    func prepareOneShotControlPlaneStartsVoiceAuthorizationForGuardedLaunch() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            let probe = SupervisorVoiceAuthorizationIssueProbe()
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        await probe.record(payload)
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_one_shot_guarded",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "975310",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { _ in
                        makeVerifyFailure(reasonCode: "unexpected_verify")
                    }
                )
            )

            let snapshot = await manager.prepareOneShotControlPlane(
                submission: makeOneShotSubmission()
            )

            let payload = await probe.first()
            #expect(snapshot.runState.state == .awaitingGrant)
            #expect(manager.oneShotRunState?.state == .awaitingGrant)
            #expect(manager.voiceAuthorizationResolution?.state == .escalatedToMobile)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_one_shot_guarded")
            #expect(payload?.templateId == "voice.grant.guarded_one_shot_launch.v1")
            #expect(payload?.riskLevel == "high")
            #expect(payload?.allowVoiceOnly == false)
            #expect(payload?.requiresMobileConfirm == true)
            #expect(payload?.actionDigest.hasPrefix("action:sha256:") == true)
            #expect(payload?.scopeDigest.hasPrefix("scope:sha256:") == true)
        }
    }

    @Test
    func prepareOneShotControlPlaneDoesNotDuplicateActiveVoiceChallenge() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            let probe = SupervisorVoiceAuthorizationIssueProbe()
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        await probe.record(payload)
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_one_shot_dedupe",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "864200",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { _ in
                        makeVerifyFailure(reasonCode: "unexpected_verify")
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())

            #expect(await probe.count() == 1)
            #expect(manager.voiceAuthorizationResolution?.state == .escalatedToMobile)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_one_shot_dedupe")
        }
    }

    @Test
    func verifiedVoiceAuthorizationResumesGuardedOneShotLaunch() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, planDecision, buildResult in
                #expect(planDecision.requestID == "66666666-7777-8888-9999-000000000026")
                #expect(buildResult.proposal.lanes.isEmpty == false)
                return .launched(
                    LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: ["lane-1"],
                        blockedLaneReasons: ["lane-2": "dependency_not_ready"],
                        deferredLaneIDs: ["lane-3"],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[lane-1->root]::blocked:[lane-2=dependency_not_ready|lane-3=launch_queue_waiting]"
                    )
                )
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_one_shot_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "112233",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "hub_memory_v1_grpc",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:one-shot-resume",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(
                submission: makeOneShotSubmission()
            )
            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve guarded one-shot launch",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )

            #expect(resolution.state == .verified)
            #expect(manager.oneShotRunState?.state == .running)
            #expect(manager.oneShotRunState?.currentOwner == .supervisor)
            #expect(manager.oneShotRunState?.topBlocker == "none")
            #expect(manager.oneShotRunState?.nextDirectedTarget == "Supervisor")
            #expect(manager.oneShotRunState?.activeLanes == ["lane-1"])
            #expect(manager.oneShotRunState?.userVisibleSummary == "one-shot launch started: launched=1, blocked=1, deferred=1")
            #expect(manager.messages.last?.content.contains("已进入真实执行") == true)
        }
    }

    @Test
    func verifiedVoiceAuthorizationFailsClosedWithoutExecutionRuntime() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_one_shot_fail_closed",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "445566",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "hub_memory_v1_grpc",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:one-shot-fail-closed",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(
                submission: makeOneShotSubmission()
            )
            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve guarded one-shot launch",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )

            #expect(resolution.state == .verified)
            #expect(manager.oneShotRunState?.state == .failedClosed)
            #expect(manager.oneShotRunState?.topBlocker == "supervisor_model_unavailable")
            #expect(manager.oneShotRunState?.userVisibleSummary == "failed closed: supervisor_model_unavailable")
            #expect(manager.messages.last?.content.contains("失败闭锁") == true)
        }
    }

    @Test
    func prepareOneShotControlPlaneLaunchesImmediatelyWhenAuthorizationIsNotRequired() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { request, planDecision, buildResult in
                #expect(request.requiresHumanAuthorizationTypes.isEmpty)
                #expect(planDecision.requestID == request.requestID)
                return .launched(
                    LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: ["lane-1", "lane-2"],
                        blockedLaneReasons: [:],
                        deferredLaneIDs: [],
                        concurrencyLimit: 2,
                        reproducibilitySignature: "assign:[lane-1->root|lane-2->root]::blocked:[]"
                    )
                )
            }

            let snapshot = await manager.prepareOneShotControlPlane(
                submission: makeSafeOneShotSubmission()
            )

            #expect(snapshot.runState.state == .running)
            #expect(snapshot.runState.currentOwner == .supervisor)
            #expect(snapshot.runState.topBlocker == "none")
            #expect(snapshot.runState.activeLanes == ["lane-1", "lane-2"])
            #expect(snapshot.runState.userVisibleSummary == "one-shot launch started: launched=2, blocked=0, deferred=0")
            #expect(manager.voiceAuthorizationResolution == nil)
            #expect(manager.oneShotRunState?.state == .running)
            #expect(manager.messages.last?.content.contains("已进入真实执行") == true)
        }
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

    private func makeSafeOneShotSubmission() -> OneShotIntakeSubmission {
        OneShotIntakeSubmission(
            projectID: "11111111-2222-3333-4444-555555555556",
            requestID: "66666666-7777-8888-9999-000000000029",
            userGoal: "Refactor the parser module and add local unit coverage.",
            documents: [],
            contextRefs: [
                "memory://project/xt-w3-29-safe-parser"
            ],
            preferredSplitProfile: .balanced,
            participationMode: .guidedTouch,
            innovationLevel: .l1,
            tokenBudgetClass: .standard,
            deliveryMode: .implementationFirst,
            allowAutoLaunch: true,
            requiresHumanAuthorizationTypes: [],
            auditRef: "audit-xt-w3-29-safe-one-shot",
            now: Date(timeIntervalSince1970: 1_772_220_029)
        )
    }
}
