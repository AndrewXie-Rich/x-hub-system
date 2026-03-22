import Foundation

struct SupervisorInfrastructureFeedBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var summaryLine: String
    var items: [SupervisorInfrastructureFeedPresentation.Item]
    var emptyStateText: String?
}

enum SupervisorInfrastructureFeedBoardPresentationMapper {
    static func map(
        feed: SupervisorInfrastructureFeedPresentation
    ) -> SupervisorInfrastructureFeedBoardPresentation {
        SupervisorInfrastructureFeedBoardPresentation(
            iconName: feed.isEmpty ? "server.rack" : "server.rack.fill",
            iconTone: feed.isEmpty ? .neutral : .accent,
            title: "基础设施动态",
            summaryLine: feed.summaryLine,
            items: feed.items,
            emptyStateText: feed.isEmpty
                ? "当前没有需要额外关注的基础设施事件。官方 skills channel、XT native builtin skills、待处理授权和基础设施级自动跟进会在这里聚合展示。"
                : nil
        )
    }
}
