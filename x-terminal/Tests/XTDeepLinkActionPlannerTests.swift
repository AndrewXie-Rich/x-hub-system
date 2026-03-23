import Foundation
import Testing
@testable import XTerminal

struct XTDeepLinkActionPlannerTests {

    @Test
    func supervisorGrantRouteBuildsSupervisorWindowPlanWithPrefillAndFocus() {
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkSupervisorRoute(
                projectId: "project-alpha",
                focusTarget: .grant,
                requestId: nil,
                grantRequestId: "grant-1",
                grantCapability: "ai.generate.paid",
                grantReason: "Need remote model access"
            )
        )

        #expect(plan.selectProjectId == "project-alpha")
        #expect(plan.projectPaneIntent == nil)
        #expect(
            plan.openSupervisorIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
        #expect(
            plan.prefillGrantContext == XTDeepLinkGrantPrefillIntent(
                projectId: "project-alpha",
                grantRequestId: "grant-1",
                capability: "ai.generate.paid",
                reason: "Need remote model access"
            )
        )
        #expect(
            plan.focusIntent == .supervisorGrant(
                projectId: "project-alpha",
                grantRequestId: "grant-1",
                capability: "ai.generate.paid"
            )
        )
    }

    @Test
    func projectApprovalRoutePreservesRequestedPaneAndOpensSupervisorWithoutConversation() {
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkProjectRoute(
                projectId: "project-beta",
                pane: .terminal,
                openTarget: nil,
                focusTarget: .approval,
                requestId: "req-5",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(plan.selectProjectId == "project-beta")
        #expect(
            plan.projectPaneIntent == XTDeepLinkProjectPaneIntent(
                projectId: "project-beta",
                pane: .terminal
            )
        )
        #expect(
            plan.openSupervisorIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor_focus",
                focusConversation: false,
                startConversation: false
            )
        )
        #expect(plan.prefillGrantContext == nil)
        #expect(
            plan.focusIntent == .supervisorApproval(
                projectId: "project-beta",
                requestId: "req-5"
            )
        )
    }

    @Test
    func resumeRouteDiagnosePlanForcesChatAndSelectsProjectWithoutSupervisorWindow() {
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkProjectRoute(
                projectId: "project-gamma",
                pane: .terminal,
                openTarget: nil,
                focusTarget: .routeDiagnose,
                requestId: nil,
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: true
            )
        )

        #expect(plan.selectProjectId == "project-gamma")
        #expect(
            plan.projectPaneIntent == XTDeepLinkProjectPaneIntent(
                projectId: "project-gamma",
                pane: .chat
            )
        )
        #expect(plan.openSupervisorIntent == nil)
        #expect(plan.prefillGrantContext == nil)
        #expect(plan.focusIntent == .projectRouteDiagnose(projectId: "project-gamma"))
    }

    @Test
    func toolApprovalPlanKeepsProjectSurfaceAndSkipsSupervisorWindow() {
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkProjectRoute(
                projectId: "project-delta",
                pane: .terminal,
                openTarget: nil,
                focusTarget: .toolApproval,
                requestId: "tool-9",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(plan.selectProjectId == "project-delta")
        #expect(
            plan.projectPaneIntent == XTDeepLinkProjectPaneIntent(
                projectId: "project-delta",
                pane: .chat
            )
        )
        #expect(plan.openSupervisorIntent == nil)
        #expect(plan.prefillGrantContext == nil)
        #expect(
            plan.focusIntent == .projectToolApproval(
                projectId: "project-delta",
                requestId: "tool-9"
            )
        )
    }

    @Test
    func explicitSupervisorOpenWithApprovalFocusDoesNotStartConversation() {
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkProjectRoute(
                projectId: "project-epsilon",
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: .approval,
                requestId: "req-21",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )

        #expect(plan.selectProjectId == "project-epsilon")
        #expect(
            plan.projectPaneIntent == XTDeepLinkProjectPaneIntent(
                projectId: "project-epsilon",
                pane: .chat
            )
        )
        #expect(
            plan.openSupervisorIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
        #expect(plan.prefillGrantContext == nil)
        #expect(
            plan.focusIntent == .supervisorApproval(
                projectId: "project-epsilon",
                requestId: "req-21"
            )
        )
    }
}
