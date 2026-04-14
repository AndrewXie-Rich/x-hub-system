import Foundation
import Testing
@testable import XTerminal

struct SupervisorAuditDrillDownActionResolverTests {

    @Test
    func officialSkillsChannelActionResolvesSelection() {
        let selection = SupervisorAuditDrillDownActionResolver.selection(
            for: .officialSkillsChannel,
            context: context(
                officialSkillsTopBlockerSummaries: [
                    AXOfficialSkillBlockerSummaryItem(
                        packageSHA256: "sha-secondary",
                        title: "Secondary Skill",
                        subtitle: "skill.secondary",
                        stateLabel: "blocked",
                        summaryLine: "version=2.0.0 package=ready risk=medium grant=none",
                        timelineLine: "last_blocked=2026-03-19T11:00:00Z"
                    ),
                    AXOfficialSkillBlockerSummaryItem(
                        packageSHA256: "sha-agent-browser",
                        title: "Agent Browser",
                        subtitle: "agent-browser",
                        stateLabel: "blocked",
                        summaryLine: "version=2.0.0 package=ready risk=high grant=required",
                        timelineLine: "last_blocked=2026-03-19T12:00:00Z"
                    )
                ]
            ),
            loadFullRecord: { _, _, _ in nil }
        )

        #expect(selection?.source == .officialSkillsChannel)
        #expect(selection?.presentation.title == "官方技能通道")
        #expect(selection?.presentation.actionLabel == "处理授权阻塞")
        #expect(selection?.presentation.secondaryActions.map(\.label) == ["查看 Secondary Skill"])
    }

    @Test
    func recentSkillActivityActionLoadsEmbeddedRecord() {
        let activity = recentSkillActivity(requestId: "req-1", projectId: "project-alpha", projectName: "Project Alpha")
        let fullRecord = skillFullRecord(requestId: "req-1", projectName: "Project Alpha")

        let selection = SupervisorAuditDrillDownActionResolver.selection(
            for: .recentSkillActivity(activity),
            context: context(recentSupervisorSkillActivities: [activity]),
            loadFullRecord: { projectId, projectName, requestId in
                #expect(projectId == "project-alpha")
                #expect(projectName == "Project Alpha")
                #expect(requestId == "req-1")
                return fullRecord
            }
        )

        #expect(selection?.source == .recentSkillActivity(activity))
        #expect(selection?.fullRecord == fullRecord)
    }

    @Test
    func fullRecordFallbackActionReturnsFallbackSelection() {
        let record = skillFullRecord(requestId: "req-fallback", projectName: "Project Fallback")

        let selection = SupervisorAuditDrillDownActionResolver.selection(
            for: .fullRecordFallback(
                projectId: "project-fallback",
                projectName: "Project Fallback",
                record: record
            ),
            context: context(),
            loadFullRecord: { _, _, _ in nil }
        )

        #expect(selection?.source == .fullRecordFallback(
            projectId: "project-fallback",
            projectName: "Project Fallback",
            record: record
        ))
        #expect(selection?.fullRecord == record)
    }

    @Test
    func infrastructureItemActionRoutesThroughInfrastructureResolver() {
        let activity = eventLoopActivity(
            id: "event-1",
            projectId: "project-gamma",
            projectName: "Project Gamma",
            dedupeKey: "approval_resolution:req-3"
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-3",
            projectId: "project-gamma",
            projectName: "Project Gamma"
        )
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "event-loop-event-1",
            kind: .eventLoop,
            iconName: "bolt",
            title: "Approval Resolution",
            summary: "resolved",
            detail: "Project Gamma",
            badgeText: "done",
            tone: .success,
            timestamp: activity.updatedAt,
            actionURL: nil,
            actionLabel: nil
        )
        let record = skillFullRecord(requestId: "req-3", projectName: "Project Gamma")

        let selection = SupervisorAuditDrillDownActionResolver.selection(
            for: .infrastructureItem(item),
            context: context(
                recentSupervisorSkillActivities: [relatedSkill],
                recentSupervisorEventLoopActivities: [activity]
            ),
            loadFullRecord: { _, _, _ in record }
        )

        #expect(selection?.source == .eventLoop(activity))
        #expect(selection?.fullRecord == record)
    }

    @Test
    func builtinInfrastructureItemActionResolvesBuiltinSelection() {
        let builtinSkills = [
            AXBuiltinGovernedSkillSummary(
                skillID: "guarded-automation",
                displayName: "Guarded Automation",
                summary: "Inspect trusted automation readiness.",
                capabilitiesRequired: ["project.snapshot", "browser.read", "device.browser.control"],
                sideEffectClass: "external_side_effect",
                riskLevel: "high",
                policyScope: "xt_builtin"
            )
        ]
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "xt-builtin-governed-skills",
            kind: .xtBuiltinGovernedSkills,
            iconName: "bolt.shield",
            title: "XT Native Skills",
            summary: "1 builtin ready",
            detail: "local/native only",
            badgeText: "builtin",
            tone: .success,
            timestamp: nil,
            actionURL: nil,
            actionLabel: nil
        )

        let selection = SupervisorAuditDrillDownActionResolver.selection(
            for: .infrastructureItem(item),
            context: context(),
            loadFullRecord: { _, _, _ in nil }
        )

        #expect(selection?.source == .xtBuiltinGovernedSkills(builtinSkills))
        #expect(selection?.presentation.actionLabel == "打开诊断")
    }

    private func context(
        officialSkillsTopBlockerSummaries: [AXOfficialSkillBlockerSummaryItem] = [],
        builtinGovernedSkills: [AXBuiltinGovernedSkillSummary] = [
            AXBuiltinGovernedSkillSummary(
                skillID: "guarded-automation",
                displayName: "Guarded Automation",
                summary: "Inspect trusted automation readiness.",
                capabilitiesRequired: ["project.snapshot", "browser.read", "device.browser.control"],
                sideEffectClass: "external_side_effect",
                riskLevel: "high",
                policyScope: "xt_builtin"
            )
        ],
        recentSupervisorSkillActivities: [SupervisorManager.SupervisorRecentSkillActivity] = [],
        recentSupervisorEventLoopActivities: [SupervisorManager.SupervisorEventLoopActivity] = []
    ) -> SupervisorAuditDrillDownResolver.Context {
        SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: officialSkillsTopBlockerSummaries,
            builtinGovernedSkills: builtinGovernedSkills,
            managedSkillsStatusLine: "skills ok",
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: recentSupervisorSkillActivities,
            recentSupervisorEventLoopActivities: recentSupervisorEventLoopActivities
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
            triggerSource: "approval_resolution",
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

    private func skillFullRecord(
        requestId: String,
        projectName: String
    ) -> SupervisorSkillFullRecord {
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
}
