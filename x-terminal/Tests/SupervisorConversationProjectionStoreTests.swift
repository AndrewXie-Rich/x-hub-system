import Testing
@testable import XTerminal

@MainActor
struct SupervisorConversationProjectionStoreTests {
    @Test
    func timelineSnapshotFiltersNonConversationRows() {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = [
            SupervisorMessage(
                id: "heartbeat",
                role: .assistant,
                content: "🫀 Supervisor Heartbeat (8:28)\n变化：无重大状态变化",
                isVoice: false,
                timestamp: 1
            ),
            SupervisorMessage(
                id: "system",
                role: .system,
                content: "system-only event",
                isVoice: false,
                timestamp: 2
            ),
            SupervisorMessage(
                id: "chat",
                role: .assistant,
                content: "visible reply",
                isVoice: false,
                timestamp: 3
            )
        ]

        let snapshot = SupervisorConversationTimelineSnapshot.make(from: manager)

        #expect(snapshot.rows.map(\.id) == ["chat"])
        #expect(snapshot.lastMessageContent == "visible reply")
    }

    @Test
    func timelineSnapshotProjectsStreamingPlaceholder() {
        let manager = SupervisorManager.makeForTesting()
        let placeholderID = manager.prepareConversationStreamingAssistantMessageForTesting(
            id: "streaming-preflight"
        )
        manager.setConversationPlaceholderStatusForTesting("我在读取当前上下文。")

        let snapshot = SupervisorConversationTimelineSnapshot.make(from: manager)
        let row = snapshot.rows.first { $0.id == placeholderID }

        #expect(row?.thinkingPresentation?.title == "读取上下文")
        #expect(row?.thinkingPresentation?.detail == nil)
    }

    @Test
    func timelineStoreTracksOnlyConversationProjectionInputs() async {
        let manager = SupervisorManager.makeForTesting()
        let store = SupervisorConversationTimelineStore()
        store.bind(to: manager)

        manager.messages = [
            SupervisorMessage(
                id: "chat",
                role: .assistant,
                content: "first",
                isVoice: false,
                timestamp: 1
            )
        ]
        await Task.yield()

        #expect(store.snapshot.rows.map(\.id) == ["chat"])

        manager.processingStatusText = "我在执行工具。"
        await Task.yield()

        #expect(store.snapshot.processingStatusText == "我在执行工具。")
    }
}
