import Foundation
import Testing
@testable import XTerminal

struct SupervisorLaneHealthBoardPresentationTests {

    @Test
    func mapBuildsEmptySnapshotState() {
        let presentation = SupervisorLaneHealthBoardPresentationMapper.map(
            snapshot: nil,
            statusLine: "lane health: idle",
            filter: .abnormal,
            focusedLaneID: nil,
            splitPlanTextByLaneID: [:],
            now: Date(timeIntervalSince1970: 20)
        )

        #expect(presentation.iconName == "heart.text.square.fill")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "泳道健康态")
        #expect(presentation.statusLine == "lane health: idle")
        #expect(presentation.summaryLine == "running=0 · blocked=0 · stalled=0 · failed=0 · waiting=0 · recovering=0")
        #expect(presentation.rows.isEmpty)
        #expect(presentation.emptyStateText == "暂无 lane 运行快照。启动多泳道后会自动展示 running/blocked/stalled/failed。")
    }

    @Test
    func mapBuildsFilteredRowsAndSummary() {
        let snapshot = SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_000,
            summary: LaneHealthSummary(
                total: 3,
                running: 1,
                blocked: 1,
                stalled: 0,
                failed: 1,
                waiting: 0,
                recovering: 0,
                completed: 0
            ),
            lanes: [
                lane(id: "lane-failed", status: .failed, heartbeatSeq: 9),
                lane(id: "lane-running", status: .running, heartbeatSeq: 8),
                lane(id: "lane-blocked", status: .blocked, heartbeatSeq: 7)
            ]
        )

        let presentation = SupervisorLaneHealthBoardPresentationMapper.map(
            snapshot: snapshot,
            statusLine: "lane health: warning",
            filter: .abnormal,
            focusedLaneID: "lane-blocked",
            splitPlanTextByLaneID: [
                "lane-failed": "split-a",
                "lane-blocked": "split-b"
            ],
            now: Date(timeIntervalSince1970: 20)
        )

        #expect(presentation.iconTone == .danger)
        #expect(presentation.summaryLine == "running=1 · blocked=1 · stalled=0 · failed=1 · waiting=0 · recovering=0")
        #expect(presentation.emptyStateText == nil)
        #expect(presentation.rows.map(\.laneID) == ["lane-failed", "lane-blocked"])
        #expect(presentation.rows.map(\.splitPlanText) == ["plan=split-a", "plan=split-b"])
        #expect(presentation.rows.last?.isFocused == true)
    }

    @Test
    func mapBuildsNoMatchesStateWhenFilterEliminatesRows() {
        let snapshot = SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_000,
            summary: LaneHealthSummary(
                total: 1,
                running: 1,
                blocked: 0,
                stalled: 0,
                failed: 0,
                waiting: 0,
                recovering: 0,
                completed: 0
            ),
            lanes: [
                lane(id: "lane-running", status: .running, heartbeatSeq: 4)
            ]
        )

        let presentation = SupervisorLaneHealthBoardPresentationMapper.map(
            snapshot: snapshot,
            statusLine: "lane health: ok",
            filter: .failed,
            focusedLaneID: nil,
            splitPlanTextByLaneID: [:]
        )

        #expect(presentation.iconTone == .success)
        #expect(presentation.rows.isEmpty)
        #expect(presentation.emptyStateText == "当前过滤条件下无匹配 lane。")
    }

    private func lane(
        id: String,
        status: LaneHealthStatus,
        heartbeatSeq: Int
    ) -> SupervisorLaneHealthLaneState {
        var state = LaneRuntimeState(
            laneID: id,
            taskId: UUID(),
            projectId: UUID(),
            agentProfile: "coder",
            status: status,
            blockedReason: status == .blocked ? .grantPending : nil,
            nextActionRecommendation: "continue"
        )
        state.heartbeatSeq = heartbeatSeq
        state.lastHeartbeatAtMs = 19_000
        return SupervisorLaneHealthLaneState(state: state)
    }
}
