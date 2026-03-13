import Foundation
import Testing
@testable import XTerminal

@MainActor
struct ChatSessionModelRecentContextTests {

    @Test
    func defaultRecentPromptWindowUsesEightTurns() {
        let session = ChatSessionModel()

        #expect(session.recentPromptTurnLimitForTesting(userText: "继续写这个功能") == 16)
        #expect(session.recentPromptTurnLimitForTesting(userText: "请分析当前实现") == 8)
        #expect(
            session.recentPromptTurnLimitForTesting(
                userText: "普通新请求",
                expandRecentOnceAfterLoad: true
            ) == 16
        )
    }

    @Test
    func recentConversationPreviewKeepsEightTurnsByDefault() {
        let session = ChatSessionModel()
        session.messages = makeTurns(count: 10)

        let preview = session.recentConversationForTesting(userText: "新的问题", maxTurns: 8)

        let lines = Set(preview.split(separator: "\n").map(String.init))
        #expect(!lines.contains("user: user-1"))
        #expect(!lines.contains("assistant: assistant-2"))
        #expect(lines.contains("user: user-3"))
        #expect(lines.contains("assistant: assistant-10"))
    }

    @Test
    func projectMemoryRetrievalTriggersOnlyForHistoryOrSpecQueries() {
        let session = ChatSessionModel()

        #expect(session.shouldRequestProjectMemoryRetrievalForTesting(userText: "你能把我之前说过的话再总结一下吗"))
        #expect(session.shouldRequestProjectMemoryRetrievalForTesting(userText: "这个项目的 tech stack 决策是什么"))
        #expect(!session.shouldRequestProjectMemoryRetrievalForTesting(userText: "继续修当前编译错误"))
    }

    private func makeTurns(count: Int) -> [AXChatMessage] {
        var out: [AXChatMessage] = []
        for index in 1...count {
            let base = Double(index * 10)
            out.append(AXChatMessage(role: .user, content: "user-\(index)", createdAt: base))
            out.append(AXChatMessage(role: .assistant, content: "assistant-\(index)", createdAt: base + 1))
        }
        return out
    }
}
