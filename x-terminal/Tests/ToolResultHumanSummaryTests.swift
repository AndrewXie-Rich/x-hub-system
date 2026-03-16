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
            body: "project governance blocks run_command under execution tier a0_observe"
        )
        let result = ToolResult(
            id: "tool-1",
            tool: .run_command,
            ok: false,
            output: output
        )

        let body = ToolResultHumanSummary.body(for: result)

        #expect(body.contains("does not allow command execution"))
        #expect(body.contains("Raise the execution tier"))
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

        #expect(body.contains("Project tool policy blocks"))
        #expect(body.contains("Allow this tool"))
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

        #expect(body.contains("not authenticated"))
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
        #expect(body.contains("require"))
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

        #expect(body.contains("could not resolve"))
        #expect(body.contains("GitHub repository"))
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
        #expect(body.contains("could not be started"))
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

        #expect(body.contains("Multiple git remotes"))
        #expect(body.contains("explicit remote"))
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

        #expect(body.contains("explicit branch"))
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

        #expect(body.contains("configured remote"))
        #expect(body.contains("before it can continue"))
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

        #expect(body.contains("local branch"))
        #expect(body.contains("does not exist yet"))
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

        #expect(body.contains("user identity"))
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

        #expect(body.contains("requested commit paths"))
        #expect(body.contains("tracked changes"))
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

        #expect(body.contains("tracked changes"))
        #expect(!body.contains("staged changes"))
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

        #expect(body.contains("commit paths"))
        #expect(body.contains("not tracked"))
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
        #expect(body.contains("explicit `paths`"))
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

        #expect(body.contains("could not reach"))
        #expect(body.contains("configured git remote"))
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

        #expect(body.contains("rejected"))
        #expect(body.contains("remote branch has diverged"))
    }
}
