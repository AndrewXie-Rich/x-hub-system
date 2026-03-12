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
}
