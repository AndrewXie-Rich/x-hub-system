import Foundation

struct LaneWorktreeMergebackConflictTriageRecord: Codable, Equatable, Identifiable {
    let id: String
    let laneID: String
    let file: String
    let reason: String
    let fixSuggestion: String

    enum CodingKeys: String, CodingKey {
        case id
        case laneID = "lane_id"
        case file
        case reason
        case fixSuggestion = "fix_suggestion"
    }
}

struct LaneWorktreeMergebackReport: Codable, Equatable {
    let schemaVersion: String
    let laneID: String
    let pass: Bool
    let preMergeOK: Bool
    let applyOK: Bool
    let postMergeOK: Bool
    let rollbackAttempted: Bool
    let rollbackOK: Bool
    let diffRef: String
    let changedFiles: [String]
    let preMergeRunID: String
    let postMergeRunID: String
    let blockedReason: String
    let reportRef: String
    let applyOutput: String
    let rollbackOutput: String
    let conflictTriage: [LaneWorktreeMergebackConflictTriageRecord]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case laneID = "lane_id"
        case pass
        case preMergeOK = "pre_merge_ok"
        case applyOK = "apply_ok"
        case postMergeOK = "post_merge_ok"
        case rollbackAttempted = "rollback_attempted"
        case rollbackOK = "rollback_ok"
        case diffRef = "diff_ref"
        case changedFiles = "changed_files"
        case preMergeRunID = "pre_merge_run_id"
        case postMergeRunID = "post_merge_run_id"
        case blockedReason = "blocked_reason"
        case reportRef = "report_ref"
        case applyOutput = "apply_output"
        case rollbackOutput = "rollback_output"
        case conflictTriage = "conflict_triage"
    }
}

final class LaneWorktreeMergebackRunner {
    func mergeback(
        laneID: String,
        projectRoot: URL,
        timeoutSec: Double = 120.0
    ) throws -> LaneWorktreeMergebackReport {
        let manager = LaneWorktreeManager(projectRoot: projectRoot)
        func finish(_ report: LaneWorktreeMergebackReport) throws -> LaneWorktreeMergebackReport {
            try persistReport(report, projectRoot: projectRoot)
            return report
        }

        guard let state = try manager.loadState(laneID: laneID) else {
            throw failure("missing lane worktree state for \(laneID)")
        }
        let worktreeRoot = projectRoot.appendingPathComponent(state.worktreePath, isDirectory: true)

        let pre = try runDiagnostics(root: worktreeRoot, phase: "pre_merge", timeoutSec: timeoutSec)
        if !pre.ok {
            _ = try manager.updateStatus(laneID: laneID, status: .blocked, diagnosticsRunIDs: [pre.runID].filter { !$0.isEmpty })
            return try finish(report(
                laneID: laneID,
                pass: false,
                preMergeOK: false,
                applyOK: false,
                postMergeOK: false,
                rollbackAttempted: false,
                rollbackOK: false,
                diffRef: state.diffRef,
                changedFiles: [],
                preMergeRunID: pre.runID,
                postMergeRunID: "",
                blockedReason: "pre_merge_diagnostics_failed",
                applyOutput: "",
                rollbackOutput: ""
            ))
        }

        let dirty = try gitStatus(projectRoot)
        guard dirty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            _ = try manager.updateStatus(laneID: laneID, status: .blocked, diagnosticsRunIDs: [pre.runID].filter { !$0.isEmpty })
            return try finish(report(
                laneID: laneID,
                pass: false,
                preMergeOK: true,
                applyOK: false,
                postMergeOK: false,
                rollbackAttempted: false,
                rollbackOK: false,
                diffRef: state.diffRef,
                changedFiles: [],
                preMergeRunID: pre.runID,
                postMergeRunID: "",
                blockedReason: "main_worktree_dirty",
                applyOutput: dirty,
                rollbackOutput: ""
            ))
        }

        let diff = try manager.generateDiff(laneID: laneID)
        let patchURL = projectRoot.appendingPathComponent(diff.diffRef)
        let patch = try String(contentsOf: patchURL, encoding: .utf8)
        if diff.isEmpty {
            _ = try manager.updateStatus(laneID: laneID, status: .merged, diagnosticsRunIDs: [pre.runID].filter { !$0.isEmpty })
            return try finish(report(
                laneID: laneID,
                pass: true,
                preMergeOK: true,
                applyOK: true,
                postMergeOK: true,
                rollbackAttempted: false,
                rollbackOK: false,
                diffRef: diff.diffRef,
                changedFiles: [],
                preMergeRunID: pre.runID,
                postMergeRunID: "",
                blockedReason: "none",
                applyOutput: "no changes",
                rollbackOutput: ""
            ))
        }

        let apply = try GitApplier.applyPatch(patch, cwd: projectRoot, threeWay: true)
        guard apply.exit == 0 else {
            _ = try manager.updateStatus(laneID: laneID, status: .blocked, diagnosticsRunIDs: [pre.runID].filter { !$0.isEmpty })
            return try finish(report(
                laneID: laneID,
                pass: false,
                preMergeOK: true,
                applyOK: false,
                postMergeOK: false,
                rollbackAttempted: false,
                rollbackOK: false,
                diffRef: diff.diffRef,
                changedFiles: diff.changedFiles,
                preMergeRunID: pre.runID,
                postMergeRunID: "",
                blockedReason: "patch_apply_failed",
                applyOutput: apply.output,
                rollbackOutput: "",
                conflictTriage: conflictTriageRecords(
                    laneID: laneID,
                    changedFiles: diff.changedFiles,
                    applyOutput: apply.output
                )
            ))
        }

        let post = try runDiagnostics(root: projectRoot, phase: "post_merge", timeoutSec: timeoutSec)
        if post.ok {
            _ = try manager.updateStatus(
                laneID: laneID,
                status: .merged,
                diagnosticsRunIDs: [pre.runID, post.runID].filter { !$0.isEmpty }
            )
            return try finish(report(
                laneID: laneID,
                pass: true,
                preMergeOK: true,
                applyOK: true,
                postMergeOK: true,
                rollbackAttempted: false,
                rollbackOK: false,
                diffRef: diff.diffRef,
                changedFiles: diff.changedFiles,
                preMergeRunID: pre.runID,
                postMergeRunID: post.runID,
                blockedReason: "none",
                applyOutput: apply.output,
                rollbackOutput: ""
            ))
        }

        let rollback = try reverseApply(patch, cwd: projectRoot)
        _ = try manager.updateStatus(
            laneID: laneID,
            status: .blocked,
            diagnosticsRunIDs: [pre.runID, post.runID].filter { !$0.isEmpty }
        )
        return try finish(report(
            laneID: laneID,
            pass: false,
            preMergeOK: true,
            applyOK: true,
            postMergeOK: false,
            rollbackAttempted: true,
            rollbackOK: rollback.exit == 0,
            diffRef: diff.diffRef,
            changedFiles: diff.changedFiles,
            preMergeRunID: pre.runID,
            postMergeRunID: post.runID,
            blockedReason: "post_merge_diagnostics_failed",
            applyOutput: apply.output,
            rollbackOutput: rollback.output
        ))
    }

    private struct DiagnosticsRun {
        let ok: Bool
        let runID: String
    }

    private func runDiagnostics(root: URL, phase: String, timeoutSec: Double) throws -> DiagnosticsRun {
        let call = ToolCall(
            tool: .projectDiagnostics,
            args: [
                "kind": .string("check"),
                "trigger": .string(phase),
                "timeout_sec": .number(timeoutSec),
            ]
        )
        let result = try XTProjectDiagnosticsTool.run(
            tool: .projectDiagnostics,
            call: call,
            projectRoot: root,
            config: AXProjectConfig.default(forProjectRoot: root)
        )
        let summary = ToolExecutor.parseStructuredToolOutput(result.output).summary
        return DiagnosticsRun(ok: result.ok, runID: stringField("run_id", in: summary))
    }

    private func gitStatus(_ root: URL) throws -> String {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["status", "--porcelain", "--untracked-files=no"],
            cwd: root,
            timeoutSec: 10.0
        )
        guard result.exitCode == 0 else {
            throw failure("git status failed\n\(result.combined)")
        }
        return result.stdout
    }

    private func reverseApply(_ patch: String, cwd: URL) throws -> (exit: Int32, output: String) {
        let result = try ProcessCapture.run(
            "/usr/bin/git",
            ["apply", "-R", "-"],
            cwd: cwd,
            stdin: patch.data(using: .utf8),
            timeoutSec: 20.0
        )
        return (result.exitCode, result.combined)
    }

    private func report(
        laneID: String,
        pass: Bool,
        preMergeOK: Bool,
        applyOK: Bool,
        postMergeOK: Bool,
        rollbackAttempted: Bool,
        rollbackOK: Bool,
        diffRef: String,
        changedFiles: [String],
        preMergeRunID: String,
        postMergeRunID: String,
        blockedReason: String,
        applyOutput: String,
        rollbackOutput: String,
        conflictTriage: [LaneWorktreeMergebackConflictTriageRecord] = []
    ) -> LaneWorktreeMergebackReport {
        LaneWorktreeMergebackReport(
            schemaVersion: "xt.lane_worktree_mergeback.v1",
            laneID: laneID,
            pass: pass,
            preMergeOK: preMergeOK,
            applyOK: applyOK,
            postMergeOK: postMergeOK,
            rollbackAttempted: rollbackAttempted,
            rollbackOK: rollbackOK,
            diffRef: diffRef,
            changedFiles: changedFiles,
            preMergeRunID: preMergeRunID,
            postMergeRunID: postMergeRunID,
            blockedReason: blockedReason,
            reportRef: reportRef(laneID: laneID),
            applyOutput: applyOutput,
            rollbackOutput: rollbackOutput,
            conflictTriage: conflictTriage
        )
    }

    private func conflictTriageRecords(
        laneID: String,
        changedFiles: [String],
        applyOutput: String
    ) -> [LaneWorktreeMergebackConflictTriageRecord] {
        let reasonLines = applyOutput
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                line.localizedCaseInsensitiveContains("error:")
                    || line.localizedCaseInsensitiveContains("conflict")
                    || line.localizedCaseInsensitiveContains("patch failed")
            }
        let reason = reasonLines.isEmpty ? "git apply failed" : reasonLines.joined(separator: " | ")
        let files = changedFiles.isEmpty ? ["(unknown)"] : changedFiles
        return files.enumerated().map { index, file in
            LaneWorktreeMergebackConflictTriageRecord(
                id: "\(laneID)-apply-conflict-\(index + 1)",
                laneID: laneID,
                file: file,
                reason: reason,
                fixSuggestion: "rebase or regenerate the lane patch against current HEAD, rerun project diagnostics in the lane worktree, then retry mergeback"
            )
        }
    }

    private func persistReport(_ report: LaneWorktreeMergebackReport, projectRoot: URL) throws {
        let url = projectRoot.appendingPathComponent(report.reportRef)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }

    private func reportRef(laneID: String) -> String {
        ".xterminal/mergeback/\(safePathComponent(laneID)).json"
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

    private func stringField(_ key: String, in value: JSONValue?) -> String {
        guard case .object(let object)? = value,
              case .string(let text)? = object[key] else {
            return ""
        }
        return text
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "xterminal.lane_worktree_mergeback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
