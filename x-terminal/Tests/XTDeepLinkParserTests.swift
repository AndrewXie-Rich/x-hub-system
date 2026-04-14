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
                    refreshReason: "official_skill_blocker",
                    pairingPrefill: nil
                )
            )
        )
    }

    @Test
    func parsesPairHubInviteRouteWithPrefill() throws {
        let url = try #require(
            URL(string: "xterminal://pair-hub?hub_alias=ops-main&hub_host=hub.tailnet.example&pairing_port=50054&grpc_port=50053&invite_token=axhub_invite_test_123&hub_instance_id=hub_deadbeefcafefeed00")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "pair_hub",
                    title: nil,
                    detail: nil,
                    refreshAction: nil,
                    refreshReason: nil,
                    pairingPrefill: XTHubPairingInvitePrefill(
                        hubAlias: "ops-main",
                        internetHost: "hub.tailnet.example",
                        pairingPort: 50054,
                        grpcPort: 50053,
                        inviteToken: "axhub_invite_test_123",
                        hubInstanceID: "hub_deadbeefcafefeed00"
                    )
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
    func parsesSettingsRouteWithHistoricalRepairRefreshAction() throws {
        let url = try #require(
            URL(string: "xterminal://settings?section_id=diagnostics&title=%E5%8E%86%E5%8F%B2%E9%A1%B9%E7%9B%AE%E4%BF%AE%E5%A4%8D&detail=%E6%89%AB%E6%8F%8F%E5%8E%86%E5%8F%B2%E9%A1%B9%E7%9B%AE%E5%B9%B6%E8%A1%A5%E9%BD%90%E7%BC%BA%E5%A4%B1%E8%BE%B9%E7%95%8C&refresh_action=repair_historical_project_boundaries&refresh_reason=supervisor_historical_project_boundary_repair")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .settings(
                XTSettingsRoute(
                    sectionId: "diagnostics",
                    title: "历史项目修复",
                    detail: "扫描历史项目并补齐缺失边界",
                    refreshAction: .repairHistoricalProjectBoundaries,
                    refreshReason: "supervisor_historical_project_boundary_repair"
                )
            )
        )
    }

    @Test
    func parsesSupervisorModelSettingsRouteWithContext() throws {
        let url = try #require(
            URL(string: "xterminal://supervisor-model-settings?title=Route%20diagnose&detail=Check%20real%20available%20models")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisorModelSettings(
                XTSupervisorModelSettingsRoute(
                    title: "Route diagnose",
                    detail: "Check real available models"
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
    func parsesSupervisorRouteWithCandidateReviewFocus() throws {
        let url = try #require(
            URL(string: "xterminal://supervisor?project_id=project-review&focus=candidate_review&request_id=req-review-1")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: "project-review",
                    focusTarget: .candidateReview,
                    requestId: "req-review-1",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil
                )
            )
        )
    }

    @Test
    func parsesSupervisorRouteWithProjectCreationBoardFocus() throws {
        let url = try #require(
            URL(string: "xterminal://supervisor?focus=project_creation_board")
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: nil,
                    focusTarget: .projectCreationBoard,
                    requestId: nil,
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
