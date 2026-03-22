import Foundation
import Testing
@testable import XTerminal

struct XTSupervisorWindowPresentationPolicyTests {

    @Test
    func focusRequestStillOpensWhenWindowIsAlreadyVisible() {
        let decision = XTSupervisorWindowPresentationPolicy.decision(
            for: SupervisorConversationWindowOpenRequest(
                reason: "status_bar",
                focusConversation: true
            ),
            isWindowVisible: true
        )

        #expect(decision == .init(shouldOpenWindow: true))
    }

    @Test
    func focuslessRequestOpensWhenWindowIsHidden() {
        let decision = XTSupervisorWindowPresentationPolicy.decision(
            for: SupervisorConversationWindowOpenRequest(
                reason: "deep_link_supervisor_focus",
                focusConversation: false
            ),
            isWindowVisible: false
        )

        #expect(decision == .init(shouldOpenWindow: true))
    }

    @Test
    func focuslessRequestDoesNotReopenVisibleWindow() {
        let decision = XTSupervisorWindowPresentationPolicy.decision(
            for: SupervisorConversationWindowOpenRequest(
                reason: "deep_link_supervisor_focus",
                focusConversation: false
            ),
            isWindowVisible: true
        )

        #expect(decision == .init(shouldOpenWindow: false))
    }
}
