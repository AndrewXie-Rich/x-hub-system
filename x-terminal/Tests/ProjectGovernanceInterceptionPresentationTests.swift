import Foundation
import Testing
@testable import XTerminal

struct ProjectGovernanceInterceptionPresentationTests {

    @Test
    func makeBuildsGovernanceEvidenceBundleForBlockedActivity() throws {
        let item = ProjectSkillActivityItem(
            requestID: "skill-guard-1",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 10,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "当前生效 A1/S2 · 审查 Periodic。"
        )

        let presentation = try #require(ProjectGovernanceInterceptionPresentation.make(from: item))

        #expect(presentation.item.requestID == "skill-guard-1")
        #expect(presentation.blockedSummary?.contains("不允许浏览器自动化") == true)
        #expect(presentation.shouldShowGovernanceReason == true)
        #expect(presentation.policyReason == "execution_tier_missing_browser_runtime")
        #expect(presentation.governanceTruthLine == "当前生效 A1/S2 · 审查 周期。")
        #expect(presentation.repairHint?.destination == .executionTier)
        #expect(presentation.repairInlineMessage?.contains("最近一次拦截：") == true)
        #expect(presentation.repairInlineMessage?.contains("governance_reason=当前项目 A-Tier 不允许浏览器自动化。") == true)
        #expect(presentation.repairInlineMessage?.contains("governance_truth=当前生效 A1/S2 · 审查 周期。") == true)
        #expect(presentation.repairInlineMessage?.contains("policy_reason=execution_tier_missing_browser_runtime") == true)
        #expect(presentation.repairInlineMessage?.contains("repair_action=打开 A-Tier：") == true)
    }

    @Test
    func makeReturnsNilForNonGovernanceActivity() {
        let item = ProjectSkillActivityItem(
            requestID: "skill-ok-1",
            skillID: "find-skills",
            toolName: "skills.search",
            status: "completed",
            createdAt: 12,
            resolutionSource: "primary",
            toolArgs: ["query": .string("browser")],
            resultSummary: "Found skills",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        #expect(ProjectGovernanceInterceptionPresentation.make(from: item) == nil)
    }

    @Test
    func latestSelectsNewestGovernanceInterception() throws {
        let older = ProjectSkillActivityItem(
            requestID: "skill-old",
            skillID: "agent-browser",
            toolName: ToolName.deviceBrowserControl.rawValue,
            status: "blocked",
            createdAt: 5,
            resolutionSource: "primary",
            toolArgs: ["action": .string("open_url")],
            resultSummary: "",
            detail: "",
            denyCode: "governance_capability_denied",
            authorizationDisposition: "deny",
            policySource: "project_governance",
            policyReason: "execution_tier_missing_browser_runtime",
            governanceTruth: "当前生效 A1/S2 · 审查 Periodic。"
        )
        let newer = ProjectSkillActivityItem(
            requestID: "skill-new",
            skillID: "agent-shell",
            toolName: "run_command",
            status: "failed",
            createdAt: 8,
            resolutionSource: "primary",
            toolArgs: ["command": .string("npm run release")],
            resultSummary: "",
            detail: "",
            denyCode: "autonomy_policy_denied",
            authorizationDisposition: "deny",
            policySource: "project_autonomy_policy",
            policyReason: "release_not_allowed_under_current_surface",
            governanceTruth: "当前生效 A2/S3 · 审查 Periodic。"
        )
        let ignored = ProjectSkillActivityItem(
            requestID: "skill-ignore",
            skillID: "find-skills",
            toolName: "skills.search",
            status: "completed",
            createdAt: 9,
            resolutionSource: "primary",
            toolArgs: [:],
            resultSummary: "Found skills",
            detail: "",
            denyCode: "",
            authorizationDisposition: ""
        )

        let presentation = try #require(
            ProjectGovernanceInterceptionPresentation.latest(from: [older, ignored, newer])
        )

        #expect(presentation.item.requestID == "skill-new")
        #expect(presentation.repairHint?.destination == .overview)
        #expect(presentation.repairInlineMessage?.contains("governance_truth=当前生效 A2/S3 · 审查 周期。") == true)
        #expect(presentation.repairInlineMessage?.contains("repair_action=打开治理设置：") == true)
    }
}
