import Foundation

struct XTSupervisorWindowOpenIntent: Equatable {
    var reason: String
    var focusConversation: Bool
    var startConversation: Bool
}

enum XTSupervisorWindowOpenPolicy {
    static func intent(for route: XTDeepLinkSupervisorRoute) -> XTSupervisorWindowOpenIntent {
        let shouldFocusConversation = route.focusTarget == nil
        return XTSupervisorWindowOpenIntent(
            reason: "deep_link_supervisor",
            focusConversation: shouldFocusConversation,
            startConversation: shouldFocusConversation
        )
    }

    static func intent(for route: XTDeepLinkProjectRoute) -> XTSupervisorWindowOpenIntent? {
        switch route.openTarget {
        case .supervisor:
            let shouldFocusConversation = route.focusTarget == nil
            return XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor",
                focusConversation: shouldFocusConversation,
                startConversation: shouldFocusConversation
            )
        case .supervisorSettings:
            return nil
        case nil:
            guard requiresSupervisorWindow(for: route.focusTarget) else { return nil }
            return XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor_focus",
                focusConversation: false,
                startConversation: false
            )
        }
    }

    static func requiresSupervisorWindow(for focusTarget: XTDeepLinkFocusTarget?) -> Bool {
        switch focusTarget {
        case .grant, .approval, .skillRecord:
            return true
        case .toolApproval, .routeDiagnose, nil:
            return false
        }
    }
}
