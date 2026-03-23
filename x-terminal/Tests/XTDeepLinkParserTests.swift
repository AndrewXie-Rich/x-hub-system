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
    func parsesHubSetupRouteWithSectionAndContext() throws {
        let url = try #require(
            URL(string: "xterminal://hub-setup?section_id=verify_readiness&title=Review%20official%20skills%20blockers&detail=Top%20blockers%3A%20agent-browser&refresh_action=recheck_official_skills&refresh_reason=official_skill_blocker")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "verify_readiness",
                    title: "Review official skills blockers",
                    detail: "Top blockers: agent-browser",
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func parsesSettingsRouteWithSectionAndContext() throws {
        let url = try #require(
            URL(string: "xterminal://settings?section_id=diagnostics&title=Review%20official%20skill%20revocation&detail=Revoked%20Skill&refresh_action=recheck_official_skills&refresh_reason=official_skill_blocker")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .settings(
                XTSettingsRoute(
                    sectionId: "diagnostics",
                    title: "Review official skill revocation",
                    detail: "Revoked Skill",
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
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
    func parsesSupervisorRouteWithSkillRecordFocus() throws {
        let url = try #require(
            URL(string: "xterminal://supervisor?project_id=project-record&focus=skill_record&request_id=req-record-1")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: "project-record",
                    focusTarget: .skillRecord,
                    requestId: "req-record-1",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil
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

    @Test
    func parsesProjectRouteWithGovernanceDestination() throws {
        let url = try #require(
            URL(string: "xterminal://project?project_id=project-mu&governance_destination=execution_tier&pane=chat")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-mu",
                    pane: .chat,
                    openTarget: nil,
                    focusTarget: nil,
                    requestId: nil,
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false,
                    governanceDestination: .executionTier
                )
            )
        )
    }
}
