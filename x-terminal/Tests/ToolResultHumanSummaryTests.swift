import Foundation
import Testing
@testable import XTerminal

struct ToolResultHumanSummaryTests {

    @Test
    func governanceDeniedCommandUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.run_command.rawValue),
                "ok": .bool(false),
                "deny_code": .string("governance_capability_denied"),
                "policy_source": .string("project_governance"),
                "policy_reason": .string("execution_tier_missing_repo_build_test")
            ],
            body: "project governance blocks run_command under A-Tier a0_observe"
        )
        let result = ToolResult(
            id: "tool-1",
            tool: .run_command,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("不允许运行构建或测试命令"))
        #expect(body.contains("打开项目设置 -> A-Tier"))
        #expect(body.contains("A2 Repo Auto"))
    }

    @Test
    func toolPolicyDeniedWriteUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.write_file.rawValue),
                "ok": .bool(false),
                "deny_code": .string("tool_policy_denied"),
                "policy_source": .string("project_tool_policy"),
                "policy_reason": .string("tool_not_allowed")
            ],
            body: "project tool policy blocks tool write_file (profile=coding)"
        )
        let result = ToolResult(
            id: "tool-2",
            tool: .write_file,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("项目工具策略禁止执行"))
        #expect(body.contains("放行这个工具"))
    }

    @Test
    func githubDeliveryFailureUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.pr_create.rawValue),
                "ok": .bool(false),
                "provider": .string("github"),
                "reason_code": .string("github_auth_missing"),
                "failure_stage": .string("auth"),
                "preflight_checked": .bool(true),
            ],
            body: "GitHub CLI is installed but not authenticated for this machine."
        )
        let result = ToolResult(
            id: "tool-3",
            tool: .pr_create,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("还没有完成 GitHub 登录授权"))
        #expect(body.contains("GitHub CLI"))
    }

    @Test
    func githubCLIMissingUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.pr_create.rawValue),
                "ok": .bool(false),
                "provider": .string("github"),
                "reason_code": .string("github_cli_missing"),
                "failure_stage": .string("cli"),
                "preflight_checked": .bool(true),
            ],
            body: "GitHub CLI (`gh`) is not installed on this machine."
        )
        let result = ToolResult(
            id: "tool-3b",
            tool: .pr_create,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("GitHub CLI"))
        #expect(body.contains("还没有安装"))
    }

    @Test
    func githubRepoContextUnavailableUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.ci_trigger.rawValue),
                "ok": .bool(false),
                "provider": .string("github"),
                "reason_code": .string("github_repo_context_unavailable"),
                "failure_stage": .string("repo"),
                "preflight_checked": .bool(true),
            ],
            body: "XT could not resolve a GitHub repository from the current folder."
        )
        let result = ToolResult(
            id: "tool-3c",
            tool: .ci_trigger,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("无法从当前目录解析出 GitHub 仓库"))
    }

    @Test
    func githubCLIExecutionFailedUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.ci_read.rawValue),
                "ok": .bool(false),
                "provider": .string("github"),
                "reason_code": .string("github_cli_execution_failed"),
                "failure_stage": .string("cli"),
                "preflight_checked": .bool(true),
            ],
            body: "GitHub CLI could not be started from this project."
        )
        let result = ToolResult(
            id: "tool-3d",
            tool: .ci_read,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("GitHub CLI"))
        #expect(body.contains("无法从当前项目启动"))
    }

    @Test
    func gitPushAmbiguousRemoteUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_remote_ambiguous"),
                "failure_stage": .string("remote"),
            ],
            body: "git_push requires an explicit remote because multiple remotes are configured"
        )
        let result = ToolResult(
            id: "tool-4",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("多个远端仓库"))
        #expect(body.contains("显式指定 remote"))
    }

    @Test
    func gitPushDetachedHeadUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_detached_head"),
                "failure_stage": .string("branch"),
            ],
            body: "git_push requires a branch when HEAD is detached"
        )
        let result = ToolResult(
            id: "tool-4b",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("显式指定分支"))
        #expect(body.contains("detached HEAD"))
    }

    @Test
    func gitPushRemoteMissingUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_remote_missing"),
                "failure_stage": .string("remote"),
            ],
            body: "git_push requires a configured remote"
        )
        let result = ToolResult(
            id: "tool-4c",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("先配置远端仓库"))
    }

    @Test
    func gitPushBranchMissingUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_branch_missing"),
                "failure_stage": .string("branch"),
                "branch": .string("release/missing"),
            ],
            body: "The local branch to push does not exist yet."
        )
        let result = ToolResult(
            id: "tool-4d",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("本地分支"))
        #expect(body.contains("还不存在"))
    }

    @Test
    func gitCommitIdentityMissingUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_commit.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_identity_missing"),
                "failure_stage": .string("identity"),
            ],
            body: "Git user identity is not configured for this repository."
        )
        let result = ToolResult(
            id: "tool-5",
            tool: .git_commit,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("Git 身份"))
        #expect(body.contains("user.name"))
        #expect(body.contains("user.email"))
    }

    @Test
    func gitCommitNoChangesForSpecificPathsUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_commit.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_commit_no_changes"),
                "failure_stage": .string("commit"),
                "paths": .array([.string("README.md")]),
            ],
            body: "There are no tracked changes to commit for the requested paths."
        )
        let result = ToolResult(
            id: "tool-5b",
            tool: .git_commit,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("提交路径"))
        #expect(body.contains("已跟踪改动"))
    }

    @Test
    func gitCommitAllNoChangesUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_commit.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_commit_no_changes"),
                "failure_stage": .string("commit"),
                "all": .bool(true),
            ],
            body: "There are no tracked changes ready to commit."
        )
        let result = ToolResult(
            id: "tool-5bb",
            tool: .git_commit,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("已跟踪改动"))
        #expect(!body.contains("暂存改动"))
    }

    @Test
    func gitCommitPathspecInvalidUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_commit.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_commit_pathspec_invalid"),
                "failure_stage": .string("paths"),
                "paths": .array([.string("draft.md")]),
            ],
            body: "One or more commit paths are not tracked by git in this repository."
        )
        let result = ToolResult(
            id: "tool-5c",
            tool: .git_commit,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("提交路径"))
        #expect(body.contains("Git 跟踪范围"))
    }

    @Test
    func gitCommitAllAndPathsUnsupportedUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_commit.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_commit_paths_with_all_unsupported"),
                "failure_stage": .string("args"),
                "all": .bool(true),
                "paths": .array([.string("README.md")]),
            ],
            body: "git_commit cannot combine all=true with explicit paths."
        )
        let result = ToolResult(
            id: "tool-5d",
            tool: .git_commit,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("all=true"))
        #expect(body.contains("显式 `paths`"))
    }

    @Test
    func gitPushRemoteUnreachableUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_remote_unreachable"),
                "failure_stage": .string("remote"),
            ],
            body: "XT could not reach the configured git remote."
        )
        let result = ToolResult(
            id: "tool-6",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("无法连接到已配置的 Git 远端"))
    }

    @Test
    func gitPushNonFastForwardUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.git_push.rawValue),
                "ok": .bool(false),
                "reason_code": .string("git_push_non_fast_forward"),
                "failure_stage": .string("push"),
            ],
            body: "The push was rejected because the remote branch has diverged."
        )
        let result = ToolResult(
            id: "tool-7",
            tool: .git_push,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("被拒绝"))
        #expect(body.contains("远端分支已发生分叉"))
    }

    @Test
    func skillsPinSuccessUsesHumanGuidanceInsteadOfFailurePrefix() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.skills_pin.rawValue),
                "ok": .bool(true),
                "scope": .string("global"),
                "skill_id": .string("find-skills"),
                "package_sha256": .string("abcdef1234567890"),
            ],
            body: "Hub 已通过审查并启用技能：find-skills@abcdef123456（global）"
        )
        let result = ToolResult(
            id: "tool-skills-pin-success",
            tool: .skills_pin,
            ok: true,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("已通过审查并启用技能"))
        #expect(!body.contains("无法更新技能可用性"))
    }

    @Test
    func skillsPinOfficialReviewBlockedUsesHumanGuidance() {
        let output = ToolExecutor.structuredOutput(
            summary: [
                "tool": .string(ToolName.skills_pin.rawValue),
                "ok": .bool(false),
                "reason": .string("official_skill_review_blocked"),
            ],
            body: "Hub 已自动审查该官方技能包，但当前 official_skills doctor 结果还不是 ready，暂不能启用。"
        )
        let result = ToolResult(
            id: "tool-skills-pin-blocked",
            tool: .skills_pin,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("Hub 已自动审查该官方技能包"))
        #expect(body.contains("doctor"))
        #expect(body.contains("lifecycle"))
    }
}
