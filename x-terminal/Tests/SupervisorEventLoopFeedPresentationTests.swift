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
        #expect(row.nextSafeActionText == "安全下一步： open_hub_grants")
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
        #expect(row.nextSafeActionText == "安全下一步： open_ui_review")
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
        #expect(row.policyReasonText == "策略原因： ui review blocker detected")
        #expect(row.policyText == "review=Blocker Detected · next=open_ui_review")
    }
}
