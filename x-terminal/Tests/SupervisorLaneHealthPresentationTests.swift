import Foundation
import Testing
@testable import XTerminal

struct SupervisorLaneHealthPresentationTests {

    @Test
    func filteredLanesKeepAbnormalOnlyAndSortByPriority() {
        let snapshot = SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_000,
            summary: LaneHealthSummary(
                total: 4,
                running: 1,
                blocked: 1,
                stalled: 1,
                failed: 1,
                waiting: 0,
                recovering: 0,
                completed: 0
            ),
            lanes: [
                lane(id: "lane-c", status: .blocked),
                lane(id: "lane-b", status: .stalled),
                lane(id: "lane-a", status: .failed),
                lane(id: "lane-d", status: .running)
            ]
        )

        let lanes = SupervisorLaneHealthPresentation.filteredLanes(
            from: snapshot,
            filter: .abnormal
        )

        #expect(lanes.map(\.laneID) == ["lane-a", "lane-b", "lane-c"])
    }

    @Test
    func rowPresentationBuildsTextsAndActions() {
        let now = Date(timeIntervalSince1970: 20)
        var runtimeState = LaneRuntimeState(
            laneID: "lane-7",
            taskId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            projectId: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            agentProfile: "coder",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "wait_grant"
        )
        runtimeState.heartbeatSeq = 3
        runtimeState.lastHeartbeatAtMs = 19_000
        runtimeState.oldestWaitMs = 12_000
        let customLane = SupervisorLaneHealthLaneState(state: runtimeState)

        let presentation = SupervisorLaneHealthPresentation.rowPresentation(
            lane: customLane,
            splitPlanText: "split-1",
            focusedLaneID: "lane-7",
            now: now
        )

        #expect(presentation.isFocused)
        #expect(presentation.title == "lane-7 · 阻塞")
        #expect(presentation.statusIconName == "pause.circle.fill")
        #expect(presentation.heartbeatSequenceText == "hb#3")
        #expect(presentation.heartbeatAgeText == "heartbeat=1s")
        #expect(presentation.waitText == "wait=8s")
        #expect(presentation.splitPlanText == "plan=split-1")
        #expect(presentation.reasonLine == "原因：等待授权（grant_pending） · 下一步：等待授权结果（wait_grant）")
        #expect(presentation.contractText == "合同： 授权处理 · blocker=grant_pending")
        #expect(presentation.nextSafeActionText == "安全下一步： 打开 Hub 授权面板 · 建议动作：等待授权结果")
        #expect(presentation.focusAction.label == "已定位")
        #expect(presentation.openAction?.label == "查看项目")
    }

    @Test
    func rowPresentationBuildsIncidentRecoveryContractForFailedLaneWithoutExplicitBlocker() {
        let now = Date(timeIntervalSince1970: 20)
        var runtimeState = LaneRuntimeState(
            laneID: "lane-9",
            taskId: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-FFFFFFFFFFFF")!,
            projectId: UUID(uuidString: "11111111-2222-3333-4444-666666666666")!,
            agentProfile: "coder",
            status: .failed,
            blockedReason: nil,
            nextActionRecommendation: "pause_lane"
        )
        runtimeState.heartbeatSeq = 4
        runtimeState.lastHeartbeatAtMs = 18_000
        let lane = SupervisorLaneHealthLaneState(state: runtimeState)

        let presentation = SupervisorLaneHealthPresentation.rowPresentation(
            lane: lane,
            splitPlanText: "split-9",
            focusedLaneID: nil,
            now: now
        )

        #expect(presentation.reasonLine == "原因：无显式阻塞原因（none） · 下一步：暂停当前泳道（pause_lane）")
        #expect(presentation.contractText == "合同： 故障恢复 · blocker=lane_failed")
        #expect(presentation.nextSafeActionText == "安全下一步： 先检查当前异常，再决定是否重规划 · 建议动作：暂停当前泳道")
    }

    @Test
    func summaryToneAndProjectUrlFollowStatusSemantics() {
        let tone = SupervisorLaneHealthPresentation.summaryTone(
            LaneHealthSummary(
                total: 2,
                running: 0,
                blocked: 0,
                stalled: 0,
                failed: 1,
                waiting: 1,
                recovering: 0,
                completed: 0
            )
        )

        #expect(tone == .danger)
        #expect(
            SupervisorLaneHealthPresentation.projectURL(projectID: nil)
                == XTDeepLinkURLBuilder.supervisorURL()
        )
        #expect(
            SupervisorLaneHealthPresentation.heartbeatAgeText(0, now: Date(timeIntervalSince1970: 5))
                == "heartbeat=unknown"
        )
    }

    private func lane(
        id: String,
        status: LaneHealthStatus
    ) -> SupervisorLaneHealthLaneState {
        SupervisorLaneHealthLaneState(state: LaneRuntimeState(
            laneID: id,
            taskId: UUID(),
            projectId: UUID(),
            agentProfile: "coder",
            status: status,
            blockedReason: status == .blocked ? .grantPending : nil,
            nextActionRecommendation: "continue"
        ))
    }
}
