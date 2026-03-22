import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonalMemoryAutoCaptureTests {

    @Test
    func extractsPreferredUserNameFromStandaloneAndMixedStatements() {
        let standalone = SupervisorPersonalMemoryAutoCapture.extract(from: "你好，我叫 Andrew。")
        #expect(standalone?.preferredUserName == "Andrew")
        #expect(standalone?.isStandaloneStatement == true)

        let mixed = SupervisorPersonalMemoryAutoCapture.extract(from: "我叫 Andrew，帮我看下今天最重要的事")
        #expect(mixed?.preferredUserName == "Andrew")
        #expect(mixed?.isStandaloneStatement == false)

        let english = SupervisorPersonalMemoryAutoCapture.extract(from: "Call me Taylor")
        #expect(english?.preferredUserName == "Taylor")
        #expect(english?.isStandaloneStatement == true)
    }

    @Test
    func extractsExplicitDurablePreferenceHabitAndRelationshipRecords() {
        let preferenceRecords = SupervisorPersonalMemoryAutoCapture.extractAdditionalRecords(
            from: "记一下，我偏好简洁直接的回答。"
        )
        #expect(preferenceRecords.count == 1)
        #expect(preferenceRecords.first?.category == .preference)
        #expect(preferenceRecords.first?.title.contains("简洁直接的回答") == true)

        let habitRecords = SupervisorPersonalMemoryAutoCapture.extractAdditionalRecords(
            from: "记一下，我习惯早上先做深度工作。"
        )
        #expect(habitRecords.count == 1)
        #expect(habitRecords.first?.category == .habit)
        #expect(habitRecords.first?.title.contains("早上先做深度工作") == true)

        let relationshipRecords = SupervisorPersonalMemoryAutoCapture.extractAdditionalRecords(
            from: "记一下，Alex 是我的合伙人。"
        )
        #expect(relationshipRecords.count == 1)
        #expect(relationshipRecords.first?.category == .relationship)
        #expect(relationshipRecords.first?.personName == "Alex")
        #expect(relationshipRecords.first?.title.contains("合伙人") == true)
    }

    @MainActor
    @Test
    func managerCapturesPreferredUserNameAndAnswersFollowUpLocally() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_capture_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )

        manager.sendMessage("我叫 Andrew")

        try await waitUntil("assistant capture acknowledgement") {
            manager.messages.contains { message in
                message.role == .assistant && message.content.contains("记住了，我会叫你 Andrew")
            }
        }

        #expect(store.snapshot.preferredUserName() == "Andrew")

        let remembered = try #require(manager.directSupervisorReplyIfApplicableForTesting("我叫什么名字"))
        #expect(remembered.contains("Andrew"))
        #expect(remembered.contains("已经记下来了"))
    }

    @MainActor
    @Test
    func localDirectReplyPublishesTurnExplainabilityAfterTurn() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_explainability_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )

        manager.sendMessage("我叫 Andrew")

        try await waitUntil("after-turn explainability published") {
            manager.supervisorLatestTurnRoutingDecisionForTesting()?.mode == .personalFirst &&
                manager.supervisorLatestTurnContextAssemblyForTesting()?.turnMode == .personalFirst
        }

        let routing = try #require(manager.supervisorLatestTurnRoutingDecisionForTesting())
        #expect(routing.mode == .personalFirst)
        #expect(routing.focusedProjectId == nil)
        #expect(routing.focusedPersonName == nil)
        #expect(routing.routingReasons == ["default_personal_fallback"])

        let assembly = try #require(manager.supervisorLatestTurnContextAssemblyForTesting())
        #expect(assembly.turnMode == .personalFirst)
        #expect(assembly.selectedSlots.contains(.personalCapsule))
        #expect(assembly.selectedRefs.contains("dialogue_window"))
        #expect(assembly.selectedRefs.contains("personal_capsule"))

        let writeback = try #require(manager.supervisorAfterTurnWritebackClassificationForTesting())
        #expect(writeback.candidates.first?.scope == .userScope)
        #expect(writeback.summaryLine.contains("user_scope"))
    }

    @MainActor
    @Test
    func capturedPreferredUserNameFlowsIntoSupervisorPromptContext() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_prompt_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        store.upsert(
            SupervisorPersonalMemoryAutoCaptureResult(
                preferredUserName: "Andrew",
                isStandaloneStatement: true
            ).preferredUserNameRecord(
                now: Date(timeIntervalSince1970: 1_773_196_800)
            )
        )

        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )
        let prompt = manager.buildSupervisorSystemPromptForTesting("帮我看下今天最重要的事")

        #expect(prompt.contains("Preferred user name: Andrew"))
        #expect(prompt.contains("## Personal Memory Context"))
    }

    @MainActor
    @Test
    func managerCarriesExplicitPreferenceCaptureIntoPromptContextBeforeReply() async throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_remote_prompt_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )
        manager.installSchedulerSnapshotRefreshOverrideForTesting { _ in }

        manager.sendMessage("记一下，我偏好简洁直接的回答")

        try await waitUntil("stored personal preference") {
            store.snapshot.items.contains { record in
                record.category == .preference
                    && record.title.contains("简洁直接的回答")
            }
        }

        let storedPreference = store.snapshot.items.first { $0.category == .preference }
        #expect(storedPreference?.title.contains("简洁直接的回答") == true)

        let prompt = manager.buildSupervisorSystemPromptForTesting(
            "记一下，我偏好简洁直接的回答"
        )
        #expect(prompt.contains("## Personal Memory Context"))
        #expect(prompt.contains("简洁直接的回答"))
    }

    @MainActor
    @Test
    func afterTurnWritebackPersistsExplicitPreferenceThroughUnifiedLane() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_writeback_explicit_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "记一下，我偏好简洁直接的回答。",
            responseText: "收到。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.91,
                routingReasons: ["personal_planning_language"]
            ),
            now: Date(timeIntervalSince1970: 1_773_800_000)
        )

        #expect(store.snapshot.items.contains { record in
            record.category == .preference && record.title.contains("简洁直接的回答")
        })

        let prompt = manager.buildSupervisorSystemPromptForTesting("今天怎么安排")
        #expect(prompt.contains("简洁直接的回答"))
    }

    @MainActor
    @Test
    func afterTurnWritebackPersistsInferredStableHabitThroughUnifiedLane() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_writeback_inferred_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "我通常早上先做深度工作。",
            responseText: "收到。",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.84,
                routingReasons: ["personal_planning_language"]
            ),
            now: Date(timeIntervalSince1970: 1_773_800_120)
        )

        #expect(store.snapshot.items.contains { record in
            record.category == .habit && record.title.contains("早上先做深度工作")
        })

        let prompt = manager.buildSupervisorSystemPromptForTesting("今天怎么安排")
        #expect(prompt.contains("早上先做深度工作"))
    }

    @MainActor
    @Test
    func afterTurnWritebackDoesNotPromoteUserMemoryForNonUserTriggers() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_writeback_non_user_\(UUID().uuidString).json")
        let store = SupervisorPersonalMemoryStore(url: tempURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: store
        )

        manager.syncSupervisorAfterTurnWritebackClassificationForTesting(
            userMessage: "我喜欢简洁直接。",
            responseText: "收到。",
            triggerSource: "heartbeat",
            routingDecision: SupervisorTurnRoutingDecision(
                mode: .personalFirst,
                focusedProjectId: nil,
                focusedProjectName: nil,
                focusedPersonName: nil,
                focusedCommitmentId: nil,
                confidence: 0.79,
                routingReasons: ["personal_planning_language"]
            ),
            now: Date(timeIntervalSince1970: 1_773_800_240)
        )

        #expect(store.snapshot.items.isEmpty)
    }

    @MainActor
    @Test
    func afterTurnLifecycleSyncsDerivedPersonalReviewNotes() async throws {
        let tempMemoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_memory_after_turn_\(UUID().uuidString).json")
        let tempReviewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_review_after_turn_\(UUID().uuidString).json")
        let personalMemoryStore = SupervisorPersonalMemoryStore(url: tempMemoryURL)
        let personalReviewStore = SupervisorPersonalReviewNoteStore(url: tempReviewURL)
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalMemoryStore: personalMemoryStore,
            supervisorPersonalReviewStore: personalReviewStore
        )
        let fixedNow = Date(timeIntervalSince1970: 1_773_711_000)
        manager.installSupervisorAfterTurnNowOverrideForTesting { fixedNow }

        let appModel = AppModel()
        let policy = personalPolicyForTesting()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            supervisorPersonalPolicy: policy
        )
        manager.setAppModel(appModel)

        manager.sendMessage("我叫 Andrew")

        try await waitUntil("after-turn review sync") {
            personalReviewStore.snapshot.notes.contains { note in
                note.reviewType == .morningBrief && note.reviewAnchor == "2026-03-17"
            }
        }

        #expect(personalReviewStore.snapshot.notes.contains { note in
            note.reviewType == .morningBrief && note.reviewAnchor == "2026-03-17"
        })
        #expect(manager.latestRuntimeActivity?.text.contains("after_turn personal_memory_capture") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("reviews_due=1") == true)
        #expect(manager.latestRuntimeActivity?.text.contains("follow_ups=0") == true)
        #expect(manager.supervisorAfterTurnDerivedSummary?.trend == .initialized)
        #expect(manager.supervisorAfterTurnDerivedSummary?.detailLines.contains {
            $0.contains("Morning Brief")
        } == true)
    }

    @MainActor
    @Test
    func eventLoopReplyUsesAfterTurnLifecycleWithoutOpeningConversationWindow() async throws {
        let tempReviewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_review_event_loop_\(UUID().uuidString).json")
        let personalReviewStore = SupervisorPersonalReviewNoteStore(url: tempReviewURL)
        let fixedNow = Date(timeIntervalSince1970: 1_773_711_000)
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .manualText,
            wakeMode: .pushToTalk,
            nowProvider: { fixedNow }
        )
        let speechSynth = SupervisorSpeechSynthesizer(speakSink: { _ in })
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalReviewStore: personalReviewStore,
            supervisorSpeechSynthesizer: speechSynth,
            conversationSessionController: controller
        )
        manager.installSupervisorAfterTurnNowOverrideForTesting { fixedNow }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            supervisorPersonalPolicy: personalPolicyForTesting()
        )
        manager.setAppModel(appModel)
        manager.setSupervisorEventLoopResponseOverrideForTesting { message, _ in
            "后台继续跟进：\(message)"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: "继续看下今天的安排",
            triggerSource: "heartbeat",
            dedupeKey: "after-turn-event-loop"
        )
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(manager.messages.contains { message in
            message.role == .assistant && message.content.contains("后台继续跟进：继续看下今天的安排")
        })
        #expect(personalReviewStore.snapshot.notes.contains { note in
            note.reviewType == .morningBrief && note.reviewAnchor == "2026-03-17"
        })
        #expect(manager.latestRuntimeActivity?.text.contains("after_turn event_loop_reply") == true)
        #expect(manager.supervisorAfterTurnDerivedSummary?.statusLine.contains("reviews 1 due") == true)
        #expect(controller.snapshot.isConversing == false)
    }

    @MainActor
    @Test
    func voiceAuthorizationCancelReplyRunsAfterTurnLifecycle() async throws {
        let tempReviewURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("supervisor_personal_review_voice_cancel_\(UUID().uuidString).json")
        let personalReviewStore = SupervisorPersonalReviewNoteStore(url: tempReviewURL)
        let fixedNow = Date(timeIntervalSince1970: 1_773_711_000)
        let controller = SupervisorConversationSessionController.makeForTesting(
            route: .manualText,
            wakeMode: .pushToTalk,
            nowProvider: { fixedNow }
        )
        let speechSynth = SupervisorSpeechSynthesizer(speakSink: { _ in })
        let manager = SupervisorManager.makeForTesting(
            supervisorPersonalReviewStore: personalReviewStore,
            supervisorSpeechSynthesizer: speechSynth,
            conversationSessionController: controller
        )
        manager.installSupervisorAfterTurnNowOverrideForTesting { fixedNow }

        let appModel = AppModel()
        appModel.settingsStore.settings = appModel.settingsStore.settings.setting(
            supervisorPersonalPolicy: personalPolicyForTesting()
        )
        manager.setAppModel(appModel)

        let challenge = HubIPCClient.VoiceGrantChallengeSnapshot(
            challengeId: "challenge-1",
            templateId: "voice.grant.v1",
            actionDigest: "approve grant",
            scopeDigest: "project=test",
            amountDigest: "",
            challengeCode: "1234",
            riskLevel: "high",
            requiresMobileConfirm: false,
            allowVoiceOnly: true,
            boundDeviceId: "device-1",
            mobileTerminalId: "mobile-1",
            issuedAtMs: fixedNow.timeIntervalSince1970 * 1000,
            expiresAtMs: fixedNow.addingTimeInterval(120).timeIntervalSince1970 * 1000
        )
        let request = SupervisorVoiceAuthorizationRequest(
            requestId: "voice-request-1",
            templateId: "voice.grant.v1",
            actionText: "approve grant",
            scopeText: "project=test",
            riskTier: .high,
            boundDeviceId: "device-1",
            mobileTerminalId: "mobile-1",
            challengeCode: "1234"
        )
        let resolution = SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: .pending,
            ok: true,
            requestId: request.requestId,
            projectId: nil,
            templateId: request.templateId,
            riskTier: request.riskTier.rawValue,
            challengeId: challenge.challengeId,
            challenge: challenge,
            verified: false,
            requiresMobileConfirm: false,
            allowVoiceOnly: true,
            denyCode: nil,
            reasonCode: nil,
            transcriptHash: nil,
            semanticMatchScore: nil,
            policyRef: "state=pending",
            nextAction: "repeat the challenge"
        )
        manager.setActiveVoiceAuthorizationStateForTesting(
            request: request,
            resolution: resolution,
            challenge: challenge
        )

        manager.sendMessage("取消", fromVoice: true)

        try await waitUntil("voice auth cancel after-turn") {
            manager.messages.contains { message in
                message.role == .assistant && message.content.contains("已取消当前语音授权。")
            }
        }

        #expect(personalReviewStore.snapshot.notes.contains { note in
            note.reviewType == .morningBrief && note.reviewAnchor == "2026-03-17"
        })
        #expect(manager.latestRuntimeActivity?.text.contains("after_turn voice_auth_cancel") == true)
        #expect(manager.supervisorAfterTurnDerivedSummary?.replySource == "voice_auth_cancel")
        #expect(manager.activeVoiceChallenge == nil)
        #expect(manager.voiceAuthorizationResolution?.reasonCode == "user_cancelled")
    }

    private func personalPolicyForTesting() -> SupervisorPersonalPolicy {
        SupervisorPersonalPolicy(
            relationshipMode: .operatorPartner,
            briefingStyle: .balanced,
            riskTolerance: .balanced,
            interruptionTolerance: .balanced,
            reminderAggressiveness: .balanced,
            preferredMorningBriefTime: "08:00",
            preferredEveningWrapUpTime: "23:59",
            weeklyReviewDay: "Sunday"
        )
    }

    private func waitUntil(
        _ reason: String,
        timeoutMs: Int = 2_000,
        condition: @escaping @Sendable @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        Issue.record("Timed out waiting for \(reason)")
        throw CancellationError()
    }
}
