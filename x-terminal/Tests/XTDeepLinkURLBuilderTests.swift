import Foundation
import Testing
@testable import XTerminal

struct XTDeepLinkURLBuilderTests {
    @Test
    func hubSetupURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.hubSetupURL(
                sectionId: "verify_readiness",
                title: "Review official skills blockers",
                detail: "Top blockers: Secondary Skill (skill.secondary) [blocked]",
                refreshAction: .recheckOfficialSkills,
                refreshReason: "official_skill_blocker"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "verify_readiness",
                    title: "Review official skills blockers",
                    detail: "Top blockers: Secondary Skill (skill.secondary) [blocked]",
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func settingsURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: "Review official skill revocation",
                detail: "Revoked Skill (skill.revoked) [revoked]",
                refreshAction: .recheckOfficialSkills,
                refreshReason: "official_skill_blocker"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .settings(
                XTSettingsRoute(
                    sectionId: "diagnostics",
                    title: "Review official skill revocation",
                    detail: "Revoked Skill (skill.revoked) [revoked]",
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func settingsURLBuildsRoundTrippableHistoricalRepairLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.settingsURL(
                sectionId: "diagnostics",
                title: "历史项目修复",
                detail: "扫描历史项目并补齐缺失边界",
                refreshAction: .repairHistoricalProjectBoundaries,
                refreshReason: "supervisor_historical_project_boundary_repair"
            )
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
    func supervisorModelSettingsURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.supervisorModelSettingsURL(
                title: "Route diagnose",
                detail: "Check real available models"
            )
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
    func supervisorProjectCreationBoardURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .projectCreationBoard
            )
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
    func projectSkillRecordSupervisorURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-record",
                pane: .chat,
                openTarget: .supervisor,
                focusTarget: .skillRecord,
                requestId: "req-record-1"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-record",
                    pane: .chat,
                    openTarget: .supervisor,
                    focusTarget: .skillRecord,
                    requestId: "req-record-1",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil,
                    resumeRequested: false
                )
            )
        )
    }

    @Test
    func supervisorCandidateReviewURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .candidateReview,
                requestId: "req-candidate-1"
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .supervisor(
                XTDeepLinkSupervisorRoute(
                    projectId: nil,
                    focusTarget: .candidateReview,
                    requestId: "req-candidate-1",
                    grantRequestId: nil,
                    grantCapability: nil,
                    grantReason: nil
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

    @Test
    func projectGovernanceURLBuildsRoundTrippableFocusLink() throws {
        let url = try #require(
            XTDeepLinkURLBuilder.projectURL(
                projectId: "project-lambda",
                pane: .chat,
                governanceDestination: .executionTier
            )
        )
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(
            route == .project(
                XTDeepLinkProjectRoute(
                    projectId: "project-lambda",
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
