import Foundation
import Testing
@testable import XTerminal

private actor SupervisorVoiceAuthorizationRecoveryIssueProbe {
    private var counter = 0

    func nextChallengeID(prefix: String) -> String {
        counter += 1
        return "\(prefix)_\(counter)"
    }
}

private actor SupervisorVoiceAuthorizationRecoveryVerifyPlan {
    private var steps: [String]

    init(_ steps: [String]) {
        self.steps = steps
    }

    func next() -> String {
        if steps.isEmpty {
            return "deny"
        }
        return steps.removeFirst()
    }
}

private actor SupervisorVoiceAuthorizationRecoveryApproveProbe {
    private var grantIDs: [String] = []

    func record(_ grantID: String) {
        grantIDs.append(grantID)
    }

    func first() -> String? {
        grantIDs.first
    }
}

private actor SupervisorVoiceAuthorizationRecoveryBriefProbe {
    private var payloads: [HubIPCClient.SupervisorBriefProjectionRequestPayload] = []

    func record(_ payload: HubIPCClient.SupervisorBriefProjectionRequestPayload) {
        payloads.append(payload)
    }

    func first() -> HubIPCClient.SupervisorBriefProjectionRequestPayload? {
        payloads.first
    }
}

@MainActor
struct SupervisorVoiceAuthorizationRecoveryActionTests {
    private static let gate = HubGlobalStateTestGate.shared

    @Test
    func uiRepeatPromptReplaysChallengeWithoutAddingUserTurn() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
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
                                challengeId: "voice_chal_ui_repeat",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "554433",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
                                riskLevel: payload.riskLevel
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
                    requestId: "voice-ui-repeat",
                    projectId: "project-ui-repeat",
                    actionText: "Approve production release",
                    scopeText: "project=Release Runtime; capability=production release; source=Slack / 私聊消息入口; reason=需要确认生产发布",
                    riskTier: .high
                )
            )

            let userMessageCount = manager.messages.filter { $0.role == .user }.count
            let repeated = manager.repeatActiveVoiceAuthorizationPromptFromUI()

            #expect(repeated)
            try await waitUntil("ui repeat prompt rendered") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("高风险语音授权") &&
                        $0.content.contains("554433") &&
                        $0.content.contains("Approve production release")
                })
            }
            #expect(manager.messages.filter { $0.role == .user }.count == userMessageCount)
            #expect(spoken.contains(where: { $0.contains("554433") }))
        }
    }

    @Test
    func uiRestartIssuesFreshChallengeAfterDeniedVerification() async throws {
        await Self.gate.runOnMainActor { @MainActor in
            let issueProbe = SupervisorVoiceAuthorizationRecoveryIssueProbe()
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
                        let challengeID = await issueProbe.nextChallengeID(prefix: "voice_chal_ui_restart")
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: challengeID,
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "331122",
                                requiresMobileConfirm: false,
                                allowVoiceOnly: true,
                                riskLevel: payload.riskLevel
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: false,
                            decision: .deny,
                            source: "test",
                            denyCode: "semantic_ambiguous",
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:denied",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: false,
                            reasonCode: nil
                        )
                    }
                )
            )

            _ = await manager.startVoiceAuthorization(
                SupervisorVoiceAuthorizationRequest(
                    requestId: "voice-ui-restart",
                    projectId: "project-ui-restart",
                    actionText: "Approve deploy",
                    scopeText: "Release Runtime production path",
                    riskTier: .medium
                )
            )

            let denied = await manager.retryVoiceAuthorizationVerification(
                transcript: "something unclear",
                semanticMatchScore: 0.61
            )

            #expect(denied.state == .denied)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.canRestartLastVoiceAuthorizationChallengeFromUI())

            let restarted = await manager.restartLastVoiceAuthorizationChallengeFromUI()

            #expect(restarted?.state == .pending)
            #expect(restarted?.challengeId == "voice_chal_ui_restart_2")
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_ui_restart_2")
        }
    }

    @Test
    func uiRestartRestoresPendingGrantContextBeforeFreshChallenge() async throws {
        try await Self.gate.runOnMainActor { @MainActor in
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

            let root = try makeProjectRoot(named: "voice-ui-restart-pending-grant")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let grant = makePendingGrant(
                project: project,
                grantRequestId: "grant-ui-restart-1",
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

            let issueProbe = SupervisorVoiceAuthorizationRecoveryIssueProbe()
            let verifyPlan = SupervisorVoiceAuthorizationRecoveryVerifyPlan(["deny", "allow"])
            let approveProbe = SupervisorVoiceAuthorizationRecoveryApproveProbe()
            let briefProbe = SupervisorVoiceAuthorizationRecoveryBriefProbe()

            manager.installPendingHubGrantApproveOverrideForTesting { grantRequestId, _, _, _, _ in
                await approveProbe.record(grantRequestId)
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
                        topline: "Release Runtime grant 已恢复推进。",
                        blocker: "",
                        next: "继续执行 release production deploy。",
                        pendingGrantCount: 0,
                        ttsScript: [
                            "Supervisor Hub 简报。Release Runtime grant 已恢复推进。",
                            "建议下一步：继续执行 release production deploy。"
                        ],
                        auditRef: "audit-voice-ui-restart-grant"
                    ),
                    reasonCode: nil
                )
            }

            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        let challengeID = await issueProbe.nextChallengeID(prefix: "voice_chal_ui_restart_grant")
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "test",
                            challenge: makeChallenge(
                                challengeId: challengeID,
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "665544",
                                requiresMobileConfirm: true,
                                allowVoiceOnly: false,
                                riskLevel: payload.riskLevel
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        let step = await verifyPlan.next()
                        if step == "allow" {
                            return makeVerifySuccess(
                                challengeId: payload.challengeId,
                                transcriptHash: "sha256:grant-verified",
                                semanticMatchScore: payload.semanticMatchScore ?? 0,
                                mobileConfirmed: payload.mobileConfirmed
                            )
                        }
                        return HubIPCClient.VoiceGrantVerificationResult(
                            ok: true,
                            verified: false,
                            decision: .deny,
                            source: "test",
                            denyCode: "semantic_ambiguous",
                            challengeId: payload.challengeId,
                            transcriptHash: "sha256:grant-denied",
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: true,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: nil
                        )
                    }
                )
            )

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("pending grant voice challenge issued") {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_ui_restart_grant_1" &&
                    manager.activeVoicePendingGrantActionRequestIDForTesting() != nil
            }

            let denied = await manager.retryVoiceAuthorizationVerification(
                transcript: "approve release runtime grant",
                semanticMatchScore: 0.61,
                mobileConfirmed: true
            )

            #expect(denied.state == .denied)
            #expect(manager.activeVoiceChallenge == nil)
            #expect(manager.activeVoicePendingGrantActionRequestIDForTesting() == nil)
            #expect(manager.canRestartLastVoiceAuthorizationChallengeFromUI())

            let restarted = await manager.restartLastVoiceAuthorizationChallengeFromUI()

            #expect(restarted?.state == .escalatedToMobile)
            #expect(manager.activeVoiceChallenge?.challengeId == "voice_chal_ui_restart_grant_2")
            #expect(manager.activeVoicePendingGrantActionRequestIDForTesting() != nil)

            let verified = await manager.retryVoiceAuthorizationVerification(
                transcript: "approve hub grant for release runtime",
                semanticMatchScore: 0.99,
                mobileConfirmed: true
            )

            #expect(verified.state == .verified)
            #expect(await approveProbe.first() == "grant-ui-restart-1")
            #expect(manager.pendingHubGrants.isEmpty)
            try await waitUntil("restart grant follow-up brief emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                        $0.content.contains("🧭 Supervisor Brief") &&
                        $0.content.contains("Release Runtime grant 已恢复推进。") &&
                        $0.content.contains("下一步：继续执行 release production deploy。")
                })
            }
            #expect(await briefProbe.first()?.trigger == "critical_path_changed")
            #expect(spoken.contains(where: { $0.contains("Supervisor Hub 简报") }))
        }
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

    private func makeProjectEntry(root: URL, displayName: String) -> AXProjectEntry {
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
            modelId: "",
            reason: reason,
            requestedTtlSec: 900,
            requestedTokenCap: 0,
            createdAt: Date().timeIntervalSince1970,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "test",
            nextAction: "test"
        )
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-voice-ui-restart-fixtures", isDirectory: true)
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

    private func makeChallenge(
        challengeId: String,
        templateId: String,
        actionDigest: String,
        scopeDigest: String,
        amountDigest: String,
        challengeCode: String,
        requiresMobileConfirm: Bool,
        allowVoiceOnly: Bool,
        riskLevel: String
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
            boundDeviceId: "bt-headset-1",
            mobileTerminalId: "mobile-1",
            issuedAtMs: 1_730_000_000_000,
            expiresAtMs: 1_730_000_120_000
        )
    }

    private func makeVerifyFailure(reasonCode: String) -> HubIPCClient.VoiceGrantVerificationResult {
        HubIPCClient.VoiceGrantVerificationResult(
            ok: false,
            verified: false,
            decision: .failed,
            source: "test",
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
        challengeId: String,
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
}
