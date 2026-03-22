import Foundation

struct SupervisorRecentSkillActivityBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var summaryLine: String
    var items: [SupervisorManager.SupervisorRecentSkillActivity]
    var emptyStateText: String?
}

enum SupervisorRecentSkillActivityBoardPresentationMapper {
    static func map(
        feed: SupervisorSkillActivityFeedPresentation
    ) -> SupervisorRecentSkillActivityBoardPresentation {
        SupervisorRecentSkillActivityBoardPresentation(
            iconName: feed.isEmpty ? "sparkles.rectangle.stack" : "sparkles.rectangle.stack.fill",
            iconTone: feed.isEmpty ? .neutral : .accent,
            title: "最近技能活动：\(feed.items.count)",
            summaryLine: feed.summaryLine,
            items: feed.items,
            emptyStateText: feed.isEmpty
                ? "当前还没有最近技能调用记录。出现本地审批、Hub 授权、失败重试或运行中的技能调用后，这里会先按可处理优先级排序，再提供完整记录与动作入口。"
                : nil
        )
    }
}
