import Foundation
import Testing
@testable import XTerminal

struct XTOfficialSkillsBlockerActionSupportTests {
    @Test
    func blockedBlockerBuildsVerifyReadinessAction() throws {
        let item = AXOfficialSkillBlockerSummaryItem(
            packageSHA256: "sha-secondary",
            title: "Secondary Skill",
            subtitle: "skill.secondary",
            stateLabel: "blocked",
            summaryLine: "version=2.0.0 package=ready risk=medium grant=none",
            timelineLine: "last_blocked=2026-03-19T11:30:00Z"
        )

        let action = try #require(XTOfficialSkillsBlockerActionSupport.action(for: item))
        let url = try #require(URL(string: action.url))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(action.label == "查看阻塞状态")
        #expect(action.title == "查看受阻的官方技能")
        #expect(action.detail.contains("Secondary Skill (skill.secondary) [blocked]"))
        #expect(action.detail.contains("version=2.0.0"))
        #expect(action.detail.contains("last_blocked="))
        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "verify_readiness",
                    title: "查看受阻的官方技能",
                    detail: action.detail,
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func revokedBlockerUsesRevocationAction() throws {
        let item = AXOfficialSkillBlockerSummaryItem(
            packageSHA256: "sha-revoked",
            title: "Revoked Skill",
            subtitle: "skill.revoked",
            stateLabel: "revoked",
            summaryLine: "version=3.1.0 package=revoked risk=high grant=required failures=2",
            timelineLine: "updated=2026-03-19T09:00:00Z"
        )

        let action = try #require(XTOfficialSkillsBlockerActionSupport.action(for: item))
        let url = try #require(URL(string: action.url))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(action.label == "打开诊断")
        #expect(action.title == "查看官方技能撤销状态")
        #expect(action.detail.contains("Revoked Skill (skill.revoked) [revoked]"))
        #expect(action.detail.contains("package=revoked"))
        #expect(
            route == .settings(
                XTSettingsRoute(
                    sectionId: "diagnostics",
                    title: "查看官方技能撤销状态",
                    detail: action.detail,
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func unsupportedStateNormalizesLegacyUnderscoreLabel() throws {
        let item = AXOfficialSkillBlockerSummaryItem(
            packageSHA256: "sha-unsupported",
            title: "Legacy Skill",
            subtitle: "skill.legacy",
            stateLabel: "not_supported",
            summaryLine: "version=1.4.0 package=active risk=low grant=none",
            timelineLine: ""
        )

        let action = try #require(XTOfficialSkillsBlockerActionSupport.action(for: item))
        let url = try #require(URL(string: action.url))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(action.label == "打开诊断")
        #expect(action.title == "查看官方技能支持状态")
        #expect(action.detail.contains("[not supported]"))
        #expect(
            route == .settings(
                XTSettingsRoute(
                    sectionId: "diagnostics",
                    title: "查看官方技能支持状态",
                    detail: action.detail,
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func blockedGrantRequiredBlockerRoutesToTroubleshoot() throws {
        let item = AXOfficialSkillBlockerSummaryItem(
            packageSHA256: "sha-grant",
            title: "Grant Skill",
            subtitle: "skill.grant",
            stateLabel: "blocked",
            summaryLine: "version=2.1.0 package=ready risk=high grant=required failures=1",
            timelineLine: "last_blocked=2026-03-19T13:00:00Z"
        )

        let action = try #require(XTOfficialSkillsBlockerActionSupport.action(for: item))
        let url = try #require(URL(string: action.url))
        let route = try #require(XTDeepLinkParser.parse(url))

        #expect(action.label == "处理授权阻塞")
        #expect(action.title == "处理官方技能授权阻塞")
        #expect(
            route == .hubSetup(
                XTHubSetupRoute(
                    sectionId: "troubleshoot",
                    title: "处理官方技能授权阻塞",
                    detail: action.detail,
                    refreshAction: .recheckOfficialSkills,
                    refreshReason: "official_skill_blocker"
                )
            )
        )
    }

    @Test
    func blockerActionFallsBackToPackageHashWhenDisplayMetadataMissing() throws {
        let item = AXOfficialSkillBlockerSummaryItem(
            packageSHA256: "sha-missing-display",
            title: "",
            subtitle: "",
            stateLabel: "degraded",
            summaryLine: "",
            timelineLine: ""
        )

        let action = try #require(XTOfficialSkillsBlockerActionSupport.action(for: item))

        #expect(action.label == "查看降级状态")
        #expect(action.detail == "sha-missing-display [degraded]")
    }

    @Test
    func rankedBlockersPrioritizeActionableAndHigherRiskReasons() {
        let blockers = [
            AXOfficialSkillBlockerSummaryItem(
                packageSHA256: "sha-secondary",
                title: "Secondary Skill",
                subtitle: "skill.secondary",
                stateLabel: "blocked",
                summaryLine: "version=2.0.0 package=ready risk=medium grant=none failures=1",
                timelineLine: "last_blocked=2026-03-19T11:00:00Z"
            ),
            AXOfficialSkillBlockerSummaryItem(
                packageSHA256: "sha-revoked",
                title: "Revoked Skill",
                subtitle: "skill.revoked",
                stateLabel: "revoked",
                summaryLine: "version=3.1.0 package=revoked risk=high grant=none failures=1",
                timelineLine: "updated=2026-03-19T10:00:00Z"
            ),
            AXOfficialSkillBlockerSummaryItem(
                packageSHA256: "sha-agent-browser",
                title: "Agent Browser",
                subtitle: "agent-browser",
                stateLabel: "blocked",
                summaryLine: "version=2.1.0 package=ready risk=high grant=required failures=2",
                timelineLine: "last_blocked=2026-03-19T12:00:00Z"
            )
        ]

        let ranked = XTOfficialSkillsBlockerActionSupport.rankedBlockers(blockers)

        #expect(ranked.map(\.title) == ["Agent Browser", "Revoked Skill", "Secondary Skill"])
    }
}
