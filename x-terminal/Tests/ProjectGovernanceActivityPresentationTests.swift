import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceActivityPresentationTests {

    @Test
    func presentationSummarizesLatestGovernanceActivity() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-activity-presentation-\(UUID().uuidString)", isDirectory: true)
        var config = AXProjectConfig.default(forProjectRoot: root)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1200,
            brainstormReviewSeconds: 2400,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .planDrift, .preDoneSummary]
        )
        let resolvedGovernance = xtResolveProjectGovernance(
            projectRoot: root,
            config: config,
            projectAIStrengthProfile: AXProjectAIStrengthProfile(
                strengthBand: .strong,
                confidence: 0.91,
                recommendedSupervisorFloor: .s3StrategicCoach,
                recommendedWorkOrderDepth: .executionReady,
                reasons: ["governance activity view should expose cadence"],
                assessedAtMs: nowMs,
                auditRef: "audit-governance-activity-strength"
            )
        )

        let review = SupervisorReviewNoteRecord(
            schemaVersion: SupervisorReviewNoteRecord.currentSchemaVersion,
            reviewId: "review-1",
            projectId: "project-alpha",
            trigger: .blockerDetected,
            reviewLevel: .r2Strategic,
            verdict: .betterPathFound,
            targetRole: .coder,
            deliveryMode: .replanRequest,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            projectAIStrengthBand: .strong,
            projectAIStrengthConfidence: 0.91,
            projectAIStrengthAuditRef: "audit-strength-review-1",
            workOrderRef: "plan:plan-review-1",
            summary: "Current implementation path is too wide.",
            recommendedActions: ["Reduce scope", "Re-run focused tests"],
            anchorGoal: "Ship governance activity UI",
            anchorDoneDefinition: "Project settings shows latest review and guidance",
            anchorConstraints: ["Do not touch unrelated screens", "Keep ctx-based loading only"],
            currentState: "ProjectSettingsView already owns stable ctx",
            nextStep: "Render latest note and latest guidance",
            blocker: "ProjectDetailView still uses random UUID",
            createdAtMs: nowMs - 10 * 60 * 1000,
            auditRef: "audit-review-1"
        )

        let guidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-1",
            reviewId: "review-1",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "Keep the first version inside ProjectSettingsView and expose pending ack.",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "plan:plan-review-1",
            ackNote: "",
            injectedAtMs: nowMs - 5 * 60 * 1000,
            ackUpdatedAtMs: 0,
            auditRef: "audit-guidance-1"
        )

        let presentation = ProjectGovernanceActivityPresentation(
            reviewNotes: SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: review.createdAtMs,
                notes: [review]
            ),
            guidance: SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: guidance.injectedAtMs,
                items: [guidance]
            ),
            scheduleState: SupervisorReviewScheduleState(
                schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
                projectId: "project-alpha",
                updatedAtMs: nowMs,
                lastHeartbeatAtMs: nowMs - 2 * 60 * 1000,
                lastObservedProgressAtMs: nowMs - 8 * 60 * 1000,
                lastPulseReviewAtMs: nowMs - 30 * 60 * 1000,
                lastBrainstormReviewAtMs: nowMs - 90 * 60 * 1000,
                lastTriggerReviewAtMs: ["blocker_detected": review.createdAtMs],
                nextHeartbeatDueAtMs: nowMs + 15 * 60 * 1000,
                nextPulseReviewDueAtMs: nowMs + 20 * 60 * 1000,
                nextBrainstormReviewDueAtMs: nowMs + 45 * 60 * 1000
            ),
            resolvedGovernance: resolvedGovernance,
            now: now
        )

        #expect(presentation.reviewCount == 1)
        #expect(presentation.guidanceCount == 1)
        #expect(presentation.pendingAckCount == 1)
        #expect(presentation.followUpRhythmSummary.contains("blocker cooldown"))
        #expect(presentation.recentReviews.count == 1)
        #expect(presentation.recentGuidance.count == 1)
        #expect(presentation.pendingGuidance?.injectionID == "guidance-1")

        let latestReview = try #require(presentation.latestReview)
        #expect(latestReview.triggerText == "Blocker Detected")
        #expect(latestReview.reviewLevelText == "R2 Strategic")
        #expect(latestReview.verdictText == "Better Path Found")
        #expect(latestReview.deliveryModeText == "Replan Request")
        #expect(latestReview.ackText == "required")
        #expect(latestReview.effectiveSupervisorTierText == "S3 Strategic Coach")
        #expect(latestReview.workOrderDepthText == "Execution Ready")
        #expect(latestReview.projectAIStrengthText.contains("Strong"))
        #expect(latestReview.workOrderRef == "plan:plan-review-1")
        #expect(latestReview.anchorGoal == "Ship governance activity UI")
        #expect(latestReview.blocker == "ProjectDetailView still uses random UUID")
        #expect(latestReview.recommendedActions.count == 2)
        #expect(latestReview.createdAtText.contains("10m ago"))

        let latestGuidance = try #require(presentation.latestGuidance)
        #expect(latestGuidance.deliveryModeText == "Priority Insert")
        #expect(latestGuidance.interventionText == "Replan At Safe Point")
        #expect(latestGuidance.safePointText == "Next Step Boundary")
        #expect(latestGuidance.lifecycleText == "active")
        #expect(latestGuidance.ackText == "Pending · required")
        #expect(latestGuidance.effectiveSupervisorTierText == "S3 Strategic Coach")
        #expect(latestGuidance.workOrderDepthText == "Execution Ready")
        #expect(latestGuidance.workOrderRef == "plan:plan-review-1")
        #expect(latestGuidance.ackUpdatedAtText == "(none)")
        #expect(latestGuidance.guidanceText.contains("pending ack"))

        #expect(presentation.schedule.lastHeartbeatText.contains("2m ago"))
        #expect(presentation.schedule.nextHeartbeatText.contains("in 15m"))
        #expect(presentation.schedule.nextPulseReviewText.contains("in 20m"))
        #expect(presentation.schedule.nextBrainstormReviewText.contains("in 45m"))
    }

    @Test
    func presentationCapsRecentHistoryToFiveNewestItems() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)

        let reviews = (0..<7).map { index in
            SupervisorReviewNoteRecord(
                schemaVersion: SupervisorReviewNoteRecord.currentSchemaVersion,
                reviewId: "review-\(index)",
                projectId: "project-alpha",
                trigger: .periodicPulse,
                reviewLevel: .r1Pulse,
                verdict: .watch,
                targetRole: .coder,
                deliveryMode: .contextAppend,
                ackRequired: false,
                summary: "review \(index)",
                recommendedActions: [],
                anchorGoal: "",
                anchorDoneDefinition: "",
                anchorConstraints: [],
                currentState: "",
                nextStep: "step \(index)",
                blocker: "",
                createdAtMs: nowMs - Int64(index * 60_000),
                auditRef: "audit-review-\(index)"
            )
        }
        let guidance = (0..<7).map { index in
            SupervisorGuidanceInjectionRecord(
                schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
                injectionId: "guidance-\(index)",
                reviewId: "review-\(index)",
                projectId: "project-alpha",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextToolBoundary,
                guidanceText: "guidance \(index)",
                ackStatus: index == 0 ? .pending : .accepted,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: nowMs - Int64(index * 90_000),
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-\(index)"
            )
        }

        let presentation = ProjectGovernanceActivityPresentation(
            reviewNotes: SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: nowMs,
                notes: reviews
            ),
            guidance: SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: nowMs,
                items: guidance
            ),
            scheduleState: SupervisorReviewScheduleState(
                schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
                projectId: "project-alpha",
                updatedAtMs: 0,
                lastHeartbeatAtMs: 0,
                lastObservedProgressAtMs: 0,
                lastPulseReviewAtMs: 0,
                lastBrainstormReviewAtMs: 0,
                lastTriggerReviewAtMs: [:],
                nextHeartbeatDueAtMs: 0,
                nextPulseReviewDueAtMs: 0,
                nextBrainstormReviewDueAtMs: 0
            ),
            now: now
        )

        #expect(presentation.reviewCount == 7)
        #expect(presentation.guidanceCount == 7)
        #expect(presentation.recentReviews.count == 5)
        #expect(presentation.recentGuidance.count == 5)
        #expect(presentation.recentReviews.first?.reviewID == "review-0")
        #expect(presentation.recentReviews.last?.reviewID == "review-4")
        #expect(presentation.recentGuidance.first?.injectionID == "guidance-0")
        #expect(presentation.recentGuidance.last?.injectionID == "guidance-4")
        #expect(presentation.pendingGuidance?.injectionID == "guidance-0")
    }

    @Test
    func presentationTreatsRetryDueDeferredGuidanceAsActionable() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)

        let deferredDue = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-retry-due",
            reviewId: "review-retry-due",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .replanRequest,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: "Retry this replan guidance at the next strategic window.",
            ackStatus: .deferred,
            ackRequired: true,
            ackNote: "Need a safer checkpoint first.",
            injectedAtMs: nowMs - 20 * 60 * 1000,
            ackUpdatedAtMs: nowMs - 15 * 60 * 1000,
            expiresAtMs: nowMs + 30 * 60 * 1000,
            retryAtMs: nowMs - 60 * 1000,
            retryCount: 1,
            maxRetryCount: 2,
            auditRef: "audit-guidance-retry-due"
        )

        let presentation = ProjectGovernanceActivityPresentation(
            reviewNotes: SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                notes: []
            ),
            guidance: SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: deferredDue.injectedAtMs,
                items: [deferredDue]
            ),
            scheduleState: SupervisorReviewScheduleState(
                schemaVersion: SupervisorReviewScheduleState.currentSchemaVersion,
                projectId: "project-alpha",
                updatedAtMs: 0,
                lastHeartbeatAtMs: 0,
                lastObservedProgressAtMs: 0,
                lastPulseReviewAtMs: 0,
                lastBrainstormReviewAtMs: 0,
                lastTriggerReviewAtMs: [:],
                nextHeartbeatDueAtMs: 0,
                nextPulseReviewDueAtMs: 0,
                nextBrainstormReviewDueAtMs: 0
            ),
            now: now
        )

        #expect(presentation.pendingAckCount == 1)
        #expect(presentation.pendingGuidance?.injectionID == "guidance-retry-due")
        #expect(presentation.pendingGuidance?.ackStatus == .deferred)
        #expect(presentation.pendingGuidance?.lifecycleText == "retry due now")
    }

    @Test
    func guidanceAckActionPersistsStoreAndRawLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-ack-action-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let guidance = SupervisorGuidanceInjectionBuilder.build(
            injectionId: "guidance-pending",
            reviewId: "review-pending",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .suggestNextSafePoint,
            safePointPolicy: .nextToolBoundary,
            guidanceText: "Narrow scope before adding more UI surface.",
            ackStatus: .pending,
            ackRequired: true,
            ackNote: "",
            injectedAtMs: 100,
            ackUpdatedAtMs: 0,
            auditRef: "audit-guidance-pending"
        )
        try SupervisorGuidanceInjectionStore.upsert(guidance, for: ctx)

        let updated = try ProjectGovernanceGuidanceAckAction.acknowledge(
            ctx: ctx,
            injectionId: "guidance-pending",
            status: .accepted,
            note: "",
            source: "project_settings_governance_activity"
        )

        #expect(updated.ackStatus == .accepted)
        #expect(updated.ackNote == "manual_accept_from_project_settings")
        #expect(updated.ackUpdatedAtMs > 0)

        let stored = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(stored.ackStatus == .accepted)
        #expect(stored.ackNote == "manual_accept_from_project_settings")

        let rawEntries = try readRawLogEntries(at: ctx.rawLogURL)
        let ackEntry = try #require(rawEntries.last)
        #expect(ackEntry["type"] as? String == "supervisor_guidance_ack")
        #expect(ackEntry["action"] as? String == "manual_ack")
        #expect(ackEntry["source"] as? String == "project_settings_governance_activity")
        #expect(ackEntry["injection_id"] as? String == "guidance-pending")
        #expect(ackEntry["ack_status"] as? String == "accepted")
        #expect(ackEntry["ack_note"] as? String == "manual_accept_from_project_settings")
    }

    @Test
    func emptyPresentationFallsBackToNonePlaceholders() {
        let presentation = ProjectGovernanceActivityPresentation.empty

        #expect(presentation.reviewCount == 0)
        #expect(presentation.guidanceCount == 0)
        #expect(presentation.pendingAckCount == 0)
        #expect(presentation.followUpRhythmSummary == "(none)")
        #expect(presentation.latestReview == nil)
        #expect(presentation.recentReviews.isEmpty)
        #expect(presentation.pendingGuidance == nil)
        #expect(presentation.latestGuidance == nil)
        #expect(presentation.recentGuidance.isEmpty)
        #expect(presentation.schedule.lastHeartbeatText == "(none)")
        #expect(presentation.schedule.nextBrainstormReviewText == "(none)")
    }
}

private func readRawLogEntries(at url: URL) throws -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    guard let text = String(data: data, encoding: .utf8) else { return [] }
    return try text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { line in
            guard let lineData = String(line).data(using: .utf8) else {
                throw CocoaError(.coderInvalidValue)
            }
            guard let object = try JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                throw CocoaError(.coderReadCorrupt)
            }
            return object
        }
}
