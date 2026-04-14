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
                nextBrainstormReviewDueAtMs: nowMs + 45 * 60 * 1000,
                latestQualitySnapshot: HeartbeatQualitySnapshot(
                    overallScore: 82,
                    overallBand: .strong,
                    freshnessScore: 88,
                    deltaSignificanceScore: 80,
                    evidenceStrengthScore: 84,
                    blockerClarityScore: 78,
                    nextActionSpecificityScore: 86,
                    executionVitalityScore: 80,
                    completionConfidenceScore: 78,
                    weakReasons: [],
                    computedAtMs: nowMs - 60 * 1000
                ),
                openAnomalies: [
                    HeartbeatAnomalyNote(
                        anomalyId: "anomaly-hollow",
                        projectId: "project-alpha",
                        anomalyType: .hollowProgress,
                        severity: .concern,
                        confidence: 0.74,
                        reason: "Heartbeat delta is too weak",
                        evidenceRefs: ["project_digest:project-alpha"],
                        detectedAtMs: nowMs - 60 * 1000,
                        recommendedEscalation: .pulseReview
                    )
                ]
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
        let cadence = try #require(presentation.cadenceExplainability)
        #expect(cadence.progressHeartbeat.configuredSeconds == 600)
        #expect(cadence.progressHeartbeat.recommendedSeconds == 600)
        #expect(cadence.progressHeartbeat.effectiveSeconds == 600)
        #expect(cadence.reviewPulse.configuredSeconds == 1200)
        #expect(cadence.reviewPulse.recommendedSeconds == 1200)
        #expect(cadence.reviewPulse.effectiveSeconds == 1200)
        #expect(cadence.brainstormReview.configuredSeconds == 2400)
        #expect(cadence.brainstormReview.recommendedSeconds == 2400)
        #expect(cadence.brainstormReview.effectiveSeconds == 2400)
        #expect(cadence.reviewPulse.isDue)
        #expect(cadence.brainstormReview.isDue == false)

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
        #expect(latestGuidance.guidanceSummaryText == "Keep the first version inside ProjectSettingsView and expose pending ack.")
        #expect(latestGuidance.contractSummary?.kind == .supervisorReplan)
        #expect(latestGuidance.contractSummary?.primaryBlocker == "ProjectDetailView still uses random UUID")
        #expect(latestGuidance.contractSummary?.nextSafeAction == "apply_supervisor_replan")

        #expect(presentation.schedule.lastHeartbeatText.contains("2m ago"))
        #expect(presentation.schedule.nextHeartbeatText.contains("in 8m"))
        #expect(presentation.schedule.nextPulseReviewText.contains("10m ago"))
        #expect(presentation.schedule.nextBrainstormReviewText.contains("in 32m"))
        #expect(presentation.schedule.heartbeatQualityBandText == "Strong")
        #expect(presentation.schedule.heartbeatQualityScoreText == "82 / 100")
        #expect(presentation.schedule.heartbeatOpenAnomaliesText.contains("1 open"))
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
    func presentationParsesStructuredUIReviewRepairGuidanceContract() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)

        let guidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-ui-review-1",
            reviewId: "review-ui-review-1",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .stopImmediately,
            safePointPolicy: .nextToolBoundary,
            guidanceText: """
source=ui_review_repair
summary=Primary CTA is missing from the current screen.
repair_action=Expose the primary CTA
repair_focus=Landing hero actions
next_safe_action=repair_before_execution
instruction=Fix the CTA before resuming browser automation.
ui_review_ref=local://.xterminal/ui_review/reviews/project-alpha-latest.json
ui_review_issue_codes=critical_action_not_visible
""",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s4TightSupervision,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "plan:ui-repair-1",
            ackNote: "",
            injectedAtMs: nowMs - 120_000,
            ackUpdatedAtMs: 0,
            auditRef: "audit-guidance-ui-review-1"
        )

        let presentation = ProjectGovernanceActivityPresentation(
            reviewNotes: SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                notes: []
            ),
            guidance: SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: guidance.injectedAtMs,
                items: [guidance]
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

        let pendingGuidance = try #require(presentation.pendingGuidance)
        let contract = try #require(pendingGuidance.contractSummary)
        let uiReview = try #require(contract.uiReviewRepair)

        #expect(pendingGuidance.guidanceSummaryText == "Primary CTA is missing from the current screen.")
        #expect(contract.kind == SupervisorGuidanceContractSummary.Kind.uiReviewRepair)
        #expect(contract.summaryText == "Primary CTA is missing from the current screen.")
        #expect(contract.nextSafeAction == "repair_before_execution")
        #expect(uiReview.repairAction == "Expose the primary CTA")
        #expect(uiReview.repairFocus == "Landing hero actions")
        #expect(uiReview.instruction == "Fix the CTA before resuming browser automation.")
    }

    @Test
    func presentationParsesWrappedStructuredGrantResolutionContractSummary() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)

        let guidance = SupervisorGuidanceInjectionRecord(
            schemaVersion: SupervisorGuidanceInjectionRecord.currentSchemaVersion,
            injectionId: "guidance-grant-wrapped-1",
            reviewId: "review-grant-wrapped-1",
            projectId: "project-alpha",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .replanNextSafePoint,
            safePointPolicy: .nextStepBoundary,
            guidanceText: """
收到，我会按《Release Runtime》这条指导继续推进：summary=当前没有待处理的 Hub 授权。
contract_kind=grant_resolution
primary_blocker=grant_required
next_safe_action=open_hub_grants
recommended_actions=Open Hub grant approval for this project | Retry the governed step after grant approval
""",
            ackStatus: .pending,
            ackRequired: true,
            effectiveSupervisorTier: .s3StrategicCoach,
            effectiveWorkOrderDepth: .executionReady,
            workOrderRef: "plan:grant-wrapped-1",
            ackNote: "",
            injectedAtMs: nowMs - 120_000,
            ackUpdatedAtMs: 0,
            auditRef: "audit-guidance-grant-wrapped-1"
        )

        let presentation = ProjectGovernanceActivityPresentation(
            reviewNotes: SupervisorReviewNoteSnapshot(
                schemaVersion: SupervisorReviewNoteSnapshot.currentSchemaVersion,
                updatedAtMs: 0,
                notes: []
            ),
            guidance: SupervisorGuidanceInjectionSnapshot(
                schemaVersion: SupervisorGuidanceInjectionSnapshot.currentSchemaVersion,
                updatedAtMs: guidance.injectedAtMs,
                items: [guidance]
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

        let pendingGuidance = try #require(presentation.pendingGuidance)
        let contract = try #require(pendingGuidance.contractSummary)

        #expect(pendingGuidance.guidanceSummaryText == "当前没有待处理的 Hub 授权。")
        #expect(contract.kind == .grantResolution)
        #expect(contract.summaryText == "当前没有待处理的 Hub 授权。")
        #expect(contract.primaryBlocker == "grant_required")
        #expect(contract.nextSafeAction == "open_hub_grants")
        #expect(contract.recommendedActionsText == "Open Hub grant approval for this project | Retry the governed step after grant approval")
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
    func presentationLoadsRecentGovernanceConfigUpdatesFromRawLog() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-config-updates-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendRawLog(
            [
                "type": "project_governance_bundle",
                "action": "update",
                "created_at": now.timeIntervalSince1970 - 3600,
                "execution_tier": "a1_plan",
                "supervisor_intervention_tier": "s2_periodic_review",
                "review_policy_mode": "milestone_only",
                "progress_heartbeat_sec": 900,
                "review_pulse_sec": 0,
                "brainstorm_review_sec": 0,
                "event_driven_review_enabled": false,
                "event_review_triggers": ["manual_request"],
                "compat_source": "explicit_dual_dial",
                "runtime_surface_configured": "manual",
                "effective_runtime_surface": "manual",
                "runtime_surface_hub_override": "none",
                "runtime_surface_remote_override": "none",
                "runtime_surface_ttl_sec": 1800,
                "runtime_surface_remaining_sec": 1800,
                "invalid_reasons": [],
                "warning_reasons": [],
                "should_fail_closed": false
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "project_governance_bundle",
                "action": "update",
                "created_at": now.timeIntervalSince1970 - 300,
                "execution_tier": "a3_deliver_auto",
                "configured_execution_tier": "a3_deliver_auto",
                "effective_execution_tier": "a3_deliver_auto",
                "supervisor_intervention_tier": "s2_periodic_review",
                "configured_supervisor_tier": "s2_periodic_review",
                "effective_supervisor_tier": "s3_strategic_coach",
                "effective_supervisor_intervention_tier": "s3_strategic_coach",
                "effective_supervisor_work_order_depth": "execution_ready",
                "review_policy_mode": "hybrid",
                "progress_heartbeat_sec": 600,
                "review_pulse_sec": 1200,
                "brainstorm_review_sec": 2400,
                "event_driven_review_enabled": true,
                "event_review_triggers": ["blocker_detected", "plan_drift", "pre_done_summary"],
                "compat_source": "explicit_dual_dial",
                "governance_truth": "治理真相：预设 A3/S2 · 当前生效 A3/S3 · 审查 混合 · 节奏 心跳 10m / 脉冲 20m / 脑暴 40m。",
                "runtime_surface_configured": "guided",
                "effective_runtime_surface": "guided",
                "runtime_surface_hub_override": "clamp_guided",
                "runtime_surface_remote_override": "none",
                "runtime_surface_ttl_sec": 1800,
                "runtime_surface_remaining_sec": 900,
                "invalid_reasons": [],
                "warning_reasons": ["supervisor_escalated_for_safety"],
                "should_fail_closed": false
            ],
            for: ctx
        )

        let presentation = ProjectGovernanceActivityPresentation.load(for: ctx, now: now)

        #expect(presentation.latestConfigUpdate != nil)
        #expect(presentation.recentConfigUpdates.count == 2)

        let latest = try #require(presentation.latestConfigUpdate)
        #expect(latest.updatedAtText.contains("5m ago"))
        #expect(latest.configuredGovernanceText == "A3 交付自动推进 · S2 周期审查")
        #expect(latest.effectiveGovernanceText == "A3 交付自动推进 · S3 战略教练")
        #expect(latest.effectiveWorkOrderDepthText == "执行就绪")
        #expect(latest.reviewPolicyText == "审查 混合")
        #expect(latest.cadenceText == "心跳 10分钟 / 脉冲 20分钟 / 脑暴 40分钟")
        #expect(latest.eventReviewText == "开启 · 发现阻塞 | 计划漂移 | 完成前审查")
        #expect(latest.runtimeSurfaceText.contains("执行面 浏览器受控执行面"))
        #expect(latest.runtimeSurfaceText.contains("Hub 收束 浏览器受控收束"))
        #expect(latest.governanceTruthText.contains("预设 A3/S2"))
        #expect(latest.governanceTruthText.contains("当前生效 A3/S3"))
        #expect(latest.validationText.contains("警告原因"))

        let older = try #require(presentation.recentConfigUpdates.last)
        #expect(older.reviewPolicyText == "审查 里程碑")
        #expect(older.eventReviewText == "关闭")
        #expect(older.runtimeSurfaceText.contains("执行面 最保守执行面"))
    }

    @Test
    func presentationLoadsAutomationRuntimeSummaryFromRawLog() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-automation-activity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": now.timeIntervalSince1970 - 600,
                "run_id": "run-auto-1",
                "recipe_id": "recipe-auto",
                "recipe_ref": "recipe-auto@v1",
                "audit_ref": "audit-launch"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": now.timeIntervalSince1970 - 300,
                "run_id": "run-auto-1",
                "recipe_id": "recipe-auto",
                "state": "blocked",
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 90,
                "resume_token": "resume-auto-1",
                "checkpoint_ref": "checkpoint-auto-1",
                "stable_identity": true,
                "current_step_id": "verify_smoke",
                "current_step_title": "Run focused smoke checks",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting for the bounded retry window.",
                "audit_ref": "audit-checkpoint"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": now.timeIntervalSince1970 - 240,
                "run_id": "run-auto-1",
                "recipe_ref": "recipe-auto@v1",
                "final_state": "blocked",
                "hold_reason": "automation_verify_failed",
                "detail": "1 of 2 checks passed",
                "executed_action_count": 3,
                "succeeded_action_count": 2,
                "total_action_count": 4,
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 2,
                    "passed_command_count": 1,
                    "hold_reason": "automation_verify_failed",
                    "detail": "1 of 2 checks passed",
                    "verification_contract": [
                        "expected_state": "post_change_verification_passes",
                        "verify_method": "project_verify_commands",
                        "retry_policy": "manual_retry_or_replan",
                        "hold_policy": "block_run_and_emit_structured_blocker",
                        "evidence_required": true,
                        "trigger_action_ids": ["verify_smoke"],
                        "verify_commands": ["swift test --filter SmokeTests"]
                    ]
                ],
                "blocker": [
                    "code": "automation_verify_failed",
                    "summary": "验证失败，需要收窄验证集后重试",
                    "stage": "verification",
                    "detail": "1 of 2 checks passed",
                    "next_safe_action": "rerun_focused_verification",
                    "retry_eligible": true,
                    "current_step_id": "verify_smoke",
                    "current_step_title": "Run focused smoke checks",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting for the bounded retry window."
                ],
                "current_step_id": "verify_smoke",
                "current_step_title": "Run focused smoke checks",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting for the bounded retry window.",
                "audit_ref": "audit-execution"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_verification",
                "phase": "completed",
                "created_at": now.timeIntervalSince1970 - 210,
                "run_id": "run-auto-1",
                "recipe_ref": "recipe-auto@v1",
                "required": true,
                "executed": true,
                "command_count": 2,
                "passed_command_count": 1,
                "hold_reason": "automation_verify_failed",
                "detail": "1 of 2 checks passed",
                "audit_ref": "audit-verify"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": now.timeIntervalSince1970 - 180,
                "source_run_id": "run-prev",
                "retry_run_id": "run-auto-1",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "revised_verification_contract": [
                    "expected_state": "post_change_verification_passes",
                    "verify_method": "project_verify_commands_override",
                    "retry_policy": "retry_failed_verify_commands_within_budget",
                    "hold_policy": "block_run_and_emit_structured_blocker",
                    "evidence_required": true,
                    "trigger_action_ids": ["verify_smoke"],
                    "verify_commands": ["swift test --filter SmokeTests --skip PassedCase"]
                ],
                "retry_reason_descriptor": [
                    "code": "automation_verify_failed",
                    "category": "verification",
                    "summary": "只重跑失败的验证命令",
                    "strategy": "verify_failed_retry",
                    "blocker_code": "automation_verify_failed",
                    "planning_mode": "verify_only_retry",
                    "current_step_id": "verify_smoke",
                    "current_step_title": "Run focused smoke checks",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting for the bounded retry window."
                ],
                "source_blocker": [
                    "code": "automation_verify_failed",
                    "summary": "验证失败，需要收窄验证集后重试",
                    "stage": "verification",
                    "detail": "1 of 2 checks passed",
                    "next_safe_action": "rerun_focused_verification",
                    "retry_eligible": true,
                    "current_step_id": "verify_smoke",
                    "current_step_title": "Run focused smoke checks",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting for the bounded retry window."
                ],
                "source_handoff_artifact_path": "build/reports/handoff.json",
                "source_hold_reason": "automation_verify_failed",
                "current_step_id": "verify_smoke",
                "current_step_title": "Run focused smoke checks",
                "current_step_state": "retry_wait",
                "current_step_summary": "Waiting for the bounded retry window.",
                "audit_ref": "audit-retry"
            ],
            for: ctx
        )

        let presentation = ProjectGovernanceActivityPresentation.load(for: ctx, now: now)

        let latestAutomation = try #require(presentation.latestAutomation)
        #expect(latestAutomation.runID == "run-auto-1")
        #expect(latestAutomation.stateText == "受阻")
        #expect(latestAutomation.stepText.contains("Run focused smoke checks"))
        #expect(latestAutomation.stepText.contains("等待重试"))
        #expect(latestAutomation.verificationText == "验证失败 1/2 · 1 of 2 checks passed")
        #expect(latestAutomation.verificationContractText == "项目校验命令 · 目标=变更后验证通过 · 失败后=人工重试或重规划 · 证据必需")
        #expect(latestAutomation.blockerText == "验证失败，需要收窄验证集后重试")
        #expect(latestAutomation.retryText == "只重跑失败的验证命令")
        #expect(latestAutomation.retryVerificationContractText == "覆写校验命令 · 目标=变更后验证通过 · 失败后=预算内只重试失败验证 · 证据必需")
        #expect(latestAutomation.recoveryText == "可恢复")
        #expect(latestAutomation.handoffText == "无")
        #expect(latestAutomation.auditRef == "audit-execution")
        #expect(presentation.recentAutomationEvents.count == 5)
        #expect(presentation.recentAutomationEvents.first?.eventTypeText == "已排队重试")
        #expect(presentation.recentAutomationEvents.first?.retryText == "只重跑失败的验证命令")
        #expect(presentation.recentAutomationEvents.first?.retryVerificationContractText == "覆写校验命令 · 目标=变更后验证通过 · 失败后=预算内只重试失败验证 · 证据必需")
        #expect(presentation.recentAutomationEvents.first?.blockerText == "验证失败，需要收窄验证集后重试")
        #expect(presentation.recentAutomationEvents[1].eventTypeText == "验证完成")
        #expect(presentation.recentAutomationEvents[1].stateText == "失败")
        #expect(presentation.recentAutomationEvents[1].verificationText == "验证失败 1/2 · 1 of 2 checks passed")
        #expect(presentation.recentAutomationEvents[1].verificationContractText == nil)
        #expect(presentation.recentAutomationEvents[2].eventTypeText == "执行完成")
        #expect(presentation.recentAutomationEvents[2].stateText == "受阻")
        #expect(presentation.recentAutomationEvents[2].verificationText == "验证失败 1/2 · 1 of 2 checks passed")
        #expect(presentation.recentAutomationEvents[2].verificationContractText == "项目校验命令 · 目标=变更后验证通过 · 失败后=人工重试或重规划 · 证据必需")
        #expect(projectId.isEmpty == false)
    }

    @Test
    func presentationShowsStableIdentityRecoveryFailureInAutomationSummary() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_100)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("governance-automation-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": now.timeIntervalSince1970 - 120,
                "run_id": "run-identity-drift",
                "recipe_id": "recipe-auto",
                "recipe_ref": "recipe-auto@v1",
                "audit_ref": "audit-launch-identity"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": now.timeIntervalSince1970 - 60,
                "run_id": "run-identity-drift",
                "recipe_id": "recipe-auto",
                "state": "blocked",
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-identity-drift",
                "checkpoint_ref": "checkpoint-identity-drift",
                "stable_identity": false,
                "current_step_id": "verify_smoke",
                "current_step_title": "Run focused smoke checks",
                "current_step_state": "blocked",
                "current_step_summary": "Stable identity drifted before restart recovery.",
                "audit_ref": "audit-checkpoint-identity"
            ],
            for: ctx
        )

        let presentation = ProjectGovernanceActivityPresentation.load(for: ctx, now: now)

        let latestAutomation = try #require(presentation.latestAutomation)
        #expect(latestAutomation.runID == "run-identity-drift")
        #expect(latestAutomation.stateText == "受阻")
        #expect(latestAutomation.recoveryText == "身份校验失败")
    }

    @Test
    func emptyPresentationFallsBackToNonePlaceholders() {
        let presentation = ProjectGovernanceActivityPresentation.empty

        #expect(presentation.reviewCount == 0)
        #expect(presentation.guidanceCount == 0)
        #expect(presentation.pendingAckCount == 0)
        #expect(presentation.followUpRhythmSummary == "(none)")
        #expect(presentation.latestConfigUpdate == nil)
        #expect(presentation.recentConfigUpdates.isEmpty)
        #expect(presentation.latestReview == nil)
        #expect(presentation.recentReviews.isEmpty)
        #expect(presentation.pendingGuidance == nil)
        #expect(presentation.latestGuidance == nil)
        #expect(presentation.recentGuidance.isEmpty)
        #expect(presentation.latestAutomation == nil)
        #expect(presentation.recentAutomationEvents.isEmpty)
        #expect(presentation.schedule.lastHeartbeatText == "(none)")
        #expect(presentation.schedule.nextBrainstormReviewText == "(none)")
    }

    @Test
    func governanceDisplayLocalizesFieldLabelsAndAckCopy() {
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("ack_status") == "确认状态")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("updated_at") == "更新时间")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("configured_governance") == "预设治理档")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("validation") == "治理校验")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("retry_at_ms") == "重试时间(ms)")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("work_order_depth") == "工单深度")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("recommended_actions") == "建议动作")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_state") == "运行状态")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_step") == "当前步骤")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_verification") == "验证状态")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_verification_contract") == "验证合同")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_retry") == "重试策略")
        #expect(ProjectGovernanceActivityDisplay.fieldLabel("automation_retry_verification_contract") == "重试验证合同")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "ack", value: "Pending · required") == "待确认 · 需要确认")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "ack_status", value: "Accepted") == "已接受")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: "retry due now") == "现在可重试")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: "settled") == "已结束")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: "expires in 5m") == "将在5分钟后过期")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "lifecycle", value: "retry in 1h 5m") == "将在1小时5分钟后重试")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "trigger", value: "Blocker Detected") == "发现阻塞")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "level", value: "R2 Strategic") == "R2 战略")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "verdict", value: "Better Path Found") == "发现更优路径")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "delivery", value: "Replan Request") == "请求重规划")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "intervention", value: "Replan At Safe Point") == "在安全点重规划")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "safe_point", value: "Next Step Boundary") == "下一步边界")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "supervisor_tier", value: "S3 Strategic Coach") == "S3 战略教练")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "work_order_depth", value: "Execution Ready") == "执行就绪")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "project_ai_strength", value: "Strong · conf=0.91") == "强 · 置信度=0.91")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "follow_up_rhythm", value: "cadence=active · blocker cooldown≈600s") == "节奏=活跃 · 阻塞冷却≈600秒")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "updated_at", value: "2023-11-14 22:08:20 · 5m ago") == "2023-11-14 22:08:20 · 5分钟前")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "created_at", value: "2023-11-14 22:03:20 · 10m ago") == "2023-11-14 22:03:20 · 10分钟前")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "next_heartbeat", value: "2023-11-14 22:28:20 · in 15m") == "2023-11-14 22:28:20 · 15分钟后")
        #expect(ProjectGovernanceActivityDisplay.displayValue(label: "ack_updated_at", value: "(none)") == "无")
        #expect(ProjectGovernanceActivityDisplay.fieldLine("work_order_ref", value: "(none)") == "工单引用：无")
        #expect(ProjectGovernanceActivityDisplay.fieldLine("next_safe_action", value: "repair_before_execution") == "下一个安全动作：repair_before_execution")
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
