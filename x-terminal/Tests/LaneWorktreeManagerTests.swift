import Foundation
import Testing
@testable import XTerminal

struct LaneWorktreeManagerTests {
    @Test
    func prepareLaneWorktreeCreatesGitWorktreeAndPersistsState() throws {
        let fixture = ToolExecutorProjectFixture(name: "lane-worktree-create")
        defer { fixture.cleanup() }

        try seedCommittedRepo(at: fixture.root)
        let manager = LaneWorktreeManager(projectRoot: fixture.root)

        let state = try manager.prepareLaneWorktree(
            laneID: "lane-1",
            sessionID: "session-1",
            mode: .code
        )

        #expect(state.schemaVersion == "xt.lane_worktree_state.v1")
        #expect(state.laneID == "lane-1")
        #expect(state.sessionID == "session-1")
        #expect(state.baseRef == "HEAD")
        #expect(state.branch == "xt/lane/lane-1")
        #expect(state.worktreePath == ".xterminal/worktrees/lane-1")
        #expect(state.mode == .code)
        #expect(state.status == .created)

        let loaded = try #require(try manager.loadState(laneID: "lane-1"))
        #expect(loaded == state)

        let worktreeURL = fixture.root.appendingPathComponent(state.worktreePath, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: worktreeURL.appendingPathComponent("README.md").path))
        let branch = try runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: worktreeURL)
        try requireGitSuccess(branch, "git rev-parse")
        #expect(branch.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "xt/lane/lane-1")
    }

    @Test
    func generateDiffPersistsLanePatchWithoutTouchingMainWorktree() throws {
        let fixture = ToolExecutorProjectFixture(name: "lane-worktree-diff")
        defer { fixture.cleanup() }

        try seedCommittedRepo(at: fixture.root)
        let manager = LaneWorktreeManager(projectRoot: fixture.root)
        let state = try manager.prepareLaneWorktree(
            laneID: "lane-review",
            sessionID: "session-1",
            mode: .code
        )
        let worktreeURL = fixture.root.appendingPathComponent(state.worktreePath, isDirectory: true)
        try "new\n".write(
            to: worktreeURL.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )

        let diff = try manager.generateDiff(laneID: "lane-review")

        #expect(!diff.isEmpty)
        #expect(diff.changedFiles == ["README.md"])
        #expect(diff.binaryFiles.isEmpty)
        #expect(diff.hunkCount == 1)
        #expect(diff.diffRef == ".xterminal/diffs/lane-review.patch")

        let updatedState = try #require(try manager.loadState(laneID: "lane-review"))
        #expect(updatedState.status == .readyForReview)
        #expect(updatedState.diffRef == diff.diffRef)

        let rootReadme = try String(contentsOf: fixture.root.appendingPathComponent("README.md"), encoding: .utf8)
        #expect(rootReadme == "old\n")
        let patch = try String(contentsOf: fixture.root.appendingPathComponent(diff.diffRef), encoding: .utf8)
        #expect(patch.contains("diff --git a/README.md b/README.md"))
    }

    @Test
    func unsafeLaneIDIsConfinedToManagedWorktreeStorage() throws {
        let fixture = ToolExecutorProjectFixture(name: "lane-worktree-safe-id")
        defer { fixture.cleanup() }

        try seedCommittedRepo(at: fixture.root)
        let manager = LaneWorktreeManager(projectRoot: fixture.root)

        let state = try manager.prepareLaneWorktree(
            laneID: "../unsafe lane",
            sessionID: "session-1",
            mode: .debug
        )

        #expect(state.laneID == "../unsafe lane")
        #expect(state.worktreePath == ".xterminal/worktrees/unsafe-lane")
        #expect(state.branch == "xt/lane/unsafe-lane")
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(state.worktreePath).path))
        #expect(FileManager.default.fileExists(atPath: manager.stateFileURL(laneID: "../unsafe lane").path))
    }

    @Test
    func mergebackDiagnosticsGateBlocksWhenLaneWorktreeFailsPreMergeDiagnostics() throws {
        let fixture = ToolExecutorProjectFixture(name: "lane-mergeback-diagnostics")
        defer { fixture.cleanup() }

        try seedCommittedSwiftPackageRepo(at: fixture.root)
        let manager = LaneWorktreeManager(projectRoot: fixture.root)
        let state = try manager.prepareLaneWorktree(
            laneID: "lane-diagnostics",
            sessionID: "session-1",
            mode: .code
        )
        let worktreeURL = fixture.root.appendingPathComponent(state.worktreePath, isDirectory: true)
        try """
        let value: Int = "not an int"
        print(value)
        """.write(
            to: worktreeURL.appendingPathComponent("Sources/GateFixture/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let report = try LaneMergebackDiagnosticsGate().run(
            laneID: "lane-diagnostics",
            projectRoot: fixture.root,
            timeoutSec: 120
        )

        #expect(report.pass == false)
        #expect(report.preMergeOK == false)
        #expect(report.postMergeOK == true)
        #expect(report.blockedReason == "diagnostics_failed")
        #expect(report.preMergeDiagnosticsRef.hasPrefix(".xterminal/diagnostics/diag-"))
        #expect(report.postMergeDiagnosticsRef.hasPrefix(".xterminal/diagnostics/diag-"))

        let updated = try #require(try manager.loadState(laneID: "lane-diagnostics"))
        #expect(updated.status == .blocked)
        #expect(updated.diagnosticsRunIDs == [report.preMergeRunID, report.postMergeRunID])
    }

    @Test
    func mergebackRunnerAppliesLanePatchAndMarksLaneMergedWhenDiagnosticsPass() throws {
        let fixture = ToolExecutorProjectFixture(name: "lane-mergeback-runner")
        defer { fixture.cleanup() }

        try seedCommittedSwiftPackageRepo(at: fixture.root)
        let manager = LaneWorktreeManager(projectRoot: fixture.root)
        let state = try manager.prepareLaneWorktree(
            laneID: "lane-merge",
            sessionID: "session-1",
            mode: .code
        )
        let worktreeURL = fixture.root.appendingPathComponent(state.worktreePath, isDirectory: true)
        try """
        print("merged")
        """.write(
            to: worktreeURL.appendingPathComponent("Sources/GateFixture/main.swift"),
            atomically: true,
            encoding: .utf8
        )

        let report = try LaneWorktreeMergebackRunner().mergeback(
            laneID: "lane-merge",
            projectRoot: fixture.root,
            timeoutSec: 120
        )

        #expect(report.pass)
        #expect(report.preMergeOK)
        #expect(report.applyOK)
        #expect(report.postMergeOK)
        #expect(report.rollbackAttempted == false)
        #expect(report.changedFiles == ["Sources/GateFixture/main.swift"])
        #expect(report.diffRef == ".xterminal/diffs/lane-merge.patch")

        let updated = try String(
            contentsOf: fixture.root.appendingPathComponent("Sources/GateFixture/main.swift"),
            encoding: .utf8
        )
        #expect(updated.contains("merged"))

        let updatedState = try #require(try manager.loadState(laneID: "lane-merge"))
        #expect(updatedState.status == .merged)
        #expect(updatedState.diagnosticsRunIDs == [report.preMergeRunID, report.postMergeRunID])
    }

    private func seedCommittedRepo(at root: URL) throws {
        try requireGitSuccess(try runGit(["init", "-q"], cwd: root), "git init")
        try requireGitSuccess(try runGit(["config", "user.email", "xt-tests@example.com"], cwd: root), "git config user.email")
        try requireGitSuccess(try runGit(["config", "user.name", "XT Tests"], cwd: root), "git config user.name")
        try "old\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(try runGit(["add", "README.md"], cwd: root), "git add")
        try requireGitSuccess(try runGit(["commit", "-q", "-m", "base"], cwd: root), "git commit")
    }

    private func seedCommittedSwiftPackageRepo(at root: URL) throws {
        try requireGitSuccess(try runGit(["init", "-q"], cwd: root), "git init")
        try requireGitSuccess(try runGit(["config", "user.email", "xt-tests@example.com"], cwd: root), "git config user.email")
        try requireGitSuccess(try runGit(["config", "user.name", "XT Tests"], cwd: root), "git config user.name")
        try """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "GateFixture",
            targets: [
                .executableTarget(name: "GateFixture", path: "Sources/GateFixture")
            ]
        )
        """.write(
            to: root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )
        let sourceDir = root.appendingPathComponent("Sources/GateFixture", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try """
        print("ok")
        """.write(
            to: sourceDir.appendingPathComponent("main.swift"),
            atomically: true,
            encoding: .utf8
        )
        try requireGitSuccess(try runGit(["add", "."], cwd: root), "git add")
        try requireGitSuccess(try runGit(["commit", "-q", "-m", "base"], cwd: root), "git commit")
    }

    private func runGit(_ args: [String], cwd: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", args, cwd: cwd)
    }

    private func requireGitSuccess(_ result: ProcessResult, _ operation: String) throws {
        guard result.exitCode == 0 else {
            throw NSError(
                domain: "LaneWorktreeManagerTests",
                code: Int(result.exitCode),
                userInfo: [NSLocalizedDescriptionKey: "\(operation) failed\n\(result.combined)"]
            )
        }
    }
}
