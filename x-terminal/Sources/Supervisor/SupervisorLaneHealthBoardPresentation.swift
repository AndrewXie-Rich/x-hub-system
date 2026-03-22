import Foundation

struct SupervisorLaneHealthBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorLaneHealthTone
    var title: String
    var statusLine: String
    var summaryLine: String
    var rows: [SupervisorLaneHealthRowPresentation]
    var emptyStateText: String?
}

enum SupervisorLaneHealthBoardPresentationMapper {
    static func map(
        snapshot: SupervisorLaneHealthSnapshot?,
        statusLine: String,
        filter: SupervisorLaneHealthFilter,
        focusedLaneID: String?,
        splitPlanTextByLaneID: [String: String],
        now: Date = Date()
    ) -> SupervisorLaneHealthBoardPresentation {
        let summary = snapshot?.summary ?? .empty
        let lanes = SupervisorLaneHealthPresentation.filteredLanes(
            from: snapshot,
            filter: filter
        )

        return SupervisorLaneHealthBoardPresentation(
            iconName: "heart.text.square.fill",
            iconTone: SupervisorLaneHealthPresentation.summaryTone(summary),
            title: "泳道健康态",
            statusLine: statusLine,
            summaryLine: summaryLine(summary),
            rows: lanes.map { lane in
                SupervisorLaneHealthPresentation.rowPresentation(
                    lane: lane,
                    splitPlanText: splitPlanTextByLaneID[lane.laneID] ?? "n/a",
                    focusedLaneID: focusedLaneID,
                    now: now
                )
            },
            emptyStateText: emptyStateText(
                snapshot: snapshot,
                lanes: lanes
            )
        )
    }

    static func summaryLine(_ summary: LaneHealthSummary) -> String {
        "running=\(summary.running) · blocked=\(summary.blocked) · stalled=\(summary.stalled) · failed=\(summary.failed) · waiting=\(summary.waiting) · recovering=\(summary.recovering)"
    }

    static func emptyStateText(
        snapshot: SupervisorLaneHealthSnapshot?,
        lanes: [SupervisorLaneHealthLaneState]
    ) -> String? {
        guard lanes.isEmpty else { return nil }
        if snapshot == nil {
            return "暂无 lane 运行快照。启动多泳道后会自动展示 running/blocked/stalled/failed。"
        }
        return "当前过滤条件下无匹配 lane。"
    }
}
