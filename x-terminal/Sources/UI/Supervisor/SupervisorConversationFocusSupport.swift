import Foundation

enum SupervisorConversationFocusSupport {
    static func shouldFocusOnAppear(
        latestWindowRequest: SupervisorConversationWindowOpenRequest?
    ) -> Bool {
        latestWindowRequest?.focusConversation ?? false
    }

    static func shouldFocusForWindowOpenRequest(
        _ request: SupervisorConversationWindowOpenRequest
    ) -> Bool {
        request.focusConversation
    }

    static func shouldFocusForExplicitRequest(
        lastHandledRequestID: Int,
        currentRequestID: Int
    ) -> Bool {
        currentRequestID > lastHandledRequestID
    }
}
