import Foundation
import Testing
@testable import XTerminal

struct SupervisorEventLoopFeedPresentationTests {

    @Test
    func boardBuildsEmptyState() {
        let presentation = SupervisorEventLoopFeedPresentation.board(
            items: [],
            statusLine: "idle",
            now: 1_000
        )

        #expect(presentation.iconName == "arrow.triangle.branch")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "自动跟进记录：0")
        #expect(presentation.statusLine == "idle")
        #expect(presentation.isEmpty)
        #expect(presentation.emptyStateText?.isEmpty == false)
    }

    @Test
    func rowBuildsStatusLabelsActionAndAge() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "grant_resolution",
            status: "queued",
            reasonCode: "grant_pending",
            dedupeKey: "grant_resolution:req-123:grant_approved",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "grant approved",
            resultSummary: "follow-up queued",
            policySummary: "needs acknowledgement"
        )

        let row = SupervisorEventLoopFeedPresentation.row(activity, now: 1_000)

        #expect(row.triggerLabel == "授权处理")
        #expect(row.projectLabel == "Project Alpha")
        #expect(row.statusLabel == "排队中")
        #expect(row.statusTone == .info)
        #expect(row.triggerText == "触发：grant approved")
        #expect(row.resultText == "结果：follow-up queued")
        #expect(row.blockedSummaryText == nil)
        #expect(row.governanceTruthText == nil)
        #expect(row.governanceReasonText == nil)
        #expect(row.policyReasonText == nil)
        #expect(row.policyText == "needs acknowledgement")
        #expect(row.contractText == nil)
        #expect(row.nextSafeActionText == nil)
        #expect(row.reasonText == "原因：grant_pending")
        #expect(row.dedupeKeyText == "去重键：grant_resolution:req-123:grant_approved")
        #expect(row.ageText == "刚刚")
        #expect(row.actionDescriptors.map(\.label) == ["详情", "打开记录"])
    }

    @Test
    func rowHumanizesRouteReasonWithoutChangingGenericWorkflowReasons() {
        let routeActivity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-route-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "heartbeat",
            status: "queued",
            reasonCode: "deny_code=policy_remote_denied",
            dedupeKey: "heartbeat:project-alpha:route_waiting",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "route waiting",
            resultSummary: "fallback to local",
            policySummary: ""
        )
        let genericActivity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-generic-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "grant_resolution",
            status: "queued",
            reasonCode: "grant_pending",
            dedupeKey: "grant_resolution:req-123:grant_approved",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "grant approved",
            resultSummary: "follow-up queued",
            policySummary: ""
        )

        let routeRow = SupervisorEventLoopFeedPresentation.row(routeActivity, now: 1_000)
        let genericRow = SupervisorEventLoopFeedPresentation.row(genericActivity, now: 1_000)

        #expect(routeRow.reasonText == "原因：当前策略不允许远端执行（policy_remote_denied）")
        #expect(genericRow.reasonText == "原因：grant_pending")
    }

    @Test
    func rowParsesGrantResolutionContractFromPolicySummary() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-grant-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "grant_resolution",
            status: "completed",
            reasonCode: "grant_pending",
            dedupeKey: "grant_resolution:req-123:grant_approved",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "grant approved",
            resultSummary: "rerun queued",
            policySummary: "review=Blocker Detected · next=open_hub_grants · tier=S3 Strategic Coach"
        )

        let row = SupervisorEventLoopFeedPresentation.row(activity, now: 1_000)

        #expect(row.contractText == "合同： 授权处理 · blocker=grant_pending")
        #expect(row.nextSafeActionText == "安全下一步： 打开 Hub 授权面板")
    }

    @Test
    func rowParsesUIReviewRepairContractFromPolicySummary() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-ui-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "ui_review_attention",
            dedupeKey: "skill_callback:req-ui-1:completed",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "ui review attention needed",
            resultSummary: "open governance review",
            policySummary: "next=open_ui_review · repair=expose_primary_cta@landing_hero_actions"
        )

        let row = SupervisorEventLoopFeedPresentation.row(activity, now: 1_000)

        #expect(row.contractText == "合同： UI 审查修复 · repair_action=expose_primary_cta · repair_focus=landing_hero_actions")
        #expect(row.nextSafeActionText == "安全下一步： 打开 UI 审查")
    }

    @Test
    func rowSurfacesBlockedSummaryGovernanceTruthAndPolicyReason() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-governance-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "heartbeat",
            status: "queued",
            reasonCode: "blocker_detected",
            dedupeKey: "heartbeat:project-alpha:blocker_detected",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "governance follow-up queued",
            resultSummary: "",
            policySummary: "review=Blocker Detected · next=open_ui_review",
            blockedSummary: "Primary CTA is still missing from the landing screen.",
            policyReason: "ui review blocker detected",
            governanceTruth: "治理真相：当前生效 A3/S3 · 审查 Hybrid · 节奏 心跳 5m / 脉冲 10m / 脑暴 30m。"
        )

        let row = SupervisorEventLoopFeedPresentation.row(activity, now: 1_000)

        #expect(row.blockedSummaryText == "阻塞说明： Primary CTA is still missing from the landing screen.")
        #expect(row.governanceTruthText?.contains("当前生效 A3/S3") == true)
        #expect(row.governanceTruthText?.contains("审查 混合") == true)
        #expect(row.governanceReasonText == nil)
        #expect(row.policyReasonText == "策略原因： ui review blocker detected")
        #expect(row.policyText == "review=Blocker Detected · next=open_ui_review")
    }

    @Test
    func boardFallsBackToRelatedSkillGovernanceTruthAndReasonWhenSnapshotIsIncomplete() {
        let activity = SupervisorManager.SupervisorEventLoopActivity(
            id: "evt-governance-fallback-1",
            createdAt: 100,
            updatedAt: 940,
            triggerSource: "skill_callback",
            status: "queued",
            reasonCode: "blocked_skill_followup",
            dedupeKey: "skill_callback:req-governance-fallback-1:blocked",
            projectId: "project-alpha",
            projectName: "Project Alpha",
            triggerSummary: "blocked skill follow up",
            resultSummary: "needs governance repair",
            policySummary: "review=Blocker Detected · next=open_ui_review",
            blockedSummary: "",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: ""
        )
        let relatedSkill = recentSkillActivity(
            requestId: "req-governance-fallback-1",
            status: .blocked,
            tool: .deviceBrowserControl,
            toolSummary: "open project dashboard",
            denyCode: "governance_capability_denied",
            policyReason: "execution_tier_missing_browser_runtime",
            governance: .init(
                configuredExecutionTier: .a1Plan,
                effectiveExecutionTier: .a1Plan,
                configuredSupervisorTier: .s2PeriodicReview,
                effectiveSupervisorTier: .s2PeriodicReview,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 900,
                reviewPulseSeconds: 1800,
                brainstormReviewSeconds: 0
            )
        )

        let presentation = SupervisorEventLoopFeedPresentation.board(
            items: [activity],
            recentSkillActivities: [relatedSkill],
            statusLine: "queued",
            now: 1_000
        )

        #expect(presentation.rows.count == 1)
        let row = presentation.rows[0]
        #expect(row.blockedSummaryText?.contains("当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(row.governanceTruthText == "治理真相：当前生效 A1/S2 · 审查 周期 · 节奏 心跳 15m / 脉冲 30m / 脑暴 关闭。")
        #expect(row.governanceReasonText == "治理原因： 当前项目 A-Tier 不允许浏览器自动化。")
        #expect(row.policyReasonText == "策略原因： execution_tier_missing_browser_runtime")
    }

    private func recentSkillActivity(
        requestId: String,
        status: SupervisorSkillCallStatus,
        tool: ToolName?,
        toolSummary: String,
        denyCode: String,
        policyReason: String,
        governance: SupervisorManager.SupervisorRecentSkillActivity.GovernanceSummary?
    ) -> SupervisorManager.SupervisorRecentSkillActivity {
        let toolName = tool?.rawValue ?? ToolName.run_command.rawValue
        let record = SupervisorSkillCallRecord(
            schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
            requestId: requestId,
            projectId: "project-alpha",
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            toolName: toolName,
            status: status,
            payload: [:],
            currentOwner: "supervisor",
            resultSummary: "browser automation blocked by governance",
            denyCode: denyCode,
            policySource: "project_governance",
            policyReason: policyReason,
            resultEvidenceRef: "evidence-\(requestId)",
            requiredCapability: nil,
            grantRequestId: nil,
            grantId: nil,
            createdAtMs: 100,
            updatedAtMs: 940,
            auditRef: "audit-\(requestId)"
        )

        return SupervisorManager.SupervisorRecentSkillActivity(
            projectId: "project-alpha",
            projectName: "Project Alpha",
            record: record,
            tool: tool,
            toolCall: nil,
            toolSummary: toolSummary,
            actionURL: nil,
            governance: governance
        )
    }
}
