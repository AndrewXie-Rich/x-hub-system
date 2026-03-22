import Foundation
import Testing
@testable import XTerminal

struct SupervisorCardActionResolverTests {

    @Test
    func pendingHubGrantActionsRespectFlightAndAuthorityState() {
        let grant = pendingGrant(actionURL: "xt://grant/1")

        let actions = SupervisorCardActionResolver.pendingHubGrantActions(
            grant,
            inFlight: true,
            canAct: false
        )

        #expect(actions.map(\.label) == ["详情", "打开", "批准", "拒绝"])
        #expect(actions[0].isEnabled == false)
        #expect(actions[1].isEnabled == false)
        #expect(actions[2].style == .prominent)
        #expect(actions[2].isEnabled == false)
        #expect(actions[3].isEnabled == false)
    }

    @Test
    func recentSkillActivityActionsIncludeApprovalRetryAndOpenWhenApplicable() {
        let item = recentSkillActivity(
            status: .awaitingAuthorization,
            requiredCapability: "",
            actionURL: "xt://project/1"
        )

        let actions = SupervisorCardActionResolver.recentSkillActivityActions(item)

        #expect(actions.map(\.label) == ["批准", "拒绝", "打开审批", "查看详情"])
        #expect(actions[0].style == .prominent)
        #expect(actions[1].style == .standard)
    }

    @Test
    func recentSkillActivityActionsIncludeRetryWhenBlocked() {
        let item = recentSkillActivity(
            status: .blocked,
            requiredCapability: "web.fetch",
            actionURL: nil
        )

        let actions = SupervisorCardActionResolver.recentSkillActivityActions(item)

        #expect(actions.map(\.label) == ["重试", "查看详情"])
    }

    @Test
    func recentSkillActivityActionsUseOpenUIReviewLabelWhenActionTargetsUIReview() {
        let item = recentSkillActivity(
            status: .completed,
            requiredCapability: nil,
            actionURL: XTDeepLinkURLBuilder.projectURL(
                projectId: "project-alpha",
                pane: .chat,
                governanceDestination: .uiReview
            )?.absoluteString
        )

        let actions = SupervisorCardActionResolver.recentSkillActivityActions(item)

        #expect(actions.map(\.label) == ["打开 UI 审查", "查看详情"])
    }

    @Test
    func recentSkillActivityActionsIncludeGovernanceRepairShortcutWhenBlockedByExecutionTier() {
        let item = recentSkillActivity(
            status: .blocked,
            requiredCapability: nil,
            actionURL: nil,
            denyCode: "governance_capability_denied"
        )

        let actions = SupervisorCardActionResolver.recentSkillActivityActions(item)

        #expect(actions.map(\.label) == ["打开执行档位", "重试", "查看详情"])
        switch actions[0].action {
        case .openProjectGovernance(let projectId, let destination):
            #expect(projectId == "project-alpha")
            #expect(destination == .executionTier)
        default:
            Issue.record("expected governance repair action")
        }
    }

    @Test
    func auditSheetActionsKeepGovernanceRepairShortcutForBlockedSkillActivity() {
        let item = recentSkillActivity(
            status: .blocked,
            requiredCapability: nil,
            actionURL: nil,
            denyCode: "governance_capability_denied"
        )
        let detail = SupervisorAuditDrillDownSelection.recentSkillActivity(item, fullRecord: nil)

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["打开执行档位", "重试"])
    }

    @Test
    func auditSheetActionsRecoverGovernanceRepairShortcutFromFallbackRecord() {
        let record = SupervisorSkillFullRecord(
            requestID: "req-1",
            projectName: "Project Alpha",
            title: "Supervisor skill blocked",
            latestStatus: "blocked",
            latestStatusLabel: "Blocked",
            requestMetadata: [],
            approvalFields: [
                .init(label: "deny_code", value: "governance_capability_denied"),
                .init(label: "policy_source", value: "project_governance"),
                .init(label: "policy_reason", value: "execution_tier_missing")
            ],
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
        let detail = SupervisorAuditDrillDownSelection.fullRecordFallback(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record
        )

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["打开执行档位"])
        switch actions[0].action {
        case .openProjectGovernance(let projectId, let destination):
            #expect(projectId == "project-alpha")
            #expect(destination == .executionTier)
        default:
            Issue.record("expected governance repair action for fallback record")
        }
    }

    @Test
    func auditSheetActionsReuseRecentSkillActivityActionRulesWithoutNavigationActions() {
        let item = recentSkillActivity(
            status: .awaitingAuthorization,
            requiredCapability: "",
            actionURL: "xt://project/1"
        )
        let detail = SupervisorAuditDrillDownSelection.recentSkillActivity(item, fullRecord: nil)

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["打开审批", "批准", "拒绝"])
    }

    @Test
    func auditSheetActionsPromoteOpenUIReviewWhenEmbeddedRecordFlagsUnsafeUI() {
        let item = recentSkillActivity(
            status: .completed,
            requiredCapability: nil,
            actionURL: XTDeepLinkURLBuilder.projectURL(
                projectId: "project-alpha",
                pane: .chat
            )?.absoluteString
        )
        let fullRecord = SupervisorSkillFullRecord(
            requestID: "req-1",
            projectName: "Project Alpha",
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
            uiReviewAgentEvidenceFields: [
                .init(label: "verdict", value: "attention_needed"),
                .init(label: "sufficient_evidence", value: "true"),
                .init(label: "objective_ready", value: "false"),
                .init(label: "issue_codes", value: "critical_action_not_visible")
            ],
            uiReviewAgentEvidenceText: nil,
            supervisorEvidenceJSON: nil
        )
        let detail = SupervisorAuditDrillDownSelection.recentSkillActivity(
            item,
            fullRecord: fullRecord
        )

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["打开 UI 审查", "打开项目"])
    }

    @Test
    func auditSheetActionsKeepOpenRecordSecondaryWhenEventLoopRoutesToUIReview() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "event-ui-review-1",
            createdAt: 10,
            updatedAt: 20,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "ui_review_attention",
            dedupeKey: "skill_callback:req-evt-ui-1:completed",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "skill callback completed",
            resultSummary: "follow up required",
            policySummary: "policy=retry_once\nnext=open_ui_review"
        )
        let detail = SupervisorAuditDrillDownSelection.eventLoop(
            activity,
            relatedSkillActivity: nil,
            fullRecord: nil
        )

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["打开 UI 审查", "打开记录"])
    }

    @Test
    func auditSheetActionsIncludeOfficialSkillsSecondaryShortcuts() {
        let detail = SupervisorAuditDrillDownSelection.officialSkillsChannel(
            statusLine: "official healthy skills=24 auto=persisted",
            transitionLine: "synced",
            detailLine: "pkg=4 ready=2 blocked=2",
            blockerSummaries: [
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
            ],
            eventLoopStatusLine: "idle"
        )

        let actions = SupervisorCardActionResolver.auditSheetActions(detail)

        #expect(actions.map(\.label) == ["处理授权阻塞", "查看 Secondary Skill"])
    }

    private func pendingGrant(actionURL: String?) -> SupervisorManager.SupervisorPendingGrant {
        SupervisorManager.SupervisorPendingGrant(
            id: "grant-1",
            dedupeKey: "grant-1",
            grantRequestId: "grant-1",
            requestId: "req-1",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            capability: "web.fetch",
            modelId: "gpt-5.4",
            reason: "needs network",
            requestedTtlSec: 3600,
            requestedTokenCap: 8000,
            createdAt: 1,
            actionURL: actionURL,
            priorityRank: 1,
            priorityReason: "test",
            nextAction: "approve"
        )
    }

    private func recentSkillActivity(
        status: SupervisorSkillCallStatus,
        requiredCapability: String?,
        actionURL: String?,
        denyCode: String = ""
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "req-1",
                projectId: "project-alpha",
                jobId: "job-1",
                planId: "plan-1",
                stepId: "step-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: status,
                payload: [:],
                currentOwner: "supervisor",
                resultSummary: status == .blocked ? "blocked" : "",
                denyCode: denyCode,
                resultEvidenceRef: nil,
                requiredCapability: requiredCapability,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-1"
            ),
            tool: .deviceBrowserControl,
            toolCall: nil,
            toolSummary: "open dashboard",
            actionURL: actionURL,
            governance: nil
        )
    }
}
