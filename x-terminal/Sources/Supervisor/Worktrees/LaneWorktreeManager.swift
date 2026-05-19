import Foundation

enum LaneWorktreeStatus: String, Codable, Equatable, CaseIterable {
    case created
    case running
    case blocked
    case readyForReview = "ready_for_review"
    case merged
    case abandoned
}

struct LaneWorktreeState: Codable, Equatable, Identifiable {
    var id: String { laneID }

    var schemaVersion: String = "xt.lane_worktree_state.v1"
    let laneID: String
    let sessionID: String
    let baseRef: String
    let branch: String
    let worktreePath: String
    let mode: XTAgentMode
    var status: LaneWorktreeStatus
    var diagnosticsRunIDs: [String]
    var diffRef: String
    let createdAtMs: Int64
    var updatedAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case laneID = "lane_id"
        case sessionID = "session_id"
        case baseRef = "base_ref"
        case branch
        case worktreePath = "worktree_path"
        case mode
        case status
        case diagnosticsRunIDs = "diagnostics_run_ids"
        case diffRef = "diff_ref"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
    }
}

struct LaneWorktreeDiffResult: Codable, Equatable {
    let laneID: String
    let diffRef: String
    let changedFiles: [String]
    let binaryFiles: [String]
    let hunkCount: Int
    let isEmpty: Bool

    enum CodingKeys: String, CodingKey {
        case laneID = "lane_id"
        case diffRef = "diff_ref"
        case changedFiles = "changed_files"
        case binaryFiles = "binary_files"
        case hunkCount = "hunk_count"
        case isEmpty = "is_empty"
    }
}

final class LaneWorktreeManager {
    private let projectRoot: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(projectRoot: URL, fileManager: FileManager = .default) {
        self.projectRoot = projectRoot.standardizedFileURL
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    func prepareLaneWorktree(
        laneID: String,
        sessionID: String,
        baseRef: String = "HEAD",
        mode: XTAgentMode
    ) throws -> LaneWorktreeState {
        let safeLaneID = safePathComponent(laneID)
        let branch = "xt/lane/\(safeLaneID)"
        let worktreeRelativePath = ".xterminal/worktrees/\(safeLaneID)"
        let worktreeURL = projectRoot.appendingPathComponent(worktreeRelativePath, isDirectory: true)
        try validateOwnedPath(worktreeURL, requiredParent: worktreesRootURL)

        try fileManager.createDirectory(at: worktreesRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: laneStateRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: diffsRootURL, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: worktreeURL.path) {
            let result = try runGit(["worktree", "add", "-q", "-b", branch, worktreeURL.path, baseRef], cwd: projectRoot)
            try requireGitSuccess(result, operation: "git worktree add")
        }

        let now = currentTimeMs()
        let state = LaneWorktreeState(
            laneID: laneID,
            sessionID: sessionID,
            baseRef: baseRef,
            branch: branch,
            worktreePath: worktreeRelativePath,
            mode: mode,
            status: .created,
            diagnosticsRunIDs: [],
            diffRef: ".xterminal/diffs/\(safeLaneID).patch",
            createdAtMs: now,
            updatedAtMs: now
        )
        try persist(state)
        return state
    }

    func loadState(laneID: String) throws -> LaneWorktreeState? {
        let url = laneStateURL(laneID: laneID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try decoder.decode(LaneWorktreeState.self, from: data)
    }

    func updateStatus(
        laneID: String,
        status: LaneWorktreeStatus,
        diagnosticsRunIDs: [String]? = nil
    ) throws -> LaneWorktreeState {
        guard var state = try loadState(laneID: laneID) else {
            throw failure("missing lane worktree state for \(laneID)")
        }
        state.status = status
        if let diagnosticsRunIDs {
            state.diagnosticsRunIDs = diagnosticsRunIDs
        }
        state.updatedAtMs = currentTimeMs()
        try persist(state)
        return state
    }

    func generateDiff(laneID: String) throws -> LaneWorktreeDiffResult {
        guard var state = try loadState(laneID: laneID) else {
            throw failure("missing lane worktree state for \(laneID)")
        }
        let worktreeURL = projectRoot.appendingPathComponent(state.worktreePath, isDirectory: true)
        try validateOwnedPath(worktreeURL, requiredParent: worktreesRootURL)

        let diff = try runGit(["diff", "--binary", state.baseRef], cwd: worktreeURL)
        try requireGitSuccess(diff, operation: "git diff")
        let patch = diff.stdout
        let plan = GitApplier.planPatch(patch)

        let diffURL = projectRoot.appendingPathComponent(state.diffRef)
        try validateOwnedPath(diffURL, requiredParent: diffsRootURL)
        try fileManager.createDirectory(at: diffURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try patch.write(to: diffURL, atomically: true, encoding: .utf8)

        state.diffRef = relativePath(for: diffURL)
        state.updatedAtMs = currentTimeMs()
        if !patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.status = .readyForReview
        }
        try persist(state)

        return LaneWorktreeDiffResult(
            laneID: laneID,
            diffRef: state.diffRef,
            changedFiles: plan.changedFiles,
            binaryFiles: plan.binaryFiles,
            hunkCount: plan.hunkCount,
            isEmpty: patch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    func stateFileURL(laneID: String) -> URL {
        laneStateURL(laneID: laneID)
    }

    private var xterminalRootURL: URL {
        projectRoot.appendingPathComponent(".xterminal", isDirectory: true)
    }

    private var worktreesRootURL: URL {
        xterminalRootURL.appendingPathComponent("worktrees", isDirectory: true)
    }

    private var laneStateRootURL: URL {
        xterminalRootURL.appendingPathComponent("lane-state", isDirectory: true)
    }

    private var diffsRootURL: URL {
        xterminalRootURL.appendingPathComponent("diffs", isDirectory: true)
    }

    private func laneStateURL(laneID: String) -> URL {
        laneStateRootURL.appendingPathComponent("\(safePathComponent(laneID)).json")
    }

    private func persist(_ state: LaneWorktreeState) throws {
        let url = laneStateURL(laneID: state.laneID)
        try validateOwnedPath(url, requiredParent: laneStateRootURL)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    private func runGit(_ args: [String], cwd: URL) throws -> ProcessResult {
        try ProcessCapture.run("/usr/bin/git", args, cwd: cwd)
    }

    private func requireGitSuccess(_ result: ProcessResult, operation: String) throws {
        guard result.exitCode == 0 else {
            throw failure("\(operation) failed\n\(result.combined)")
        }
    }

    private func validateOwnedPath(_ url: URL, requiredParent: URL) throws {
        let path = url.standardizedFileURL.path
        let parent = requiredParent.standardizedFileURL.path
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        guard path == parent || path.hasPrefix(prefix) else {
            throw failure("path escapes managed worktree storage: \(path)")
        }
    }

    private func relativePath(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let root = projectRoot.standardizedFileURL.path
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    private func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let scalars = raw.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".-_"))
        return collapsed.isEmpty ? "lane" : collapsed
    }

    private func currentTimeMs() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "xterminal.lane_worktree", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
