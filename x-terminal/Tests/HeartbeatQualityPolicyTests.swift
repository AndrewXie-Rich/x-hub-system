import Foundation
import Testing
@testable import XTerminal

struct HeartbeatQualityPolicyTests {
    @Test
    func assessFlagsRepeatedGenericHeartbeatAsStaleAndHollow() {
        let project = AXProjectEntry(
            projectId: "project-repeat",
            rootPath: "/tmp/project-repeat",
            displayName: "project-repeat",
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "continue current task",
            currentStateSummary: "Still active",
            nextStepSummary: "Continue current task",
            blockerSummary: nil,
            lastSummaryAt: 1_700_000_000,
            lastEventAt: 1_700_000_000
        )
        let previous = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-repeat",
            updatedAtMs: 1_700_000_100_000,
            lastHeartbeatAtMs: 1_700_000_100_000,
            lastObservedProgressAtMs: 1_700_000_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0,
            lastHeartbeatFingerprint: "continue current task|still active|continue current task|",
            lastHeartbeatRepeatCount: 1
        )

        let assessment = HeartbeatQualityPolicy.assess(
            project: project,
            previousState: previous,
            blockerDetected: false,
            nowMs: 1_700_001_200_000
        )

        #expect(assessment.repeatCount == 2)
        #expect(assessment.qualitySnapshot.overallBand == .hollow)
        #expect(assessment.openAnomalies.contains { $0.anomalyType == .staleRepeat })
        #expect(assessment.openAnomalies.contains { $0.anomalyType == .hollowProgress })
    }

    @Test
    func assessFlagsWeakDoneClaimWithoutEvidence() throws {
        let project = AXProjectEntry(
            projectId: "project-done",
            rootPath: "/tmp/project-done",
            displayName: "project-done",
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "done candidate",
            currentStateSummary: "Implementation looks done",
            nextStepSummary: "Ship release",
            blockerSummary: nil,
            lastSummaryAt: 1_700_000_300,
            lastEventAt: 1_700_000_300
        )

        let assessment = HeartbeatQualityPolicy.assess(
            project: project,
            previousState: emptyState(projectId: "project-done"),
            blockerDetected: false,
            nowMs: 1_700_000_600_000
        )

        let anomaly = try #require(
            assessment.openAnomalies.first { $0.anomalyType == .weakDoneClaim }
        )
        #expect(anomaly.severity == .high)
        #expect(anomaly.recommendedEscalation == .rescueReview)
        #expect(assessment.qualitySnapshot.completionConfidenceScore < 40)
        #expect(assessment.qualitySnapshot.overallBand == .weak || assessment.qualitySnapshot.overallBand == .hollow)
        #expect(assessment.projectPhase == .release)
        #expect(assessment.executionStatus == .doneCandidate)
        #expect(assessment.riskTier == .high)
    }

    @Test
    func assessFlagsQueueStallWhenQueueCuePersistsWithoutProgress() throws {
        let project = AXProjectEntry(
            projectId: "project-queue",
            rootPath: "/tmp/project-queue",
            displayName: "project-queue",
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "queue still blocked",
            currentStateSummary: "Queue depth remains high",
            nextStepSummary: "Wait for queue to clear",
            blockerSummary: "queue_starvation waiting on upstream queue",
            lastSummaryAt: 1_700_000_000,
            lastEventAt: 1_700_000_000
        )
        let previous = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-queue",
            updatedAtMs: 1_700_000_100_000,
            lastHeartbeatAtMs: 1_700_000_100_000,
            lastObservedProgressAtMs: 1_700_000_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0,
            lastHeartbeatFingerprint: "queue still blocked|queue depth remains high|wait for queue to clear|queue_starvation waiting on upstream queue",
            lastHeartbeatRepeatCount: 1
        )

        let assessment = HeartbeatQualityPolicy.assess(
            project: project,
            previousState: previous,
            blockerDetected: true,
            nowMs: 1_700_001_800_000
        )

        let anomaly = try #require(
            assessment.openAnomalies.first { $0.anomalyType == .queueStall }
        )
        #expect(anomaly.recommendedEscalation == .strategicReview)
        #expect(anomaly.severity == .concern || anomaly.severity == .high)
        #expect(assessment.executionStatus == .stalled)
        #expect(assessment.projectPhase == .explore || assessment.projectPhase == .build)
        #expect(assessment.riskTier == .medium)
    }

    @Test
    func assessFlagsWeakBlockerWhenHeartbeatCannotExplainWhatIsMissing() throws {
        let project = AXProjectEntry(
            projectId: "project-weak-blocker",
            rootPath: "/tmp/project-weak-blocker",
            displayName: "project-weak-blocker",
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "Still blocked",
            nextStepSummary: "Continue current task",
            blockerSummary: "blocked",
            lastSummaryAt: 1_700_000_000,
            lastEventAt: 1_700_000_000
        )
        let previous = SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: "project-weak-blocker",
            updatedAtMs: 1_700_000_100_000,
            lastHeartbeatAtMs: 1_700_000_100_000,
            lastObservedProgressAtMs: 1_700_000_000_000,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0,
            lastHeartbeatFingerprint: "blocked|still blocked|continue current task|blocked",
            lastHeartbeatRepeatCount: 1
        )

        let assessment = HeartbeatQualityPolicy.assess(
            project: project,
            previousState: previous,
            blockerDetected: true,
            nowMs: 1_700_001_900_000
        )

        let anomaly = try #require(
            assessment.openAnomalies.first { $0.anomalyType == .weakBlocker }
        )
        #expect(anomaly.severity == .concern || anomaly.severity == .high)
        #expect(anomaly.recommendedEscalation == .pulseReview || anomaly.recommendedEscalation == .strategicReview)
        #expect(assessment.qualitySnapshot.blockerClarityScore < 40)
    }

    @Test
    func assessInfersVerifyPhaseAndCriticalRiskForProductionValidationWork() {
        let project = AXProjectEntry(
            projectId: "project-verify-critical",
            rootPath: "/tmp/project-verify-critical",
            displayName: "project-verify-critical",
            lastOpenedAt: 0,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "production validation in progress",
            currentStateSummary: "Run security verification before production deploy",
            nextStepSummary: "Verify migration and release checklist",
            blockerSummary: nil,
            lastSummaryAt: 1_700_000_500,
            lastEventAt: 1_700_000_500
        )

        let assessment = HeartbeatQualityPolicy.assess(
            project: project,
            previousState: emptyState(projectId: "project-verify-critical"),
            blockerDetected: false,
            nowMs: 1_700_000_800_000
        )

        #expect(assessment.projectPhase == .release || assessment.projectPhase == .verify)
        #expect(assessment.executionStatus == .active)
        #expect(assessment.riskTier == .critical)
    }

    private func emptyState(projectId: String) -> SupervisorReviewScheduleState {
        SupervisorReviewScheduleState(
            schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
            projectId: projectId,
            updatedAtMs: 0,
            lastHeartbeatAtMs: 0,
            lastObservedProgressAtMs: 0,
            lastPulseReviewAtMs: 0,
            lastBrainstormReviewAtMs: 0,
            lastTriggerReviewAtMs: [:],
            nextHeartbeatDueAtMs: 0,
            nextPulseReviewDueAtMs: 0,
            nextBrainstormReviewDueAtMs: 0
        )
    }
}
