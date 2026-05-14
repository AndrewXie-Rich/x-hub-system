import Combine
import Testing
@testable import XTerminal

struct XTChatSessionProjectionStoresTests {
    @Test
    @MainActor
    func statusStoreTracksOnlyHeaderAndDockFields() async {
        let session = ChatSessionModel()
        let store = XTChatStatusStore()
        store.bind(to: session)

        session.messages = [
            AXChatMessage(role: .assistant, content: "first")
        ]
        await Task.yield()
        #expect(store.snapshot.messageCount == 1)

        let stableSnapshot = store.snapshot
        session.messages[0].content = "first chunk plus more streamed text"
        await Task.yield()

        #expect(store.snapshot == stableSnapshot)
    }

    @Test
    @MainActor
    func statusStoreTracksPendingToolsAndErrors() async {
        let session = ChatSessionModel()
        let store = XTChatStatusStore()
        store.bind(to: session)

        session.pendingToolCalls = [
            ToolCall(id: "tool-1", tool: .read_file, args: [:])
        ]
        session.lastError = "route blocked"
        await Task.yield()

        #expect(store.snapshot.pendingToolCallIDs == ["tool-1"])
        #expect(store.snapshot.lastError == "route blocked")
    }

    @Test
    @MainActor
    func timelineStoreTracksMessageContentChanges() async {
        let session = ChatSessionModel()
        let store = XTMessageTimelineSessionStore()
        store.bind(to: session)

        session.messages = [
            AXChatMessage(role: .assistant, content: "first")
        ]
        await Task.yield()
        let firstSignature = store.snapshot.tailSignature

        session.messages[0].content = "first chunk plus more streamed text"
        await Task.yield()

        #expect(store.snapshot.tailSignature != firstSignature)
        #expect(
            store.snapshot.tailSignature.lastMessageContentByteCount
                == "first chunk plus more streamed text".utf8.count
        )
    }

    @Test
    @MainActor
    func timelineStoreTracksSameLengthTailContentChanges() async {
        let session = ChatSessionModel()
        let store = XTMessageTimelineSessionStore()
        store.bind(to: session)

        session.messages = [
            AXChatMessage(role: .assistant, content: "stream abc")
        ]
        await Task.yield()
        let firstSignature = store.snapshot.tailSignature

        session.messages[0].content = "stream abd"
        await Task.yield()

        #expect(store.snapshot.tailSignature != firstSignature)
    }

    @Test
    @MainActor
    func timelineSnapshotEqualityUsesTailSignature() {
        var first = AXChatMessage(role: .assistant, content: "stable older content")
        first.id = "older"
        var tail = AXChatMessage(role: .assistant, content: "tail")
        tail.id = "tail"
        var mutatedOlder = first
        mutatedOlder.content = "older content changed after it left the streaming tail"

        let lhs = XTMessageTimelineSessionSnapshot(
            tailSignature: XTMessageTimelineTailSignature.make(from: [first, tail]),
            isSending: false,
            pendingToolCalls: [],
            shouldShowThinkingIndicator: false,
            presentationVersion: 0
        )
        let rhs = XTMessageTimelineSessionSnapshot(
            tailSignature: XTMessageTimelineTailSignature.make(from: [mutatedOlder, tail]),
            isSending: false,
            pendingToolCalls: [],
            shouldShowThinkingIndicator: false,
            presentationVersion: 0
        )
        var changedTail = tail
        changedTail.content = "tail changed"
        let changedTailSnapshot = XTMessageTimelineSessionSnapshot(
            tailSignature: XTMessageTimelineTailSignature.make(from: [first, changedTail]),
            isSending: false,
            pendingToolCalls: [],
            shouldShowThinkingIndicator: false,
            presentationVersion: 0
        )

        #expect(lhs == rhs)
        #expect(lhs != changedTailSnapshot)
        #expect(lhs.messageCount == 2)
    }

    @Test
    @MainActor
    func timelineTailSignatureIgnoresHiddenToolTailContentChanges() {
        var assistant = AXChatMessage(role: .assistant, content: "visible answer")
        assistant.id = "assistant-1"
        var tool = AXChatMessage(role: .tool, content: "[tool:run_command] ok=true\nfirst")
        tool.id = "tool-1"
        var changedTool = tool
        changedTool.content = "[tool:run_command] ok=true\nsecond"

        let firstSignature = XTMessageTimelineTailSignature.make(from: [assistant, tool])
        let changedSignature = XTMessageTimelineTailSignature.make(from: [assistant, changedTool])

        #expect(firstSignature == changedSignature)
        #expect(firstSignature.messageCount == 2)
    }

    @Test
    @MainActor
    func timelineStoreCoalescesSameTurnSessionMutations() async {
        let session = ChatSessionModel()
        let store = XTMessageTimelineSessionStore()
        store.bind(to: session)
        await Task.yield()

        var publishCount = 0
        var cancellables = Set<AnyCancellable>()
        store.objectWillChange
            .sink { publishCount += 1 }
            .store(in: &cancellables)

        session.messages = [
            AXChatMessage(role: .assistant, content: "first")
        ]
        session.messages[0].content = "first chunk plus more streamed text"
        session.isSending = true
        session.pendingToolCalls = [
            ToolCall(id: "tool-1", tool: .read_file, args: [:])
        ]
        await Task.yield()

        #expect(store.snapshot.messageCount == 1)
        #expect(
            store.snapshot.tailSignature.lastMessageContentByteCount
                == "first chunk plus more streamed text".utf8.count
        )
        #expect(store.snapshot.isSending)
        #expect(store.snapshot.pendingToolCallIDs == ["tool-1"])
        #expect(publishCount == 1)
    }
}
