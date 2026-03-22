import Foundation
import Testing
@testable import XTerminal

struct SupervisorConversationFocusSupportTests {

    @Test
    func onAppearDoesNotFocusWithoutAnExplicitWindowRequest() {
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusOnAppear(
                latestWindowRequest: nil
            )
        )
    }

    @Test
    func onAppearRespectsLatestWindowRequestFocusPreference() {
        #expect(
            SupervisorConversationFocusSupport.shouldFocusOnAppear(
                latestWindowRequest: SupervisorConversationWindowOpenRequest(
                    reason: "deep_link_supervisor"
                )
            )
        )
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusOnAppear(
                latestWindowRequest: SupervisorConversationWindowOpenRequest(
                    reason: "deep_link_supervisor_focus_only",
                    focusConversation: false
                )
            )
        )
    }

    @Test
    func notificationFocusOnlyWhenWindowRequestAllowsIt() {
        #expect(
            SupervisorConversationFocusSupport.shouldFocusForWindowOpenRequest(
                SupervisorConversationWindowOpenRequest(reason: "status_bar")
            )
        )
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusForWindowOpenRequest(
                SupervisorConversationWindowOpenRequest(
                    reason: "pending_hub_grant:demo",
                    focusConversation: false
                )
            )
        )
    }

    @Test
    func explicitFocusRequestsOnlyTriggerForMonotonicIncrements() {
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusForExplicitRequest(
                lastHandledRequestID: 0,
                currentRequestID: 0
            )
        )
        #expect(
            SupervisorConversationFocusSupport.shouldFocusForExplicitRequest(
                lastHandledRequestID: 0,
                currentRequestID: 1
            )
        )
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusForExplicitRequest(
                lastHandledRequestID: 3,
                currentRequestID: 3
            )
        )
        #expect(
            !SupervisorConversationFocusSupport.shouldFocusForExplicitRequest(
                lastHandledRequestID: 3,
                currentRequestID: 2
            )
        )
    }
}
