import Testing
@testable import XTerminal

@MainActor
struct XTStreamingPlaceholderSupportTests {

    @Test
    func compactDetailRewritesPlanningCopy() {
        #expect(
            XTStreamingPlaceholderSupport.compactDetail(from: "我先梳理下一步。")
                == "梳理上下文"
        )
    }

    @Test
    func presentationExtractsWaitStageAndShortDetail() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "已把请求发给 Hub 本地模型 gpt-oss-20b，正在等待首段输出。"
        )

        #expect(presentation.title == "等待首字")
        #expect(presentation.detail == "Hub 模型预热中")
    }

    @Test
    func presentationExtractsContextReadStage() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "我在读取 Sources/App.swift。"
        )

        #expect(presentation.title == "读取上下文")
        #expect(presentation.detail == "读取 Sources/App.swift")
    }

    @Test
    func presentationTreatsDiffInspectionAsContextRead() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "我在查看当前改动差异。"
        )

        #expect(presentation.title == "读取上下文")
        #expect(presentation.detail == "查看改动差异")
    }

    @Test
    func presentationHidesDuplicateCurrentContextDetail() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "我在读取当前上下文。"
        )

        #expect(presentation.title == "读取上下文")
        #expect(presentation.detail == nil)
    }

    @Test
    func presentationTreatsVerificationCommandAsVerificationStage() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "我在执行 swift test --filter XTStreamingPlaceholderSupportTests。"
        )

        #expect(presentation.title == "运行验证")
        #expect(
            presentation.detail
                == "运行 swift test --filter XTStreamingPlaceholderSupportTests"
        )
    }

    @Test
    func presentationTreatsNetworkGrantAsConfirmationStage() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "我在申请联网能力。"
        )

        #expect(presentation.title == "等待确认")
        #expect(presentation.detail == "等待联网授权")
    }

    @Test
    func presentationShortensSafePointPauseDetail() {
        let presentation = XTStreamingPlaceholderSupport.presentation(
            from: "Supervisor 指导命中工具边界，先暂停剩余工具。"
        )

        #expect(presentation.title == "等待确认")
        #expect(presentation.detail == "等待继续指令")
    }

    @Test
    func chatSessionExposesThinkingPlaceholderBeforeVisibleAssistantText() {
        let session = ChatSessionModel()
        let message = AXChatMessage(role: .assistant, content: "")
        session.messages = [message]
        session.isSending = true
        session.setAssistantProgressLinesForTesting(
            ["我在整理这一步的执行方案。"],
            messageID: message.id
        )

        let presentation = session.assistantThinkingPresentationForTesting(message)

        #expect(presentation?.title == "准备回复")
        #expect(presentation?.detail == nil)
    }

    @Test
    func chatSessionHidesThinkingPlaceholderAfterVisibleStreamingStarts() {
        let session = ChatSessionModel()
        let message = AXChatMessage(role: .assistant, content: "")
        session.messages = [message]
        session.isSending = true
        session.setAssistantProgressLinesForTesting(
            ["我在整理这一步的执行方案。"],
            messageID: message.id,
            visibleStreaming: true
        )

        #expect(session.assistantThinkingPresentationForTesting(message) == nil)
    }
}
