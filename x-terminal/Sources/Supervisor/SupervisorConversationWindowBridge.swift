import Combine
import Foundation

struct SupervisorConversationWindowOpenRequest: Equatable {
    static let reasonUserInfoKey = "reason"
    static let focusConversationUserInfoKey = "focusConversation"
    static let sessionWindowStateUserInfoKey = "window_state"
    static let sessionRemainingTTLSecondsUserInfoKey = "remaining_ttl_sec"
    static let sessionReasonCodeUserInfoKey = "reason_code"
    static let sessionEventUserInfoKey = "session_event"

    let reason: String
    let focusConversation: Bool

    init(
        reason: String,
        focusConversation: Bool = true
    ) {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        self.reason = trimmedReason.isEmpty ? "unknown" : trimmedReason
        self.focusConversation = focusConversation
    }

    init(notification: Notification) {
        let reason = notification.userInfo?[Self.reasonUserInfoKey] as? String ?? ""
        let focusConversation = notification.userInfo?[Self.focusConversationUserInfoKey] as? Bool ?? true
        self.init(
            reason: reason,
            focusConversation: focusConversation
        )
    }

    var userInfo: [AnyHashable: Any] {
        [
            Self.reasonUserInfoKey: reason,
            Self.focusConversationUserInfoKey: focusConversation
        ]
    }
}

enum SupervisorConversationWindowOpenDeduplicationPolicy {
    static func shouldPost(
        request: SupervisorConversationWindowOpenRequest,
        lastRequest: SupervisorConversationWindowOpenRequest?,
        lastOpenAt: Date,
        now: Date,
        dedupeInterval: TimeInterval,
        isWindowVisible: Bool
    ) -> Bool {
        guard let lastRequest else { return true }
        guard request == lastRequest else { return true }
        guard now.timeIntervalSince(lastOpenAt) < dedupeInterval else { return true }
        return !isWindowVisible
    }
}

@MainActor
final class SupervisorConversationWindowBridge {
    static let shared = SupervisorConversationWindowBridge()

    private let notificationCenter: NotificationCenter
    private let windowVisibleProvider: @MainActor () -> Bool
    private let conversationSessionController: SupervisorConversationSessionController
    private var lastOpenAt: Date = .distantPast
    private var lastOpenRequest: SupervisorConversationWindowOpenRequest?
    private let dedupeInterval: TimeInterval
    private var cancellables: Set<AnyCancellable> = []
    private(set) var latestRequest: SupervisorConversationWindowOpenRequest?
    private(set) var latestSessionOutwardState: SupervisorConversationSessionOutwardState
    private(set) var latestSessionEvent: SupervisorConversationSessionEvent?

    init(
        notificationCenter: NotificationCenter = .default,
        dedupeInterval: TimeInterval = 0.8,
        conversationSessionController: SupervisorConversationSessionController? = nil,
        windowVisibleProvider: (@MainActor () -> Bool)? = nil
    ) {
        self.notificationCenter = notificationCenter
        self.dedupeInterval = dedupeInterval
        let resolvedConversationSessionController = conversationSessionController ?? SupervisorConversationSessionController.shared
        self.conversationSessionController = resolvedConversationSessionController
        self.latestSessionOutwardState = resolvedConversationSessionController.snapshot.outwardState
        self.latestSessionEvent = resolvedConversationSessionController.latestEvent
        self.windowVisibleProvider = windowVisibleProvider ?? Self.defaultWindowVisibleProvider
        bindConversationSession()
    }

    func requestOpen(
        reason: String,
        focusConversation: Bool = true
    ) {
        requestOpen(
            SupervisorConversationWindowOpenRequest(
                reason: reason,
                focusConversation: focusConversation
            )
        )
    }

    func requestOpen(_ request: SupervisorConversationWindowOpenRequest) {
        let now = Date()
        let shouldPost = SupervisorConversationWindowOpenDeduplicationPolicy.shouldPost(
            request: request,
            lastRequest: lastOpenRequest,
            lastOpenAt: lastOpenAt,
            now: now,
            dedupeInterval: dedupeInterval,
            isWindowVisible: windowVisibleProvider()
        )
        guard shouldPost else {
            return
        }
        lastOpenAt = now
        lastOpenRequest = request
        latestRequest = request
        var userInfo = request.userInfo
        userInfo[SupervisorConversationWindowOpenRequest.sessionWindowStateUserInfoKey] = latestSessionOutwardState.windowState.rawValue
        userInfo[SupervisorConversationWindowOpenRequest.sessionRemainingTTLSecondsUserInfoKey] = latestSessionOutwardState.remainingTTLSeconds
        userInfo[SupervisorConversationWindowOpenRequest.sessionReasonCodeUserInfoKey] = latestSessionOutwardState.reasonCode
        if let latestSessionEvent {
            userInfo[SupervisorConversationWindowOpenRequest.sessionEventUserInfoKey] = latestSessionEvent.event.rawValue
        }
        notificationCenter.post(
            name: .xterminalOpenSupervisorWindow,
            object: nil,
            userInfo: userInfo
        )
    }

    private static func defaultWindowVisibleProvider() -> Bool {
        XTSupervisorWindowVisibilityRegistry.shared.isWindowVisible
    }

    private func bindConversationSession() {
        conversationSessionController.$snapshot
            .sink { [weak self] snapshot in
                self?.latestSessionOutwardState = snapshot.outwardState
            }
            .store(in: &cancellables)

        conversationSessionController.$latestEvent
            .sink { [weak self] event in
                self?.latestSessionEvent = event
            }
            .store(in: &cancellables)
    }
}
