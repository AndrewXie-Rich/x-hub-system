import Foundation

@MainActor
final class SupervisorConversationWindowBridge {
    static let shared = SupervisorConversationWindowBridge()

    private let notificationCenter: NotificationCenter
    private var lastOpenAt: Date = .distantPast
    private let dedupeInterval: TimeInterval

    init(
        notificationCenter: NotificationCenter = .default,
        dedupeInterval: TimeInterval = 0.8
    ) {
        self.notificationCenter = notificationCenter
        self.dedupeInterval = dedupeInterval
    }

    func requestOpen(reason: String) {
        let now = Date()
        guard now.timeIntervalSince(lastOpenAt) >= dedupeInterval else {
            return
        }
        lastOpenAt = now
        notificationCenter.post(
            name: .xterminalOpenSupervisorWindow,
            object: nil,
            userInfo: ["reason": reason]
        )
    }
}
