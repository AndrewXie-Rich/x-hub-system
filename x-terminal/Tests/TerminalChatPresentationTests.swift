import Testing
@testable import XTerminal

struct TerminalChatPresentationTests {
    @Test
    func streamingTailUsesBoundedAssistantPreview() {
        var message = AXChatMessage(
            role: .assistant,
            content: String(repeating: "a", count: 13_000)
        )
        message.id = "assistant-tail"

        let visible = TerminalChatTranscriptPresentation.visibleContent(
            for: message,
            isStreamingTail: true
        )

        #expect(
            visible == MessageTimelineStreamingTextPresentation.visibleContent(
                for: message.content,
                isStreamingTail: true
            )
        )
    }

    @Test
    func finalLongMessageUsesBoundedPreview() {
        let content = String(repeating: "abcdef", count: 5_000)
        let message = AXChatMessage(role: .assistant, content: content)

        let visible = TerminalChatTranscriptPresentation.visibleContent(
            for: message,
            isStreamingTail: false
        )

        #expect(
            visible == MessageTimelineLongTextPresentation.previewContent(
                for: content
            )
        )
        #expect(visible.utf8.count < content.utf8.count)
    }
}
