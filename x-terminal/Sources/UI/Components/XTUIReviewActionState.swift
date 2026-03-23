import Foundation
import SwiftUI

@MainActor
final class XTUIReviewActionState: ObservableObject {
    typealias SnapshotExecutor = (URL) async throws -> ToolResult

    @Published var showHistorySheet = false
    @Published var isResampling = false
    @Published var statusMessage = ""
    @Published var statusIsError = false
    @Published private(set) var refreshNonce = 0

    private let executeSnapshot: SnapshotExecutor

    init(
        executeSnapshot: @escaping SnapshotExecutor = XTUIReviewActionState.liveExecuteSnapshot
    ) {
        self.executeSnapshot = executeSnapshot
    }

    func presentHistory() {
        showHistorySheet = true
    }

    func runSnapshot(
        in ctx: AXProjectContext,
        onSnapshotResolved: ((ToolResult) -> Void)? = nil
    ) async {
        guard !isResampling else { return }

        isResampling = true
        statusMessage = ""
        statusIsError = false

        let result: ToolResult
        do {
            result = try await executeSnapshot(ctx.root)
        } catch {
            statusMessage = "Snapshot failed: \(error.localizedDescription)"
            statusIsError = true
            isResampling = false
            return
        }

        if result.ok {
            refreshNonce += 1
        }
        onSnapshotResolved?(result)
        statusMessage = ToolResultHumanSummary.body(for: result)
        statusIsError = !result.ok
        isResampling = false
    }

    private static func liveExecuteSnapshot(projectRoot: URL) async throws -> ToolResult {
        try await ToolExecutor.execute(
            call: ToolCall(
                tool: .deviceBrowserControl,
                args: [
                    "action": .string("snapshot"),
                    "probe_depth": .string("standard")
                ]
            ),
            projectRoot: projectRoot
        )
    }
}
