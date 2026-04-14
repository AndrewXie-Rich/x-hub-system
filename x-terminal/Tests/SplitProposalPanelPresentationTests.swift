import Foundation
import Testing
@testable import XTerminal

struct SplitProposalPanelPresentationTests {

    @Test
    func hotspotSummaryHumanizesBlockedReasonAndNextAction() {
        let lane = makeLane(
            laneID: "lane-7",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "wait_grant"
        )

        #expect(
            SplitProposalPanelPresentation.hotspotSummary(for: lane) ==
                "lane-7 · 阻塞 · 原因：等待授权（grant_pending） · 下一步：等待授权结果（wait_grant）"
        )
    }

    @Test
    func hotspotSummaryFallsBackWhenBlockerMissing() {
        let lane = makeLane(
            laneID: "lane-9",
            status: .failed,
            blockedReason: nil,
            nextActionRecommendation: "pause_lane"
        )

        #expect(
            SplitProposalPanelPresentation.hotspotSummary(for: lane) ==
                "lane-9 · 失败 · 原因：无显式阻塞原因（none） · 下一步：暂停当前泳道（pause_lane）"
        )
    }

    @Test
    func hotspotSummaryFormatsUnknownActionWithReadableFallback() {
        let lane = makeLane(
            laneID: "lane-3",
            status: .stalled,
            blockedReason: .dependencyBlocked,
            nextActionRecommendation: "sync_remote_context"
        )

        #expect(
            SplitProposalPanelPresentation.hotspotSummary(for: lane) ==
                "lane-3 · 停滞 · 原因：依赖任务未完成（dependency_blocked） · 下一步：sync remote context（sync_remote_context）"
        )
    }

    @Test
    func incidentSummaryOmitsDuplicateDenyCodeAndHumanizesAction() {
        let incident = makeIncident(
            incidentCode: "grant_pending",
            denyCode: "grant_pending",
            proposedAction: .autoGrant,
            takeoverLatencyMs: 320
        )

        #expect(
            SplitProposalPanelPresentation.incidentSummary(for: incident) ==
                "等待授权（grant_pending） → 自动授权（auto_grant） · 接管耗时：320ms"
        )
    }

    @Test
    func incidentSummaryIncludesDistinctDenyReasonWhenNeeded() {
        let incident = makeIncident(
            incidentCode: "runtime_error",
            denyCode: "remote_export_blocked",
            proposedAction: .notifyUser,
            takeoverLatencyMs: nil
        )

        #expect(
            SplitProposalPanelPresentation.incidentSummary(for: incident) ==
                "运行时错误（runtime_error） → 通知用户（notify_user） · 阻断原因：Hub remote export gate 阻断了远端请求（remote_export_blocked） · 接管耗时：未知"
        )
    }

    @Test
    func incidentSummaryHumanizesSharedGrantRequiredDenyCode() {
        let incident = makeIncident(
            incidentCode: "runtime_error",
            denyCode: "grant_required",
            proposedAction: .notifyUser,
            takeoverLatencyMs: nil
        )

        #expect(
            SplitProposalPanelPresentation.incidentSummary(for: incident) ==
                "运行时错误（runtime_error） → 通知用户（notify_user） · 阻断原因：继续这个动作前，仍然需要先通过 Hub 授权。（grant_required） · 接管耗时：未知"
        )
    }

    @Test
    func validationIssueSummaryHumanizesSeverityAndCode() {
        let issue = SplitProposalValidationIssue(
            code: "lane_missing_dod",
            message: "Lane lane-1 is missing DoD checklist.",
            severity: .blocking,
            laneId: "lane-1"
        )

        #expect(
            SplitProposalPanelPresentation.validationIssueSummary(issue) ==
                "阻塞：泳道缺少完成标准（lane_missing_dod）"
        )
    }

    @Test
    func promptPresentationHelpersHumanizeStatusAndLintCode() {
        let issue = PromptLintIssue(
            laneId: "lane-2",
            severity: .error,
            code: "missing_risk_boundary",
            message: "Prompt contract is missing risk boundary section."
        )

        #expect(SplitProposalPanelPresentation.promptStatusText(.ready) == "已就绪")
        #expect(
            SplitProposalPanelPresentation.promptLintIssueSummary(issue) ==
                "错误：缺少风险边界（missing_risk_boundary）"
        )
    }

    @Test
    func auditAndLaunchHelpersHumanizeEventAndSimpleBlocker() {
        #expect(
            SplitProposalPanelPresentation.auditEventText(.splitOverridden) ==
                "已覆写拆分提案"
        )
        #expect(
            SplitProposalPanelPresentation.launchBlockedLaneSummary(
                laneID: "lane-3",
                reason: "dependency_not_ready"
            ) ==
                "lane-3：依赖泳道尚未就绪（dependency_not_ready）"
        )
    }

    @Test
    func blockingIssueCodesTextUsesHumanizedLabels() {
        #expect(
            SplitProposalPanelPresentation.blockingIssueCodesText(
                ["high_risk_hard_to_soft_confirmation_required", "lane_missing_dod"]
            ) ==
                "高风险泳道从独立项目降级到项目内执行前需要明确确认（high_risk_hard_to_soft_confirmation_required），泳道缺少完成标准（lane_missing_dod）"
        )
    }

    private func makeLane(
        laneID: String,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason?,
        nextActionRecommendation: String
    ) -> SupervisorLaneHealthLaneState {
        var state = LaneRuntimeState(
            laneID: laneID,
            taskId: UUID(),
            projectId: nil,
            agentProfile: nil,
            status: status,
            blockedReason: blockedReason,
            nextActionRecommendation: nextActionRecommendation
        )
        state.heartbeatSeq = 3
        state.lastHeartbeatAtMs = 1_000
        state.oldestWaitMs = 0
        return SupervisorLaneHealthLaneState(state: state)
    }

    private func makeIncident(
        incidentCode: String,
        denyCode: String,
        proposedAction: SupervisorIncidentAction,
        takeoverLatencyMs: Int64?
    ) -> SupervisorLaneIncident {
        SupervisorLaneIncident(
            id: "incident-1",
            laneID: "lane-1",
            taskID: UUID(),
            projectID: nil,
            incidentCode: incidentCode,
            eventType: "supervisor.incident.\(incidentCode).handled",
            denyCode: denyCode,
            severity: .medium,
            category: .runtime,
            autoResolvable: false,
            requiresUserAck: proposedAction == .notifyUser,
            proposedAction: proposedAction,
            detectedAtMs: 100,
            handledAtMs: 420,
            takeoverLatencyMs: takeoverLatencyMs,
            auditRef: "audit-1",
            detail: "",
            status: .handled
        )
    }
}
