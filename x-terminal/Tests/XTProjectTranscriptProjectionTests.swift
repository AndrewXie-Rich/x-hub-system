import Foundation
import Testing
@testable import XTerminal

struct XTProjectTranscriptProjectionTests {
    @Test
    func projectionKeepsSupervisorDispatchCoderReplyAndReviewerNoteRoleAware() {
        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-1",
            projectName: "坦克大战",
            messages: [
                AXChatMessage(
                    role: .user,
                    sender: .supervisor,
                    content: "来自 Supervisor 的项目执行派发。\n原始用户指令：搭建骨架",
                    createdAt: 1
                ),
                AXChatMessage(
                    role: .assistant,
                    content: "Coder 已完成 index.html、style.css、main.js。",
                    createdAt: 2
                ),
                AXChatMessage(
                    role: .user,
                    sender: .reviewer,
                    content: "Reviewer: 测试证据不足，需要补一条 build 验证。",
                    createdAt: 3
                )
            ],
            pendingToolCallCount: 0,
            isSending: false,
            lastError: nil
        )

        #expect(projection.status == "latest_coder_reply_observed")
        #expect(projection.latestSupervisorDispatch?.role == "supervisor")
        #expect(projection.latestCoderReply?.role == "coder")
        #expect(projection.latestReviewerNote?.role == "reviewer")

        let block = projection.promptBlock()
        #expect(block.contains("truth_boundary=XT local project chat runtime projection only"))
        #expect(block.contains("latest_supervisor_dispatch=来自 Supervisor 的项目执行派发。"))
        #expect(block.contains("latest_coder_reply=Coder 已完成 index.html"))
        #expect(block.contains("latest_reviewer_note=Reviewer: 测试证据不足"))
        #expect(block.contains("- supervisor: 来自 Supervisor 的项目执行派发。"))
        #expect(block.contains("- coder: Coder 已完成 index.html"))
        #expect(block.contains("- reviewer: Reviewer: 测试证据不足"))
    }

    @Test
    func projectionStatusReflectsPendingToolApprovalBeforeCompletion() {
        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-2",
            projectName: "亮亮",
            messages: [
                AXChatMessage(
                    role: .user,
                    sender: .supervisor,
                    content: "来自 Supervisor 的项目执行派发。\n原始用户指令：继续修复",
                    createdAt: 1
                )
            ],
            pendingToolCallCount: 2,
            isSending: true,
            lastError: nil
        )

        #expect(projection.status == "awaiting_authorization")
        #expect(projection.promptBlock().contains("pending_tool_calls=2"))
        #expect(projection.promptBlock().contains("is_sending=true"))
    }

    @Test
    func projectionPrefersDispatchLineageOverTextPrefixes() throws {
        let dispatchLineage = AXChatMessageLineageMetadata(
            dispatchId: "xt_dispatch_project_123",
            sourceRole: "supervisor",
            targetRole: "coder",
            dispatchKind: "supervisor_to_coder",
            projectId: "project-3",
            runId: "job-1",
            launchRunId: "step-2",
            status: "dispatched",
            createdAtMs: 123
        )
        let replyLineage = dispatchLineage.coderReply(status: "completed")

        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-3",
            projectName: "声学工具",
            messages: [
                AXChatMessage(
                    role: .user,
                    content: "读取附件 app 包并逆向梳理界面能力",
                    createdAt: 1,
                    lineage: dispatchLineage
                ),
                AXChatMessage(
                    role: .assistant,
                    content: "已读取 Info.plist 和 Resources，整理出菜单与按钮。",
                    createdAt: 2,
                    lineage: replyLineage
                )
            ]
        )

        #expect(projection.latestSupervisorDispatch?.role == "supervisor")
        #expect(projection.latestSupervisorDispatch?.dispatchKind == "supervisor_to_coder")
        #expect(projection.latestCoderReply?.role == "coder")
        #expect(projection.latestDispatchId == "xt_dispatch_project_123")
        #expect(projection.latestDispatchStatus == "completed")

        let block = projection.promptBlock()
        #expect(block.contains("latest_dispatch_id=xt_dispatch_project_123"))
        #expect(block.contains("latest_dispatch_status=completed"))
        #expect(block.contains("latest_supervisor_dispatch=读取附件 app 包并逆向梳理界面能力"))
        #expect(block.contains("- supervisor [dispatch_id=xt_dispatch_project_123 kind=supervisor_to_coder status=dispatched]"))
        #expect(block.contains("- coder [dispatch_id=xt_dispatch_project_123 kind=coder_reply status=completed]"))
    }

    @Test
    func projectionPrefersHubRoleTurnMetadataOverWireRoles() {
        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-4",
            projectName: "Hub Memory",
            hubMessages: [
                XTProjectConversationMirrorMessage(
                    role: "user",
                    content: "Do the role-aware contract upgrade.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-1",
                        sourceRole: "supervisor",
                        targetRole: "coder",
                        projectId: "project-4",
                        threadKey: "xterminal_project_project-4",
                        dispatchId: "dispatch-hub-1",
                        dispatchKind: "supervisor_to_coder",
                        status: "dispatched",
                        observedAtMs: 123
                    )
                ),
                XTProjectConversationMirrorMessage(
                    role: "assistant",
                    content: "The metadata round trip is now stored in Hub.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-2",
                        sourceRole: "coder",
                        targetRole: "supervisor",
                        projectId: "project-4",
                        threadKey: "xterminal_project_project-4",
                        dispatchId: "dispatch-hub-1",
                        dispatchKind: "coder_reply",
                        status: "completed",
                        observedAtMs: 124
                    )
                )
            ]
        )

        #expect(projection.source == "hub_role_turn_metadata_projection")
        #expect(projection.latestSupervisorDispatch?.role == "supervisor")
        #expect(projection.latestCoderReply?.role == "coder")
        #expect(projection.latestDispatchId == "dispatch-hub-1")
        #expect(projection.latestDispatchStatus == "completed")

        let block = projection.promptBlock()
        #expect(block.contains("truth_boundary=Hub role-turn metadata projection"))
        #expect(block.contains("- supervisor [dispatch_id=dispatch-hub-1 kind=supervisor_to_coder status=dispatched]"))
        #expect(block.contains("- coder [dispatch_id=dispatch-hub-1 kind=coder_reply status=completed]"))
    }

    @Test
    func projectionUsesHubToolApprovalAndHeartbeatMetadata() {
        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-5",
            projectName: "Role Events",
            hubMessages: [
                XTProjectConversationMirrorMessage(
                    role: "user",
                    content: "Dispatch from Supervisor",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-1",
                        sourceRole: "supervisor",
                        targetRole: "coder",
                        projectId: "project-5",
                        threadKey: "xterminal_project_project-5",
                        dispatchId: "dispatch-hub-5",
                        dispatchKind: "supervisor_to_coder",
                        status: "dispatched",
                        observedAtMs: 123
                    )
                ),
                XTProjectConversationMirrorMessage(
                    role: "tool",
                    content: "Tool approval awaiting authorization.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-2",
                        sourceRole: "tool",
                        targetRole: "supervisor",
                        projectId: "project-5",
                        threadKey: "xterminal_project_project-5",
                        dispatchId: "dispatch-hub-5",
                        dispatchKind: "tool_approval",
                        toolCallId: "call-1",
                        status: "awaiting_authorization",
                        observedAtMs: 124
                    )
                ),
                XTProjectConversationMirrorMessage(
                    role: "system",
                    content: "Tool approval decision observed.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-3",
                        sourceRole: "user",
                        targetRole: "coder",
                        projectId: "project-5",
                        threadKey: "xterminal_project_project-5",
                        dispatchId: "dispatch-hub-5",
                        dispatchKind: "tool_approval_decision",
                        toolCallId: "call-1",
                        status: "completed",
                        observedAtMs: 125
                    )
                ),
                XTProjectConversationMirrorMessage(
                    role: "tool",
                    content: "Tool result observed.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-4",
                        sourceRole: "tool",
                        targetRole: "coder",
                        projectId: "project-5",
                        threadKey: "xterminal_project_project-5",
                        dispatchId: "dispatch-hub-5",
                        dispatchKind: "tool_result",
                        toolCallId: "call-1",
                        status: "completed",
                        observedAtMs: 126
                    )
                ),
                XTProjectConversationMirrorMessage(
                    role: "system",
                    content: "Heartbeat observed for dispatch-hub-5.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-5",
                        sourceRole: "hub",
                        targetRole: "all",
                        projectId: "project-5",
                        threadKey: "xterminal_project_project-5",
                        dispatchId: "dispatch-hub-5",
                        dispatchKind: "heartbeat",
                        status: "observed",
                        observedAtMs: 127
                    )
                )
            ],
            pendingToolCallCount: 0
        )

        #expect(projection.status == "tool_result_observed")
        #expect(projection.latestToolApproval?.role == "tool")
        #expect(projection.latestToolApproval?.dispatchId == "dispatch-hub-5")
        #expect(projection.latestToolApproval?.status == "awaiting_authorization")
        #expect(projection.latestToolApprovalDecision?.role == "user")
        #expect(projection.latestToolApprovalDecision?.status == "completed")
        #expect(projection.latestToolResult?.role == "tool")
        #expect(projection.latestToolResult?.status == "completed")
        #expect(projection.latestHeartbeat?.role == "hub")
        #expect(projection.latestDispatchId == "dispatch-hub-5")
        #expect(projection.latestDispatchStatus == "completed")

        let block = projection.promptBlock()
        #expect(block.contains("latest_tool_approval=Tool approval awaiting authorization."))
        #expect(block.contains("latest_tool_approval_decision=Tool approval decision observed."))
        #expect(block.contains("latest_tool_result=Tool result observed."))
        #expect(block.contains("latest_heartbeat=Heartbeat observed for dispatch-hub-5."))
        #expect(block.contains("- tool [dispatch_id=dispatch-hub-5 kind=tool_approval status=awaiting_authorization]"))
        #expect(block.contains("- user [dispatch_id=dispatch-hub-5 kind=tool_approval_decision status=completed]"))
        #expect(block.contains("- tool [dispatch_id=dispatch-hub-5 kind=tool_result status=completed]"))
        #expect(block.contains("- hub [dispatch_id=dispatch-hub-5 kind=heartbeat status=observed]"))
    }

    @Test
    func projectionStatusCanComeFromHubToolApprovalWhenLocalPendingCountIsUnavailable() {
        let projection = XTProjectTranscriptProjection.build(
            projectId: "project-6",
            projectName: "Hub Pending",
            hubMessages: [
                XTProjectConversationMirrorMessage(
                    role: "tool",
                    content: "Tool approval awaiting authorization.",
                    turnMetadata: XTProjectConversationTurnMetadata(
                        clientMessageId: "hub-msg-1",
                        sourceRole: "tool",
                        targetRole: "supervisor",
                        projectId: "project-6",
                        threadKey: "xterminal_project_project-6",
                        dispatchId: "dispatch-hub-6",
                        dispatchKind: "tool_approval",
                        status: "awaiting_authorization",
                        observedAtMs: 123
                    )
                )
            ],
            pendingToolCallCount: 0
        )

        #expect(projection.status == "awaiting_authorization")
        #expect(projection.latestDispatchStatus == "awaiting_authorization")
    }
}
