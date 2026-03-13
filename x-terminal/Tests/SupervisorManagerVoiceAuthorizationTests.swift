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

private actor SupervisorPendingGrantApproveProbe {
    private var payloads: [(grantRequestId: String, projectId: String?, requestedTtlSec: Int?, requestedTokenCap: Int?, note: String)] = []

    func record(
        grantRequestId: String,
        projectId: String?,
        requestedTtlSec: Int?,
        requestedTokenCap: Int?,
        note: String
    ) {
        payloads.append(
            (
                grantRequestId: grantRequestId,
                projectId: projectId,
                requestedTtlSec: requestedTtlSec,
                requestedTokenCap: requestedTokenCap,
                note: note
            )
        )
    }

    func first() -> (grantRequestId: String, projectId: String?, requestedTtlSec: Int?, requestedTokenCap: Int?, note: String)? {
        payloads.first
    }
}

private actor SupervisorPendingGrantDenyProbe {
    private var payloads: [(grantRequestId: String, projectId: String?, reason: String)] = []

    func record(grantRequestId: String, projectId: String?, reason: String) {
        payloads.append((grantRequestId: grantRequestId, projectId: projectId, reason: reason))
    }

    func first() -> (grantRequestId: String, projectId: String?, reason: String)? {
        payloads.first
    }
}

private actor SupervisorVoiceAuthorizationVerifyProbe {
    private var payloads: [HubIPCClient.VoiceGrantVerificationPayload] = []

    func record(_ payload: HubIPCClient.VoiceGrantVerificationPayload) {
        payloads.append(payload)
    }

    func count() -> Int {
        payloads.count
    }

    func first() -> HubIPCClient.VoiceGrantVerificationPayload? {
        payloads.first
    }
}

private actor SupervisorBriefProjectionRequestProbe {
    private var payloads: [HubIPCClient.SupervisorBriefProjectionRequestPayload] = []

    func record(_ payload: HubIPCClient.SupervisorBriefProjectionRequestPayload) {
        payloads.append(payload)
    }

    func first() -> HubIPCClient.SupervisorBriefProjectionRequestPayload? {
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

    @Test
    func voicePendingGrantApproveIntentStartsAuthorizationAndVerifiedResolutionExecutesGrantAndRebriefs() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-approve")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-approve-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()
            let briefProbe = SupervisorBriefProjectionRequestProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grant])
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, projectId, requestedTtlSec, requestedTokenCap, note in
                await approveProbe.record(
                    grantRequestId: grantRequestId,
                    projectId: projectId,
                    requestedTtlSec: requestedTtlSec,
                    requestedTokenCap: requestedTokenCap,
                    note: note
                )
                return HubIPCClient.PendingGrantActionResult(
                    ok: true,
                    decision: .approved,
                    source: "test",
                    grantRequestId: grantRequestId,
                    grantId: grantRequestId,
                    expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                    reasonCode: nil
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                await briefProbe.record(payload)
                return HubIPCClient.SupervisorBriefProjectionResult(
                    ok: true,
                    source: "test",
                    projection: Self.makeBriefProjection(
                        projectId: payload.projectId,
                        trigger: payload.trigger,
                        topline: "发布路径已恢复。",
                        blocker: "",
                        next: "恢复 release pipeline。",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Supervisor Hub 简报。发布路径已恢复。",
                            "建议下一步：恢复 release pipeline。"
                        ],
                        auditRef: "audit-voice-grant-approve-1"
                    ),
                    reasonCode: nil
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_approve",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "981273",
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
                        return HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-approve",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准这个 release grant", fromVoice: true)

            try await waitUntil("pending grant voice challenge issued") {
                manager.voiceAuthorizationResolution?.state == .escalatedToMobile &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_approve"
            }

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve Hub grant for Release Runtime",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )
            #expect(resolution.state == .verified)

            try await waitUntil("pending grant approve follow-up brief emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("🧭 Supervisor Brief") &&
                        $0.content.contains("发布路径已恢复。") &&
                        $0.content.contains("下一步：恢复 release pipeline。")
                })
            }

            let approveCall = await approveProbe.first()
            let briefCall = await briefProbe.first()
            #expect(approveCall?.grantRequestId == "grant-release-approve-1")
            #expect(approveCall?.projectId == project.projectId)
            #expect(approveCall?.note.contains("x_terminal_supervisor_voice_grant_approve") == true)
            #expect(briefCall?.trigger == "critical_path_changed")
            #expect(manager.pendingHubGrants.isEmpty)
            #expect(spoken.contains(where: { $0.contains("mobile confirmation") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization verified") }))
            #expect(spoken.contains(where: { $0.contains("Supervisor Hub 简报") }))
        }
    }

    @Test
    func voicePendingGrantDenyIntentVerifiedResolutionExecutesDenyAndFallsBackWithoutBrief() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-deny")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Local Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-local-deny-1",
                capability: "ai.generate.local",
                reason: "local summarization retry"
            )
            let denyProbe = SupervisorPendingGrantDenyProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grant])
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.installPendingHubGrantDenyOverrideForTesting { grantRequestId, projectId, reason in
                await denyProbe.record(grantRequestId: grantRequestId, projectId: projectId, reason: reason)
                return HubIPCClient.PendingGrantActionResult(
                    ok: true,
                    decision: .denied,
                    source: "test",
                    grantRequestId: grantRequestId,
                    grantId: nil,
                    expiresAtMs: nil,
                    reasonCode: nil
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                HubIPCClient.SupervisorBriefProjectionResult(
                    ok: false,
                    source: "test",
                    projection: nil,
                    reasonCode: payload.trigger
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_deny",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "112358",
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
                        return HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-deny",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("拒绝这个 grant", fromVoice: true)

            try await waitUntil("pending grant deny challenge issued") {
                manager.voiceAuthorizationResolution?.state == .pending &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_deny"
            }

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Deny Hub grant for Local Runtime",
                semanticMatchScore: 0.99,
                mobileConfirmed: false
            )
            #expect(resolution.state == .verified)

            try await waitUntil("pending grant deny fallback reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("已拒绝 Local Runtime 的 本地模型调用 Hub grant")
                })
            }

            let denyCall = await denyProbe.first()
            #expect(denyCall?.grantRequestId == "grant-local-deny-1")
            #expect(denyCall?.projectId == project.projectId)
            #expect(denyCall?.reason.contains("voice_authorized_supervisor_denial") == true)
            #expect(manager.pendingHubGrants.isEmpty)
            #expect(spoken.contains(where: { $0.contains("Voice authorization challenge issued") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization verified") }))
            #expect(spoken.contains(where: { $0.contains("已拒绝 Local Runtime 的 本地模型调用 Hub grant") }))
        }
    }

    @Test
    func voicePendingGrantIntentFailsClosedWhenSelectionIsAmbiguous() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let rootA = try makeProjectRoot(named: "voice-pending-grant-ambiguous-a")
            let rootB = try makeProjectRoot(named: "voice-pending-grant-ambiguous-b")
            defer {
                try? FileManager.default.removeItem(at: rootA)
                try? FileManager.default.removeItem(at: rootB)
            }

            let projectA = makeProjectEntry(root: rootA, displayName: "Runtime Alpha")
            let projectB = makeProjectEntry(root: rootB, displayName: "Runtime Beta")
            let grantA = makePendingGrant(
                project: projectA,
                grantRequestId: "grant-alpha-1",
                capability: "web.fetch",
                reason: "alpha browser fetch"
            )
            let grantB = makePendingGrant(
                project: projectB,
                grantRequestId: "grant-beta-1",
                capability: "ai.generate.paid",
                reason: "beta paid model"
            )

            let appModel = AppModel()
            appModel.registry = registry(with: [projectA, projectB])
            appModel.selectedProjectId = AXProjectRegistry.globalHomeId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grantA, grantB])

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("ambiguous pending grant reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("多个待处理 Hub grant")
                })
            }

            #expect(manager.voiceAuthorizationResolution == nil)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(spoken.contains(where: { $0.contains("多个待处理 Hub grant") }))
        }
    }

    @Test
    func activeVoiceChallengeNextVoiceTurnCanVerifyPendingGrantWithoutManualRetryCall() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-continuous-verify")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-continuous-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grant])
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, projectId, requestedTtlSec, requestedTokenCap, note in
                await approveProbe.record(
                    grantRequestId: grantRequestId,
                    projectId: projectId,
                    requestedTtlSec: requestedTtlSec,
                    requestedTokenCap: requestedTokenCap,
                    note: note
                )
                return HubIPCClient.PendingGrantActionResult(
                    ok: true,
                    decision: .approved,
                    source: "test",
                    grantRequestId: grantRequestId,
                    grantId: grantRequestId,
                    expiresAtMs: (Date().timeIntervalSince1970 + 900) * 1000.0,
                    reasonCode: nil
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                HubIPCClient.SupervisorBriefProjectionResult(
                    ok: true,
                    source: "test",
                    projection: Self.makeBriefProjection(
                        projectId: payload.projectId,
                        trigger: payload.trigger,
                        topline: "发布路径已恢复。",
                        blocker: "",
                        next: "继续 release pipeline。",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Supervisor Hub 简报。发布路径已恢复。",
                            "建议下一步：继续 release pipeline。"
                        ],
                        auditRef: "audit-voice-grant-continuous-1"
                    ),
                    reasonCode: nil
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_continuous",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "773311",
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
                        return HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: true,
                            decision: .allow,
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-continuous",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准这个 release grant", fromVoice: true)
            try await waitUntil("continuous verify challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_continuous"
            }

            manager.sendMessage("手机已确认，现在批准 release grant", fromVoice: true)

            try await waitUntil("continuous voice verify finished") {
                manager.pendingHubGrants.isEmpty &&
                    manager.activeVoiceChallenge == nil &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("🧭 Supervisor Brief") &&
                            $0.content.contains("继续 release pipeline。")
                    })
            }

            let approveCall = await approveProbe.first()
            #expect(approveCall?.grantRequestId == "grant-release-continuous-1")
            #expect(spoken.contains(where: { $0.contains("Voice authorization requires mobile confirmation") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization verified") }))
            #expect(spoken.contains(where: { $0.contains("Supervisor Hub 简报") }))
        }
    }

    @Test
    func activeVoiceChallengeVoiceTurnSupportsRepeatAndCancelCommands() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
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
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_repeat_cancel",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "554433",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
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

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-repeat-cancel",
                    projectId: "project-repeat-cancel",
                    actionText: "Approve production release",
                    scopeText: "Release Runtime production path",
                    riskTier: .high
                )
            )

            manager.sendMessage("再说一遍授权要求", fromVoice: true)
            try await waitUntil("voice auth repeat prompt emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("challenge code") &&
                        $0.content.contains("Approve production release")
                })
            }

            manager.sendMessage("取消当前语音授权", fromVoice: true)
            try await waitUntil("voice auth cancel emitted") {
                manager.activeVoiceChallenge == nil &&
                    manager.voiceAuthorizationResolution?.reasonCode == "user_cancelled" &&
                    manager.messages.contains(where: {
                        $0.role == .assistant && $0.content.contains("已取消当前语音授权")
                    })
            }

            #expect(spoken.contains(where: { $0.contains("当前语音授权仍在等待移动端确认") }))
            #expect(spoken.contains(where: { $0.contains("Approve production release") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization failed closed") }))
        }
    }

    @Test
    func activeVoiceChallengeStandaloneMobileConfirmationLatchesWithoutVerifying() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let verifyProbe = SupervisorVoiceAuthorizationVerifyProbe()
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_mobile_latch_only",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "220011",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        await verifyProbe.record(payload)
                        return makeVerifyFailure(reasonCode: "unexpected_verify")
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-mobile-latch-only",
                    projectId: "project-mobile-latch-only",
                    actionText: "Approve production release",
                    scopeText: "Release Runtime production path",
                    amountText: nil,
                    riskTier: .high,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1",
                    challengeCode: nil,
                    ttlMs: 120_000
                )
            )

            manager.sendMessage("手机已确认", fromVoice: true)

            try await waitUntil("standalone mobile confirmation latched") {
                manager.voiceAuthorizationMobileConfirmationLatched &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_mobile_latch_only" &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("已记录移动端确认") &&
                            $0.content.contains("继续说授权短语")
                    })
            }

            let verifyCount = await verifyProbe.count()
            #expect(verifyCount == 0)
            #expect(manager.voiceAuthorizationResolution?.state == .escalatedToMobile)
            #expect(spoken.contains(where: { $0.contains("已记录移动端确认") }))
        }
    }

    @Test
    func activeVoiceChallengeLaterVerificationUsesLatchedMobileConfirmation() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let verifyProbe = SupervisorVoiceAuthorizationVerifyProbe()
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_mobile_latch_verify",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "331122",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        await verifyProbe.record(payload)
                        if !payload.mobileConfirmed {
                            return makeVerifyFailure(reasonCode: "mobile_confirmation_missing")
                        }
                        return makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:mobile-latch-verify",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-mobile-latch-verify",
                    projectId: "project-mobile-latch-verify",
                    actionText: "Approve production release",
                    scopeText: "Release Runtime production path",
                    amountText: nil,
                    riskTier: .high,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1",
                    challengeCode: nil,
                    ttlMs: 120_000
                )
            )

            manager.sendMessage("手机已确认", fromVoice: true)
            try await waitUntil("mobile confirmation latched before verify") {
                manager.voiceAuthorizationMobileConfirmationLatched
            }

            manager.sendMessage("批准 production release", fromVoice: true)

            try await waitUntil("latched mobile confirmation verify finished") {
                manager.voiceAuthorizationResolution?.state == .verified &&
                    manager.activeVoiceChallenge == nil
            }

            let verifyPayload = await verifyProbe.first()
            #expect(verifyPayload?.mobileConfirmed == true)
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)
            #expect(manager.messages.last?.content.contains("Approve production release") == true)
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

    private func makeVerifySuccess(
        challengeId: String?,
        transcriptHash: String,
        semanticMatchScore: Double,
        mobileConfirmed: Bool
    ) -> HubIPCClient.VoiceGrantVerificationResult {
        HubIPCClient.VoiceGrantVerificationResult(
            ok: true,
            verified: true,
            decision: .allow,
            source: "test",
            denyCode: nil,
            challengeId: challengeId,
            transcriptHash: transcriptHash,
            semanticMatchScore: semanticMatchScore,
            challengeMatch: true,
            deviceBindingOK: true,
            mobileConfirmed: mobileConfirmed,
            reasonCode: nil
        )
    }

    private func configuredSettings(from settings: XTerminalSettings) -> XTerminalSettings {
        var next = settings
        next.voice.quietHours.enabled = false
        return next
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId,
            projects: projects
        )
    }

    private func makeProjectEntry(
        root: URL,
        displayName: String
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "runtime=blocked",
            currentStateSummary: "等待授权",
            nextStepSummary: "等待 Hub grant 处理",
            blockerSummary: "等待 Hub grant",
            lastSummaryAt: Date().timeIntervalSince1970,
            lastEventAt: Date().timeIntervalSince1970
        )
    }

    private func makePendingGrant(
        project: AXProjectEntry,
        grantRequestId: String,
        capability: String,
        reason: String
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "grant:\(grantRequestId)",
            dedupeKey: "grant:\(grantRequestId)",
            grantRequestId: grantRequestId,
            requestId: "request-\(grantRequestId)",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: capability,
            modelId: capability.contains("paid") ? "openai/gpt-5.3-codex" : "",
            reason: reason,
            requestedTtlSec: 900,
            requestedTokenCap: capability.contains("paid") ? 8192 : 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "test",
            nextAction: "test"
        )
    }

    nonisolated private static func makeBriefProjection(
        projectId: String,
        trigger: String,
        topline: String,
        blocker: String,
        next: String,
        pendingGrantCount: Int,
        ttsScript: [String],
        auditRef: String
    ) -> HubIPCClient.SupervisorBriefProjectionSnapshot {
        HubIPCClient.SupervisorBriefProjectionSnapshot(
            schemaVersion: "xhub.supervisor_brief_projection.v1",
            projectionId: "projection-\(projectId)-\(auditRef)",
            projectionKind: "progress_brief",
            projectId: projectId,
            runId: "",
            missionId: "",
            trigger: trigger,
            status: blocker.isEmpty ? "running" : "blocked",
            criticalBlocker: blocker,
            topline: topline,
            nextBestAction: next,
            pendingGrantCount: pendingGrantCount,
            ttsScript: ttsScript,
            cardSummary: topline,
            evidenceRefs: ["memory://projection/\(auditRef)"],
            generatedAtMs: 1_777_000_400_000,
            expiresAtMs: 1_777_000_460_000,
            auditRef: auditRef
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-voice-grant-fixtures", isDirectory: true)
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 2_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
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
