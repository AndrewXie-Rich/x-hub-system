import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorProjectDrillDownTests {
    @Test
    func ownerCanRequestCapsulePlusRecent() throws {
        let now = Date(timeIntervalSince1970: 1_773_500_000).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let projectRoot = FileManager.default.temporaryDirectory.appendingPathComponent("xt_w3_31_drill_owner_\(UUID().uuidString)")
        let project = AXProjectEntry(
            projectId: "p-owner",
            rootPath: projectRoot.path,
            displayName: "Owner Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing drill-down",
            nextStepSummary: "Check recent turns",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let ctx = AXProjectContext(root: projectRoot)
        try ctx.ensureDirs()
        var config = AXProjectConfig.default(forProjectRoot: projectRoot)
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
        try AXProjectStore.saveConfig(config, for: ctx)
        AXRecentContextStore.appendUserMessage(ctx: ctx, text: "Need the latest status", createdAt: now - 3)
        AXRecentContextStore.appendAssistantMessage(ctx: ctx, text: "Working on the local contract", createdAt: now - 2)
        try SupervisorProjectSpecCapsuleStore.upsert(
            SupervisorProjectSpecCapsuleBuilder.build(
                projectId: project.projectId,
                goal: "Ship structured drill-down without leaking full chat history",
                mvpDefinition: "Expose spec, approved decisions, and workflow summary",
                nonGoals: ["Do not expose complete cross-project chat logs"],
                approvedTechStack: ["Swift", "SwiftUI"],
                milestoneMap: [
                    SupervisorProjectSpecMilestone(
                        milestoneId: "ms-1",
                        title: "Scope-safe drill-down",
                        status: .active
                    )
                ],
                sourceRefs: ["/tmp/spec-source.md"]
            ),
            for: ctx
        )
        try SupervisorDecisionTrackStore.upsert(
            SupervisorDecisionTrackBuilder.build(
                decisionId: "decision-1",
                projectId: project.projectId,
                category: .techStack,
                status: .approved,
                statement: "Keep cross-project drill-down in XT only and stay digest-first by default.",
                source: "owner",
                reversible: true,
                approvalRequired: false,
                auditRef: "audit-decision-1",
                evidenceRefs: ["/tmp/decision-evidence.json"],
                createdAtMs: Int64(now * 1000) - 2000
            ),
            for: ctx
        )
        try SupervisorBackgroundPreferenceTrackStore.upsert(
            SupervisorBackgroundPreferenceTrackBuilder.build(
                noteId: "note-1",
                projectId: project.projectId,
                domain: .techStack,
                strength: .medium,
                statement: "Prefer concise structured summaries over prose-heavy context dumps.",
                createdAtMs: Int64(now * 1000) - 1500
            ),
            for: ctx
        )
        try SupervisorReviewNoteStore.upsert(
            SupervisorReviewNoteBuilder.build(
                reviewId: "review-1",
                projectId: project.projectId,
                trigger: .manualRequest,
                reviewLevel: .r2Strategic,
                verdict: .betterPathFound,
                targetRole: .projectChat,
                deliveryMode: .replanRequest,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                projectAIStrengthBand: .strong,
                projectAIStrengthConfidence: 0.92,
                projectAIStrengthAuditRef: "audit-strength-1",
                workOrderRef: "wo-1",
                summary: "Use the scoped drill-down as the shared audit surface instead of free-form recap.",
                recommendedActions: [
                    "Expose the latest review and pending guidance in the supervisor drill-down."
                ],
                anchorGoal: "Ship a scope-safe supervisor-facing audit view",
                anchorDoneDefinition: "Supervisor can inspect governance, workflow, and recent context without opening raw chat logs.",
                anchorConstraints: ["Keep the panel compact and scope-safe."],
                currentState: "Project governance is visible only from the project-side activity view.",
                nextStep: "Promote the same summary into the supervisor drill-down.",
                blocker: "",
                createdAtMs: Int64(now * 1000) - 1_400,
                auditRef: "audit-review-1"
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-1",
                reviewId: "review-1",
                projectId: project.projectId,
                targetRole: .supervisor,
                deliveryMode: .priorityInsert,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "Surface the latest governance metadata in the drill-down before opening broader recent context.",
                ackStatus: .pending,
                ackRequired: true,
                effectiveSupervisorTier: .s3StrategicCoach,
                effectiveWorkOrderDepth: .executionReady,
                workOrderRef: "wo-1",
                ackNote: "",
                injectedAtMs: Int64(now * 1000) - 1_200,
                ackUpdatedAtMs: Int64(now * 1000) - 1_200,
                expiresAtMs: Int64(now * 1000) + 30 * 24 * 3_600_000,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 0,
                auditRef: "audit-guidance-1"
            ),
            for: ctx
        )
        let job = SupervisorJobRecord(
            schemaVersion: SupervisorJobRecord.currentSchemaVersion,
            jobId: "job-1",
            projectId: project.projectId,
            goal: "Wire cross-project drill-down into supervisor memory",
            priority: .high,
            status: .running,
            source: .supervisor,
            currentOwner: "supervisor",
            activePlanId: "plan-1",
            createdAtMs: Int64(now * 1000) - 3_000,
            updatedAtMs: Int64(now * 1000) - 1_000,
            auditRef: "audit-job-1"
        )
        try SupervisorProjectJobStore.append(job, for: ctx)
        try SupervisorProjectPlanStore.upsert(
            SupervisorPlanRecord(
                schemaVersion: SupervisorPlanRecord.currentSchemaVersion,
                planId: "plan-1",
                jobId: "job-1",
                projectId: project.projectId,
                status: .active,
                currentOwner: "supervisor",
                steps: [
                    SupervisorPlanStepRecord(
                        schemaVersion: SupervisorPlanStepRecord.currentSchemaVersion,
                        stepId: "step-1",
                        title: "Render drill-down summary into Memory v1",
                        kind: .writeMemory,
                        status: .running,
                        skillId: "",
                        currentOwner: "supervisor",
                        detail: "append scope-safe structured drill-down block",
                        orderIndex: 0,
                        updatedAtMs: Int64(now * 1000) - 900
                    )
                ],
                createdAtMs: Int64(now * 1000) - 2_500,
                updatedAtMs: Int64(now * 1000) - 900,
                auditRef: "audit-plan-1"
            ),
            for: ctx
        )
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "call-1",
                projectId: project.projectId,
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "memory.drilldown",
                toolName: "memory_snapshot",
                status: .running,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "assembling structured drill-down",
                denyCode: "",
                resultEvidenceRef: "/tmp/workflow-evidence.json",
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: Int64(now * 1000) - 850,
                updatedAtMs: Int64(now * 1000) - 850,
                auditRef: "audit-call-1"
            ),
            for: ctx
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .owner, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let snapshot = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsulePlusRecent,
            recentMessageLimit: 4
        )

        #expect(snapshot.status == .allowed)
        #expect(snapshot.grantedScope == .capsulePlusRecent)
        #expect(snapshot.openedReason == "explicit_portfolio_drilldown")
        #expect(snapshot.capsule?.projectId == project.projectId)
        #expect(snapshot.specCapsule?.goal == "Ship structured drill-down without leaking full chat history")
        #expect(snapshot.decisionRails?.decisionTrack.first?.category == .techStack)
        #expect(snapshot.latestReview?.reviewId == "review-1")
        #expect(snapshot.latestGuidance?.injectionId == "guidance-1")
        #expect(snapshot.pendingAckGuidance?.injectionId == "guidance-1")
        #expect(snapshot.followUpRhythmSummary?.contains("blocker cooldown") == true)
        #expect(snapshot.followUpRhythmSummary?.contains("Execution Ready") == true)
        #expect(snapshot.workflow?.activeJob?.jobId == "job-1")
        #expect(snapshot.recentMessages.count == 2)
        #expect(snapshot.refs.contains(where: { $0.contains("xterminal.project.capsule.summary_json") }))
        #expect(snapshot.refs.contains(where: { $0.contains("xterminal.project.action.summary_json") }))
        #expect(snapshot.refs.contains(AXRecentContextStore.jsonURL(for: ctx).path))
        #expect(snapshot.refs.contains(ctx.xterminalDir.appendingPathComponent("supervisor_project_spec_capsule.json").path))
        #expect(snapshot.refs.contains(ctx.supervisorReviewNotesURL.path))
        #expect(snapshot.refs.contains(ctx.supervisorGuidanceInjectionsURL.path))
        #expect(snapshot.refs.contains(ctx.supervisorJobsURL.path))
        #expect(snapshot.refs.contains("/tmp/decision-evidence.json"))
        #expect(snapshot.refs.contains("/tmp/workflow-evidence.json"))
        #expect(!snapshot.refs.contains(ctx.rawLogURL.path))
    }

    @Test
    func observerCannotEscalateBeyondCapsuleOnly() {
        let now = Date(timeIntervalSince1970: 1_773_500_100).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let project = AXProjectEntry(
            projectId: "p-observer",
            rootPath: "/tmp/p-observer",
            displayName: "Observer Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing",
            nextStepSummary: "Continue",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .observer, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let denied = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsulePlusRecent
        )
        let allowed = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly
        )

        #expect(denied.status == .deniedScope)
        #expect(denied.denyReason == "requested_scope_exceeds_jurisdiction_cap")
        #expect(allowed.status == .allowed)
        #expect(allowed.grantedScope == .capsuleOnly)
        #expect(allowed.refs.contains(where: { $0.contains("xterminal.project.capsule.summary_json") }))
        #expect(!allowed.refs.contains(where: { $0.contains("xterminal.project.action.summary_json") }))
    }

    @Test
    func triageOnlyCannotSeeNonCriticalProject() {
        let now = Date(timeIntervalSince1970: 1_773_500_200).timeIntervalSince1970
        let manager = SupervisorManager.makeForTesting()
        let project = AXProjectEntry(
            projectId: "p-triage",
            rootPath: "/tmp/p-triage",
            displayName: "Triage Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "working",
            currentStateSummary: "Implementing",
            nextStepSummary: "Continue",
            blockerSummary: nil,
            lastSummaryAt: now,
            lastEventAt: now
        )

        let registry = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(registry, persist: false, normalizeWithKnownProjects: false)

        let denied = manager.buildSupervisorProjectDrillDown(
            for: project,
            requestedScope: .capsuleOnly
        )

        #expect(denied.status == .deniedProjectInvisible)
        #expect(denied.denyReason == "project_not_visible_in_current_jurisdiction")
    }
}
