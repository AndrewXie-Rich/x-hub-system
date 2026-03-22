import Foundation
import Testing
@testable import XTerminal

struct SupervisorRhythmRecommendationTests {
    @Test
    func blockedAndAuthorizationEventsEmitActionFirstRecommendations() {
        let authEvent = SupervisorProjectActionEvent(
            eventId: "evt-auth",
            projectId: "p-auth",
            projectName: "Auth Project",
            eventType: .awaitingAuthorization,
            severity: .authorizationRequired,
            actionTitle: "项目待授权：Auth Project",
            actionSummary: "grant_required",
            whyItMatters: "The project is blocked until approval lands.",
            nextAction: "Approve paid model access",
            occurredAt: 1
        )
        let blockedEvent = SupervisorProjectActionEvent(
            eventId: "evt-blocked",
            projectId: "p-blocked",
            projectName: "Blocked Project",
            eventType: .blocked,
            severity: .briefCard,
            actionTitle: "项目阻塞：Blocked Project",
            actionSummary: "Missing RR02 sample",
            whyItMatters: "The blocker is preventing forward progress.",
            nextAction: "Run RR02 on paired XT",
            occurredAt: 1
        )

        let authRecommendation = SupervisorRhythmRecommendationEngine.recommendation(for: authEvent)
        let blockedRecommendation = SupervisorRhythmRecommendationEngine.recommendation(for: blockedEvent)
        let authDecision = SupervisorProjectNotificationPolicy.decide(for: authEvent)
        let blockedDecision = SupervisorProjectNotificationPolicy.decide(for: blockedEvent)

        #expect(authRecommendation.schemaVersion == "xt.supervisor_rhythm_recommendation.v1")
        #expect(authRecommendation.isSubstantiveChange)
        #expect(authRecommendation.recommendationType == .decisionRequired)
        #expect(authRecommendation.recommendedNextAction == "Approve paid model access")
        #expect(!authRecommendation.whyItMatters.isEmpty)
        #expect(authDecision.channel == .interruptNow)
        #expect(authDecision.systemMessage?.contains("下一步：Approve paid model access") == true)

        #expect(blockedRecommendation.isSubstantiveChange)
        #expect(blockedRecommendation.recommendationType == .unblockRequired)
        #expect(blockedRecommendation.recommendedNextAction == "Run RR02 on paired XT")
        #expect(blockedDecision.channel == .briefCard)
        #expect(!blockedDecision.recommendation.whyItMatters.isEmpty)
    }

    @Test
    func quietProgressUsesRecommendationBasedFingerprintAndDoesNotEscalate() {
        let progressEventA = SupervisorProjectActionEvent(
            eventId: "evt-progress-a",
            projectId: "p-active",
            projectName: "Active Project",
            eventType: .progressed,
            severity: .silentLog,
            actionTitle: "项目推进：Active Project",
            actionSummary: "Adjusted dashboard row spacing",
            whyItMatters: "Routine implementation churn only.",
            nextAction: "Continue current task",
            occurredAt: 10
        )
        let progressEventB = SupervisorProjectActionEvent(
            eventId: "evt-progress-b",
            projectId: "p-active",
            projectName: "Active Project",
            eventType: .progressed,
            severity: .silentLog,
            actionTitle: "项目推进：Active Project",
            actionSummary: "Refined dashboard card spacing",
            whyItMatters: "Routine implementation churn only.",
            nextAction: "Continue current task",
            occurredAt: 20
        )

        let recommendationA = SupervisorRhythmRecommendationEngine.recommendation(for: progressEventA)
        let recommendationB = SupervisorRhythmRecommendationEngine.recommendation(for: progressEventB)
        let decision = SupervisorProjectNotificationPolicy.decide(for: progressEventA)
        let fingerprintA = SupervisorProjectNotificationPolicy.dedupeFingerprint(
            for: progressEventA,
            channel: decision.channel
        )
        let fingerprintB = SupervisorProjectNotificationPolicy.dedupeFingerprint(
            for: progressEventB,
            channel: decision.channel
        )

        #expect(!recommendationA.isSubstantiveChange)
        #expect(recommendationA.recommendationType == .steadyState)
        #expect(recommendationA.recommendedNextAction.contains("Wait for the next material change") == true)
        #expect(recommendationA.nextUpdateEta == "only when the recommendation changes")
        #expect(recommendationA.dedupeKey == recommendationB.dedupeKey)
        #expect(fingerprintA == fingerprintB)
        #expect(decision.channel == .silentLog)
        #expect(decision.systemMessage == nil)
    }

    @Test
    func pendingDecisionProposalRemainsDecisionRequiredWithoutBypassingGovernance() {
        let proposalEvent = SupervisorProjectActionEvent(
            eventId: "evt-proposal",
            projectId: "p-proposal",
            projectName: "Proposal Project",
            eventType: .blocked,
            severity: .briefCard,
            actionTitle: "项目阻塞：Proposal Project",
            actionSummary: "default_proposal_pending:test_stack=swift_testing_contract_default",
            whyItMatters: "This proposal needs a portfolio decision before safe routing can continue.",
            nextAction: "需要确认默认建议：swift_testing_contract_default，再决定是否采纳。",
            occurredAt: 30
        )

        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: proposalEvent)
        let decision = SupervisorProjectNotificationPolicy.decide(for: proposalEvent)

        #expect(recommendation.isSubstantiveChange)
        #expect(recommendation.recommendationType == .decisionRequired)
        #expect(recommendation.waitingOn == "a portfolio-level decision")
        #expect(recommendation.recommendedNextAction.contains("确认默认建议"))
        #expect(recommendation.recommendedNextAction.contains("swift_testing_contract_default"))
        #expect(decision.channel == .briefCard)
        #expect(decision.systemMessage == nil)
    }

    @Test
    func decisionRailCleanupProgressUsesActionFirstBriefCardCadence() {
        let now = Date(timeIntervalSince1970: 1_773_210_000).timeIntervalSince1970
        let entry = AXProjectEntry(
            projectId: "p-rail",
            rootPath: "/tmp/p-rail",
            displayName: "Decision Rail Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "in_progress",
            currentStateSummary: "Implementing locked stack",
            nextStepSummary: "Continue current task",
            blockerSummary: "(无)",
            lastSummaryAt: now,
            lastEventAt: now
        )

        let event = SupervisorPortfolioSnapshotBuilder.makeActionEvent(
            from: entry,
            kind: .updated,
            shadowedBackgroundNoteCount: 2,
            weakOnlyBackgroundNoteCount: 1,
            now: now
        )
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        let decision = SupervisorProjectNotificationPolicy.decide(for: event)

        #expect(event.eventType == .progressed)
        #expect(event.severity == .briefCard)
        #expect(event.actionSummary == "Decision rail cleanup: 2 shadowed background notes + 1 weak-only preference")
        #expect(recommendation.isSubstantiveChange)
        #expect(recommendation.recommendationType == .decisionRailCleanup)
        #expect(recommendation.waitingOn == "decision/background precedence cleanup")
        #expect(recommendation.recommendedNextAction.contains("either formalize them or keep them explicitly non-binding"))
        #expect(decision.channel == .briefCard)
        #expect(decision.recommendation.recommendationType == .decisionRailCleanup)
    }

    @Test
    func completedArchiveCandidateKeepsSpecificArchiveReviewNextAction() {
        let now = Date(timeIntervalSince1970: 1_773_240_000).timeIntervalSince1970
        let entry = AXProjectEntry(
            projectId: "p-archive",
            rootPath: "/tmp/p-archive",
            displayName: "Archive Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "completed",
            currentStateSummary: "已完成",
            nextStepSummary: "(暂无)",
            blockerSummary: "(无)",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let signal = SupervisorMemoryCompactionSignal(
            rollupSummary: "rolled_up=2; archived=3; kept_decisions=1; archive_candidate=true",
            rolledUpCount: 2,
            archivedCount: 3,
            keptDecisionCount: 1,
            keptMilestoneCount: 0,
            archiveCandidate: true
        )

        let event = SupervisorPortfolioSnapshotBuilder.makeActionEvent(
            from: entry,
            kind: .updated,
            memoryCompactionSignal: signal,
            now: now
        )
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)

        #expect(event.actionTitle.contains("归档候选"))
        #expect(event.nextAction.contains("确认归档"))
        #expect(recommendation.recommendationType == .closeOut)
        #expect(recommendation.recommendedNextAction == event.nextAction)
        #expect(recommendation.isSubstantiveChange)
    }
}
