import Foundation
import Darwin
import Testing
@testable import XTerminal

@Suite(.serialized)
struct ToolExecutorDeliveryToolsTests {
    private final class GitHubToolRunRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var invocationsStore: [(args: [String], cwd: URL, timeoutSec: Double)] = []

        func record(args: [String], cwd: URL, timeoutSec: Double) {
            lock.lock()
            invocationsStore.append((args, cwd, timeoutSec))
            lock.unlock()
        }

        func invocations() -> [(args: [String], cwd: URL, timeoutSec: Double)] {
            lock.lock()
            defer { lock.unlock() }
            return invocationsStore
        }
    }

    private func configureGitIdentity(at root: URL) throws {
        _ = try ProcessCapture.run("/usr/bin/git", ["config", "user.email", "xt@example.com"], cwd: root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["config", "user.name", "XT Test"], cwd: root, timeoutSec: 10.0)
    }

    private func initGitRepo(at root: URL) throws {
        _ = try ProcessCapture.run("/usr/bin/git", ["init"], cwd: root, timeoutSec: 10.0)
        try configureGitIdentity(at: root)
    }

    private func saveGovernanceConfig(
        at root: URL,
        executionTier: AXProjectExecutionTier,
        supervisorInterventionTier: AXProjectSupervisorInterventionTier
    ) throws {
        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingHubMemoryPreference(enabled: false)
        config = config.settingProjectGovernance(
            executionTier: executionTier,
            supervisorInterventionTier: supervisorInterventionTier
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func currentEnvironmentValue(_ key: String) -> String? {
        guard let value = getenv(key) else { return nil }
        return String(cString: value)
    }

    private func withTemporaryEnvironment<T>(
        _ overrides: [String: String?],
        operation: () async throws -> T
    ) async rethrows -> T {
        let original = Dictionary(uniqueKeysWithValues: overrides.keys.map { ($0, currentEnvironmentValue($0)) })
        for (key, value) in overrides {
            if let value {
                setenv(key, value, 1)
            } else {
                unsetenv(key)
            }
        }
        defer {
            for (key, value) in original {
                if let value {
                    setenv(key, value, 1)
                } else {
                    unsetenv(key)
                }
            }
        }
        return try await operation()
    }

    private func currentBranch(at root: URL) throws -> String {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["rev-parse", "--abbrev-ref", "HEAD"],
            cwd: root,
            timeoutSec: 10.0
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test
    func gitCommitCreatesCommitWithinA3DeliverAuto() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let target = fixture.root.appendingPathComponent("README.md")
        try "hello".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Initial commit")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["message"]) == "Initial commit")

        let log = try ProcessCapture.run(
            "/usr/bin/git",
            ["log", "--pretty=%s", "-n", "1"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Initial commit")
    }

    @Test
    func gitCommitAllowEmptyCreatesCommitWithoutChanges() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-allow-empty")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Empty commit"),
                    "allow_empty": .bool(true),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonBool(summary["allow_empty"]) == true)
        #expect(jsonString(summary["message"]) == "Empty commit")

        let log = try ProcessCapture.run(
            "/usr/bin/git",
            ["log", "--pretty=%s", "-n", "1"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Empty commit")
    }

    @Test
    func gitCommitAllowEmptyWithTrackedPathCreatesEmptyCommit() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-allow-empty-paths")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let target = fixture.root.appendingPathComponent("README.md")
        try "v1".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: fixture.root, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Empty path commit"),
                    "allow_empty": .bool(true),
                    "paths": .array([.string("README.md")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonBool(summary["allow_empty"]) == true)
        #expect(jsonArray(summary["paths"])?.contains(where: { jsonString($0) == "README.md" }) == true)

        let show = try ProcessCapture.run(
            "/usr/bin/git",
            ["show", "--pretty=format:", "--name-only", "HEAD"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(show.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func gitCommitWithExplicitPathsCommitsOnlyRequestedTrackedChanges() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-paths")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let readme = fixture.root.appendingPathComponent("README.md")
        let notes = fixture.root.appendingPathComponent("NOTES.md")
        try "readme-v1".write(to: readme, atomically: true, encoding: .utf8)
        try "notes-v1".write(to: notes, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md", "NOTES.md"], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: fixture.root, timeoutSec: 10.0)

        try "readme-v2".write(to: readme, atomically: true, encoding: .utf8)
        try "notes-v2".write(to: notes, atomically: true, encoding: .utf8)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Readme only"),
                    "paths": .array([.string("README.md")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonArray(summary["paths"])?.contains(where: { jsonString($0) == "README.md" }) == true)

        let show = try ProcessCapture.run(
            "/usr/bin/git",
            ["show", "--pretty=format:", "--name-only", "HEAD"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        let committedPaths = show.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
        #expect(committedPaths == ["README.md"])

        let status = try ProcessCapture.run(
            "/usr/bin/git",
            ["status", "--short"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(status.stdout.contains(" M NOTES.md"))
        #expect(!status.stdout.contains("README.md"))
    }

    @Test
    func gitCommitAllCommitsTrackedChangesWithoutStaging() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-all")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let target = fixture.root.appendingPathComponent("README.md")
        try "hello-v1".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: fixture.root, timeoutSec: 10.0)

        try "hello-v2".write(to: target, atomically: true, encoding: .utf8)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Tracked update"),
                    "all": .bool(true),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonBool(summary["all"]) == true)

        let log = try ProcessCapture.run(
            "/usr/bin/git",
            ["log", "--pretty=%s", "-n", "1"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(log.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "Tracked update")

        let status = try ProcessCapture.run(
            "/usr/bin/git",
            ["status", "--short", "--", "README.md"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(status.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func gitCommitFailsClosedWhenExplicitPathsHaveNoTrackedChanges() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-paths-no-changes")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let readme = fixture.root.appendingPathComponent("README.md")
        let notes = fixture.root.appendingPathComponent("NOTES.md")
        try "readme-v1".write(to: readme, atomically: true, encoding: .utf8)
        try "notes-v1".write(to: notes, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md", "NOTES.md"], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: fixture.root, timeoutSec: 10.0)

        try "notes-v2".write(to: notes, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "NOTES.md"], cwd: fixture.root, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Readme only"),
                    "paths": .array([.string("README.md")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_commit_no_changes")
        #expect(jsonString(summary["failure_stage"]) == "commit")
        #expect(jsonArray(summary["paths"])?.contains(where: { jsonString($0) == "README.md" }) == true)
    }

    @Test
    func gitCommitAllFailsClosedWhenOnlyUntrackedFilesExist() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-all-untracked-only")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try "draft".write(
            to: fixture.root.appendingPathComponent("draft.md"),
            atomically: true,
            encoding: .utf8
        )

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Should fail"),
                    "all": .bool(true),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_commit_no_changes")
        #expect(jsonString(summary["failure_stage"]) == "commit")
        #expect(jsonBool(summary["all"]) == true)
    }

    @Test
    func gitCommitFailsClosedWhenExplicitPathIsNotTracked() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-paths-invalid")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try "draft".write(
            to: fixture.root.appendingPathComponent("draft.md"),
            atomically: true,
            encoding: .utf8
        )

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Draft only"),
                    "paths": .array([.string("draft.md")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_commit_pathspec_invalid")
        #expect(jsonString(summary["failure_stage"]) == "paths")
        #expect(jsonArray(summary["paths"])?.contains(where: { jsonString($0) == "draft.md" }) == true)
    }

    @Test
    func gitCommitFailsClosedWhenAllAndPathsAreCombined() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-all-with-paths")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let target = fixture.root.appendingPathComponent("README.md")
        try "hello".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("Invalid commit mode"),
                    "all": .bool(true),
                    "paths": .array([.string("README.md")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_commit_paths_with_all_unsupported")
        #expect(jsonString(summary["failure_stage"]) == "args")
        #expect(jsonBool(summary["all"]) == true)
        #expect(jsonArray(summary["paths"])?.contains(where: { jsonString($0) == "README.md" }) == true)
    }

    @Test
    func gitPushPublishesToConfiguredOriginWithinA4FullSurface() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("origin.git")
        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "ship it".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", remoteRoot.path], cwd: workRoot, timeoutSec: 10.0)

        let branch = try currentBranch(at: workRoot)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_push,
                args: [:]
            ),
            projectRoot: workRoot
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["remote"]) == "origin")
        #expect(jsonString(summary["branch"]) == branch)
        #expect(jsonBool(summary["set_upstream"]) == false)

        let remoteHead = try ProcessCapture.run(
            "/usr/bin/git",
            ["--git-dir", remoteRoot.path, "rev-parse", "--verify", "refs/heads/\(branch)"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(remoteHead.exitCode == 0)
        #expect(!remoteHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func gitPushPublishesWithSetUpstreamAndConfiguresTracking() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-set-upstream")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("upstream.git")
        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "ship it".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "upstream", remoteRoot.path], cwd: workRoot, timeoutSec: 10.0)

        let branch = try currentBranch(at: workRoot)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_push,
                args: [
                    "set_upstream": .bool(true)
                ]
            ),
            projectRoot: workRoot
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["remote"]) == "upstream")
        #expect(jsonString(summary["branch"]) == branch)
        #expect(jsonBool(summary["set_upstream"]) == true)

        let remoteHead = try ProcessCapture.run(
            "/usr/bin/git",
            ["--git-dir", remoteRoot.path, "rev-parse", "--verify", "refs/heads/\(branch)"],
            cwd: fixture.root,
            timeoutSec: 10.0
        )
        #expect(remoteHead.exitCode == 0)
        #expect(!remoteHead.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let trackedRemote = try ProcessCapture.run(
            "/usr/bin/git",
            ["config", "--get", "branch.\(branch).remote"],
            cwd: workRoot,
            timeoutSec: 10.0
        )
        #expect(trackedRemote.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "upstream")

        let trackedMerge = try ProcessCapture.run(
            "/usr/bin/git",
            ["config", "--get", "branch.\(branch).merge"],
            cwd: workRoot,
            timeoutSec: 10.0
        )
        #expect(trackedMerge.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "refs/heads/\(branch)")
    }

    @Test
    func gitPushFailsClosedWhenHeadIsDetached() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-detached-head")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("origin.git")
        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "ship it".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", remoteRoot.path], cwd: workRoot, timeoutSec: 10.0)

        let head = try ProcessCapture.run(
            "/usr/bin/git",
            ["rev-parse", "HEAD"],
            cwd: workRoot,
            timeoutSec: 10.0
        ).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try ProcessCapture.run("/usr/bin/git", ["checkout", "--detach", head], cwd: workRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: workRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_detached_head")
        #expect(jsonString(summary["failure_stage"]) == "branch")
        #expect(jsonBool(summary["set_upstream"]) == false)
    }

    @Test
    func gitPushFailsClosedWhenRemoteIsMissing() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-remote-missing")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        let target = fixture.root.appendingPathComponent("README.md")
        try "ship it".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: fixture.root, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_remote_missing")
        #expect(jsonString(summary["failure_stage"]) == "remote")
        #expect(jsonBool(summary["set_upstream"]) == false)
    }

    @Test
    func gitPushFailsClosedWhenExplicitBranchDoesNotExist() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-branch-missing")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("origin.git")
        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "ship it".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", remoteRoot.path], cwd: workRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_push,
                args: [
                    "branch": .string("release/missing"),
                ]
            ),
            projectRoot: workRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_branch_missing")
        #expect(jsonString(summary["failure_stage"]) == "branch")
        #expect(jsonString(summary["remote"]) == "origin")
        #expect(jsonString(summary["branch"]) == "release/missing")
    }

    @Test
    func gitCommitFailsClosedWithStructuredNoChanges() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-no-changes")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .git_commit,
                args: [
                    "message": .string("No-op commit")
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_commit_no_changes")
        #expect(jsonString(summary["failure_stage"]) == "commit")
    }

    @Test
    func gitCommitFailsClosedWhenIdentityMissing() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-commit-no-identity")
        defer { fixture.cleanup() }

        _ = try ProcessCapture.run("/usr/bin/git", ["init"], cwd: fixture.root, timeoutSec: 10.0)
        let target = fixture.root.appendingPathComponent("README.md")
        try "identity".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: fixture.root, timeoutSec: 10.0)

        let isolatedHome = fixture.root.appendingPathComponent("isolated-home", isDirectory: true)
        let emptyGlobalConfig = fixture.root.appendingPathComponent("empty-global-gitconfig")
        try FileManager.default.createDirectory(at: isolatedHome, withIntermediateDirectories: true)
        try "".write(to: emptyGlobalConfig, atomically: true, encoding: .utf8)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let result = try await withTemporaryEnvironment([
            "HOME": isolatedHome.path,
            "GIT_CONFIG_GLOBAL": emptyGlobalConfig.path,
            "GIT_CONFIG_NOSYSTEM": "1",
        ]) {
            try await ToolExecutor.execute(
                call: ToolCall(
                    tool: .git_commit,
                    args: [
                        "message": .string("Needs identity")
                    ]
                ),
                projectRoot: fixture.root
            )
        }

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_identity_missing")
        #expect(jsonString(summary["failure_stage"]) == "identity")
    }

    @Test
    func gitPushFailsClosedWhenMultipleRemotesRequireExplicitRemote() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-ambiguous-remote")
        defer { fixture.cleanup() }

        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        let upstreamRoot = fixture.root.appendingPathComponent("upstream.git")
        let backupRoot = fixture.root.appendingPathComponent("backup.git")
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", upstreamRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", backupRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "ambiguous".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "upstream", upstreamRoot.path], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "backup", backupRoot.path], cwd: workRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: workRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_remote_ambiguous")
        #expect(jsonString(summary["failure_stage"]) == "remote")
    }

    @Test
    func gitPushFailsClosedWhenRemoteIsUnreachable() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-unreachable-remote")
        defer { fixture.cleanup() }

        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)
        try initGitRepo(at: workRoot)

        let target = workRoot.appendingPathComponent("README.md")
        try "offline".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        let missingRemotePath = fixture.root.appendingPathComponent("missing.git").path
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", missingRemotePath], cwd: workRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: workRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_remote_unreachable")
        #expect(jsonString(summary["failure_stage"]) == "remote")
    }

    @Test
    func gitPushFailsClosedWhenRemoteBranchHasDiverged() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-non-fast-forward")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("origin.git")
        let sourceRoot = fixture.root.appendingPathComponent("source", isDirectory: true)
        let cloneRoot = fixture.root.appendingPathComponent("clone", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try initGitRepo(at: sourceRoot)

        let sourceReadme = sourceRoot.appendingPathComponent("README.md")
        try "v1".write(to: sourceReadme, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: sourceRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: sourceRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", remoteRoot.path], cwd: sourceRoot, timeoutSec: 10.0)
        let branch = try currentBranch(at: sourceRoot)
        _ = try ProcessCapture.run("/usr/bin/git", ["push", "origin", branch], cwd: sourceRoot, timeoutSec: 10.0)

        _ = try ProcessCapture.run("/usr/bin/git", ["clone", remoteRoot.path, cloneRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        try configureGitIdentity(at: cloneRoot)

        try "source-v2".write(to: sourceRoot.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "source.txt"], cwd: sourceRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Source update"], cwd: sourceRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["push", "origin", branch], cwd: sourceRoot, timeoutSec: 10.0)

        try "clone-v2".write(to: cloneRoot.appendingPathComponent("clone.txt"), atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "clone.txt"], cwd: cloneRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Clone update"], cwd: cloneRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: cloneRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: cloneRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_non_fast_forward")
        #expect(jsonString(summary["failure_stage"]) == "push")
    }

    @Test
    func gitPushFailsClosedWhenRemoteRejectsPush() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-git-push-remote-rejected")
        defer { fixture.cleanup() }

        let remoteRoot = fixture.root.appendingPathComponent("origin.git")
        let workRoot = fixture.root.appendingPathComponent("work", isDirectory: true)
        try FileManager.default.createDirectory(at: workRoot, withIntermediateDirectories: true)

        _ = try ProcessCapture.run("/usr/bin/git", ["init", "--bare", remoteRoot.path], cwd: fixture.root, timeoutSec: 10.0)
        let hook = remoteRoot.appendingPathComponent("hooks/pre-receive")
        try """
        #!/bin/sh
        echo "blocked by remote policy" >&2
        exit 1
        """.write(to: hook, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/bin/chmod", ["+x", hook.path], cwd: fixture.root, timeoutSec: 10.0)

        try initGitRepo(at: workRoot)
        let target = workRoot.appendingPathComponent("README.md")
        try "policy".write(to: target, atomically: true, encoding: .utf8)
        _ = try ProcessCapture.run("/usr/bin/git", ["add", "README.md"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["commit", "-m", "Initial commit"], cwd: workRoot, timeoutSec: 10.0)
        _ = try ProcessCapture.run("/usr/bin/git", ["remote", "add", "origin", remoteRoot.path], cwd: workRoot, timeoutSec: 10.0)

        try saveGovernanceConfig(
            at: workRoot,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let result = try await ToolExecutor.execute(
            call: ToolCall(tool: .git_push, args: [:]),
            projectRoot: workRoot
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["reason_code"]) == "git_push_remote_rejected")
        #expect(jsonString(summary["failure_stage"]) == "push")
    }

    @Test
    func prCreateBuildsExpectedArgsAndExtractsURL() throws {
        let fixture = ToolExecutorProjectFixture(name: "github-tool-pr-create")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: "created https://github.com/acme/demo/pull/42\n",
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let summary = try GitHubTool.prCreate(
            root: fixture.root,
            title: "Release train",
            body: "Ship the queued changes",
            base: "main",
            head: "release/train",
            draft: true,
            fill: false,
            labels: ["release"],
            reviewers: ["alice"]
        )

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args) == [
            ["auth", "status"],
            ["repo", "view", "--json", "nameWithOwner,url"],
            [
                "pr", "create",
                "--title", "Release train",
                "--body", "Ship the queued changes",
                "--base", "main",
                "--head", "release/train",
                "--draft",
                "--label", "release",
                "--reviewer", "alice",
            ],
        ])
        let finalInvocation = try #require(invocations.last)
        #expect(finalInvocation.cwd == fixture.root)
        #expect(finalInvocation.timeoutSec == 60.0)
        #expect(finalInvocation.args == [
            "pr", "create",
            "--title", "Release train",
            "--body", "Ship the queued changes",
            "--base", "main",
            "--head", "release/train",
            "--draft",
            "--label", "release",
            "--reviewer", "alice",
        ])
        #expect(summary.output == "created https://github.com/acme/demo/pull/42")
        #expect(jsonString(summary.structuredSummary["tool"]) == ToolName.pr_create.rawValue)
        #expect(jsonString(summary.structuredSummary["provider"]) == "github")
        #expect(jsonString(summary.structuredSummary["repo"]) == "acme/demo")
        #expect(jsonString(summary.structuredSummary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary.structuredSummary["title"]) == "Release train")
        #expect(jsonString(summary.structuredSummary["url"]) == "https://github.com/acme/demo/pull/42")
        #expect(jsonBool(summary.structuredSummary["draft"]) == true)
        #expect(jsonBool(summary.structuredSummary["fill"]) == false)
        #expect(jsonBool(summary.structuredSummary["preflight_checked"]) == true)
    }

    @Test
    func ciReadParsesRunsAndClampsLimit() throws {
        let fixture = ToolExecutorProjectFixture(name: "github-tool-ci-read")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: """
                [{"displayTitle":"Build","workflowName":"CI","status":"completed","conclusion":"success","headBranch":"main","headSha":"abc123","url":"https://github.com/acme/demo/actions/runs/1","createdAt":"2026-03-14T00:00:00Z","updatedAt":"2026-03-14T00:01:00Z"}]
                """,
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let summary = try GitHubTool.ciRead(
            root: fixture.root,
            workflow: "build.yml",
            branch: "main",
            commit: "abc123",
            limit: 99
        )

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args).count == 3)
        let finalInvocation = try #require(invocations.last)
        #expect(finalInvocation.cwd == fixture.root)
        #expect(finalInvocation.timeoutSec == 30.0)
        #expect(finalInvocation.args == [
            "run", "list",
            "--limit", "20",
            "--json", "displayTitle,workflowName,status,conclusion,headBranch,headSha,url,createdAt,updatedAt",
            "--workflow", "build.yml",
            "--branch", "main",
            "--commit", "abc123",
        ])
        #expect(summary.output.contains("Build | status=completed | conclusion=success | branch=main"))
        #expect(jsonString(summary.structuredSummary["tool"]) == ToolName.ci_read.rawValue)
        #expect(jsonString(summary.structuredSummary["provider"]) == "github")
        #expect(jsonString(summary.structuredSummary["repo"]) == "acme/demo")
        #expect(jsonString(summary.structuredSummary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary.structuredSummary["workflow"]) == "build.yml")
        #expect(jsonString(summary.structuredSummary["branch"]) == "main")
        #expect(jsonString(summary.structuredSummary["commit"]) == "abc123")
        #expect(jsonNumber(summary.structuredSummary["runs_count"]) == 1)
        #expect(jsonBool(summary.structuredSummary["preflight_checked"]) == true)

        let runs = try #require(jsonArray(summary.structuredSummary["runs"]))
        #expect(runs.count == 1)
        let firstRun = try #require(jsonObject(runs.first))
        #expect(jsonString(firstRun["display_title"]) == "Build")
        #expect(jsonString(firstRun["status"]) == "completed")
        #expect(jsonString(firstRun["conclusion"]) == "success")
    }

    @Test
    func ciTriggerBuildsSortedInputsAndSummary() throws {
        let fixture = ToolExecutorProjectFixture(name: "github-tool-ci-trigger")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: "queued workflow\n",
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let summary = try GitHubTool.ciTrigger(
            root: fixture.root,
            workflow: "release.yml",
            ref: "main",
            inputs: [
                "platform": .string("ios"),
                "dry_run": .bool(true),
                "shards": .number(2),
            ]
        )

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args).count == 3)
        let finalInvocation = try #require(invocations.last)
        #expect(finalInvocation.cwd == fixture.root)
        #expect(finalInvocation.timeoutSec == 30.0)
        #expect(finalInvocation.args == [
            "workflow", "run", "release.yml",
            "--ref", "main",
            "-f", "dry_run=true",
            "-f", "platform=ios",
            "-f", "shards=2",
        ])
        #expect(summary.output == "queued workflow")
        #expect(jsonString(summary.structuredSummary["tool"]) == ToolName.ci_trigger.rawValue)
        #expect(jsonString(summary.structuredSummary["provider"]) == "github")
        #expect(jsonString(summary.structuredSummary["repo"]) == "acme/demo")
        #expect(jsonString(summary.structuredSummary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary.structuredSummary["workflow"]) == "release.yml")
        #expect(jsonString(summary.structuredSummary["ref"]) == "main")
        #expect(jsonBool(summary.structuredSummary["preflight_checked"]) == true)

        let inputs = try #require(jsonObject(summary.structuredSummary["inputs"]))
        #expect(jsonBool(inputs["dry_run"]) == true)
        #expect(jsonString(inputs["platform"]) == "ios")
        #expect(jsonNumber(inputs["shards"]) == 2)
    }

    @Test
    func ciReadFailsClosedWhenCurrentFolderIsNotGitRepo() throws {
        let fixture = ToolExecutorProjectFixture(name: "github-tool-ci-read-not-git")
        defer { fixture.cleanup() }

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            return ProcessResult(exitCode: 0, stdout: "unexpected preflight call", stderr: "")
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let summary = try GitHubTool.ciRead(
            root: fixture.root,
            workflow: nil,
            branch: nil,
            commit: nil,
            limit: 5
        )

        #expect(recorder.invocations().isEmpty)
        #expect(summary.output == "Current folder is not a git repository.")
        #expect(jsonBool(summary.structuredSummary["ok"]) == false)
        #expect(jsonString(summary.structuredSummary["tool"]) == ToolName.ci_read.rawValue)
        #expect(jsonString(summary.structuredSummary["provider"]) == "github")
        #expect(jsonString(summary.structuredSummary["reason_code"]) == "not_git_repository")
        #expect(jsonString(summary.structuredSummary["failure_stage"]) == "workspace")
        #expect(jsonBool(summary.structuredSummary["preflight_checked"]) == true)
    }

    @Test
    func prCreateSucceedsAtExecutionLayerWithinA3DeliverAuto() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-pr-create-success")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: "created https://github.com/acme/demo/pull/42\n",
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .pr_create,
                args: [
                    "title": .string("Release train"),
                    "body": .string("Ship the queued changes"),
                    "base": .string("main"),
                    "head": .string("release/train"),
                    "draft": .bool(true),
                    "labels": .array([.string("release")]),
                    "reviewers": .array([.string("alice")]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.pr_create.rawValue)
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["repo"]) == "acme/demo")
        #expect(jsonString(summary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary["title"]) == "Release train")
        #expect(jsonString(summary["url"]) == "https://github.com/acme/demo/pull/42")
        #expect(jsonBool(summary["draft"]) == true)
        #expect(jsonBool(summary["fill"]) == false)
        #expect(jsonBool(summary["preflight_checked"]) == true)

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args) == [
            ["auth", "status"],
            ["repo", "view", "--json", "nameWithOwner,url"],
            [
                "pr", "create",
                "--title", "Release train",
                "--body", "Ship the queued changes",
                "--base", "main",
                "--head", "release/train",
                "--draft",
                "--label", "release",
                "--reviewer", "alice",
            ],
        ])
    }

    @Test
    func ciReadSucceedsAtExecutionLayerWithinA3DeliverAuto() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-ci-read-success")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach
        )

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: """
                [{"displayTitle":"Build","workflowName":"CI","status":"completed","conclusion":"success","headBranch":"main","headSha":"abc123","url":"https://github.com/acme/demo/actions/runs/1","createdAt":"2026-03-14T00:00:00Z","updatedAt":"2026-03-14T00:01:00Z"}]
                """,
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_read,
                args: [
                    "workflow": .string("build.yml"),
                    "branch": .string("main"),
                    "commit": .string("abc123"),
                    "limit": .number(99),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.ci_read.rawValue)
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["repo"]) == "acme/demo")
        #expect(jsonString(summary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary["workflow"]) == "build.yml")
        #expect(jsonString(summary["branch"]) == "main")
        #expect(jsonString(summary["commit"]) == "abc123")
        #expect(jsonNumber(summary["runs_count"]) == 1)
        #expect(jsonBool(summary["preflight_checked"]) == true)

        let runs = try #require(jsonArray(summary["runs"]))
        #expect(runs.count == 1)
        let firstRun = try #require(jsonObject(runs.first))
        #expect(jsonString(firstRun["display_title"]) == "Build")
        #expect(jsonString(firstRun["status"]) == "completed")
        #expect(jsonString(firstRun["conclusion"]) == "success")

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args) == [
            ["auth", "status"],
            ["repo", "view", "--json", "nameWithOwner,url"],
            [
                "run", "list",
                "--limit", "20",
                "--json", "displayTitle,workflowName,status,conclusion,headBranch,headSha,url,createdAt,updatedAt",
                "--workflow", "build.yml",
                "--branch", "main",
                "--commit", "abc123",
            ],
        ])
    }

    @Test
    func ciTriggerSucceedsAtExecutionLayerWithinA4FullSurface() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-ci-trigger-success")
        defer { fixture.cleanup() }
        try initGitRepo(at: fixture.root)

        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        let recorder = GitHubToolRunRecorder()
        GitHubTool.installRunOverrideForTesting { args, cwd, timeoutSec in
            recorder.record(args: args, cwd: cwd, timeoutSec: timeoutSec)
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(
                    exitCode: 0,
                    stdout: #"{"nameWithOwner":"acme/demo","url":"https://github.com/acme/demo"}"#,
                    stderr: ""
                )
            }
            return ProcessResult(
                exitCode: 0,
                stdout: "queued workflow\n",
                stderr: ""
            )
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_trigger,
                args: [
                    "workflow": .string("release.yml"),
                    "ref": .string("main"),
                    "inputs": .object([
                        "platform": .string("ios"),
                        "dry_run": .bool(true),
                        "shards": .number(2),
                    ]),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["tool"]) == ToolName.ci_trigger.rawValue)
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["repo"]) == "acme/demo")
        #expect(jsonString(summary["repo_url"]) == "https://github.com/acme/demo")
        #expect(jsonString(summary["workflow"]) == "release.yml")
        #expect(jsonString(summary["ref"]) == "main")
        #expect(jsonBool(summary["preflight_checked"]) == true)

        let inputs = try #require(jsonObject(summary["inputs"]))
        #expect(jsonBool(inputs["dry_run"]) == true)
        #expect(jsonString(inputs["platform"]) == "ios")
        #expect(jsonNumber(inputs["shards"]) == 2)

        let invocations = recorder.invocations()
        #expect(invocations.map(\.args) == [
            ["auth", "status"],
            ["repo", "view", "--json", "nameWithOwner,url"],
            [
                "workflow", "run", "release.yml",
                "--ref", "main",
                "-f", "dry_run=true",
                "-f", "platform=ios",
                "-f", "shards=2",
            ],
        ])
    }

    @Test
    func prCreateFailsClosedWhenGitHubCLIIsMissing() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-pr-create-gh-missing")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        GitHubTool.installExecutableLookupOverrideForTesting { _ in nil }
        defer { GitHubTool.resetExecutableLookupOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .pr_create,
                args: [
                    "title": .string("Release train"),
                    "body": .string("Ship it"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["reason_code"]) == "github_cli_missing")
        #expect(jsonString(summary["failure_stage"]) == "cli")
        #expect(jsonBool(summary["preflight_checked"]) == true)
    }

    @Test
    func ciReadFailsClosedWhenGitHubAuthIsMissingAtExecutionLayer() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-ci-read-gh-auth-missing")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        GitHubTool.installRunOverrideForTesting { args, _, _ in
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 1, stdout: "", stderr: "not logged into github.com")
            }
            Issue.record("Unexpected gh invocation: \(args)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected invocation")
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_read,
                args: [
                    "workflow": .string("build.yml"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["reason_code"]) == "github_auth_missing")
        #expect(jsonString(summary["failure_stage"]) == "auth")
        #expect(jsonBool(summary["preflight_checked"]) == true)
    }

    @Test
    func ciTriggerFailsClosedWhenGitHubRepoContextIsUnavailableAtExecutionLayer() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-ci-trigger-gh-repo-context-missing")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        GitHubTool.installRunOverrideForTesting { args, _, _ in
            if args == ["auth", "status"] {
                return ProcessResult(exitCode: 0, stdout: "Logged in to github.com as xt\n", stderr: "")
            }
            if args == ["repo", "view", "--json", "nameWithOwner,url"] {
                return ProcessResult(exitCode: 1, stdout: "", stderr: "failed to determine base repository")
            }
            Issue.record("Unexpected gh invocation: \(args)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected invocation")
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .ci_trigger,
                args: [
                    "workflow": .string("release.yml"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["reason_code"]) == "github_repo_context_unavailable")
        #expect(jsonString(summary["failure_stage"]) == "repo")
        #expect(jsonBool(summary["preflight_checked"]) == true)
    }

    @Test
    func prCreateFailsClosedWhenGitHubCLIExecutionFailsAtExecutionLayer() async throws {
        let fixture = ToolExecutorProjectFixture(name: "tool-executor-pr-create-gh-exec-failed")
        defer { fixture.cleanup() }

        try initGitRepo(at: fixture.root)
        try saveGovernanceConfig(
            at: fixture.root,
            executionTier: .a4OpenClaw,
            supervisorInterventionTier: .s2PeriodicReview
        )

        GitHubTool.installRunOverrideForTesting { args, _, _ in
            if args == ["auth", "status"] {
                throw NSError(
                    domain: "xterminal.tests",
                    code: 500,
                    userInfo: [NSLocalizedDescriptionKey: "gh launch failed"]
                )
            }
            Issue.record("Unexpected gh invocation: \(args)")
            return ProcessResult(exitCode: 1, stdout: "", stderr: "unexpected invocation")
        }
        defer { GitHubTool.resetRunOverrideForTesting() }

        let result = try await ToolExecutor.execute(
            call: ToolCall(
                tool: .pr_create,
                args: [
                    "title": .string("Release train"),
                    "body": .string("Ship it"),
                ]
            ),
            projectRoot: fixture.root
        )

        #expect(!result.ok)
        let summary = try #require(toolSummaryObject(result.output))
        #expect(jsonString(summary["provider"]) == "github")
        #expect(jsonString(summary["reason_code"]) == "github_cli_execution_failed")
        #expect(jsonString(summary["failure_stage"]) == "cli")
        #expect(jsonBool(summary["preflight_checked"]) == true)
    }
}
