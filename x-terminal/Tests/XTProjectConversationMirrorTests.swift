import Foundation
import Testing
@testable import XTerminal

struct XTProjectConversationMirrorTests {
    @Test
    func projectThreadKeyUsesProjectScopeNamespace() {
        #expect(
            XTProjectConversationMirror.projectThreadKey(projectId: " abc-123 ")
                == "xterminal_project_abc-123"
        )
        #expect(
            XTProjectConversationMirror.projectThreadKey(projectId: "")
                == "xterminal_project_unknown"
        )
    }

    @Test
    func requestIDIsDeterministicForProjectAndTimestamp() {
        let req = XTProjectConversationMirror.requestID(
            projectId: "12345678-1234-1234-1234-1234567890ab",
            createdAt: 1_772_200_000.125
        )

        #expect(req == "xterminal_turn_123456781234_1772200000125")
    }

    @Test
    func dispatchIDPrefersSupervisorRunAndLaunchRunWhenPresent() {
        let id = AXChatMessageLineageMetadata.makeDispatchId(
            projectId: "Project ABC",
            runId: "job-123",
            launchRunId: "step-002",
            createdAtMs: 1_772_200_000_125
        )

        #expect(id == "xt_dispatch_project_abc_job_123_step_002")
        #expect(!id.contains("1772200000125"))
    }

    @Test
    func messagesTrimAndTruncateLargeConversationContent() {
        let large = String(repeating: "a", count: XTProjectConversationMirror.maxCharsPerMessage + 32)
        let mirrored = XTProjectConversationMirror.messages(
            userText: "  hello  ",
            assistantText: large
        )

        #expect(mirrored.count == 2)
        #expect(mirrored[0] == XTProjectConversationMirrorMessage(role: "user", content: "hello"))
        #expect(mirrored[0].turnMetadata == nil)
        #expect(mirrored[1].role == "assistant")
        #expect(mirrored[1].content.hasSuffix("[x-terminal] truncated"))
        #expect(mirrored[1].content.count > XTProjectConversationMirror.maxCharsPerMessage)
    }

    @Test
    func roleAwareMessagesUseSupervisorLineageForDispatchAndCoderReply() {
        let lineage = AXChatMessageLineageMetadata(
            dispatchId: "xt_dispatch_project_abc_1772200000125",
            sourceRole: "supervisor",
            targetRole: "coder",
            dispatchKind: "supervisor_to_coder",
            projectId: "project-abc",
            runId: "job-1",
            launchRunId: "step-1",
            status: "dispatched",
            createdAtMs: 1_772_200_000_125
        )

        let mirrored = XTProjectConversationMirror.roleAwareMessages(
            projectId: "project-abc",
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: "project-abc"),
            userText: "继续实现 Hub role-aware memory contract",
            assistantText: "Coder 已完成协议与 Hub 写入。",
            createdAt: 1_772_200_000.125,
            userSender: .supervisor,
            userLineage: lineage,
            assistantLineage: lineage.coderReply(status: "completed")
        )

        #expect(mirrored.count == 2)
        #expect(mirrored[0].turnMetadata?.schemaVersion == "xhub.role_turn_metadata.v1")
        #expect(mirrored[0].turnMetadata?.sourceRole == "supervisor")
        #expect(mirrored[0].turnMetadata?.targetRole == "coder")
        #expect(mirrored[0].turnMetadata?.dispatchKind == "supervisor_to_coder")
        #expect(mirrored[0].turnMetadata?.dispatchId == "xt_dispatch_project_abc_1772200000125")
        #expect(mirrored[1].turnMetadata?.sourceRole == "coder")
        #expect(mirrored[1].turnMetadata?.targetRole == "supervisor")
        #expect(mirrored[1].turnMetadata?.dispatchId == "xt_dispatch_project_abc_1772200000125")
        #expect(mirrored[1].turnMetadata?.status == "completed")
    }

    @Test
    func roleAwareMessagesGenerateFallbackDispatchIDWhenLineageIsMissing() {
        let mirrored = XTProjectConversationMirror.roleAwareMessages(
            projectId: "project-fallback",
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: "project-fallback"),
            userText: "Reviewer: 补一条 smoke test",
            assistantText: "",
            createdAt: 1_772_200_000.125,
            userSender: .reviewer
        )

        #expect(mirrored.count == 1)
        #expect(mirrored[0].turnMetadata?.sourceRole == "reviewer")
        #expect(mirrored[0].turnMetadata?.targetRole == "coder")
        #expect(mirrored[0].turnMetadata?.dispatchKind == "reviewer_note")
        #expect(mirrored[0].turnMetadata?.dispatchId == "xt_dispatch_project_fallback_1772200000125")
    }

    @Test
    func roleEventMessageBuildsToolApprovalMetadataFromDispatchLineage() throws {
        let lineage = AXChatMessageLineageMetadata(
            dispatchId: "xt_dispatch_project_abc_job_1_step_2",
            sourceRole: "coder",
            targetRole: "supervisor",
            dispatchKind: "coder_reply",
            projectId: "project-abc",
            runId: "job-1",
            launchRunId: "step-2",
            status: "running",
            createdAtMs: 1_772_199_999_999
        )

        let mirrored = try #require(
            XTProjectConversationMirror.roleEventMessage(
                role: "tool",
                projectId: "project-abc",
                threadKey: XTProjectConversationMirror.projectThreadKey(projectId: "project-abc"),
                content: " Tool approval awaiting authorization. ",
                createdAt: 1_772_200_000.125,
                sourceRole: "tool",
                targetRole: "supervisor",
                dispatchKind: "tool_approval",
                status: "awaiting_authorization",
                lineage: lineage,
                toolCallId: "call-write-1",
                tags: ["xt_tool_approval"]
            )
        )

        #expect(mirrored.role == "tool")
        #expect(mirrored.content == "Tool approval awaiting authorization.")
        #expect(mirrored.turnMetadata?.sourceRole == "tool")
        #expect(mirrored.turnMetadata?.targetRole == "supervisor")
        #expect(mirrored.turnMetadata?.dispatchKind == "tool_approval")
        #expect(mirrored.turnMetadata?.status == "awaiting_authorization")
        #expect(mirrored.turnMetadata?.dispatchId == "xt_dispatch_project_abc_job_1_step_2")
        #expect(mirrored.turnMetadata?.runId == "job-1")
        #expect(mirrored.turnMetadata?.launchRunId == "step-2")
        #expect(mirrored.turnMetadata?.toolCallId == "call-write-1")
        #expect(mirrored.turnMetadata?.tags.contains("xt_project_conversation") == true)
        #expect(mirrored.turnMetadata?.tags.contains("xt_tool_approval") == true)
        #expect(mirrored.turnMetadata?.observedAtMs == 1_772_200_000_125)
    }

    @Test
    func roleEventMessageSupportsHeartbeatWithoutDispatchLineage() throws {
        let mirrored = try #require(
            XTProjectConversationMirror.roleEventMessage(
                role: "system",
                projectId: "project-heartbeat",
                threadKey: XTProjectConversationMirror.projectThreadKey(projectId: "project-heartbeat"),
                content: "Heartbeat observed: reviewer cadence still green.",
                createdAt: 1_772_200_001.0,
                sourceRole: "hub",
                targetRole: "all",
                dispatchKind: "heartbeat",
                status: "observed",
                tags: ["xt_heartbeat"]
            )
        )

        #expect(mirrored.role == "system")
        #expect(mirrored.turnMetadata?.sourceRole == "hub")
        #expect(mirrored.turnMetadata?.targetRole == "all")
        #expect(mirrored.turnMetadata?.dispatchKind == "heartbeat")
        #expect(mirrored.turnMetadata?.dispatchId == "xt_dispatch_project_heartbeat_1772200001000")
        #expect(mirrored.turnMetadata?.tags.contains("xt_heartbeat") == true)
    }

    @Test
    func roleEventMessageDropsBlankContent() {
        let mirrored = XTProjectConversationMirror.roleEventMessage(
            role: "tool",
            projectId: "project-empty",
            threadKey: XTProjectConversationMirror.projectThreadKey(projectId: "project-empty"),
            content: "   ",
            createdAt: 1_772_200_000.125,
            sourceRole: "tool",
            targetRole: "supervisor",
            dispatchKind: "tool_approval",
            status: "awaiting_authorization"
        )

        #expect(mirrored == nil)
    }
}
