import Foundation

enum SupervisorProjectNotificationChannel: String, Codable, Sendable {
    case silentLog = "silent_log"
    case badgeOnly = "badge_only"
    case briefCard = "brief_card"
    case interruptNow = "interrupt_now"
}

enum SupervisorProjectNotificationDeliveryStatus: String, Codable, Sendable {
    case delivered
    case suppressedDuplicate = "suppressed_duplicate"
}

struct SupervisorProjectNotificationDecision: Equatable, Sendable {
    var channel: SupervisorProjectNotificationChannel
    var dedupeWindowSec: TimeInterval
    var shouldAddSystemMessage: Bool
    var shouldOpenConversationWindow: Bool
    var systemMessage: String?
    var recommendation: SupervisorRhythmRecommendation

    var shouldDedupe: Bool { dedupeWindowSec > 0 }
}

struct SupervisorProjectNotificationSnapshot: Equatable, Codable, Sendable {
    var updatedAt: Double
    var deliveredInterrupts: Int
    var deliveredBriefs: Int
    var deliveredBadges: Int
    var mutedLogs: Int
    var suppressedDuplicates: Int
    var lastDeliverySummary: String

    static let empty = SupervisorProjectNotificationSnapshot(
        updatedAt: 0,
        deliveredInterrupts: 0,
        deliveredBriefs: 0,
        deliveredBadges: 0,
        mutedLogs: 0,
        suppressedDuplicates: 0,
        lastDeliverySummary: ""
    )

    var hasActivity: Bool {
        deliveredInterrupts > 0 ||
        deliveredBriefs > 0 ||
        deliveredBadges > 0 ||
        mutedLogs > 0 ||
        suppressedDuplicates > 0
    }

    var statusLine: String {
        "notif interrupt=\(deliveredInterrupts) · brief=\(deliveredBriefs) · badge=\(deliveredBadges) · muted=\(mutedLogs) · deduped=\(suppressedDuplicates)"
    }
}

enum SupervisorProjectNotificationPolicy {
    static func decide(for event: SupervisorProjectActionEvent) -> SupervisorProjectNotificationDecision {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)

        switch event.severity {
        case .authorizationRequired:
            return SupervisorProjectNotificationDecision(
                channel: .interruptNow,
                dedupeWindowSec: 180,
                shouldAddSystemMessage: true,
                shouldOpenConversationWindow: true,
                systemMessage: interruptSystemMessage(for: recommendation),
                recommendation: recommendation
            )
        case .interruptNow:
            return SupervisorProjectNotificationDecision(
                channel: .interruptNow,
                dedupeWindowSec: 120,
                shouldAddSystemMessage: true,
                shouldOpenConversationWindow: true,
                systemMessage: interruptSystemMessage(for: recommendation),
                recommendation: recommendation
            )
        case .briefCard:
            return SupervisorProjectNotificationDecision(
                channel: recommendation.isSubstantiveChange ? .briefCard : .silentLog,
                dedupeWindowSec: 90,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        case .badgeOnly:
            return SupervisorProjectNotificationDecision(
                channel: .badgeOnly,
                dedupeWindowSec: 60,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        case .silentLog:
            return SupervisorProjectNotificationDecision(
                channel: .silentLog,
                dedupeWindowSec: 45,
                shouldAddSystemMessage: false,
                shouldOpenConversationWindow: false,
                systemMessage: nil,
                recommendation: recommendation
            )
        }
    }

    static func dedupeFingerprint(
        for event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel
    ) -> String {
        let recommendation = SupervisorRhythmRecommendationEngine.recommendation(for: event)
        return [
            event.projectId,
            channel.rawValue,
            recommendation.dedupeKey,
        ].joined(separator: "|")
    }

    static func deliverySummary(
        event: SupervisorProjectActionEvent,
        channel: SupervisorProjectNotificationChannel,
        status: SupervisorProjectNotificationDeliveryStatus
    ) -> String {
        "\(channel.rawValue):\(status.rawValue):\(event.projectName)"
    }

    private static func interruptSystemMessage(
        for recommendation: SupervisorRhythmRecommendation
    ) -> String {
        let evidence = recommendation.evidenceRefs.first ?? "supervisor_project_action_event"
        return [
            "[Supervisor Update]",
            "变化：\(recommendation.whatChanged)",
            "原因：\(recommendation.whyItMatters)",
            "当前阻塞：\(recommendation.waitingOn)",
            "下一步：\(recommendation.recommendedNextAction)",
            "预计更新时间：\(recommendation.nextUpdateEta)",
            "证据：\(evidence)",
        ].joined(separator: "\n")
    }
}
