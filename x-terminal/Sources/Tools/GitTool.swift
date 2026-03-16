import Foundation

struct GitToolFailure: LocalizedError, Equatable, Sendable {
    var reasonCode: String
    var failureStage: String
    var detail: String
    var diagnostic: String?

    var errorDescription: String? { detail }
}

struct GitCommitRunSummary: Equatable {
    var result: ProcessResult
    var inferredFailure: GitToolFailure?
}

struct GitPushRunSummary: Equatable {
    var result: ProcessResult
    var remote: String
    var branch: String
    var inferredFailure: GitToolFailure?
}

enum GitTool {
    static func isGitRepo(root: URL) -> Bool {
        let fm = FileManager.default
        var candidate = root.standardizedFileURL.path

        while true {
            let gitPath = (candidate as NSString).appendingPathComponent(".git")
            if fm.fileExists(atPath: gitPath) {
                return true
            }

            let parent = (candidate as NSString).deletingLastPathComponent
            if parent.isEmpty || parent == candidate {
                return false
            }
            candidate = parent
        }
    }

    static func status(root: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", ["status", "--porcelain=v1"], cwd: root, timeoutSec: 10.0)
    }

    static func diff(root: URL, cached: Bool = false) throws -> ProcessResult {
        let args = cached ? ["diff", "--cached"] : ["diff"]
        return try ProcessCapture.run("/usr/bin/git", args, cwd: root, timeoutSec: 20.0)
    }

    static func commit(
        root: URL,
        message: String,
        all: Bool = false,
        allowEmpty: Bool = false,
        paths: [String] = []
    ) throws -> GitCommitRunSummary {
        guard isGitRepo(root: root) else {
            throw GitToolFailure(
                reasonCode: "not_git_repository",
                failureStage: "workspace",
                detail: "Current folder is not a git repository.",
                diagnostic: nil
            )
        }
        let guardedPaths = try guardedGitPaths(paths, root: root)
        try requireCommitArgumentCompatibility(all: all, paths: guardedPaths)
        try requireTrackedCommitPaths(root: root, paths: guardedPaths)
        try requireCommitIdentity(root: root)
        if !allowEmpty {
            try requireCommitChanges(root: root, all: all, paths: guardedPaths)
        }

        var args = ["commit", "-m", message]
        if all {
            args.append("-a")
        }
        if allowEmpty {
            args.append("--allow-empty")
        }
        if !guardedPaths.isEmpty {
            args.append("--")
            args.append(contentsOf: guardedPaths)
        }
        let result = try ProcessCapture.run("/usr/bin/git", args, cwd: root, timeoutSec: 30.0)
        return GitCommitRunSummary(
            result: result,
            inferredFailure: inferCommitFailure(result)
        )
    }

    static func push(
        root: URL,
        remote: String? = nil,
        branch: String? = nil,
        setUpstream: Bool = false
    ) throws -> GitPushRunSummary {
        guard isGitRepo(root: root) else {
            throw GitToolFailure(
                reasonCode: "not_git_repository",
                failureStage: "workspace",
                detail: "Current folder is not a git repository.",
                diagnostic: nil
            )
        }

        let resolvedBranch = try resolvedPushBranch(root: root, branch: branch)
        let resolvedRemote = try resolvedPushRemote(root: root, remote: remote, branch: resolvedBranch)
        var args = ["push"]
        if setUpstream {
            args.append("--set-upstream")
        }
        args.append(resolvedRemote)
        args.append(resolvedBranch)
        let result = try ProcessCapture.run("/usr/bin/git", args, cwd: root, timeoutSec: 60.0)
        return GitPushRunSummary(
            result: result,
            remote: resolvedRemote,
            branch: resolvedBranch,
            inferredFailure: inferPushFailure(result, remote: resolvedRemote, branch: resolvedBranch)
        )
    }

    static func currentBranch(root: URL) throws -> String {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["rev-parse", "--abbrev-ref", "HEAD"],
            cwd: root,
            timeoutSec: 10.0
        )
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func diffFile(root: URL, path: String) throws -> ProcessResult {
        // Path is passed to git; still guard it's inside the project root.
        let url = FileTool.resolvePath(path, projectRoot: root)
        try PathGuard.requireInside(root: root, target: url)

        return try ProcessCapture.run("/usr/bin/git", ["diff", "--", url.path], cwd: root, timeoutSec: 20.0)
    }

    private static func guardedGitPaths(_ paths: [String], root: URL) throws -> [String] {
        try paths.map { raw in
            let url = FileTool.resolvePath(raw, projectRoot: root)
            try PathGuard.requireInside(root: root, target: url)
            return url.path
        }
    }

    private static func requireCommitArgumentCompatibility(all: Bool, paths: [String]) throws {
        guard !(all && !paths.isEmpty) else {
            throw GitToolFailure(
                reasonCode: "git_commit_paths_with_all_unsupported",
                failureStage: "args",
                detail: "git_commit cannot combine all=true with explicit paths.",
                diagnostic: nil
            )
        }
    }

    private static func requireCommitIdentity(root: URL) throws {
        let userName = try configuredGitValue(root: root, key: "user.name")
        let userEmail = try configuredGitValue(root: root, key: "user.email")
        guard userName != nil, userEmail != nil else {
            throw GitToolFailure(
                reasonCode: "git_identity_missing",
                failureStage: "identity",
                detail: "Git user identity is not configured for this repository.",
                diagnostic: nil
            )
        }
    }

    private static func requireTrackedCommitPaths(root: URL, paths: [String]) throws {
        guard !paths.isEmpty else { return }

        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["ls-files", "--error-unmatch", "--"] + paths,
            cwd: root,
            timeoutSec: 10.0
        )
        guard result.exitCode == 0 else {
            throw GitToolFailure(
                reasonCode: "git_commit_pathspec_invalid",
                failureStage: "paths",
                detail: "One or more commit paths are not tracked by git in this repository.",
                diagnostic: normalizedDiagnostic(result.combined)
            )
        }
    }

    private static func requireCommitChanges(root: URL, all: Bool, paths: [String]) throws {
        let hasChanges: Bool
        if !paths.isEmpty {
            hasChanges = try gitStatusEntries(root: root, paths: paths).contains(where: { !$0.isUntracked })
        } else if all {
            let statusEntries = try gitStatusEntries(root: root)
            hasChanges = statusEntries.contains(where: { !$0.isUntracked })
        } else {
            let statusEntries = try gitStatusEntries(root: root)
            hasChanges = statusEntries.contains(where: \.hasStagedChange)
        }

        guard hasChanges else {
            let detail: String
            if !paths.isEmpty {
                detail = "There are no tracked changes to commit for the requested paths."
            } else if all {
                detail = "There are no tracked changes ready to commit."
            } else {
                detail = "There are no staged changes ready to commit."
            }
            throw GitToolFailure(
                reasonCode: "git_commit_no_changes",
                failureStage: "commit",
                detail: detail,
                diagnostic: nil
            )
        }
    }

    private static func resolvedPushBranch(root: URL, branch: String?) throws -> String {
        if let branch = branch?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
            return branch
        }
        let current = try currentBranch(root: root).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !current.isEmpty, current != "HEAD" else {
            throw GitToolFailure(
                reasonCode: "git_push_detached_head",
                failureStage: "branch",
                detail: "git_push requires a branch when HEAD is detached",
                diagnostic: nil
            )
        }
        return current
    }

    private static func resolvedPushRemote(root: URL, remote: String?, branch: String) throws -> String {
        if let remote = remote?.trimmingCharacters(in: .whitespacesAndNewlines), !remote.isEmpty {
            return remote
        }

        if let branchRemote = try configuredBranchRemote(root: root, branch: branch) {
            return branchRemote
        }

        let remotes = try configuredRemotes(root: root)
        if remotes.contains("origin") {
            return "origin"
        }
        if remotes.count == 1, let only = remotes.first {
            return only
        }
        if remotes.isEmpty {
            throw GitToolFailure(
                reasonCode: "git_push_remote_missing",
                failureStage: "remote",
                detail: "git_push requires a configured remote",
                diagnostic: nil
            )
        }
        throw GitToolFailure(
            reasonCode: "git_push_remote_ambiguous",
            failureStage: "remote",
            detail: "git_push requires an explicit remote because multiple remotes are configured",
            diagnostic: nil
        )
    }

    private static func configuredBranchRemote(root: URL, branch: String) throws -> String? {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["config", "--get", "branch.\(branch).remote"],
            cwd: root,
            timeoutSec: 10.0
        )
        guard result.exitCode == 0 else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func configuredRemotes(root: URL) throws -> [String] {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["remote"],
            cwd: root,
            timeoutSec: 10.0
        )
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func configuredGitValue(root: URL, key: String) throws -> String? {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["config", "--get", key],
            cwd: root,
            timeoutSec: 10.0
        )
        guard result.exitCode == 0 else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private struct GitStatusEntry {
        var raw: String

        var isUntracked: Bool {
            raw.hasPrefix("??")
        }

        var hasStagedChange: Bool {
            guard let first = raw.first else { return false }
            return first != " " && first != "?"
        }
    }

    private static func gitStatusEntries(root: URL, paths: [String] = []) throws -> [GitStatusEntry] {
        let result: ProcessResult
        if paths.isEmpty {
            result = try status(root: root)
        } else {
            result = try ProcessCapture.run(
                "/usr/bin/git",
                ["status", "--porcelain=v1", "--"] + paths,
                cwd: root,
                timeoutSec: 10.0
            )
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { GitStatusEntry(raw: String($0)) }
    }

    private static func inferCommitFailure(_ result: ProcessResult) -> GitToolFailure? {
        guard result.exitCode != 0 else { return nil }
        let combined = normalizedDiagnostic(result.combined)
        let lower = combined.lowercased()

        if lower.contains("author identity unknown")
            || lower.contains("unable to auto-detect email address")
            || lower.contains("please tell me who you are") {
            return GitToolFailure(
                reasonCode: "git_identity_missing",
                failureStage: "identity",
                detail: "Git user identity is not configured for this repository.",
                diagnostic: combined
            )
        }
        if lower.contains("with -a does not make sense") {
            return GitToolFailure(
                reasonCode: "git_commit_paths_with_all_unsupported",
                failureStage: "args",
                detail: "git_commit cannot combine all=true with explicit paths.",
                diagnostic: combined
            )
        }
        if lower.contains("nothing to commit")
            || lower.contains("no changes added to commit")
            || lower.contains("nothing added to commit") {
            return GitToolFailure(
                reasonCode: "git_commit_no_changes",
                failureStage: "commit",
                detail: "There are no staged changes ready to commit.",
                diagnostic: combined
            )
        }
        if lower.contains("pathspec") && lower.contains("did not match") {
            return GitToolFailure(
                reasonCode: "git_commit_pathspec_invalid",
                failureStage: "paths",
                detail: "One or more commit paths are not tracked by git in this repository.",
                diagnostic: combined
            )
        }
        if lower.contains("not a git repository") {
            return GitToolFailure(
                reasonCode: "not_git_repository",
                failureStage: "workspace",
                detail: "Current folder is not a git repository.",
                diagnostic: combined
            )
        }
        return GitToolFailure(
            reasonCode: "git_commit_failed",
            failureStage: "commit",
            detail: "git commit failed.",
            diagnostic: combined
        )
    }

    private static func inferPushFailure(
        _ result: ProcessResult,
        remote: String,
        branch: String
    ) -> GitToolFailure? {
        guard result.exitCode != 0 else { return nil }
        let combined = normalizedDiagnostic(result.combined)
        let lower = combined.lowercased()

        if lower.contains("src refspec \(branch.lowercased()) does not match any") {
            return GitToolFailure(
                reasonCode: "git_push_branch_missing",
                failureStage: "branch",
                detail: "The local branch to push does not exist yet.",
                diagnostic: combined
            )
        }
        if lower.contains("does not appear to be a git repository")
            || lower.contains("could not read from remote repository") {
            return GitToolFailure(
                reasonCode: "git_push_remote_unreachable",
                failureStage: "remote",
                detail: "XT could not reach the configured git remote.",
                diagnostic: combined
            )
        }
        if lower.contains("remote rejected")
            || lower.contains("pre-receive hook declined")
            || lower.contains("hook declined") {
            return GitToolFailure(
                reasonCode: "git_push_remote_rejected",
                failureStage: "push",
                detail: "The remote rejected this push.",
                diagnostic: combined
            )
        }
        if lower.contains("updates were rejected because the remote contains work that you do")
            || lower.contains("non-fast-forward")
            || lower.contains("failed to push some refs") {
            return GitToolFailure(
                reasonCode: "git_push_non_fast_forward",
                failureStage: "push",
                detail: "The push was rejected because the remote branch has diverged.",
                diagnostic: combined
            )
        }
        if lower.contains("not a git repository") {
            return GitToolFailure(
                reasonCode: "not_git_repository",
                failureStage: "workspace",
                detail: "Current folder is not a git repository.",
                diagnostic: combined
            )
        }
        return GitToolFailure(
            reasonCode: "git_push_failed",
            failureStage: "push",
            detail: "git push failed for \(remote) \(branch).",
            diagnostic: combined
        )
    }

    private static func normalizedDiagnostic(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(no output)" : trimmed
    }
}
