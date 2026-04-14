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
private final class VoiceAuthorizationTalkLoopMockTranscriber: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode
    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false
    private(set) var startCount: Int = 0

    private var onChunk: ((VoiceTranscriptChunk) -> Void)?
    private var onFailure: ((String) -> Void)?

    init(
        routeMode: VoiceRouteMode = .systemSpeechCompatibility,
        authorizationStatus: VoiceTranscriberAuthorizationStatus = .authorized,
        engineHealth: VoiceEngineHealth = .ready,
        healthReasonCode: String? = nil
    ) {
        self.routeMode = routeMode
        self.authorizationStatus = authorizationStatus
        self.engineHealth = engineHealth
        self.healthReasonCode = healthReasonCode
    }

    func requestAuthorization() async -> VoiceTranscriberAuthorizationStatus {
        authorizationStatus
    }

    func refreshEngineHealth() async -> VoiceEngineHealth {
        engineHealth
    }

    func startTranscribing(
        onChunk: @escaping (VoiceTranscriptChunk) -> Void,
        onFailure: @escaping (String) -> Void
    ) throws {
        guard authorizationStatus.isAuthorized else {
            throw VoiceTranscriberError.notAuthorized
        }
        startCount += 1
        isRunning = true
        self.onChunk = onChunk
        self.onFailure = onFailure
    }

    func stopTranscribing() {
        isRunning = false
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
            #expect(!manager.canRestartLastVoiceAuthorizationChallengeFromUI())
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
    func guardedOneShotVerifiedVoiceFollowUpUsesProjectionAndResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_660)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-guarded-one-shot-followup")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = AXProjectEntry(
                projectId: oneShotTestProjectID,
                rootPath: root.path,
                displayName: "Guarded One-Shot",
                lastOpenedAt: Date().timeIntervalSince1970,
                manualOrderIndex: 0,
                pinned: false,
                statusDigest: "runtime=running",
                currentStateSummary: "执行中",
                nextStepSummary: "继续监控 lane-1",
                blockerSummary: "",
                lastSummaryAt: Date().timeIntervalSince1970,
                lastEventAt: Date().timeIntervalSince1970
            )
            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            settings.voice.speechRateMultiplier = 1.35
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)

            let projectionProbe = SupervisorBriefProjectionRequestProbe()
            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, buildResult in
                .launched(
                    LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: ["lane-1"],
                        blockedLaneReasons: [:],
                        deferredLaneIDs: [],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[lane-1->root]::blocked:[]"
                    )
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                await projectionProbe.record(payload)
                return HubIPCClient.SupervisorBriefProjectionResult(
                    ok: true,
                    source: "test",
                    projection: Self.makeBriefProjection(
                        projectId: payload.projectId,
                        trigger: payload.trigger,
                        topline: "one-shot 已进入真实执行。",
                        blocker: "",
                        next: "继续监控 lane-1。",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Supervisor Hub 简报。one-shot 已进入真实执行。",
                            "建议下一步：继续监控 lane-1。"
                        ],
                        auditRef: "audit-voice-guarded-one-shot-followup-1"
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
                                challengeId: "voice_chal_guarded_one_shot_followup",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "112233",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-followup",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_followup"
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot follow up brief emitted") {
                manager.oneShotRunState?.state == .running &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("🧭 Supervisor Brief") &&
                            $0.content.contains("one-shot 已进入真实执行。") &&
                            $0.content.contains("继续监控 lane-1。")
                    })
            }

            try await waitUntil("talk loop resumed after guarded one shot follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_guarded_one_shot_follow_up")
                    })
            }

            let projectionRequest = await projectionProbe.first()
            #expect(projectionRequest?.projectId == oneShotTestProjectID)
            #expect(projectionRequest?.trigger == "critical_path_changed")
            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("语音授权已验证通过，正在继续执行")
            }) == false)
        }
    }

    @Test
    func guardedOneShotVerifiedVoiceFollowUpHumanizesRescueGovernedReviewProjection() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(
                now: 7_662,
                supervisorSpeechSynthesizer: synthesizer
            )
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-guarded-one-shot-governed-review")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = AXProjectEntry(
                projectId: oneShotTestProjectID,
                rootPath: root.path,
                displayName: "Guarded One-Shot",
                lastOpenedAt: Date().timeIntervalSince1970,
                manualOrderIndex: 0,
                pinned: false,
                statusDigest: "runtime=running",
                currentStateSummary: "执行中",
                nextStepSummary: "继续监控 lane-1",
                blockerSummary: "",
                lastSummaryAt: Date().timeIntervalSince1970,
                lastEventAt: Date().timeIntervalSince1970
            )
            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            settings.voice.speechRateMultiplier = 1.35
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)

            let projectionProbe = SupervisorBriefProjectionRequestProbe()
            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, buildResult in
                .launched(
                    LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: ["lane-1"],
                        blockedLaneReasons: [:],
                        deferredLaneIDs: [],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[lane-1->root]::blocked:[]"
                    )
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                await projectionProbe.record(payload)
                return HubIPCClient.SupervisorBriefProjectionResult(
                    ok: true,
                    source: "test",
                    projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                        schemaVersion: "xhub.supervisor_brief_projection.v1",
                        projectionId: "guarded-one-shot-governed-review-\(payload.projectId)",
                        projectionKind: payload.projectionKind,
                        projectId: payload.projectId,
                        runId: "",
                        missionId: "",
                        trigger: payload.trigger,
                        status: "attention_required",
                        criticalBlocker: "Queued rescue governance review requires prompt supervisor attention.",
                        topline: "Project \(payload.projectId) has queued rescue governance review. Supervisor heartbeat queued it via event-driven review trigger because of weak completion evidence.",
                        nextBestAction: "Open the project and prioritize the queued rescue review before autonomous execution continues.",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Project \(payload.projectId) has queued rescue governance review.",
                            "Supervisor heartbeat queued it via event-driven review trigger because of weak completion evidence.",
                            "Next best action: Open the project and prioritize the queued rescue review before autonomous execution continues."
                        ],
                        cardSummary: "GOVERNANCE REVIEW: queued rescue governance review.",
                        evidenceRefs: ["memory://projection/guarded-one-shot-governed-review"],
                        generatedAtMs: 1_777_000_610_000,
                        expiresAtMs: 1_777_000_670_000,
                        auditRef: "audit-guarded-one-shot-governed-review-1"
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
                                challengeId: "voice_chal_guarded_one_shot_governed_review",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "112255",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-governed-review",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot governed review challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_governed_review"
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot rescue review follow up emitted") {
                manager.oneShotRunState?.state == .running &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("救援审查已排队") &&
                            $0.content.contains("完成声明证据偏弱") &&
                            $0.content.contains("查看：打开项目并优先处理这次救援审查")
                    })
            }

            try await waitUntil("talk loop resumed after guarded rescue review follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_guarded_one_shot_follow_up")
                    })
            }

            let projectionRequest = await projectionProbe.first()
            #expect(projectionRequest?.projectId == oneShotTestProjectID)
            #expect(projectionRequest?.trigger == "critical_path_changed")
            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("rescue governance review")
            }) == false)
            #expect(spoken.contains(where: { $0.contains("救援审查已排队") }))
            #expect(spoken.contains(where: { $0.contains("完成声明证据偏弱") }))
            #expect(!spoken.contains(where: { $0.contains("rescue governance review") }))
        }
    }

    @Test
    func guardedOneShotVerifiedVoiceFollowUpUnavailableProjectionResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_661)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, buildResult in
                .launched(
                    LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: ["lane-1"],
                        blockedLaneReasons: [:],
                        deferredLaneIDs: [],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[lane-1->root]::blocked:[]"
                    )
                )
            }
            manager.installSupervisorBriefProjectionFetcherForTesting { payload in
                HubIPCClient.SupervisorBriefProjectionResult(
                    ok: false,
                    source: "test",
                    projection: nil,
                    reasonCode: "projection_unavailable"
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_guarded_one_shot_followup_unavailable",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "112244",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-followup-unavailable",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot unavailable challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_followup_unavailable"
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot unavailable follow up emitted") {
                manager.oneShotRunState?.state == .running &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("⚠️ Hub Brief 暂不可用") &&
                            $0.content.contains("guarded one-shot 已进入真实执行") &&
                            $0.content.contains("没有拿到 Hub 统一投影")
                    })
            }

            try await waitUntil("talk loop resumed after guarded one shot unavailable follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_guarded_one_shot_follow_up")
                    })
            }

            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("🧭 Supervisor Brief")
            }) == false)
        }
    }

    @Test
    func guardedOneShotVerifiedVoiceFollowUpReportsBlockedLaunchTruthfully() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, buildResult in
                .blocked(
                    reason: "dependency_not_ready",
                    report: LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: [],
                        blockedLaneReasons: ["lane-1": "dependency_not_ready"],
                        deferredLaneIDs: [],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[]::blocked:[lane-1=dependency_not_ready]"
                    )
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_guarded_one_shot_blocked",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "445577",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-blocked",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot blocked challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_blocked"
            }

            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot blocked follow up emitted") {
                manager.oneShotRunState?.state == .blocked &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("还没有进入执行") &&
                            $0.content.contains("dependency_not_ready")
                    })
            }

            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("语音授权已验证通过，正在继续执行")
            }) == false)
        }
    }

    @Test
    func guardedOneShotBlockedVoiceFollowUpResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_662)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, buildResult in
                .blocked(
                    reason: "dependency_not_ready",
                    report: LaneLaunchReport(
                        splitPlanID: buildResult.proposal.splitPlanId.uuidString.lowercased(),
                        launchedLaneIDs: [],
                        blockedLaneReasons: ["lane-1": "dependency_not_ready"],
                        deferredLaneIDs: [],
                        concurrencyLimit: 1,
                        reproducibilitySignature: "assign:[]::blocked:[lane-1=dependency_not_ready]"
                    )
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_guarded_one_shot_blocked_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "445578",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-blocked-resume",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot blocked resume challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_blocked_resume"
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot blocked resume follow up emitted") {
                manager.oneShotRunState?.state == .blocked &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("还没有进入执行") &&
                            $0.content.contains("dependency_not_ready")
                    })
            }

            try await waitUntil("talk loop resumed after guarded one shot blocked follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_guarded_one_shot_blocked")
                    })
            }
        }
    }

    @Test
    func guardedOneShotVerifiedVoiceFollowUpReportsFailClosedTruthfully() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.resetOneShotControlPlaneState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, _ in
                .failedClosed(reason: "legacy_supervisor_runtime_unavailable")
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_guarded_one_shot_fail_closed_followup",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "667788",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-fail-closed-followup",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot fail closed challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_fail_closed_followup"
            }

            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot fail closed follow up emitted") {
                manager.oneShotRunState?.state == .failedClosed &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("失败闭锁") &&
                            $0.content.contains("legacy_supervisor_runtime_unavailable")
                    })
            }

            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("语音授权已验证通过，正在继续执行")
            }) == false)
        }
    }

    @Test
    func guardedOneShotFailClosedVoiceFollowUpResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_663)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.resetOneShotControlPlaneState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installPreparedOneShotLaunchExecutorForTesting { _, _, _ in
                .failedClosed(reason: "legacy_supervisor_runtime_unavailable")
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_guarded_one_shot_fail_closed_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "667789",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:guarded-one-shot-fail-closed-resume",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.prepareOneShotControlPlane(submission: makeOneShotSubmission())
            try await waitUntil("guarded one shot fail closed resume challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_guarded_one_shot_fail_closed_resume"
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            manager.sendMessage("Approve guarded one-shot launch", fromVoice: true)

            try await waitUntil("guarded one shot fail closed resume follow up emitted") {
                manager.oneShotRunState?.state == .failedClosed &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("失败闭锁") &&
                            $0.content.contains("legacy_supervisor_runtime_unavailable")
                    })
            }

            try await waitUntil("talk loop resumed after guarded one shot fail closed follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_guarded_one_shot_fail_closed")
                    })
            }
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
            #expect(manager.oneShotRunState?.topBlocker == "legacy_supervisor_runtime_unavailable")
            #expect(manager.oneShotRunState?.userVisibleSummary == "failed closed: legacy_supervisor_runtime_unavailable")
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
    func ensureOneShotAnchorProjectCreatesLowRiskRootWithGovernanceTiers() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            let supervisor = SupervisorModel()
            let request = makeAnchorIntakeRequest(
                projectID: "11111111-2222-3333-4444-555555555560",
                requestID: "66666666-7777-8888-9999-000000000060",
                userGoal: "Stabilize parser internals and ship repo-only fixes."
            )
            let planDecision = makeAnchorPlanDecision(
                projectID: request.projectID,
                requestID: request.requestID,
                riskSurface: .low
            )

            let project = await manager.ensureOneShotAnchorProjectForTesting(
                in: supervisor,
                request: request,
                planDecision: planDecision
            )

            #expect(project.name == "Root")
            #expect(project.status == .running)
            #expect(project.taskDescription == request.userGoal)
            #expect(project.executionTier == .a3DeliverAuto)
            #expect(project.supervisorInterventionTier == .s2PeriodicReview)
            #expect(project.autonomyLevel == .auto)
            #expect(project.currentModel.id == "one-shot-anchor-low")
            #expect(supervisor.activeProjects.count == 1)
            #expect(supervisor.activeProjects.first?.id == project.id)
        }
    }

    @Test
    func ensureOneShotAnchorProjectRefreshesExistingRootToCriticalGovernance() async {
        await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            let supervisor = SupervisorModel()
            let staleRoot = ProjectModel(
                name: "Root",
                taskDescription: "Old root",
                status: .pending,
                modelName: "legacy-root",
                autonomyLevel: .manual,
                executionTier: .a1Plan,
                supervisorInterventionTier: .s1MilestoneReview
            )
            staleRoot.status = .pending
            supervisor.activeProjects = [staleRoot]

            let request = makeAnchorIntakeRequest(
                projectID: "11111111-2222-3333-4444-555555555561",
                requestID: "66666666-7777-8888-9999-000000000061",
                userGoal: "Execute the critical production recovery flow."
            )
            let planDecision = makeAnchorPlanDecision(
                projectID: request.projectID,
                requestID: request.requestID,
                riskSurface: .critical
            )

            let project = await manager.ensureOneShotAnchorProjectForTesting(
                in: supervisor,
                request: request,
                planDecision: planDecision
            )

            #expect(project.id == staleRoot.id)
            #expect(project.status == .running)
            #expect(project.taskDescription == request.userGoal)
            #expect(project.executionTier == .a4OpenClaw)
            #expect(project.supervisorInterventionTier == .s4TightSupervision)
            #expect(project.autonomyLevel == .fullAuto)
            #expect(project.currentModel.id == "one-shot-anchor-critical")
            #expect(supervisor.activeProjects.count == 1)
            #expect(supervisor.activeProjects.first?.id == staleRoot.id)
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
            let now = Date()
            let nowMs = now.timeIntervalSince1970 * 1000.0
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "test",
                    updatedAtMs: nowMs,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-grant-approve",
                            requestId: "request-voice-grant-approve",
                            projectId: project.projectId,
                            connector: "slack",
                            targetId: "dm-release",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-release",
                            messageId: "message-voice-grant-approve",
                            dedupeKey: "sha256:voice-grant-approve",
                            receivedAtMs: nowMs - 5_000,
                            eventSequence: 8,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )
            manager.setPendingHubGrantsForTesting([grant], now: now)
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
            try await waitUntil("pending grant source reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("Slack / 私聊消息入口")
                })
            }
            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("Slack / 私聊消息入口")
            }))

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
    func wakeHitDoesNotAutoAuthorizeHighRiskPendingGrantVoiceAction() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let now = Date(timeIntervalSince1970: 7_205)
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .systemSpeechCompatibility,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-wake-challenge")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-wake-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            appModel.settingsStore.settings = settings
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grant], now: now)
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
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_after_wake",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "661199",
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

            try await waitUntil("wake mode promoted for pending grant wake auth") {
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
            }

            manager.handleVoiceWakeEventForTesting(
                phrase: "supervisor",
                route: .systemSpeechCompatibility,
                timestamp: now.timeIntervalSince1970
            )

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.openedBy == .wakePhrase)

            manager.sendMessage("批准这个 release grant", fromVoice: true)

            try await waitUntil("wake-triggered high risk action still asks challenge") {
                manager.voiceAuthorizationResolution?.state == .escalatedToMobile &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_after_wake"
            }

            let approveCall = await approveProbe.first()
            #expect(approveCall == nil)
            #expect(spoken.contains(where: { $0.contains("mobile confirmation") }))
        }
    }

    @Test
    func voicePendingGrantApproveUsesFriendlyProjectNameFromPendingSnapshotNormalization() async throws {
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

            let root = try makeProjectRoot(named: "voice-pending-grant-snapshot-friendly-name")
            defer { try? FileManager.default.removeItem(at: root) }

            let friendlyName = "Headset Grocery Run"
            let project = makeProjectEntry(root: root, displayName: friendlyName)
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingGrantSnapshotForTesting(
                HubIPCClient.PendingGrantSnapshot(
                    source: "hub_runtime_grpc",
                    updatedAtMs: Date().timeIntervalSince1970 * 1000.0,
                    items: [
                        HubIPCClient.PendingGrantItem(
                            grantRequestId: "grant-snapshot-voice-1",
                            requestId: "request-snapshot-voice-1",
                            deviceId: "device_xt_001",
                            userId: "user-voice-1",
                            appId: "x-terminal",
                            projectId: project.projectId,
                            capability: "web.fetch",
                            modelId: "",
                            reason: "buy groceries from remote workflow",
                            requestedTtlSec: 900,
                            requestedTokenCap: 0,
                            status: "pending",
                            decision: "queued",
                            createdAtMs: Date().timeIntervalSince1970 * 1000.0,
                            decidedAtMs: 0
                        )
                    ]
                )
            )
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
                                challengeId: "voice_chal_pending_grant_snapshot_friendly",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "765432",
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
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-snapshot-friendly",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            #expect(manager.pendingHubGrants.count == 1)
            #expect(manager.pendingHubGrants.first?.projectName == friendlyName)
            #expect(manager.pendingHubGrants.first?.projectName.contains(root.lastPathComponent) == false)

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("pending grant voice challenge issued with normalized friendly name") {
                manager.voiceAuthorizationResolution?.state == .escalatedToMobile &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_snapshot_friendly" &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains(friendlyName) &&
                            !$0.content.contains(root.lastPathComponent)
                    })
            }

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve Hub grant for \(friendlyName)",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )
            #expect(resolution.state == .verified)

            try await waitUntil("pending grant friendly fallback reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("已批准 \(friendlyName) 的 联网访问 Hub 授权") &&
                        !$0.content.contains(root.lastPathComponent)
                })
            }

            let approveCall = await approveProbe.first()
            #expect(approveCall?.grantRequestId == "grant-snapshot-voice-1")
            #expect(approveCall?.projectId == project.projectId)
            #expect(manager.pendingHubGrants.isEmpty)
            #expect(spoken.contains(where: { $0.contains(friendlyName) }))
            #expect(spoken.allSatisfy { !$0.contains(root.lastPathComponent) })
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
                        $0.content.contains("已拒绝 Local Runtime 的 本地文本模型调用 Hub 授权")
                })
            }

            let denyCall = await denyProbe.first()
            #expect(denyCall?.grantRequestId == "grant-local-deny-1")
            #expect(denyCall?.projectId == project.projectId)
            #expect(denyCall?.reason.contains("voice_authorized_supervisor_denial") == true)
            #expect(manager.pendingHubGrants.isEmpty)
            #expect(spoken.contains(where: { $0.contains("Voice authorization challenge issued") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization verified") }))
            #expect(spoken.contains(where: { $0.contains("已拒绝 Local Runtime 的 本地文本模型调用 Hub 授权") }))
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
            let now = Date()
            let nowMs = now.timeIntervalSince1970 * 1000.0
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "test",
                    updatedAtMs: nowMs,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-ambiguous-a",
                            requestId: "request-voice-ambiguous-a",
                            projectId: projectA.projectId,
                            connector: "slack",
                            targetId: "dm-alpha",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-alpha",
                            messageId: "message-voice-ambiguous-a",
                            dedupeKey: "sha256:voice-ambiguous-a",
                            receivedAtMs: nowMs - 5_000,
                            eventSequence: 1,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        ),
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-ambiguous-b",
                            requestId: "request-voice-ambiguous-b",
                            projectId: projectB.projectId,
                            connector: "telegram",
                            targetId: "group-beta",
                            ingressType: "connector_event",
                            channelScope: "group",
                            sourceId: "user-beta",
                            messageId: "message-voice-ambiguous-b",
                            dedupeKey: "sha256:voice-ambiguous-b",
                            receivedAtMs: nowMs - 4_000,
                            eventSequence: 2,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )
            manager.setPendingHubGrantsForTesting([grantA, grantB], now: now)

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("ambiguous pending grant reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("多笔待处理的 Hub 授权")
                })
            }

            #expect(manager.voiceAuthorizationResolution == nil)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(spoken.contains(where: { $0.contains("多笔待处理的 Hub 授权") }))
            #expect(
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("Runtime Alpha / 联网访问 / 授权单号：grant-alpha-1") &&
                        $0.content.contains("Runtime Beta / 付费模型调用（openai/gpt-5.3-codex） / 授权单号：grant-beta-1") &&
                        $0.content.contains("如果要指定某一笔，可以直接补授权单号")
                })
            )
        }
    }

    @Test
    func voicePendingGrantIntentSelectsGrantByRemoteIngressAlias() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let rootA = try makeProjectRoot(named: "voice-pending-grant-source-dm")
            let rootB = try makeProjectRoot(named: "voice-pending-grant-source-group")
            defer {
                try? FileManager.default.removeItem(at: rootA)
                try? FileManager.default.removeItem(at: rootB)
            }

            let projectA = makeProjectEntry(root: rootA, displayName: "Remote Slack DM")
            let projectB = makeProjectEntry(root: rootB, displayName: "Remote Slack Group")
            let grantA = makePendingGrant(
                project: projectA,
                grantRequestId: "grant-slack-dm-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let grantB = makePendingGrant(
                project: projectB,
                grantRequestId: "grant-slack-group-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )

            let appModel = AppModel()
            appModel.registry = registry(with: [projectA, projectB])
            appModel.selectedProjectId = AXProjectRegistry.globalHomeId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)

            let now = Date()
            let nowMs = now.timeIntervalSince1970 * 1000.0
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "test",
                    updatedAtMs: nowMs,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-source-dm",
                            requestId: "request-voice-source-dm",
                            projectId: projectA.projectId,
                            connector: "slack",
                            targetId: "dm-release",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-release-dm",
                            messageId: "message-voice-source-dm",
                            dedupeKey: "sha256:voice-source-dm",
                            receivedAtMs: nowMs - 5_000,
                            eventSequence: 11,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        ),
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-source-group",
                            requestId: "request-voice-source-group",
                            projectId: projectB.projectId,
                            connector: "slack",
                            targetId: "group-release",
                            ingressType: "connector_event",
                            channelScope: "group",
                            sourceId: "user-release-group",
                            messageId: "message-voice-source-group",
                            dedupeKey: "sha256:voice-source-group",
                            receivedAtMs: nowMs - 4_000,
                            eventSequence: 12,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )
            manager.setPendingHubGrantsForTesting([grantA, grantB], now: now)

            var issuedProjectID: String?
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        issuedProjectID = payload.projectId
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_source_scope",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel
                            ),
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准私聊那个 grant", fromVoice: true)

            try await waitUntil("voice challenge issued for dm grant") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_source_scope"
            }

            #expect(issuedProjectID == projectA.projectId)
            #expect(manager.messages.last?.content.contains(projectA.displayName) == true)
        }
    }

    @Test
    func voicePendingGrantIntentSelectsGrantByRemoteProviderAlias() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let rootA = try makeProjectRoot(named: "voice-pending-grant-provider-slack")
            let rootB = try makeProjectRoot(named: "voice-pending-grant-provider-feishu")
            defer {
                try? FileManager.default.removeItem(at: rootA)
                try? FileManager.default.removeItem(at: rootB)
            }

            let projectA = makeProjectEntry(root: rootA, displayName: "Slack Remote")
            let projectB = makeProjectEntry(root: rootB, displayName: "Feishu Remote")
            let grantA = makePendingGrant(
                project: projectA,
                grantRequestId: "grant-slack-provider-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let grantB = makePendingGrant(
                project: projectB,
                grantRequestId: "grant-feishu-provider-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )

            let appModel = AppModel()
            appModel.registry = registry(with: [projectA, projectB])
            appModel.selectedProjectId = AXProjectRegistry.globalHomeId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)

            let now = Date()
            let nowMs = now.timeIntervalSince1970 * 1000.0
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "test",
                    updatedAtMs: nowMs,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-provider-slack",
                            requestId: "request-voice-provider-slack",
                            projectId: projectA.projectId,
                            connector: "slack",
                            targetId: "dm-provider-slack",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-provider-slack",
                            messageId: "message-voice-provider-slack",
                            dedupeKey: "sha256:voice-provider-slack",
                            receivedAtMs: nowMs - 5_000,
                            eventSequence: 21,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        ),
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "receipt-voice-provider-feishu",
                            requestId: "request-voice-provider-feishu",
                            projectId: projectB.projectId,
                            connector: "feishu",
                            targetId: "dm-provider-feishu",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-provider-feishu",
                            messageId: "message-voice-provider-feishu",
                            dedupeKey: "sha256:voice-provider-feishu",
                            receivedAtMs: nowMs - 4_000,
                            eventSequence: 22,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )
            manager.setPendingHubGrantsForTesting([grantA, grantB], now: now)

            var issuedProjectID: String?
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        issuedProjectID = payload.projectId
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_provider_scope",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                riskLevel: payload.riskLevel
                            ),
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准 Slack 那个 grant", fromVoice: true)

            try await waitUntil("voice challenge issued for slack grant") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_provider_scope"
            }
            try await waitUntil("slack grant source reply emitted") {
                manager.messages.contains(where: {
                    $0.content.contains("Slack / 私聊消息入口")
                })
            }

            #expect(issuedProjectID == projectA.projectId)
            #expect(manager.messages.contains(where: {
                $0.content.contains("Slack / 私聊消息入口")
            }))
        }
    }

    @Test
    func voicePendingGrantIntentWithoutPendingGrantUsesSharedEmptyReply() async throws {
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

            manager.setPendingHubGrantsForTesting([])
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }

            manager.sendMessage("批准这个 grant", fromVoice: true)

            let expectedReply = XTHubGrantPresentation.emptyPendingReply(projectName: nil)
            try await waitUntil("empty pending grant reply emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content == expectedReply
                })
            }

            #expect(manager.voiceAuthorizationResolution == nil)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(spoken.contains(where: { $0.contains(expectedReply) }))
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
    func pendingGrantVerifiedVoiceFollowUpBriefResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_650)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-followup-resume")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-followup-resume-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            settings.voice.speechRateMultiplier = 1.35
            appModel.settingsStore.settings = settings
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
                        auditRef: "audit-voice-grant-followup-resume-1"
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
                                challengeId: "voice_chal_pending_grant_followup_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "773312",
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
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-followup-resume",
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

            try await waitUntil("pending grant challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_followup_resume"
            }

            try await waitUntil("talk loop resumed after pending grant prompt", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount >= 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_voice_reply")
                    })
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            voiceCoordinator.stopRecording()
            try await waitUntil("talk loop paused for next voice turn") {
                !voiceCoordinator.isRecording && !transcriber.isRunning
            }

            manager.sendMessage("手机已确认，现在批准 release grant", fromVoice: true)

            try await waitUntil("pending grant follow up brief emitted") {
                manager.pendingHubGrants.isEmpty &&
                    manager.activeVoiceChallenge == nil &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("🧭 Supervisor Brief") &&
                            $0.content.contains("继续 release pipeline。")
                    })
            }

            try await waitUntil("talk loop resumed after pending grant follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_follow_up")
                    })
            }

            let approveCall = await approveProbe.first()
            #expect(approveCall?.grantRequestId == "grant-release-followup-resume-1")
        }
    }

    @Test
    func pendingGrantVerifiedVoiceFollowUpHumanizesGovernedReviewProjection() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(
                now: 7_652,
                supervisorSpeechSynthesizer: synthesizer
            )
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-followup-governed-review")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Review Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-followup-governed-review-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            settings.voice.speechRateMultiplier = 1.35
            appModel.settingsStore.settings = settings
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
                    projection: HubIPCClient.SupervisorBriefProjectionSnapshot(
                        schemaVersion: "xhub.supervisor_brief_projection.v1",
                        projectionId: "governed-review-followup-\(payload.projectId)",
                        projectionKind: payload.projectionKind,
                        projectId: payload.projectId,
                        runId: "",
                        missionId: "",
                        trigger: payload.trigger,
                        status: "attention_required",
                        criticalBlocker: "",
                        topline: "Project \(payload.projectId) has queued strategic governance review. Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
                        nextBestAction: "Open the project and inspect why the queued governance review was scheduled.",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Project \(payload.projectId) has queued strategic governance review.",
                            "Supervisor heartbeat queued it via no-progress brainstorm cadence because of long no progress.",
                            "Next best action: Open the project and inspect why the queued governance review was scheduled."
                        ],
                        cardSummary: "GOVERNANCE REVIEW: queued strategic governance review.",
                        evidenceRefs: ["memory://projection/governed-review-followup"],
                        generatedAtMs: 1_777_000_500_000,
                        expiresAtMs: 1_777_000_560_000,
                        auditRef: "audit-voice-grant-followup-governed-review-1"
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
                                challengeId: "voice_chal_pending_grant_followup_governed_review",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "773314",
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
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-followup-governed-review",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准这个 review grant", fromVoice: true)

            try await waitUntil("pending grant governed review challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_followup_governed_review"
            }

            try await waitUntil("talk loop resumed after governed review prompt", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_voice_reply")
                    })
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            voiceCoordinator.stopRecording()
            try await waitUntil("talk loop paused before governed review follow up") {
                !voiceCoordinator.isRecording && !transcriber.isRunning
            }

            manager.sendMessage("手机已确认，现在批准 review grant", fromVoice: true)

            try await waitUntil("pending grant governed review follow up emitted") {
                manager.pendingHubGrants.isEmpty &&
                    manager.activeVoiceChallenge == nil &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("治理审查已排队") &&
                            $0.content.contains("长时间无进展") &&
                            $0.content.contains("查看：打开项目并查看这次治理审查")
                    })
            }

            try await waitUntil("talk loop resumed after governed review follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_follow_up")
                    })
            }

            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("strategic governance review")
            }) == false)
            #expect(spoken.contains(where: { $0.contains("治理审查已排队") }))
            #expect(spoken.contains(where: { $0.contains("长时间无进展") }))
            #expect(!spoken.contains(where: { $0.contains("strategic governance review") }))

            let approveCall = await approveProbe.first()
            #expect(approveCall?.grantRequestId == "grant-release-followup-governed-review-1")
        }
    }

    @Test
    func pendingGrantVerifiedVoiceFollowUpUnavailableProjectionFailsClosedAndResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_651)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-followup-unavailable")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-release-followup-unavailable-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )
            let approveProbe = SupervisorPendingGrantApproveProbe()

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            settings.voice.speechRateMultiplier = 1.35
            appModel.settingsStore.settings = settings
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
            manager.installSupervisorBriefProjectionFetcherForTesting { _ in
                HubIPCClient.SupervisorBriefProjectionResult(
                    ok: false,
                    source: "test",
                    projection: nil,
                    reasonCode: "projection_unavailable"
                )
            }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_pending_grant_followup_unavailable",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "773313",
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
                            source: "test",
                            denyCode: nil,
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-grant-followup-unavailable",
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

            try await waitUntil("pending grant unavailable challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_pending_grant_followup_unavailable"
            }

            try await waitUntil("talk loop resumed after pending grant unavailable prompt", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount >= 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_voice_reply")
                    })
            }

            let resumeCountBeforeFollowUp = transcriber.startCount
            voiceCoordinator.stopRecording()
            try await waitUntil("talk loop paused before unavailable follow up") {
                !voiceCoordinator.isRecording && !transcriber.isRunning
            }

            manager.sendMessage("手机已确认，现在批准 release grant", fromVoice: true)

            try await waitUntil("pending grant unavailable follow up emitted") {
                manager.pendingHubGrants.isEmpty &&
                    manager.activeVoiceChallenge == nil &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("⚠️ Hub Brief 暂不可用") &&
                            $0.content.contains("已批准 Release Runtime 的") &&
                            $0.content.contains("没有拿到 Hub 统一投影") &&
                            $0.content.contains("不在 XT 本地即兴拼接 Supervisor brief")
                    })
            }

            try await waitUntil("talk loop resumed after pending grant unavailable follow up", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == resumeCountBeforeFollowUp + 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: pending_grant_follow_up")
                    })
            }

            let approveCall = await approveProbe.first()
            #expect(approveCall?.grantRequestId == "grant-release-followup-unavailable-1")
            #expect(manager.messages.contains(where: {
                $0.role == .assistant &&
                    $0.content.contains("🧭 Supervisor Brief")
            }) == false)
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
                    scopeText: "project=Release Runtime; capability=production release; source=Slack / 私聊消息入口; reason=需要确认生产发布",
                    riskTier: .high
                )
            )

            manager.sendMessage("再说一遍授权要求", fromVoice: true)
            try await waitUntil("voice auth repeat prompt emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("高风险语音授权") &&
                        $0.content.contains("Slack / 私聊消息入口") &&
                        $0.content.contains("554433") &&
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

            #expect(spoken.contains(where: { $0.contains("高风险语音授权") }))
            #expect(spoken.contains(where: { $0.contains("Slack / 私聊消息入口") }))
            #expect(spoken.contains(where: { $0.contains("554433") }))
            #expect(spoken.contains(where: { $0.contains("Voice authorization failed closed") }))
        }
    }

    @Test
    func activeVoiceChallengeRepeatPromptResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_610)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_repeat_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "110022",
                                requiresMobileConfirm: false,
                                allowVoiceOnly: true,
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
                    requestId: "voice-repeat-resume",
                    projectId: "project-repeat-resume",
                    actionText: "Approve release",
                    scopeText: "project=Release; source=Slack",
                    riskTier: .high
                )
            )

            #expect(transcriber.startCount == 0)
            manager.sendMessage("再说一遍授权要求", fromVoice: true)

            try await waitUntil("voice auth repeat prompt emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("高风险语音授权") &&
                        $0.content.contains("110022") &&
                        $0.content.contains("Approve release")
                })
            }

            try await waitUntil("talk loop resumed after repeat prompt", timeoutMs: 7_500) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_repeat_prompt")
                    })
            }
        }
    }

    @Test
    func activeVoiceChallengeCancelReplyResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_620)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_cancel_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "220011",
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
                    requestId: "voice-cancel-resume",
                    projectId: "project-cancel-resume",
                    actionText: "Approve release",
                    scopeText: "project=Release; source=Slack",
                    riskTier: .high
                )
            )

            #expect(transcriber.startCount == 0)
            manager.sendMessage("取消当前语音授权", fromVoice: true)

            try await waitUntil("voice auth cancel emitted") {
                manager.activeVoiceChallenge == nil &&
                    manager.voiceAuthorizationResolution?.reasonCode == "user_cancelled" &&
                    manager.messages.contains(where: {
                        $0.role == .assistant && $0.content.contains("已取消当前语音授权")
                    })
            }

            try await waitUntil("talk loop resumed after cancel", timeoutMs: 4_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_cancel")
                    })
            }
        }
    }

    @Test
    func activeVoiceChallengeSpeechInterruptPreservesChallengeAndAllowsLaterVerification() async throws {
        try await Self.gate.run {
            var interruptCount = 0
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { _ in },
                interruptSink: {
                    interruptCount += 1
                    return true
                }
            )
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(
                now: 7_625,
                supervisorSpeechSynthesizer: synthesizer
            )
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_interrupt_preserve",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "990011",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-auth-interrupt-preserved",
                            semanticMatchScore: payload.semanticMatchScore ?? 0.97,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-interrupt-preserve",
                    projectId: "project-interrupt-preserve",
                    actionText: "Approve production release",
                    scopeText: "project=Release Runtime; capability=production release; source=voice challenge; reason=需要确认生产发布",
                    riskTier: .medium
                )
            )

            let interruptCountBeforeSpeech = interruptCount

            await voiceCoordinator.startRecording()
            try await waitUntil("voice auth interrupt enters listening") {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_interrupt_preserve" &&
                    manager.voiceAuthorizationResolution?.state == .pending
            }

            #expect(interruptCount == interruptCountBeforeSpeech + 1)

            voiceCoordinator.stopRecording()
            manager.sendMessage("Approve production release", fromVoice: true)

            try await waitUntil("voice auth interrupt can still verify afterward") {
                manager.activeVoiceChallenge == nil &&
                    manager.voiceAuthorizationResolution?.state == .verified &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("语音授权已验证通过")
                    })
            }
        }
    }

    @Test
    func wakeHitDuringActiveVoiceChallengePreservesChallengeAndAllowsLaterVerification() async throws {
        try await Self.gate.run {
            let now = Date(timeIntervalSince1970: 7_626)
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .systemSpeechCompatibility,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let manager = SupervisorManager.makeForTesting(
                conversationSessionController: controller
            )
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            let appModel = AppModel()
            var settings = configuredSettings(from: appModel.settingsStore.settings)
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_wake_preserve",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "552211",
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
                        makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:voice-auth-wake-preserved",
                            semanticMatchScore: payload.semanticMatchScore ?? 0.97,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            try await waitUntil("wake mode promoted for active challenge preservation") {
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
            }

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-wake-preserve",
                    projectId: "project-wake-preserve",
                    actionText: "Approve production release",
                    scopeText: "project=Release Runtime; capability=production release; source=wake challenge; reason=需要确认生产发布",
                    riskTier: .medium
                )
            )

            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_wake_preserve")
            #expect(manager.voiceAuthorizationResolution?.state == .pending)

            manager.handleVoiceWakeEventForTesting(
                phrase: "supervisor",
                route: .systemSpeechCompatibility,
                timestamp: now.timeIntervalSince1970 + 1
            )

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.openedBy == .wakePhrase)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_wake_preserve")
            #expect(manager.voiceAuthorizationResolution?.state == .pending)

            manager.sendMessage("Approve production release", fromVoice: true)

            try await waitUntil("wake preserved challenge can still verify") {
                manager.activeVoiceChallenge == nil &&
                    manager.voiceAuthorizationResolution?.state == .verified &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("语音授权已验证通过")
                    })
            }
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
    func activeVoiceChallengeStandaloneMobileConfirmationReplyResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_630)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_mobile_confirmed_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "330044",
                                requiresMobileConfirm: true,
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

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-mobile-confirmed-resume",
                    projectId: "project-mobile-confirmed-resume",
                    actionText: "Approve release",
                    scopeText: "project=Release; source=Slack",
                    amountText: nil,
                    riskTier: .high,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1",
                    challengeCode: nil,
                    ttlMs: 120_000
                )
            )

            #expect(transcriber.startCount == 0)
            manager.sendMessage("手机已确认", fromVoice: true)

            try await waitUntil("standalone mobile confirmation emitted") {
                manager.voiceAuthorizationMobileConfirmationLatched &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_mobile_confirmed_resume" &&
                    manager.messages.contains(where: {
                        $0.role == .assistant &&
                            $0.content.contains("已记录移动端确认") &&
                            $0.content.contains("继续说授权短语")
                    })
            }

            try await waitUntil("talk loop resumed after mobile confirmation", timeoutMs: 4_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_mobile_confirmed")
                    })
            }
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

    @Test
    func expiredVoiceAuthorizationChallengeClearsPendingGrantVoiceState() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetVoiceAuthorizationState()
            manager.clearMessages()
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
            }

            let root = try makeProjectRoot(named: "voice-pending-grant-expired-cleanup")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-expired-cleanup-1",
                capability: "web.fetch",
                reason: "release production deploy"
            )

            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            appModel.settingsStore.settings = configuredSettings(from: appModel.settingsStore.settings)
            manager.setAppModel(appModel)
            manager.setPendingHubGrantsForTesting([grant])
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_expired_cleanup",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "554400",
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
                        makeVerifyFailure(reasonCode: "challenge_expired")
                    }
                )
            )

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("expired challenge issued for pending grant") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_expired_cleanup" &&
                    manager.activeVoicePendingGrantActionRequestIDForTesting() != nil
            }

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve Hub grant for Release Runtime",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )

            #expect(resolution.state == .failClosed)
            #expect(resolution.reasonCode == "challenge_expired")
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)
            #expect(manager.activeVoicePendingGrantActionRequestIDForTesting() == nil)
            #expect(manager.pendingHubGrants.count == 1)

            let retryAfterCleanup = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve Hub grant for Release Runtime",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )

            #expect(retryAfterCleanup.state == .failClosed)
            #expect(retryAfterCleanup.reasonCode == "voice_authorization_not_started")
        }
    }

    @Test
    func mobileConfirmationMissingFailClosedPreservesChallengeForRetry() async throws {
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
                                challengeId: "voice_chal_mobile_missing_retry",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "118822",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
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
                            transcriptHash: "sha256:mobile-missing-retry",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-mobile-missing-retry",
                    projectId: "project-mobile-missing-retry",
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

            let firstResolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve production release",
                semanticMatchScore: 0.99,
                mobileConfirmed: false
            )

            #expect(firstResolution.state == .failClosed)
            #expect(firstResolution.reasonCode == "mobile_confirmation_missing")
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_mobile_missing_retry")
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)

            manager.sendMessage("手机已确认", fromVoice: true)

            try await waitUntil("mobile confirmation relatched after fail closed") {
                manager.voiceAuthorizationMobileConfirmationLatched &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_mobile_missing_retry"
            }

            let secondResolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve production release",
                semanticMatchScore: 0.99
            )

            #expect(secondResolution.state == .verified)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)
            #expect(await verifyProbe.count() == 2)
        }
    }

    @Test
    func activeVoiceChallengeFailClosedRetryReplyResumesTalkLoopListening() async throws {
        try await Self.gate.run {
            let fixture = try await makeVoiceAuthorizationTalkLoopFixture(now: 7_640)
            let manager = fixture.manager
            let voiceCoordinator = fixture.voiceCoordinator
            let transcriber = fixture.transcriber
            defer {
                manager.resetVoiceAuthorizationState()
                manager.clearMessages()
                manager.endConversationSession(reasonCode: "test_cleanup")
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: "voice_chal_retry_resume",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "771100",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        if !payload.mobileConfirmed {
                            return makeVerifyFailure(reasonCode: "mobile_confirmation_missing")
                        }
                        return makeVerifySuccess(
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:retry-resume",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-retry-resume",
                    projectId: "project-retry-resume",
                    actionText: "Approve release",
                    scopeText: "project=Release; source=Slack",
                    amountText: nil,
                    riskTier: .high,
                    boundDeviceId: "bt-headset-1",
                    mobileTerminalId: "mobile-1",
                    challengeCode: nil,
                    ttlMs: 120_000
                )
            )

            #expect(transcriber.startCount == 0)
            manager.sendMessage("批准 release", fromVoice: true)

            try await waitUntil("fail closed retry reply emitted", timeoutMs: 4_000) {
                manager.voiceAuthorizationResolution?.state == .failClosed &&
                    manager.voiceAuthorizationResolution?.reasonCode == "mobile_confirmation_missing" &&
                    manager.activeVoiceChallenge?.challengeId == "voice_chal_retry_resume"
            }

            try await waitUntil("talk loop resumed after fail closed retry", timeoutMs: 8_000) {
                voiceCoordinator.isRecording &&
                    transcriber.isRunning &&
                    transcriber.startCount == 1 &&
                    voiceCoordinator.runtimeState.state == .listening &&
                    voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed" &&
                    manager.recentEventsForTesting().contains(where: {
                        $0.contains("voice talk loop resumed: voice_auth_verification_reply")
                    })
            }
        }
    }

    @Test
    func externalMobileConfirmationLatchFeedsLaterVerificationWithoutAutoVerifying() async {
        await Self.gate.run {
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
                                challengeId: "voice_chal_external_mobile_latch",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "442211",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
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
                            transcriptHash: "sha256:external-mobile-latch",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            mobileConfirmed: payload.mobileConfirmed
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-external-mobile-latch",
                    projectId: "project-external-mobile-latch",
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

            manager.setVoiceAuthorizationMobileConfirmed(
                true,
                source: "voice_authorization_card",
                emitSystemMessage: false
            )

            #expect(manager.voiceAuthorizationMobileConfirmationLatched)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_external_mobile_latch")
            #expect(await verifyProbe.count() == 0)

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve production release",
                semanticMatchScore: 0.99
            )

            #expect(resolution.state == .verified)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)
            #expect(await verifyProbe.count() == 1)
        }
    }

    @Test
    func externalMobileConfirmationLatchClearsAfterTerminalFailClosed() async {
        await Self.gate.run {
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
                                challengeId: "voice_chal_external_mobile_expired",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "664422",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
                                riskLevel: payload.riskLevel,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? ""
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        await verifyProbe.record(payload)
                        return makeVerifyFailure(reasonCode: "challenge_expired")
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-external-mobile-expired",
                    projectId: "project-external-mobile-expired",
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

            manager.setVoiceAuthorizationMobileConfirmed(
                true,
                source: "voice_authorization_card",
                emitSystemMessage: false
            )

            let resolution = await manager.retryVoiceAuthorizationVerification(
                transcript: "Approve production release",
                semanticMatchScore: 0.99
            )

            #expect(resolution.state == .failClosed)
            #expect(resolution.reasonCode == "challenge_expired")
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.voiceAuthorizationMobileConfirmationLatched == false)
            #expect(await verifyProbe.count() == 1)
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
            nextStepSummary: "等待 Hub 授权处理",
            blockerSummary: "等待 Hub 授权",
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

    private func makeVoiceAuthorizationTalkLoopFixture(
        now timestamp: TimeInterval,
        supervisorSpeechSynthesizer: SupervisorSpeechSynthesizer? = nil
    ) async throws -> (
        manager: SupervisorManager,
        voiceCoordinator: VoiceSessionCoordinator,
        transcriber: VoiceAuthorizationTalkLoopMockTranscriber
    ) {
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .systemSpeechCompatibility,
            wakeMode: .wakePhrase,
            nowProvider: { Date(timeIntervalSince1970: timestamp) }
        )
        let transcriber = VoiceAuthorizationTalkLoopMockTranscriber()
        let voiceCoordinator = VoiceSessionCoordinator(
            transcriber: transcriber,
            preferences: .default()
        )
        let synthesizer = supervisorSpeechSynthesizer ?? SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { _ in }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer,
            conversationSessionController: controller,
            voiceSessionCoordinator: voiceCoordinator
        )
        let appModel = AppModel()
        var settings = appModel.settingsStore.settings
        settings.voice.wakeMode = .wakePhrase
        settings.voice.preferredRoute = .systemSpeechCompatibility
        settings.voice.speechRateMultiplier = 1.35
        appModel.settingsStore.settings = settings
        manager.setAppModel(appModel)
        await voiceCoordinator.refreshRouteAvailability()
        try await waitUntil("voice route ready") {
            manager.voiceRouteDecision.route == .systemSpeechCompatibility &&
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
        }
        manager.openConversationSession(openedBy: .wakePhrase)
        try await waitUntil("conversation opened") {
            manager.conversationSessionSnapshot.isConversing
        }
        return (manager, voiceCoordinator, transcriber)
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

    private func makeAnchorIntakeRequest(
        projectID: String,
        requestID: String,
        userGoal: String
    ) -> SupervisorOneShotIntakeRequest {
        SupervisorOneShotIntakeRequest(
            schemaVersion: "xterminal.supervisor_one_shot_intake_request.v1",
            projectID: projectID,
            requestID: requestID,
            userGoal: userGoal,
            contextRefs: ["memory://project/\(projectID)"],
            preferredSplitProfile: .balanced,
            participationMode: .guidedTouch,
            innovationLevel: .l1,
            tokenBudgetClass: .standard,
            deliveryMode: .implementationFirst,
            allowAutoLaunch: true,
            requiresHumanAuthorizationTypes: [],
            auditRef: "audit-anchor-\(requestID)"
        )
    }

    private func makeAnchorPlanDecision(
        projectID: String,
        requestID: String,
        riskSurface: OneShotRiskSurface
    ) -> AdaptivePoolPlanDecision {
        AdaptivePoolPlanDecision(
            schemaVersion: "xterminal.adaptive_pool_plan_decision.v1",
            projectID: projectID,
            requestID: requestID,
            complexityScore: riskSurface == .critical ? 0.95 : 0.35,
            riskSurface: riskSurface,
            selectedProfile: .balanced,
            selectedParticipationMode: .guidedTouch,
            selectedInnovationLevel: .l1,
            poolCount: 1,
            laneCount: 1,
            poolPlan: [
                AdaptivePoolPlanPoolEntry(
                    poolID: "pool-root",
                    purpose: "root anchor",
                    laneIDs: ["lane-root"],
                    requiresIsolation: riskSurface >= .high
                )
            ],
            seatCap: 1,
            blockRiskScore: riskSurface == .critical ? 0.9 : 0.2,
            estimatedMergeCost: riskSurface == .critical ? 0.8 : 0.1,
            decisionExplain: ["test_anchor_governance"],
            decision: .allow,
            denyCode: "none",
            auditRef: "audit-plan-\(requestID)"
        )
    }
}
