import Foundation
import Testing
@testable import XTerminal

struct AXProjectSkillActivityStoreMatchingTests {
    @Test
    func dispatchReconstructionIgnoresRequestIDCollisionWhenToolDiffers() {
        let raw = """
        {"type":"project_skill_call","request_id":"2","skill_id":"guarded-automation","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"created_at":2}
        """
        let call = ToolCall(
            id: "2",
            tool: .run_command,
            args: ["command": .string("swift test")]
        )

        let dispatches = AXProjectSkillActivityStore.dispatchesByRequestID(
            from: raw,
            toolCalls: [call]
        )

        #expect(dispatches["2"] == nil)
    }

    @Test
    func dispatchReconstructionUsesLatestMatchingToolCallNotLatestRequestIDOnly() {
        let raw = """
        {"type":"project_skill_call","request_id":"2","skill_id":"governed-run","tool_name":"run_command","tool_args":{"command":"swift test"},"created_at":1}
        {"type":"project_skill_call","request_id":"2","skill_id":"guarded-automation","tool_name":"device.browser.control","tool_args":{"action":"open_url","url":"https://example.com"},"created_at":2}
        """
        let call = ToolCall(
            id: "2",
            tool: .run_command,
            args: ["command": .string("swift test")]
        )

        let dispatch = AXProjectSkillActivityStore.dispatchesByRequestID(
            from: raw,
            toolCalls: [call]
        )["2"]

        #expect(dispatch?.skillId == "governed-run")
        #expect(dispatch?.toolName == ToolName.run_command.rawValue)
        #expect(dispatch?.toolCall == call)
    }

    @Test
    func latestMatchingActivityIgnoresStaleRequestIDCollision() {
        let fixture = ToolExecutorProjectFixture(name: "skill-activity-request-id-collision")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        AXProjectStore.appendRawLog(
            [
                "type": "project_skill_call",
                "request_id": "2",
                "skill_id": "guarded-automation",
                "tool_name": ToolName.deviceBrowserControl.rawValue,
                "tool_args": [
                    "action": "open_url",
                    "url": "https://example.com",
                ],
                "created_at": Date().timeIntervalSince1970,
            ],
            for: ctx
        )
        let call = ToolCall(
            id: "2",
            tool: .run_command,
            args: ["command": .string("python3 - <<'PY'\nprint('ok')\nPY")]
        )

        let item = AXProjectSkillActivityStore.latestMatchingActivity(
            ctx: ctx,
            toolCall: call
        )

        #expect(item == nil)
    }

    @Test @MainActor
    func restorePendingApprovalRefreshesStaleGovernedAssistantStub() {
        let fixture = ToolExecutorProjectFixture(name: "pending-approval-stale-stub-refresh")
        defer { fixture.cleanup() }
        let ctx = AXProjectContext(root: fixture.root)
        AXPendingActionsStore.clearAll(for: ctx)
        AXProjectStore.appendRawLog(
            [
                "type": "project_skill_call",
                "request_id": "2",
                "skill_id": "guarded-automation",
                "tool_name": ToolName.deviceBrowserControl.rawValue,
                "tool_args": [
                    "action": "open_url",
                    "url": "https://example.com",
                ],
                "created_at": Date().timeIntervalSince1970,
            ],
            for: ctx
        )

        let staleStub = "有待审批的工具操作：1 个待处理项都来自受治理 skill，当前仍受治理状态限制。"
        let seed = ChatSessionModel()
        seed.persistPendingToolApprovalForTesting(
            ctx: ctx,
            calls: [
                ToolCall(
                    id: "2",
                    tool: .run_command,
                    args: ["command": .string("python3 - <<'PY'\nprint('ok')\nPY")]
                )
            ],
            assistantStub: staleStub,
            reason: "tools",
            userText: "继续"
        )

        let restored = ChatSessionModel()
        restored.ensureLoaded(ctx: ctx)

        let pending = AXPendingActionsStore.pendingToolApproval(for: ctx)
        #expect(restored.pendingProjectSkillActivityItems()["2"] == nil)
        #expect(pending?.assistantStub != staleStub)
        #expect(pending?.assistantStub?.contains("受治理 skill") == false)
    }
}
