import Foundation
import Testing
@testable import XTerminal

struct SupervisorDialogueContinuityFilterTests {
    @Test
    func pureGreetingAndAckTurnsAreDropped() {
        #expect(SupervisorDialogueContinuityFilter.classify(message("你好")).isLowSignal)
        #expect(SupervisorDialogueContinuityFilter.classify(message("收到")).isLowSignal)
        #expect(SupervisorDialogueContinuityFilter.classify(message("hello")).isLowSignal)
        #expect(SupervisorDialogueContinuityFilter.classify(message("ok")).isLowSignal)
    }

    @Test
    func meaningfulShortTurnsAreKept() {
        #expect(!SupervisorDialogueContinuityFilter.classify(message("你好，我叫 Andrew")).isLowSignal)
        #expect(!SupervisorDialogueContinuityFilter.classify(message("好的，按网页版本做")).isLowSignal)
        #expect(!SupervisorDialogueContinuityFilter.classify(message("先别动亮亮")).isLowSignal)
        #expect(!SupervisorDialogueContinuityFilter.classify(message("他还在等我回复")).isLowSignal)
        #expect(!SupervisorDialogueContinuityFilter.classify(message("这个 done definition 不是这个意思")).isLowSignal)
    }

    @Test
    func rollingDigestSummarizesOlderContinuityWithoutLowSignalFiller() {
        let digest = SupervisorDialogueRollingDigestBuilder.build(
            olderMessages: [
                message("user-turn-1", role: .user, id: "u1"),
                message("assistant-turn-1", role: .assistant, id: "a1"),
                message("你好", role: .user, id: "u2"),
                message("收到", role: .assistant, id: "a2"),
                message("user-turn-2", role: .user, id: "u3"),
                message("assistant-turn-2", role: .assistant, id: "a3"),
            ],
            turnMode: "project_first",
            focusedProjectName: "亮亮",
            focusedProjectId: "proj-liang"
        )

        #expect(digest.contains("source_eligible_messages: 4"))
        #expect(digest.contains("turn_mode_hint: project_first"))
        #expect(digest.contains("focused_project_hint: 亮亮 (proj-liang)"))
        #expect(digest.contains("- user-turn-2"))
        #expect(digest.contains("- assistant-turn-2"))
        #expect(!digest.contains("- 你好"))
        #expect(!digest.contains("- 收到"))
    }

    @Test
    func continuityResolverUsesHubThreadWhenRemoteAlreadyCoversLocalTail() {
        let selection = SupervisorDialogueContinuitySourceResolver.resolve(
            localMessages: [
                message("user-turn-2", role: .user, id: "u2"),
                message("assistant-turn-2", role: .assistant, id: "a2"),
            ],
            remoteWorkingEntries: [
                "user: user-turn-1",
                "assistant: assistant-turn-1",
                "user: user-turn-2",
                "assistant: assistant-turn-2",
            ]
        )

        #expect(selection.source == "hub_thread")
        #expect(selection.messages.count == 4)
        #expect(selection.messages.first?.content == "user-turn-1")
        #expect(selection.messages.last?.content == "assistant-turn-2")
    }

    @Test
    func continuityResolverBuildsMixedSourceWhenLocalAddsNewTail() {
        let selection = SupervisorDialogueContinuitySourceResolver.resolve(
            localMessages: [
                message("user-turn-2", role: .user, id: "u2"),
                message("assistant-turn-2", role: .assistant, id: "a2"),
                message("user-turn-3", role: .user, id: "u3"),
            ],
            remoteWorkingEntries: [
                "user: user-turn-1",
                "assistant: assistant-turn-1",
                "user: user-turn-2",
                "assistant: assistant-turn-2",
            ]
        )

        #expect(selection.source == "mixed")
        #expect(selection.messages.count == 5)
        #expect(selection.messages.last?.content == "user-turn-3")
    }

    @Test
    func supervisorConversationMirrorNormalizesAndTruncatesPayload() {
        let assistantText = String(repeating: "a", count: XTSupervisorConversationMirror.maxCharsPerMessage + 20)
        let turn = XTSupervisorConversationMirror.normalizedTurn(
            userText: "  继续推进亮亮  ",
            assistantText: assistantText
        )

        #expect(turn?.userText == "继续推进亮亮")
        #expect(turn?.assistantText.contains("[x-terminal] truncated") == true)
        #expect(turn?.assistantText.count == XTSupervisorConversationMirror.maxCharsPerMessage + "\n\n[x-terminal] truncated".count)
        #expect(XTSupervisorConversationMirror.requestID(createdAt: 12.345).hasPrefix("xterminal_supervisor_turn_"))
    }

    private func message(
        _ content: String,
        role: SupervisorMessage.SupervisorRole = .user,
        id: String = UUID().uuidString
    ) -> SupervisorMessage {
        SupervisorMessage(
            id: id,
            role: role,
            content: content,
            isVoice: false,
            timestamp: 1
        )
    }
}
