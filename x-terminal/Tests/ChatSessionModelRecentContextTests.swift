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

    @Test
    func projectMemoryServingProfileEscalatesForStructureReviewAndRefactorPlanning() {
        let session = ChatSessionModel()

        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "梳理项目结构并给出重构建议"
            ) == .m2PlanReview
        )
        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "先完整通读整个仓库，再给我架构重构路径"
            ) == .m3DeepDive
        )
        #expect(
            session.preferredProjectMemoryServingProfileForTesting(
                userText: "继续修当前编译错误"
            ) == nil
        )
    }

    @Test
    func localProjectMemoryFallbackIncludesServingProfileAndExpandedCanonicalForReview() {
        let session = ChatSessionModel()
        let longCanonical = String(repeating: "c", count: 3_500)

        let reviewBlock = session.projectMemoryBlockForTesting(
            canonicalMemory: longCanonical,
            recentText: "recent",
            userText: "梳理项目结构并给出重构建议"
        )
        let executeBlock = session.projectMemoryBlockForTesting(
            canonicalMemory: longCanonical,
            recentText: "recent",
            userText: "继续修当前编译错误"
        )

        #expect(reviewBlock.contains("[SERVING_PROFILE]"))
        #expect(reviewBlock.contains("[LONGTERM_MEMORY]"))
        #expect(reviewBlock.contains("longterm_mode=summary_only"))
        #expect(reviewBlock.contains("retrieval_available=false"))
        #expect(reviewBlock.contains("fulltext_not_loaded=true"))
        #expect(reviewBlock.contains("profile_id: m2_plan_review"))
        #expect(reviewBlock.contains(longCanonical))
        #expect(!executeBlock.contains(longCanonical))
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
