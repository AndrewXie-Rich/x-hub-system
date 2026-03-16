import Foundation
import Testing
@testable import XTerminal

struct XTDeepLinkParserTests {
    @Test
    func parsesResumeHostWithExplicitProjectID() throws {
        let url = try #require(URL(string: "xterminal://resume?project_id=project-beta"))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(route == .resume(projectId: "project-beta"))
    }

    @Test
    func parsesProjectPathRouteAndResumeAction() throws {
        let url = try #require(
            URL(string: "x-terminal://project/project-alpha?action=resume&open=supervisor&grant_request_id=grant-1")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-alpha",
                    pane: nil,
                    openTarget: .supervisor,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-1",
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: true
                )
            )
        )
    }

    @Test
    func parsesProjectQueryRouteWithResumeFlagAndPane() throws {
        let url = try #require(
            URL(string: "xterminal://project?project_id=project-gamma&resume=1&pane=terminal&grant_reason=hub_check")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-gamma",
                    pane: .terminal,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: "hub_check",
                    resumeRequested: true
                )
            )
        )
    }

    @Test
    func parsesSupervisorRouteWithGrantFocus() throws {
        let url = try #require(
            URL(string: "xterminal://supervisor?project_id=project-delta&focus=grant&grant_request_id=grant-7&grant_capability=ai.generate.paid")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: "project-delta",
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-7",
                    grantCapability: "ai.generate.paid",
                    grantReason: nil
                )
            )
        )
    }

    @Test
    func parsesProjectRouteWithApprovalFocusAndRequestId() throws {
        let url = try #require(
            URL(string: "xterminal://project?project_id=project-epsilon&focus=approval&request_id=req-5&open=supervisor")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-epsilon",
                    pane: nil,
                    openTarget: .supervisor,
                    focusTarget: .approval,
                    requestId: "req-5",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func parsesProjectRouteWithToolApprovalFocusAndRequestId() throws {
        let url = try #require(
            URL(string: "xterminal://project?project_id=project-theta&focus=tool_approval&request_id=call-9&pane=chat")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-theta",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: .toolApproval,
                    requestId: "call-9",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func parsesProjectRouteWithRouteDiagnoseFocus() throws {
        let url = try #require(
            URL(string: "xterminal://project?project_id=project-lambda&focus=route_diagnose&pane=chat")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-lambda",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: .routeDiagnose,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }
}
