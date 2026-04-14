import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTDeepLinkActionExecutorTests {

    @Test
    func projectSupervisorApprovalPlanExecutesOpenAndFocusTogether() throws {
        let appModel = AppModel()
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkProjectRoute(
                projectId: "project-epsilon",
                pane: .terminal,
                openTarget: .supervisor,
                focusTarget: .approval,
                requestId: "req-21",
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil,
                resumeRequested: false
            )
        )
        var openedIntent: XTSupervisorWindowOpenIntent?

        XTDeepLinkActionExecutor.execute(
            plan,
            appModel: appModel
        ) { intent in
            openedIntent = intent
        }

        #expect(appModel.selectedProjectId == "project-epsilon")
        #expect(appModel.pane(for: "project-epsilon") == .terminal)
        #expect(
            openedIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_project_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
        let focusRequest = try #require(appModel.supervisorFocusRequest)
        #expect(focusRequest.projectId == "project-epsilon")
        #expect(focusRequest.subject == .approval(requestId: "req-21"))
    }

    @Test
    func supervisorGrantPlanExecutesPrefillOpenAndGrantFocusTogether() throws {
        let fixture = ToolExecutorProjectFixture(name: "deep-link-action-executor-grant")
        defer { fixture.cleanup() }

        var registry = AXProjectRegistry.empty()
        let upsert = AXProjectRegistryStore.upsertProject(registry, root: fixture.root)
        registry = upsert.0
        let projectId = upsert.1.projectId
        let appModel = AppModel()
        appModel.registry = registry

        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkSupervisorRoute(
                projectId: projectId,
                focusTarget: .grant,
                requestId: nil,
                grantRequestId: "grant-1",
                grantCapability: "ai.generate.paid",
                grantReason: "Need remote model access"
            )
        )
        var openedIntent: XTSupervisorWindowOpenIntent?

        XTDeepLinkActionExecutor.execute(
            plan,
            appModel: appModel
        ) { intent in
            openedIntent = intent
        }

        #expect(appModel.selectedProjectId == projectId)
        #expect(appModel.pane(for: projectId) == .chat)
        #expect(
            openedIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
        let focusRequest = try #require(appModel.supervisorFocusRequest)
        #expect(focusRequest.projectId == projectId)
        #expect(
            focusRequest.subject == .grant(
                grantRequestId: "grant-1",
                capability: "ai.generate.paid"
            )
        )

        let session = try #require(appModel.sessionForProjectId(projectId))
        #expect(session.draft.contains("授权单号：grant-1"))
        #expect(session.draft.contains("授权类型：付费模型调用"))
        #expect(session.draft.contains("Need remote model access"))
    }

    @Test
    func supervisorProjectCreationBoardPlanRequestsBoardFocus() throws {
        let appModel = AppModel()
        let plan = XTDeepLinkActionPlanner.plan(
            for: XTDeepLinkSupervisorRoute(
                projectId: nil,
                focusTarget: .projectCreationBoard,
                requestId: nil,
                grantRequestId: nil,
                grantCapability: nil,
                grantReason: nil
            )
        )
        var openedIntent: XTSupervisorWindowOpenIntent?

        XTDeepLinkActionExecutor.execute(
            plan,
            appModel: appModel
        ) { intent in
            openedIntent = intent
        }

        #expect(
            openedIntent == XTSupervisorWindowOpenIntent(
                reason: "deep_link_supervisor",
                focusConversation: false,
                startConversation: false
            )
        )
        let focusRequest = try #require(appModel.supervisorFocusRequest)
        #expect(focusRequest.projectId == nil)
        #expect(
            focusRequest.subject == .board(
                anchorID: SupervisorFocusPresentation.projectCreationBoardAnchorID
            )
        )
    }
}
