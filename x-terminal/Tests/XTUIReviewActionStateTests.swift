import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct XTUIReviewActionStateTests {
    @Test
    func runSnapshotSuccessPublishesStatusAndRefreshesNonce() async {
        let root = URL(fileURLWithPath: "/tmp/ui-review-action-success", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        let state = XTUIReviewActionState { projectRoot in
            #expect(projectRoot == root)
            return ToolResult(
                id: "result-1",
                tool: .deviceBrowserControl,
                ok: true,
                output: "snapshot ok"
            )
        }

        var resolvedResult: ToolResult?
        await state.runSnapshot(in: ctx) { result in
            resolvedResult = result
        }

        #expect(state.isResampling == false)
        #expect(state.statusIsError == false)
        #expect(state.statusMessage == "snapshot ok")
        #expect(state.refreshNonce == 1)
        #expect(resolvedResult?.id == "result-1")
    }

    @Test
    func runSnapshotFailureKeepsNonceAndMarksError() async {
        let root = URL(fileURLWithPath: "/tmp/ui-review-action-failure", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        let state = XTUIReviewActionState { _ in
            ToolResult(
                id: "result-2",
                tool: .deviceBrowserControl,
                ok: false,
                output: "snapshot denied"
            )
        }

        var resolvedResult: ToolResult?
        await state.runSnapshot(in: ctx) { result in
            resolvedResult = result
        }

        #expect(state.isResampling == false)
        #expect(state.statusIsError == true)
        #expect(state.statusMessage == "snapshot denied")
        #expect(state.refreshNonce == 0)
        #expect(resolvedResult?.id == "result-2")
    }

    @Test
    func runSnapshotThrownErrorSurfacesFailureMessage() async {
        struct FixtureError: LocalizedError {
            var errorDescription: String? { "fixture exploded" }
        }

        let root = URL(fileURLWithPath: "/tmp/ui-review-action-error", isDirectory: true)
        let ctx = AXProjectContext(root: root)
        let state = XTUIReviewActionState { _ in
            throw FixtureError()
        }

        await state.runSnapshot(in: ctx)

        #expect(state.isResampling == false)
        #expect(state.statusIsError == true)
        #expect(state.statusMessage == "Snapshot failed: fixture exploded")
        #expect(state.refreshNonce == 0)
    }

    @Test
    func presentHistoryTogglesHistorySheet() {
        let state = XTUIReviewActionState { _ in
            ToolResult(id: "noop", tool: .deviceBrowserControl, ok: true, output: "ok")
        }

        #expect(state.showHistorySheet == false)

        state.presentHistory()

        #expect(state.showHistorySheet == true)
    }
}
