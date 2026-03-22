import Foundation

struct SupervisorPortfolioActionEventPresentation: Equatable, Identifiable {
    var id: String
    var title: String
    var summaryLine: String
    var nextLine: String
    var whyLine: String
    var tone: SupervisorHeaderControlTone
}

enum SupervisorPortfolioActionEventPresentationMapper {
    static func map(
        _ event: SupervisorProjectActionEvent
    ) -> SupervisorPortfolioActionEventPresentation {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        return SupervisorPortfolioActionEventPresentation(
            id: event.id,
            title: event.actionTitle,
            summaryLine: recommendation.whatChanged,
            nextLine: "下一步：\(recommendation.recommendedNextAction)",
            whyLine: "为什么重要：\(recommendation.whyItMatters)",
            tone: tone(event.severity)
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
}
