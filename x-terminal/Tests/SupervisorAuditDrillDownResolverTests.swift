import Foundation
import Testing
@testable import XTerminal

struct SupervisorAuditDrillDownResolverTests {

    @Test
    func recentSkillActivitySelectionEmbedsLoadedRecord() {
        let activity = recentSkillActivity(requestId: "req-1", projectId: "project-alpha", projectName: "Project Alpha")
        let record = fullRecord(requestId: "req-1", projectName: "Project Alpha")

        let selection = SupervisorAuditDrillDownResolver.selection(for: activity) { projectId, projectName, requestId in
            #expect(projectId == "project-alpha")
            #expect(projectName == "Project Alpha")
            #expect(requestId == "req-1")
            return record
        }

        #expect(selection.source == .recentSkillActivity(activity))
        #expect(selection.fullRecord == record)
        #expect(selection.presentation.includesEmbeddedSkillRecord)
    }

    @Test
    func eventLoopSelectionUsesRelatedRecentSkillActivityForRecordLoading() {
        let activity = eventLoopActivity(
            id: "event-1",
            projectId: "",
            projectName: "",
            dedupeKey: "grant_resolution:req-2"
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-2",
            projectId: "project-beta",
            projectName: "Project Beta"
        )
        let record = fullRecord(requestId: "req-2", projectName: "Project Beta")

        let selection = SupervisorAuditDrillDownResolver.selection(
            for: activity,
            recentSkillActivities: [relatedSkill]
        ) { projectId, projectName, requestId in
            #expect(projectId == "project-beta")
            #expect(projectName == "Project Beta")
            #expect(requestId == "req-2")
            return record
        }

        #expect(selection.source == .eventLoop(activity))
        #expect(selection.fullRecord == record)
        #expect(selection.presentation.includesEmbeddedSkillRecord)
    }

    @Test
    func infrastructureEventLoopItemResolvesUnderlyingActivitySelection() {
        let event = eventLoopActivity(
            id: "event-3",
            projectId: "project-gamma",
            projectName: "Project Gamma",
            dedupeKey: "approval_resolution:req-3"
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-3",
            projectId: "project-gamma",
            projectName: "Project Gamma"
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [relatedSkill],
            recentSupervisorEventLoopActivities: [event]
        )
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "event-loop-event-3",
            kind: .eventLoop,
            iconName: "bolt",
            title: "Approval Resolution",
            summary: "resolved",
            detail: "Project Gamma",
            badgeText: "done",
            tone: .success,
            timestamp: event.updatedAt,
            actionURL: nil,
            actionLabel: nil
        )
        let record = fullRecord(requestId: "req-3", projectName: "Project Gamma")

        let selection = SupervisorAuditDrillDownResolver.selection(
            for: item,
            context: context
        ) { _, _, _ in
            record
        }

        #expect(selection?.source == .eventLoop(event))
        #expect(selection?.fullRecord == record)
        #expect(selection?.presentation.requestId == "req-3")
    }

    @Test
    func infrastructureBuiltinSkillsItemResolvesBuiltinSelection() {
        let builtinSkills = [
            AXBuiltinGovernedSkillSummary(
                skillID: "guarded-automation",
                displayName: "Guarded Automation",
                summary: "Inspect trusted automation readiness.",
                capabilitiesRequired: ["project.snapshot", "browser.read", "device.browser.control"],
                sideEffectClass: "external_side_effect",
                riskLevel: "high",
                policyScope: "xt_builtin"
            ),
            AXBuiltinGovernedSkillSummary(
                skillID: "supervisor-voice",
                displayName: "Supervisor Voice",
                summary: "Inspect and control local playback.",
                capabilitiesRequired: ["supervisor.voice.playback"],
                sideEffectClass: "local_side_effect",
                riskLevel: "low",
                policyScope: "xt_builtin"
            )
        ]
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: builtinSkills,
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "xt-builtin-governed-skills",
            kind: .xtBuiltinGovernedSkills,
            iconName: "bolt.shield",
            title: "XT Native Skills",
            summary: "2 builtin ready",
            detail: "local/native only",
            badgeText: "builtin",
            tone: .success,
            timestamp: nil,
            actionURL: nil,
            actionLabel: nil
        )

        let selection = SupervisorAuditDrillDownResolver.selection(
            for: item,
            context: context
        ) { _, _, _ in
            nil
        }

        #expect(selection?.source == .xtBuiltinGovernedSkills(builtinSkills))
        #expect(selection?.fullRecord == nil)
        #expect(selection?.presentation.title == "XT Native Governed Skills")
        #expect(selection?.presentation.statusLabel == "builtin")
    }

    @Test
    func refreshFingerprintChangesWhenRecentSkillActivityChanges() {
        let baseActivity = recentSkillActivity(
            requestId: "req-4",
            projectId: "project-delta",
            projectName: "Project Delta"
        )
        let baseContext = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [baseActivity],
            recentSupervisorEventLoopActivities: []
        )

        var updatedActivity = baseActivity
        updatedActivity.record.status = .blocked
        updatedActivity.record.resultSummary = "waiting for approval"
        updatedActivity.record.updatedAtMs = 9_999

        let updatedContext = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: baseContext.officialSkillsStatusLine,
            officialSkillsTransitionLine: baseContext.officialSkillsTransitionLine,
            officialSkillsDetailLine: baseContext.officialSkillsDetailLine,
            officialSkillsTopBlockerSummaries: baseContext.officialSkillsTopBlockerSummaries,
            eventLoopStatusLine: baseContext.eventLoopStatusLine,
            pendingHubGrants: baseContext.pendingHubGrants,
            pendingSupervisorSkillApprovals: baseContext.pendingSupervisorSkillApprovals,
            recentSupervisorSkillActivities: [updatedActivity],
            recentSupervisorEventLoopActivities: baseContext.recentSupervisorEventLoopActivities
        )

        #expect(
            SupervisorAuditDrillDownResolver.refreshFingerprint(context: baseContext)
                != SupervisorAuditDrillDownResolver.refreshFingerprint(context: updatedContext)
        )
    }

    @Test
    func refreshFingerprintChangesWhenBuiltinGovernedSkillsChange() {
        let baseContext = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            builtinGovernedSkills: [
                AXBuiltinGovernedSkillSummary(
                    skillID: "guarded-automation",
                    displayName: "Guarded Automation",
                    summary: "Inspect trusted automation readiness.",
                    capabilitiesRequired: ["project.snapshot", "browser.read"],
                    sideEffectClass: "external_side_effect",
                    riskLevel: "high",
                    policyScope: "xt_builtin"
                )
            ],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )
        let updatedContext = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: baseContext.officialSkillsStatusLine,
            officialSkillsTransitionLine: baseContext.officialSkillsTransitionLine,
            officialSkillsDetailLine: baseContext.officialSkillsDetailLine,
            officialSkillsTopBlockerSummaries: baseContext.officialSkillsTopBlockerSummaries,
            builtinGovernedSkills: baseContext.builtinGovernedSkills + [
                AXBuiltinGovernedSkillSummary(
                    skillID: "supervisor-voice",
                    displayName: "Supervisor Voice",
                    summary: "Inspect and control local playback.",
                    capabilitiesRequired: ["supervisor.voice.playback"],
                    sideEffectClass: "local_side_effect",
                    riskLevel: "low",
                    policyScope: "xt_builtin"
                )
            ],
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: baseContext.eventLoopStatusLine,
            pendingHubGrants: baseContext.pendingHubGrants,
            pendingSupervisorSkillApprovals: baseContext.pendingSupervisorSkillApprovals,
            recentSupervisorSkillActivities: baseContext.recentSupervisorSkillActivities,
            recentSupervisorEventLoopActivities: baseContext.recentSupervisorEventLoopActivities
        )

        #expect(
            SupervisorAuditDrillDownResolver.refreshFingerprint(context: baseContext)
                != SupervisorAuditDrillDownResolver.refreshFingerprint(context: updatedContext)
        )
    }

    private func fullRecord(requestId: String, projectName: String) -> SupervisorSkillFullRecord {
        SupervisorSkillFullRecord(
            requestID: requestId,
            projectName: projectName,
            title: "Supervisor skill completed",
            latestStatus: "completed",
            latestStatusLabel: "Completed",
            requestMetadata: [],
            approvalFields: [],
            governanceFields: [],
            skillPayloadText: nil,
            toolArgumentsText: nil,
            resultFields: [],
            rawOutputPreview: nil,
            rawOutput: nil,
            evidenceFields: [],
            approvalHistory: [],
            timeline: [],
            supervisorEvidenceJSON: nil
        )
    }

    private func eventLoopActivity(
        id: String,
        projectId: String,
        projectName: String,
        dedupeKey: String
    ) -> SupervisorManager.SupervisorEventLoopActivity {
        SupervisorManager.SupervisorEventLoopActivity(
            id: id,
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "grant_resolution",
            status: "completed",
            reasonCode: "resolved",
            dedupeKey: dedupeKey,
            projectId: projectId,
            projectName: projectName,
            triggerSummary: "follow up",
            resultSummary: "done",
            policySummary: "policy ok"
        )
    }

    private func recentSkillActivity(
        requestId: String,
        projectId: String,
        projectName: String
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: projectId,
            projectName: projectName,
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: requestId,
                projectId: projectId,
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .completed,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: "done",
                denyCode: "",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: nil,
            governance: nil
        )
    }
}
