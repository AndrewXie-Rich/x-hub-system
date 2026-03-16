import Foundation
import Testing
@testable import XTerminal

private actor SupervisorConversationSessionTestGate {
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

@MainActor
struct SupervisorConversationSessionIntegrationTests {
    private static let gate = SupervisorConversationSessionTestGate()

    @Test
    func voiceQueryOpensConversationAndReplyKeepsItConversing() async throws {
        try await Self.gate.run {
            var now = Date(timeIntervalSince1970: 4_000)
            var spoken: [String] = []
            let controller = SupervisorConversationSessionController.makeForTesting(
                nowProvider: { now }
            )
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller
            )
            let appModel = AppModel()
            var settings = appModel.settingsStore.settings
            settings.voice.wakeMode = .pushToTalk
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)
            spoken.removeAll()

            try await waitUntil("wake mode reset to push to talk") {
                manager.conversationSessionSnapshot.wakeMode == .pushToTalk
            }

            manager.sendMessage("/automation", fromVoice: true)

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "user_turn")

            try await waitUntil("assistant reply committed") {
                manager.messages.contains { message in
                    message.role == .assistant && message.content.contains("Automation Runtime 命令")
                }
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "tts_spoken")
            #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 45)
            #expect(spoken.count == 1)
            #expect(spoken.last?.contains("Automation Runtime 命令") == true)

            now = now.addingTimeInterval(46)
            controller.refresh()

            #expect(manager.conversationSessionSnapshot.windowState == .hidden)
            #expect(manager.conversationSessionSnapshot.reasonCode == "ttl_expired")
        }
    }

    @Test
    func voiceUnderfedMemoryFollowUpHoldsConversationUntilFactsAreCompleted() async throws {
        try await Self.gate.run {
            var now = Date(timeIntervalSince1970: 5_000)
            var spoken: [String] = []
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .funasrStreaming,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller
            )

            let root = try makeProjectRoot(named: "voice-memory-follow-up")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "亮亮")
            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            manager.setAppModel(appModel)
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    projectID: project.projectId,
                    profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                    resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                    contextRefsSelected: 0,
                    evidenceItemsSelected: 0,
                    truncatedLayers: ["l1_canonical"]
                )
            )

            manager.sendMessage("审查亮亮项目的上下文记忆，直接做战略纠偏", fromVoice: true)

            try await waitUntil("voice follow-up prompt emitted") {
                manager.messages.contains(where: {
                    $0.role == .assistant && $0.content.contains("我们一项一项补")
                })
            }
            try await waitUntil("voice follow-up prompt settled", timeoutMs: 5_000) {
                !manager.isProcessing
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "awaiting_memory_fact_follow_up")
            #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 180)
            #expect(manager.supervisorPendingMemoryFactFollowUpStatusLine.contains("亮亮"))
            #expect(manager.supervisorPendingMemoryFactFollowUpQuestion.contains("长期目标和完成标准"))
            #expect(spoken.contains(where: { $0.contains("我们一项一项补") }))

            now = now.addingTimeInterval(60)
            controller.refresh()
            #expect(manager.conversationSessionSnapshot.windowState == .conversing)

            manager.sendMessage(
                "目标是让 supervisor 用耳机持续汇报项目，完成标准是能一句话授权",
                fromVoice: true
            )

            try await waitUntil("voice follow-up advanced to decision", timeoutMs: 5_000) {
                manager.messages.contains(where: {
                    $0.role == .assistant && $0.content.contains("关键决策和原因是什么")
                })
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "awaiting_memory_fact_follow_up")
            #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 180)
            #expect(manager.supervisorPendingMemoryFactFollowUpStatusLine.contains("亮亮"))
            #expect(manager.supervisorPendingMemoryFactFollowUpQuestion.contains("关键决策和原因是什么"))

            manager.sendMessage(
                "我们决定先走 Hub 通道，原因是权限和审计统一",
                fromVoice: true
            )

            try await waitUntil("voice follow-up advanced to blocker", timeoutMs: 5_000) {
                manager.messages.contains(where: {
                    $0.role == .assistant && $0.content.contains("现在卡在哪里")
                })
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "awaiting_memory_fact_follow_up")
            #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 180)
            #expect(manager.supervisorPendingMemoryFactFollowUpStatusLine.contains("亮亮"))
            #expect(manager.supervisorPendingMemoryFactFollowUpQuestion.contains("现在卡在哪里"))

            manager.sendMessage(
                "现在卡在 voice wake 误触发太多，已经试过调阈值，下一步是先把唤醒日志打通，证据是 staging smoke 已稳定通过 12 次",
                fromVoice: true
            )

            try await waitUntil("voice follow-up completion emitted", timeoutMs: 5_000) {
                manager.messages.contains(where: {
                    $0.role == .assistant && $0.content.contains("你现在可以直接再让我审查一次方向")
                })
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(manager.conversationSessionSnapshot.reasonCode == "tts_spoken")
            #expect(manager.conversationSessionSnapshot.remainingTTLSeconds == 45)
            #expect(manager.supervisorPendingMemoryFactFollowUpStatusLine == "memory follow-up: idle")
            #expect(manager.supervisorPendingMemoryFactFollowUpQuestion.isEmpty)
            #expect(spoken.last?.contains("当前卡点我已经记进项目现状了") == true)
        }
    }

    @Test
    func voiceReplyResumesTalkLoopListeningWhenWakeSessionRemainsConversing() async throws {
        try await Self.gate.run {
            let now = Date(timeIntervalSince1970: 6_000)
            var spoken: [String] = []
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .systemSpeechCompatibility,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let transcriber = IntegrationMockVoiceStreamingTranscriber()
            let voiceCoordinator = VoiceSessionCoordinator(
                transcriber: transcriber,
                preferences: .default()
            )
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { spoken.append($0) }
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
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)
            manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }
            manager.setPendingHubGrantsForTesting([])

            try await waitUntil("wake mode promoted to continuous session") {
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
            }

            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("empty grant reply committed", timeoutMs: 5_000) {
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                    $0.content.contains("当前没有待处理的 Hub grant")
                })
            }

            try await waitUntil("talk loop resumed listening", timeoutMs: 6_000) {
                voiceCoordinator.isRecording &&
                voiceCoordinator.runtimeState.state == .listening &&
                voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed"
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(spoken.contains(where: { $0.contains("当前没有待处理的 Hub grant") }))
            #expect(transcriber.isRunning)
        }
    }

    @Test
    func proactivePendingGrantAnnouncementResumesListeningAndAnchorsGenericApproveUtterance() async throws {
        try await Self.gate.run {
            let now = Date(timeIntervalSince1970: 7_000)
            var spoken: [String] = []
            var issuedProjectID: String?
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .systemSpeechCompatibility,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let transcriber = IntegrationMockVoiceStreamingTranscriber()
            let voiceCoordinator = VoiceSessionCoordinator(
                transcriber: transcriber,
                preferences: .default()
            )
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller,
                voiceSessionCoordinator: voiceCoordinator
            )
            manager.installVoiceAuthorizationBridgeForTesting(
                SupervisorVoiceAuthorizationBridge(
                    issueHandler: { payload in
                        issuedProjectID = payload.projectId
                        return HubIPCClient.VoiceGrantChallengeResult(
                            ok: true,
                            source: "hub_memory_v1_grpc",
                            challenge: HubIPCClient.VoiceGrantChallengeSnapshot(
                                challengeId: "voice_chal_proactive_pending_grant",
                                templateId: payload.templateId,
                                actionDigest: payload.actionDigest,
                                scopeDigest: payload.scopeDigest,
                                amountDigest: payload.amountDigest ?? "",
                                challengeCode: "246810",
                                riskLevel: payload.riskLevel,
                                requiresMobileConfirm: payload.requiresMobileConfirm,
                                allowVoiceOnly: payload.allowVoiceOnly,
                                boundDeviceId: payload.boundDeviceId ?? "",
                                mobileTerminalId: payload.mobileTerminalId ?? "",
                                issuedAtMs: 1_777_100_000_000,
                                expiresAtMs: 1_777_100_120_000
                            ),
                            reasonCode: nil
                        )
                    },
                    verifyHandler: { payload in
                        HubIPCClient.VoiceGrantVerificationResult(
                            ok: false,
                            verified: false,
                            decision: .failed,
                            source: "hub_memory_v1_grpc",
                            denyCode: "unexpected_verify",
                            challengeId: payload.challengeId,
                            transcriptHash: nil,
                            semanticMatchScore: payload.semanticMatchScore ?? 0,
                            challengeMatch: false,
                            deviceBindingOK: true,
                            mobileConfirmed: payload.mobileConfirmed,
                            reasonCode: "unexpected_verify"
                        )
                    }
                )
            )

            let rootA = try makeProjectRoot(named: "voice-proactive-grant-a")
            let rootB = try makeProjectRoot(named: "voice-proactive-grant-b")
            defer {
                try? FileManager.default.removeItem(at: rootA)
                try? FileManager.default.removeItem(at: rootB)
            }

            let projectA = makeProjectEntry(root: rootA, displayName: "Release Runtime")
            let projectB = makeProjectEntry(root: rootB, displayName: "Local Review")
            let appModel = AppModel()
            appModel.registry = registry(with: [projectA, projectB])
            var settings = appModel.settingsStore.settings
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)

            try await waitUntil("wake mode promoted to continuous session") {
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
            }

            manager.setPendingHubGrantsForTesting([], announceNewArrivals: true)
            manager.setPendingHubGrantsForTesting(
                [
                    makePendingGrant(
                        project: projectA,
                        grantRequestId: "grant-release-web",
                        capability: "web.fetch",
                        modelId: "",
                        reason: "需要联网检查 release 域名",
                        requestedTtlSec: 900,
                        requestedTokenCap: 0
                    ),
                    makePendingGrant(
                        project: projectB,
                        grantRequestId: "grant-local-review",
                        capability: "ai.generate.local",
                        modelId: "qwen3-14b-mlx",
                        reason: "补一轮本地 review",
                        requestedTtlSec: 600,
                        requestedTokenCap: 0
                    )
                ],
                announceNewArrivals: true
            )

            try await waitUntil("proactive grant alert emitted") {
                spoken.contains(where: {
                    $0.contains("待处理的 Hub grant") &&
                    $0.contains("Release Runtime") &&
                    $0.contains("批准这个 grant")
                }) &&
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                    $0.content.contains("grant=grant-release-web")
                })
            }

            try await waitUntil("proactive grant alert resumed listening", timeoutMs: 6_000) {
                voiceCoordinator.isRecording &&
                voiceCoordinator.runtimeState.state == .listening &&
                voiceCoordinator.runtimeState.reasonCode == "talk_loop_resumed"
            }

            voiceCoordinator.stopRecording()
            manager.sendMessage("批准这个 grant", fromVoice: true)

            try await waitUntil("generic approve anchored to announced grant", timeoutMs: 5_000) {
                manager.activeVoiceChallenge?.challengeId == "voice_chal_proactive_pending_grant"
            }

            #expect(manager.conversationSessionSnapshot.windowState == .conversing)
            #expect(issuedProjectID == projectA.projectId)
        }
    }

    @Test
    func proactivePendingGrantAnnouncementIncludesFreshRemoteChannelSource() async throws {
        try await Self.gate.run {
            let now = Date(timeIntervalSince1970: 8_000)
            var spoken: [String] = []
            let controller = SupervisorConversationSessionController.makeForTesting(
                route: .systemSpeechCompatibility,
                wakeMode: .wakePhrase,
                nowProvider: { now }
            )
            let transcriber = IntegrationMockVoiceStreamingTranscriber()
            let voiceCoordinator = VoiceSessionCoordinator(
                transcriber: transcriber,
                preferences: .default()
            )
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 60),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer,
                conversationSessionController: controller,
                voiceSessionCoordinator: voiceCoordinator
            )

            let root = try makeProjectRoot(named: "voice-proactive-grant-remote")
            defer { try? FileManager.default.removeItem(at: root) }

            let project = makeProjectEntry(root: root, displayName: "Release Runtime")
            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            var settings = appModel.settingsStore.settings
            settings.voice.wakeMode = .wakePhrase
            settings.voice.preferredRoute = .systemSpeechCompatibility
            appModel.settingsStore.settings = settings
            manager.setAppModel(appModel)
            manager.setConnectorIngressSnapshotForTesting(
                HubIPCClient.ConnectorIngressSnapshot(
                    source: "hub_runtime_grpc",
                    updatedAtMs: 8_000_000,
                    items: [
                        HubIPCClient.ConnectorIngressReceipt(
                            receiptId: "hub-slack-grant-001",
                            requestId: "req-hub-slack-grant-001",
                            projectId: project.projectId,
                            connector: "slack",
                            targetId: "dm-42",
                            ingressType: "connector_event",
                            channelScope: "dm",
                            sourceId: "user-42",
                            messageId: "msg-slack-grant-001",
                            dedupeKey: "sha256:hub-slack-grant-001",
                            receivedAtMs: 7_995_000,
                            eventSequence: 21,
                            deliveryState: "accepted",
                            runtimeState: "queued"
                        )
                    ]
                ),
                now: now
            )

            try await waitUntil("wake mode promoted to continuous session") {
                manager.conversationSessionSnapshot.wakeMode == .wakePhrase
            }

            manager.setPendingHubGrantsForTesting(
                [],
                announceNewArrivals: true,
                now: now
            )
            manager.setPendingHubGrantsForTesting(
                [
                    makePendingGrant(
                        project: project,
                        grantRequestId: "grant-release-remote",
                        capability: "web.fetch",
                        modelId: "",
                        reason: "需要联网检查 release 域名",
                        requestedTtlSec: 900,
                        requestedTokenCap: 0
                    )
                ],
                announceNewArrivals: true,
                now: now
            )

            try await waitUntil("proactive grant alert includes remote source") {
                spoken.contains(where: {
                    $0.contains("Slack") &&
                    $0.contains("私聊消息入口")
                }) &&
                manager.messages.contains(where: {
                    $0.role == .assistant &&
                    $0.content.contains("来源：Slack / 私聊消息入口")
                })
            }
        }
    }

    @Test
    func textUnderfedMemoryFollowUpPushesOffscreenReminderOnlyWhenQuestionAdvances() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            let root = try makeProjectRoot(named: "text-memory-follow-up-notify")
            defer { try? FileManager.default.removeItem(at: root) }
            var reminders: [(title: String, body: String, actionURL: String?)] = []
            manager.installSupervisorMemoryFollowUpReminderOverrideForTesting { title, body, actionURL in
                reminders.append((title: title, body: body, actionURL: actionURL))
            }

            let project = makeProjectEntry(root: root, displayName: "亮亮")
            let appModel = AppModel()
            appModel.registry = registry(with: [project])
            appModel.selectedProjectId = project.projectId
            manager.setAppModel(appModel)
            manager.setSupervisorMemoryAssemblySnapshotForTesting(
                makeMemorySnapshot(
                    projectID: project.projectId,
                    profileFloor: XTMemoryServingProfile.m3DeepDive.rawValue,
                    resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                    contextRefsSelected: 0,
                    evidenceItemsSelected: 0,
                    truncatedLayers: ["l1_canonical"]
                )
            )

            manager.sendMessage("审查亮亮项目的上下文记忆，直接做战略纠偏")

            try await waitUntil("goal follow-up question ready", timeoutMs: 5_000) {
                !manager.isProcessing &&
                manager.supervisorPendingMemoryFactFollowUpQuestion.contains("长期目标和完成标准")
            }

            manager.sendMessage("目标是让 supervisor 用耳机持续汇报项目，完成标准是能一句话授权")

            try await waitUntil("decision follow-up question ready", timeoutMs: 5_000) {
                !manager.isProcessing &&
                manager.supervisorPendingMemoryFactFollowUpQuestion.contains("关键决策和原因")
            }

            manager.sendMessage("目标是让 supervisor 用耳机持续汇报项目，完成标准是能一句话授权")

            try await waitUntil("duplicate goal patch settled", timeoutMs: 5_000) {
                !manager.isProcessing
            }

            try await waitUntil("two follow-up reminders observed", timeoutMs: 5_000) {
                reminders.count == 2
            }

            #expect(reminders.count == 2)
            #expect(reminders.allSatisfy { $0.title == "待补背景：亮亮" })
            #expect(reminders.contains { $0.body.contains("长期目标和完成标准分别是什么") })
            #expect(reminders.contains { $0.body.contains("关键决策和原因是什么") })
            #expect(reminders.compactMap(\.actionURL).allSatisfy { $0.contains(project.projectId) })
        }
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

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("xterminal_\(name)_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeProjectEntry(
        root: URL,
        displayName: String
    ) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName,
            lastOpenedAt: 1_773_000_000,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: 1_773_000_000,
            lastEventAt: 1_773_000_000
        )
    }

    private func registry(with projects: [AXProjectEntry]) -> AXProjectRegistry {
        AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_000_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projects.first?.projectId ?? AXProjectRegistry.globalHomeId,
            projects: projects,
        )
    }

    private func makePendingGrant(
        project: AXProjectEntry,
        grantRequestId: String,
        capability: String,
        modelId: String,
        reason: String,
        requestedTtlSec: Int,
        requestedTokenCap: Int
    ) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "grant:\(grantRequestId)",
            dedupeKey: "grant:\(grantRequestId)",
            grantRequestId: grantRequestId,
            requestId: "request:\(grantRequestId)",
            projectId: project.projectId,
            projectName: project.displayName,
            capability: capability,
            modelId: modelId,
            reason: reason,
            requestedTtlSec: requestedTtlSec,
            requestedTokenCap: requestedTokenCap,
            createdAt: 1_777_100_000,
            actionURL: nil,
            priorityRank: 1,
            priorityReason: "test",
            nextAction: "test"
        )
    }

    private func makeMemorySnapshot(
        projectID: String,
        reviewLevelHint: SupervisorReviewLevel = .r2Strategic,
        requestedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        profileFloor: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        resolvedProfile: String = XTMemoryServingProfile.m3DeepDive.rawValue,
        contextRefsSelected: Int = 2,
        evidenceItemsSelected: Int = 2,
        omittedSections: [String] = [],
        truncatedLayers: [String] = []
    ) -> SupervisorMemoryAssemblySnapshot {
        SupervisorMemoryAssemblySnapshot(
            source: "unit_test",
            resolutionSource: "unit_test",
            updatedAt: 1_773_000_000,
            reviewLevelHint: reviewLevelHint.rawValue,
            requestedProfile: requestedProfile,
            profileFloor: profileFloor,
            resolvedProfile: resolvedProfile,
            attemptedProfiles: [requestedProfile, resolvedProfile],
            progressiveUpgradeCount: 0,
            focusedProjectId: projectID,
            selectedSections: [
                "portfolio_brief",
                "focused_project_anchor_pack",
                "longterm_outline",
                "delta_feed",
                "conflict_set",
                "context_refs",
                "evidence_pack",
            ],
            omittedSections: omittedSections,
            contextRefsSelected: contextRefsSelected,
            contextRefsOmitted: max(0, 2 - contextRefsSelected),
            evidenceItemsSelected: evidenceItemsSelected,
            evidenceItemsOmitted: max(0, 2 - evidenceItemsSelected),
            budgetTotalTokens: 1_800,
            usedTotalTokens: 1_040,
            truncatedLayers: truncatedLayers,
            freshness: "fresh_local_ipc",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: resolvedProfile == profileFloor ? nil : "budget_guardrail",
            reasonCode: nil,
            compressionPolicy: "progressive_disclosure"
        )
    }

}

@MainActor
private final class IntegrationMockVoiceStreamingTranscriber: VoiceStreamingTranscriber {
    let routeMode: VoiceRouteMode
    private(set) var authorizationStatus: VoiceTranscriberAuthorizationStatus
    private(set) var engineHealth: VoiceEngineHealth
    private(set) var healthReasonCode: String?
    private(set) var isRunning: Bool = false

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
        isRunning = true
        self.onChunk = onChunk
        self.onFailure = onFailure
    }

    func stopTranscribing() {
        isRunning = false
    }
}
