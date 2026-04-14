import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct AppModelSettingsFocusTests {
    @Test
    func ignoresEmptySettingsFocusRequests() {
        let appModel = AppModel()

        appModel.requestSettingsFocus(sectionId: "   ")

        #expect(appModel.settingsFocusRequest == nil)
    }

    @Test
    func settingsFocusRequestUsesFreshNonceAndClearsCurrentOnly() throws {
        let appModel = AppModel()

        appModel.requestSettingsFocus(
            sectionId: " diagnostics ",
            title: " 路由诊断 ",
            detail: " requested=openai/gpt-5.4 ",
            refreshAction: .recheckOfficialSkills,
            refreshReason: "official_skill_blocker"
        )
        let first = try #require(appModel.settingsFocusRequest)
        #expect(first.sectionId == "diagnostics")
        #expect(first.context?.title == "路由诊断")
        #expect(first.context?.detail == "requested=openai/gpt-5.4")
        #expect(first.context?.refreshAction == .recheckOfficialSkills)
        #expect(first.context?.refreshReason == "official_skill_blocker")

        appModel.requestSettingsFocus(sectionId: "diagnostics")
        let second = try #require(appModel.settingsFocusRequest)
        #expect(second.sectionId == "diagnostics")
        #expect(second.nonce == first.nonce + 1)

        appModel.clearSettingsFocusRequest(first)
        #expect(appModel.settingsFocusRequest?.nonce == second.nonce)

        appModel.clearSettingsFocusRequest(second)
        #expect(appModel.settingsFocusRequest == nil)
    }

    @Test
    func recheckOfficialSkillsWritesStatusLine() {
        let appModel = AppModel()

        appModel.recheckOfficialSkills(reason: "unit_test")

        #expect(appModel.officialSkillsRecheckStatusLine.contains("official_skills_recheck="))
        #expect(appModel.officialSkillsRecheckStatusLine.contains("reason=unit_test"))
    }

    @Test
    func governanceDestinationParsesLegacyAndFriendlyTokens() {
        #expect(XTProjectGovernanceDestination.parse("project_governance") == .overview)
        #expect(XTProjectGovernanceDestination.parse(" overview ") == .overview)
        #expect(XTProjectGovernanceDestination.parse("ui_review") == .uiReview)
        #expect(XTProjectGovernanceDestination.parse("review workspace") == .uiReview)
        #expect(XTProjectGovernanceDestination.parse("execution_tier") == .executionTier)
        #expect(XTProjectGovernanceDestination.parse("a-tier") == .executionTier)
        #expect(XTProjectGovernanceDestination.parse("supervisor_tier") == .supervisorTier)
        #expect(XTProjectGovernanceDestination.parse("supervisor") == .supervisorTier)
        #expect(XTProjectGovernanceDestination.parse("review_cadence") == .heartbeatReview)
        #expect(XTProjectGovernanceDestination.parse("heartbeat review") == .heartbeatReview)
        #expect(XTProjectGovernanceDestination.parse("   ") == nil)
    }

    @Test
    func projectSettingsFocusRequestCarriesGovernanceDestination() throws {
        let appModel = AppModel()

        appModel.requestProjectSettingsFocus(
            projectId: "  hex:demo-project  ",
            destination: .heartbeatReview,
            title: " Project Governance ",
            detail: " Heartbeat / Review "
        )

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == "hex:demo-project")
        #expect(request.destination == .heartbeatReview)
        #expect(request.sectionId == XTProjectGovernanceDestination.heartbeatReview.rawValue)
        #expect(request.context?.title == "Project Governance")
        #expect(request.context?.detail == "Heartbeat / Review")
        #expect(appModel.selectedProjectId == "hex:demo-project")
        #expect(appModel.pane(for: "hex:demo-project") == .chat)
    }

    @Test
    func projectSettingsFocusRequestCanCarryOverviewAnchor() throws {
        let appModel = AppModel()

        appModel.requestProjectSettingsFocus(
            projectId: "project-memory",
            destination: .overview,
            preserveCurrentPane: true,
            overviewAnchor: .contextAssembly,
            title: "Project Governance",
            detail: "Project AI Memory Controls"
        )

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.destination == .overview)
        #expect(request.overviewAnchor == .contextAssembly)
        #expect(request.context?.detail == "Project AI Memory Controls")
        #expect(appModel.selectedProjectId == "project-memory")
    }

    @Test
    func supervisorSettingsFocusDefaultsToSectionContext() throws {
        let appModel = AppModel()

        appModel.requestSupervisorSettingsFocus(section: .reviewMemoryDepth)

        let request = try #require(appModel.supervisorSettingsFocusRequest)
        #expect(request.section == .reviewMemoryDepth)
        #expect(request.context == XTSupervisorSettingsFocusSection.reviewMemoryDepth.focusContext)
    }

    @Test
    func clearSupervisorSettingsFocusRequestOnlyClearsMatchingNonce() throws {
        let appModel = AppModel()

        appModel.requestSupervisorSettingsFocus(section: .recentRawContext)
        let first = try #require(appModel.supervisorSettingsFocusRequest)

        appModel.requestSupervisorSettingsFocus(section: .reviewMemoryDepth)
        let second = try #require(appModel.supervisorSettingsFocusRequest)

        appModel.clearSupervisorSettingsFocusRequest(first)
        #expect(appModel.supervisorSettingsFocusRequest?.nonce == second.nonce)

        appModel.clearSupervisorSettingsFocusRequest(second)
        #expect(appModel.supervisorSettingsFocusRequest == nil)
    }

    @Test
    func projectSettingsFocusDefaultsToDestinationContext() throws {
        let appModel = AppModel()

        appModel.requestProjectSettingsFocus(
            projectId: "project-2",
            destination: .supervisorTier
        )

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.destination == .supervisorTier)
        #expect(request.context == XTProjectGovernanceDestination.supervisorTier.focusContext)
    }

    @Test
    func projectSettingsFocusCanPreserveCurrentPaneWhenRequested() throws {
        let appModel = AppModel()
        appModel.setPane(.terminal, for: "project-terminal")

        appModel.requestProjectSettingsFocus(
            projectId: "project-terminal",
            destination: .executionTier,
            preserveCurrentPane: true
        )

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.destination == .executionTier)
        #expect(appModel.selectedProjectId == "project-terminal")
        #expect(appModel.pane(for: "project-terminal") == .terminal)
    }

    @Test
    func projectSettingsInlineMessagePreservesStructuredMultilineContext() {
        let text = xtProjectSettingsInlineMessage(
            title: "治理拦截修复",
            detail: """
            最近一次拦截：当前项目 A-Tier 不允许浏览器自动化。
            governance_reason=当前项目 A-Tier 不允许浏览器自动化。
            policy_reason=execution_tier_missing_browser_runtime
            """
        )

        #expect(text.hasPrefix("治理拦截修复\n"))
        #expect(text.contains("governance_reason=当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(text.contains("policy_reason=execution_tier_missing_browser_runtime"))
    }

    @Test
    func legacyProjectSettingsSectionIdStillMapsToDestination() throws {
        let appModel = AppModel()

        appModel.requestProjectSettingsFocus(
            projectId: "project-1",
            sectionId: XTProjectSettingsSectionID.executionTier
        )
        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.destination == .executionTier)
    }

    @Test
    func projectUIReviewFocusUsesDedicatedUIDestination() throws {
        let appModel = AppModel()

        appModel.requestProjectUIReviewFocus(
            projectId: " project-ui ",
            title: " 最近 UI 审查 ",
            detail: " 项目 UI 审查工作台 "
        )

        let request = try #require(appModel.projectSettingsFocusRequest)
        #expect(request.projectId == "project-ui")
        #expect(request.destination == .uiReview)
        #expect(request.sectionId == XTProjectGovernanceDestination.uiReview.rawValue)
        #expect(request.context?.title == "最近 UI 审查")
        #expect(request.context?.detail == "项目 UI 审查工作台")
        #expect(appModel.selectedProjectId == "project-ui")
        #expect(appModel.pane(for: "project-ui") == .chat)
    }

    @Test
    func projectDetailFocusCarriesSectionAndSelectsProject() throws {
        let appModel = AppModel()

        appModel.requestProjectDetailFocus(
            projectId: " project-detail ",
            section: .uiReview,
            title: " 项目详情 ",
            detail: " 最近 UI 审查 "
        )

        let request = try #require(appModel.projectDetailFocusRequest)
        #expect(request.projectId == "project-detail")
        #expect(request.section == .uiReview)
        #expect(request.context?.title == "项目详情")
        #expect(request.context?.detail == "最近 UI 审查")
        #expect(appModel.selectedProjectId == "project-detail")
        #expect(appModel.pane(for: "project-detail") == .chat)

        appModel.clearProjectDetailFocusRequest(request)
        #expect(appModel.projectDetailFocusRequest == nil)
    }
}
