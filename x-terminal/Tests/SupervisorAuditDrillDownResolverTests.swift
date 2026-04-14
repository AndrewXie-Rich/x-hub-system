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
        #expect(selection?.presentation.title == "XT 内建受治理技能")
        #expect(selection?.presentation.statusLabel == "内建")
    }

    @Test
    func infrastructureCandidateReviewItemResolvesUnderlyingReviewSelection() {
        let candidate = HubIPCClient.SupervisorCandidateReviewItem(
            schemaVersion: "v1",
            reviewId: "review-1",
            requestId: "req-1",
            evidenceRef: "audit://candidate/1",
            reviewState: "pending_review",
            durablePromotionState: "candidate_only",
            promotionBoundary: "project",
            deviceId: "device-1",
            userId: "user-1",
            appId: "xt",
            threadId: "thread-1",
            threadKey: "thread-key-1",
            projectId: "project-alpha",
            projectIds: [],
            scopes: ["project_memory"],
            recordTypes: ["canonical"],
            auditRefs: [],
            idempotencyKeys: [],
            candidateCount: 3,
            summaryLine: "归并了 3 条候选记忆",
            mirrorTarget: "xt_local_store",
            localStoreRole: "cache",
            carrierKind: "review_bundle",
            carrierSchemaVersion: "v1",
            pendingChangeId: "",
            pendingChangeStatus: "",
            editSessionId: "",
            docId: "",
            writebackRef: "",
            stageCreatedAtMs: 0,
            stageUpdatedAtMs: 0,
            latestEmittedAtMs: 20_000,
            createdAtMs: 18_000,
            updatedAtMs: 20_000
        )
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            candidateReviews: [candidate],
            candidateReviewProjectNamesByID: ["project-alpha": "Project Alpha"],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "candidate-review-req-1",
            kind: .candidateReview,
            iconName: "square.stack.3d.up.badge.a.fill",
            title: "候选记忆审查",
            summary: "待处理 1 项",
            detail: "Project Alpha",
            badgeText: "待审查",
            tone: .attention,
            timestamp: 20,
            contractText: "合同： 候选记忆审查 · blocker=pending_review",
            nextSafeActionText: "安全下一步： 打开候选记忆审查面板 · 建议动作：转入审查",
            actionURL: nil,
            actionLabel: nil
        )

        let selection = SupervisorAuditDrillDownResolver.selection(
            for: item,
            context: context
        ) { _, _, _ in
            nil
        }

        #expect(selection?.source == .candidateReview(candidate))
        #expect(selection?.fullRecord == nil)
        #expect(selection?.presentation.title == "候选记忆审查")
        #expect(selection?.presentation.statusLabel == "待转入审查")
        #expect(selection?.presentation.summary == "归并了 3 条候选记忆")
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

    @Test
    func infrastructureMemoryAssemblyItemDoesNotResolveAuditDrillDownSelection() {
        let context = SupervisorAuditDrillDownResolver.Context(
            officialSkillsStatusLine: "official healthy",
            officialSkillsTransitionLine: "synced",
            officialSkillsDetailLine: "pkg=4 ready=4",
            officialSkillsTopBlockerSummaries: [],
            eventLoopStatusLine: "idle",
            pendingHubGrants: [],
            pendingSupervisorSkillApprovals: [],
            recentSupervisorSkillActivities: [],
            recentSupervisorEventLoopActivities: []
        )
        let item = SupervisorInfrastructureFeedPresentation.Item(
            id: "memory-assembly-hidden-project-scoped-recovery",
            kind: .memoryAssembly,
            iconName: "brain.head.profile",
            title: "记忆装配提醒",
            summary: "显式 hidden project 聚焦时没有补回项目范围上下文",
            detail: "显式 hidden focus 后仍未补回项目范围上下文",
            badgeText: "阻断",
            tone: .critical,
            timestamp: nil,
            contractText: "合同： memory_assembly · blocker=memory_scoped_hidden_project_recovery_missing",
            nextSafeActionText: "安全下一步： 打开诊断并重建 hidden project 记忆",
            actionURL: "xterminal://settings?section_id=diagnostics",
            actionLabel: "打开诊断"
        )

        let selection = SupervisorAuditDrillDownResolver.selection(
            for: item,
            context: context
        ) { _, _, _ in
            Issue.record("memory assembly infrastructure item should not load a drill-down record")
            return nil
        }

        #expect(selection == nil)
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
