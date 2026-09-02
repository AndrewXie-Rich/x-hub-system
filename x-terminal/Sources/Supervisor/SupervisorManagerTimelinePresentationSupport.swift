import Foundation

extension SupervisorManager {
    var chatTimelineMessages: [SupervisorMessage] {
        frontstageConversationMessages.filter { message in
            guard message.role != .system else { return false }
            let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("🫀 Supervisor Heartbeat")
        }
    }

    var latestHeartbeat: HeartbeatFeedEntry? {
        heartbeatHistory.first
    }

    var latestRuntimeActivity: RuntimeActivityEntry? {
        frontstageRuntimeActivityEntries.first
    }
}
