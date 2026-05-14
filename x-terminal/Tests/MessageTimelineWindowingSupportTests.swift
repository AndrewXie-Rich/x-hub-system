import Testing
@testable import XTerminal

struct MessageTimelineWindowingSupportTests {

    @Test
    func initialVisibleRangeStartsFromLatestPage() {
        let range = MessageTimelineWindowingSupport.initialVisibleRange(
            totalCount: 180,
            pageSize: 80
        )

        #expect(range == 100..<180)
    }

    @Test
    func prependedVisibleRangeKeepsLoadedTail() {
        let range = MessageTimelineWindowingSupport.prependedVisibleRange(
            currentRange: 100..<180,
            totalCount: 180,
            pageSize: 80
        )

        #expect(range == 20..<180)
    }

    @Test
    func latestVisibleRangeTracksBottomWithoutGrowingUnbounded() {
        let range = MessageTimelineWindowingSupport.latestVisibleRange(
            from: 20..<180,
            totalCount: 196,
            pageSize: 80,
            maxWindowSize: 120,
            stickToBottom: true
        )

        #expect(range == 76..<196)
    }

    @Test
    func latestVisibleRangeKeepsHistoryWindowStableWhenUserIsReadingOlderMessages() {
        let range = MessageTimelineWindowingSupport.latestVisibleRange(
            from: 20..<100,
            totalCount: 196,
            pageSize: 80,
            maxWindowSize: 120,
            stickToBottom: false
        )

        #expect(range == 20..<100)
    }

    @Test
    func prependedVisibleRangeCapsMaximumWindowSize() {
        let range = MessageTimelineWindowingSupport.prependedVisibleRange(
            currentRange: 80..<200,
            totalCount: 200,
            pageSize: 30,
            maxWindowSize: 120
        )

        #expect(range == 50..<170)
    }

    @Test
    func shouldStickToBottomOnlyWhenBottomAnchorIsNearViewport() {
        #expect(
            MessageTimelineWindowingSupport.shouldStickToBottom(
                bottomAnchorMaxY: 620,
                viewportHeight: 600,
                threshold: 32
            )
        )

        #expect(
            !MessageTimelineWindowingSupport.shouldStickToBottom(
                bottomAnchorMaxY: 680,
                viewportHeight: 600,
                threshold: 32
            )
        )
    }

    @Test
    func updatedStickToBottomStateOnlyChangesWhenThresholdIsCrossed() {
        #expect(
            MessageTimelineWindowingSupport.updatedStickToBottomState(
                currentValue: true,
                bottomAnchorMaxY: 620,
                viewportHeight: 600,
                threshold: 32
            ) == nil
        )

        #expect(
            MessageTimelineWindowingSupport.updatedStickToBottomState(
                currentValue: true,
                bottomAnchorMaxY: 700,
                viewportHeight: 600,
                threshold: 32
            ) == false
        )

        #expect(
            MessageTimelineWindowingSupport.updatedStickToBottomState(
                currentValue: false,
                bottomAnchorMaxY: 620,
                viewportHeight: 600,
                threshold: 32
            ) == true
        )
    }

    @Test
    func changeCoalescingSkipsTailRefreshAlreadyHandledByMessageCountChange() {
        var assistant = AXChatMessage(role: .assistant, content: "answer", createdAt: 1)
        assistant.id = "assistant-1"
        let handled = XTMessageTimelineTailSignature.make(from: [assistant])
        var changedAssistant = assistant
        changedAssistant.content = "answer changed"
        let changed = XTMessageTimelineTailSignature.make(from: [changedAssistant])

        #expect(
            MessageTimelineChangeCoalescing.shouldSkipTailRefresh(
                handledByMessageCountChange: handled,
                currentTailSignature: handled
            )
        )
        #expect(
            !MessageTimelineChangeCoalescing.shouldSkipTailRefresh(
                handledByMessageCountChange: nil,
                currentTailSignature: handled
            )
        )
        #expect(
            !MessageTimelineChangeCoalescing.shouldSkipTailRefresh(
                handledByMessageCountChange: handled,
                currentTailSignature: changed
            )
        )
    }

    @Test
    func streamingTextPresentationKeepsShortStreamingTextWhole() {
        let content = "short answer"

        let visible = MessageTimelineStreamingTextPresentation.visibleContent(
            for: content,
            isStreamingTail: true,
            byteThreshold: 100,
            suffixCharacterLimit: 4
        )

        #expect(visible == content)
    }

    @Test
    func streamingTextPresentationClampsOnlyLongStreamingText() {
        let content = "abcdefghijklmnopqrstuvwxyz"

        let visible = MessageTimelineStreamingTextPresentation.visibleContent(
            for: content,
            isStreamingTail: true,
            byteThreshold: 10,
            suffixCharacterLimit: 6
        )

        #expect(visible == "...\nuvwxyz")
        #expect(visible.utf8.count < content.utf8.count)
    }

    @Test
    func streamingTextPresentationLeavesFinalTextWhole() {
        let content = "abcdefghijklmnopqrstuvwxyz"

        let visible = MessageTimelineStreamingTextPresentation.visibleContent(
            for: content,
            isStreamingTail: false,
            byteThreshold: 10,
            suffixCharacterLimit: 6
        )

        #expect(visible == content)
    }

    @Test
    func longTextPresentationCollapsesOnlyLargeFinalText() {
        #expect(
            !MessageTimelineLongTextPresentation.shouldCollapse(
                "short",
                byteThreshold: 100
            )
        )
        #expect(
            MessageTimelineLongTextPresentation.shouldCollapse(
                "abcdefghijklmnopqrstuvwxyz",
                byteThreshold: 10
            )
        )
    }

    @Test
    func longTextPresentationBuildsPrefixPreview() {
        let content = "abcdefghijklmnopqrstuvwxyz"

        let preview = MessageTimelineLongTextPresentation.previewContent(
            for: content,
            characterLimit: 6
        )

        #expect(preview == "abcdef\n...")
        #expect(preview.utf8.count < content.utf8.count)
    }

    @Test
    func longTextPresentationLeavesShortPreviewWhole() {
        let content = "abcdef"

        let preview = MessageTimelineLongTextPresentation.previewContent(
            for: content,
            characterLimit: 6
        )

        #expect(preview == content)
    }

    @Test
    func rowProjectionFiltersToolMessagesAndCarriesThinkingPresentation() {
        var user = AXChatMessage(role: .user, content: "hello", createdAt: 1)
        user.id = "user-1"
        var tool = AXChatMessage(role: .tool, content: "[tool:run_command] ok=true", createdAt: 2)
        tool.id = "tool-1"
        var assistant = AXChatMessage(role: .assistant, content: "", createdAt: 3)
        assistant.id = "assistant-1"
        let thinking = XTStreamingPlaceholderPresentation(
            title: "读取上下文",
            detail: "查看项目目录"
        )

        let messages = MessageTimelineRowProjection.timelineMessages(from: [
            user,
            tool,
            assistant
        ])
        let snapshots = MessageTimelineRowProjection.snapshots(for: messages) { message in
            message.id == assistant.id ? thinking : nil
        }

        #expect(messages.map(\.id) == ["user-1", "assistant-1"])
        #expect(snapshots.map(\.id) == ["user-1", "assistant-1"])
        #expect(snapshots.last?.thinkingPresentation == thinking)
    }

    @Test
    func rowProjectionMarksStreamingTailOnlyForCurrentTail() {
        var user = AXChatMessage(role: .user, content: "hello", createdAt: 1)
        user.id = "user-1"
        var assistant = AXChatMessage(role: .assistant, content: "streaming", createdAt: 2)
        assistant.id = "assistant-1"

        let snapshots = MessageTimelineRowProjection.snapshots(
            for: [user, assistant],
            streamingTailMessageID: assistant.id
        ) { _ in nil }

        #expect(snapshots.map(\.isStreamingTail) == [false, true])
    }

    @Test
    func rowProjectionStreamingTailIDOnlyUsesAssistantTail() {
        var user = AXChatMessage(role: .user, content: "hello", createdAt: 1)
        user.id = "user-1"
        var assistant = AXChatMessage(role: .assistant, content: "streaming", createdAt: 2)
        assistant.id = "assistant-1"

        #expect(
            MessageTimelineRowProjection.streamingTailMessageID(
                isSending: true,
                timelineMessages: [user]
            ) == nil
        )
        #expect(
            MessageTimelineRowProjection.streamingTailMessageID(
                isSending: true,
                timelineMessages: [user, assistant]
            ) == "assistant-1"
        )
        #expect(
            MessageTimelineRowProjection.streamingTailMessageID(
                isSending: false,
                timelineMessages: [user, assistant]
            ) == nil
        )
    }

    @Test
    func rowProjectionFindsLatestNonToolMessageFromTail() {
        var user = AXChatMessage(role: .user, content: "hello", createdAt: 1)
        user.id = "user-1"
        var assistant = AXChatMessage(role: .assistant, content: "answer", createdAt: 2)
        assistant.id = "assistant-1"
        var tool = AXChatMessage(role: .tool, content: "[tool:run_command] ok=true", createdAt: 3)
        tool.id = "tool-1"

        let latest = MessageTimelineRowProjection.latestTimelineMessage(from: [
            user,
            assistant,
            tool
        ])

        #expect(latest?.id == "assistant-1")
    }

    @Test
    func rowProjectionFindsLatestNonToolMessageBeforeSourceTail() {
        var user = AXChatMessage(role: .user, content: "hello", createdAt: 1)
        user.id = "user-1"
        var assistant = AXChatMessage(role: .assistant, content: "answer", createdAt: 2)
        assistant.id = "assistant-1"
        var trailingTool = AXChatMessage(role: .tool, content: "[tool:run_command] ok=true", createdAt: 3)
        trailingTool.id = "tool-1"
        var appended = AXChatMessage(role: .assistant, content: "next", createdAt: 4)
        appended.id = "assistant-2"

        let previousTail = MessageTimelineRowProjection.latestTimelineMessageBeforeSourceTail(from: [
            user,
            assistant,
            trailingTool,
            appended
        ])

        #expect(previousTail?.id == "assistant-1")
    }

    @Test
    func rowProjectionReturnsNilWhenOnlyToolMessagesExist() {
        var tool = AXChatMessage(role: .tool, content: "[tool:run_command] ok=true", createdAt: 1)
        tool.id = "tool-1"

        #expect(MessageTimelineRowProjection.latestTimelineMessage(from: [tool]) == nil)
    }

    @Test
    func rowSnapshotPrecomputesRouteDiagnoseActionVisibility() {
        let message = AXChatMessage(
            role: .assistant,
            content: """
Project route diagnose: coder
当前配置：openai/gpt-5.4
"""
        )

        let snapshot = MessageRowSnapshot(message: message)

        #expect(snapshot.showsRouteDiagnoseActions)
    }

    @Test
    func rowProjectionOnlyPassesSendingStateToRouteDiagnoseRows() {
        let regular = MessageRowSnapshot(
            message: AXChatMessage(role: .assistant, content: "普通助手文本")
        )
        let routeDiagnose = MessageRowSnapshot(
            message: AXChatMessage(
                role: .assistant,
                content: """
Project route diagnose: coder
当前配置：openai/gpt-5.4
"""
            )
        )

        #expect(!MessageTimelineRowProjection.sessionSendingForRow(true, snapshot: regular))
        #expect(MessageTimelineRowProjection.sessionSendingForRow(true, snapshot: routeDiagnose))
        #expect(!MessageTimelineRowProjection.sessionSendingForRow(false, snapshot: routeDiagnose))
    }

    @Test
    func rowProjectionRefreshesOnlyLatestAndExistingThinkingRowsForPresentationChanges() {
        var first = AXChatMessage(role: .assistant, content: "", createdAt: 1)
        first.id = "assistant-1"
        var second = AXChatMessage(role: .user, content: "continue", createdAt: 2)
        second.id = "user-1"
        var latest = AXChatMessage(role: .assistant, content: "", createdAt: 3)
        latest.id = "assistant-2"
        let thinking = XTStreamingPlaceholderPresentation(
            title: "读取上下文",
            detail: "查看项目目录"
        )
        let snapshots = [
            MessageRowSnapshot(message: first, thinkingPresentation: thinking),
            MessageRowSnapshot(message: second),
            MessageRowSnapshot(message: latest)
        ]

        let indexes = MessageTimelineRowProjection.presentationRefreshIndexes(
            timelineMessages: [first, second, latest],
            previousSnapshots: snapshots
        )

        #expect(indexes == [2, 0])
    }

    @Test
    func rowProjectionPresentationRefreshFallsBackOnMismatchedSnapshots() {
        var first = AXChatMessage(role: .assistant, content: "", createdAt: 1)
        first.id = "assistant-1"
        var latest = AXChatMessage(role: .assistant, content: "", createdAt: 2)
        latest.id = "assistant-2"

        let indexes = MessageTimelineRowProjection.presentationRefreshIndexes(
            timelineMessages: [first, latest],
            previousSnapshots: [MessageRowSnapshot(message: first)]
        )

        #expect(indexes.isEmpty)
    }

    @Test
    func rowSnapshotPrecomputesStructuredAssistantContentVisibility() {
        let plain = MessageRowSnapshot(
            message: AXChatMessage(role: .assistant, content: "普通助手文本")
        )
        let structured = MessageRowSnapshot(
            message: AXChatMessage(
                role: .assistant,
                content: #"{"tool_calls":[{"id":"call-1","tool":"read_file","args":{}}]}"#
            )
        )
        let user = MessageRowSnapshot(
            message: AXChatMessage(
                role: .user,
                content: #"{"tool_calls":[{"id":"call-1","tool":"read_file","args":{}}]}"#
            )
        )

        #expect(!plain.usesStructuredAssistantContent)
        #expect(structured.usesStructuredAssistantContent)
        #expect(!user.usesStructuredAssistantContent)
    }
}
