import Foundation

enum SupervisorPortfolioActionEventDestination: Equatable {
    case projectDetail(projectId: String)
    case openURL(String)
}

struct SupervisorPortfolioSystemNotificationSignal: Equatable {
    var id: String
    var sourceLabel: String
    var scopeLine: String?
    var title: String
    var summaryLine: String
    var whyLine: String
    var nextStepLine: String
    var detailLines: [String]
    var detailActionLabel: String?
    var destination: SupervisorPortfolioActionEventDestination?
    var tone: SupervisorHeaderControlTone
    var defaultUnread: Bool
}

struct SupervisorPortfolioActionEventPresentation: Equatable, Identifiable {
    var id: String
    var sourceLabel: String
    var scopeLine: String?
    var title: String
    var summaryLine: String
    var nextLine: String
    var whyLine: String
    var detailLines: [String]
    var detailActionLabel: String?
    var destination: SupervisorPortfolioActionEventDestination?
    var defaultUnread: Bool
    var tone: SupervisorHeaderControlTone
}

enum SupervisorPortfolioActionEventPresentationMapper {
    static func map(
        _ event: SupervisorProjectActionEvent
    ) -> SupervisorPortfolioActionEventPresentation {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        return SupervisorPortfolioActionEventPresentation(
            id: event.id,
            sourceLabel: eventTypeLabel(event.eventType),
            scopeLine: event.projectName,
            title: event.actionTitle,
            summaryLine: recommendation.whatChanged,
            nextLine: "下一步：\(recommendation.recommendedNextAction)",
            whyLine: "为什么重要：\(recommendation.whyItMatters)",
            detailLines: detailLines(
                projectName: event.projectName,
                sourceLabel: eventTypeLabel(event.eventType),
                severityText: severityLabel(event.severity),
                summaryLine: recommendation.whatChanged,
                whyLine: recommendation.whyItMatters,
                nextStepLine: recommendation.recommendedNextAction
            ),
            detailActionLabel: "打开项目",
            destination: .projectDetail(projectId: event.projectId),
            defaultUnread: event.severity != .silentLog,
            tone: tone(event.severity)
        )
    }

    static func map(
        _ signal: SupervisorPortfolioSystemNotificationSignal
    ) -> SupervisorPortfolioActionEventPresentation {
        SupervisorPortfolioActionEventPresentation(
            id: signal.id,
            sourceLabel: signal.sourceLabel,
            scopeLine: signal.scopeLine,
            title: signal.title,
            summaryLine: signal.summaryLine,
            nextLine: "下一步：\(signal.nextStepLine)",
            whyLine: "为什么重要：\(signal.whyLine)",
            detailLines: signal.detailLines,
            detailActionLabel: signal.detailActionLabel,
            destination: signal.destination,
            defaultUnread: signal.defaultUnread,
            tone: signal.tone
        )
    }

    static func tone(
        _ severity: SupervisorProjectActionSeverity
    ) -> SupervisorHeaderControlTone {
        switch severity {
        case .silentLog:
            return .neutral
        case .badgeOnly:
            return .accent
        case .briefCard:
            return .warning
        case .interruptNow, .authorizationRequired:
            return .danger
        }
    }

    static func eventTypeLabel(
        _ eventType: SupervisorProjectActionEventType
    ) -> String {
        switch eventType {
        case .created:
            return "新建提醒"
        case .progressed:
            return "进展提醒"
        case .blocked:
            return "阻塞提醒"
        case .awaitingAuthorization:
            return "待授权提醒"
        case .completed:
            return "完成提醒"
        case .archived:
            return "归档提醒"
        }
    }

    static func severityLabel(
        _ severity: SupervisorProjectActionSeverity
    ) -> String {
        switch severity {
        case .silentLog:
            return "静默观察"
        case .badgeOnly:
            return "轻提醒"
        case .briefCard:
            return "需要跟进"
        case .interruptNow:
            return "立即关注"
        case .authorizationRequired:
            return "等待授权"
        }
    }

    static func detailLines(
        projectName: String,
        sourceLabel: String,
        severityText: String,
        summaryLine: String,
        whyLine: String,
        nextStepLine: String
    ) -> [String] {
        [
            "项目：\(projectName)",
            "提醒类型：\(sourceLabel)",
            "提醒强度：\(severityText)",
            "发生了什么：\(summaryLine)",
            "为什么重要：\(whyLine)",
            "建议动作：\(nextStepLine)"
        ]
    }
}
