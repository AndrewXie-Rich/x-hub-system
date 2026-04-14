import Foundation
import Testing
@testable import XTerminal

struct XTSupervisorWindowOpenPolicyTests {

    @Test
    func supervisorRouteWithoutFocusStartsConversationAndFocusesInput() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkSupervisorRoute(
                projectId: "project-alpha",
                focusTarget: nil,
                requestId: nil,
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: true,
                startConversation: true
            )
        )
    }

    @Test
    func supervisorRouteWithGrantFocusOpensWithoutStartingConversation() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkSupervisorRoute(
                projectId: "project-alpha",
                focusTarget: .grant,
                requestId: nil,
                grantRequestId: "grant-1",
                grantCapability: "ai.generate.paid",
                grantReason: nil
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
    }

    @Test
    func projectRouteWithExplicitSupervisorOpenUsesConversationFocusWhenNoSecondaryFocus() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkProjectRoute(
                projectId: "project-beta",
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: nil,
                requestId: nil,
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor",
                focusConversation: true,
                startConversation: true
            )
        )
    }

    @Test
    func projectRouteWithGrantFocusButNoExplicitOpenStillOpensSupervisorWithoutConversationFocus() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkProjectRoute(
                projectId: "project-gamma",
                pane: .chat,
                openTarget: nil,
                focusTarget: .grant,
                requestId: nil,
                grantRequestId: "grant-7",
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor_focus",
                focusConversation: false,
                startConversation: false
            )
        )
    }

    @Test
    func projectRouteWithToolApprovalFocusDoesNotOpenSupervisorWindow() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkProjectRoute(
                projectId: "project-theta",
                pane: .chat,
                openTarget: nil,
                focusTarget: .toolApproval,
                requestId: "tool-9",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(intent == nil)
    }

    @Test
    func projectRouteWithCandidateReviewFocusOpensSupervisorWindow() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkProjectRoute(
                projectId: "project-review",
                pane: .chat,
                openTarget: nil,
                focusTarget: .candidateReview,
                requestId: "req-review-1",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor_focus",
                focusConversation: false,
                startConversation: false
            )
        )
    }

    @Test
    func supervisorRouteWithProjectCreationBoardFocusOpensWithoutStartingConversation() {
        let intent = XTSupervisorWindowOpenPolicy.intent(
            for: XTDeepLinkSupervisorRoute(
                projectId: nil,
                focusTarget: .projectCreationBoard,
                requestId: nil,
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil
            )
        )

        #expect(
            intent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
    }
}
