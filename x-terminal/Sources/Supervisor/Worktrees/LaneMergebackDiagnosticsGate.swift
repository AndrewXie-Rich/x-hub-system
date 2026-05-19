import Foundation

struct LaneMergebackDiagnosticsGateReport: Codable, Equatable {
    let schemaVersion: String
    let laneID: String
    let pass: Bool
    let preMergeOK: Bool
    let postMergeOK: Bool
    let preMergeRunID: String
    let postMergeRunID: String
    let preMergeDiagnosticsRef: String
    let postMergeDiagnosticsRef: String
    let blockedReason: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case laneID = "lane_id"
        case pass
        case preMergeOK = "pre_merge_ok"
        case postMergeOK = "post_merge_ok"
        case preMergeRunID = "pre_merge_run_id"
        case postMergeRunID = "post_merge_run_id"
        case preMergeDiagnosticsRef = "pre_merge_diagnostics_ref"
        case postMergeDiagnosticsRef = "post_merge_diagnostics_ref"
        case blockedReason = "blocked_reason"
    }
}

final class LaneMergebackDiagnosticsGate {
    func run(
        laneID: String,
        projectRoot: URL,
        timeoutSec: Double = 120.0
    ) throws -> LaneMergebackDiagnosticsGateReport {
        let manager = LaneWorktreeManager(projectRoot: projectRoot)
        guard let state = try manager.loadState(laneID: laneID) else {
            throw failure("missing lane worktree state for \(laneID)")
        }

        let worktreeRoot = projectRoot.appendingPathComponent(state.worktreePath, isDirectory: true)
        let pre = try runDiagnostics(
            root: worktreeRoot,
            phase: "pre_merge",
            timeoutSec: timeoutSec
        )
        let post = try runDiagnostics(
            root: projectRoot,
            phase: "post_merge",
            timeoutSec: timeoutSec
        )

        let runIDs = [pre.runID, post.runID].filter { !$0.isEmpty }
        _ = try manager.updateStatus(
            laneID: laneID,
            status: pre.ok && post.ok ? .readyForReview : .blocked,
            diagnosticsRunIDs: runIDs
        )

        let pass = pre.ok && post.ok
        return LaneMergebackDiagnosticsGateReport(
            schemaVersion: "xt.lane_mergeback_diagnostics_gate.v1",
            laneID: laneID,
            pass: pass,
            preMergeOK: pre.ok,
            postMergeOK: post.ok,
            preMergeRunID: pre.runID,
            postMergeRunID: post.runID,
            preMergeDiagnosticsRef: pre.ref,
            postMergeDiagnosticsRef: post.ref,
            blockedReason: pass ? "none" : "diagnostics_failed"
        )
    }

    private struct DiagnosticsRun {
        let ok: Bool
        let runID: String
        let ref: String
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
        let runID = stringField("run_id", in: summary)
        let ref = runID.isEmpty ? "" : ".xterminal/diagnostics/\(runID).json"
        return DiagnosticsRun(ok: result.ok, runID: runID, ref: ref)
    }

    private func stringField(_ key: String, in value: JSONValue?) -> String {
        guard case .object(let object)? = value,
              case .string(let text)? = object[key] else {
            return ""
        }
        return text
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "xterminal.lane_mergeback_diagnostics_gate", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
