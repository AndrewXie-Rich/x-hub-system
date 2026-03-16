import Foundation
import Testing
@testable import XTerminal

struct XTDeepLinkURLBuilderTests {
    @Test
    func projectResumeURLBuildsRoundTrippableResumeLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-alpha",
                pane: .chat,
                resumeRequested: true
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-alpha",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: true
                )
            )
        )
    }

    @Test
    func projectResumeSupervisorURLBuildsRoundTrippableApprovalLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-beta",
                pane: .chat,
                openTarget: .supervisor,
                resumeRequested: true,
                grantRequestId: "grant-77",
                grantCapability: "ai.generate.paid"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-beta",
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-77",
                    grantCapability: "ai.generate.paid",
                    grantReason: nil,
                    resumeRequested: true
                )
            )
        )
    }

    @Test
    func supervisorGrantURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.supervisorURL(
                grantRequestId: "grant-91",
                grantCapability: "web.fetch"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: nil,
                    focusTarget: .grant,
                    requestId: nil,
                    grantRequestId: "grant-91",
                    grantCapability: "web.fetch",
                    grantReason: nil
                )
            )
        )
    }

    @Test
    func projectApprovalSupervisorURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-zeta",
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: .approval,
                requestId: "req-21"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-zeta",
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
        )
    }

    @Test
    func projectToolApprovalURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-iota",
                pane: .chat,
                focusTarget: .toolApproval,
                requestId: "tool-call-3"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-iota",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: .toolApproval,
                    requestId: "tool-call-3",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func projectRouteDiagnoseURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-kappa",
                pane: .chat,
                focusTarget: .routeDiagnose
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-kappa",
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
