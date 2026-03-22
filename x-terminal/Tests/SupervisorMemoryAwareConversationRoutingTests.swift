import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorMemoryAwareConversationRoutingTests {

    @Test
    func preflightKeepsOnlyOperationalRuntimeQueriesLocal() {
        let manager = SupervisorManager.makeForTesting()

        let modelRoute = manager.directSupervisorPreflightReplyIfApplicableForTesting("你现在是什么模型")
        let identity = manager.directSupervisorPreflightReplyIfApplicableForTesting("你是谁")
        let capability = manager.directSupervisorPreflightReplyIfApplicableForTesting("你能做什么")
        let projectBrief = manager.directSupervisorPreflightReplyIfApplicableForTesting("简单说下亮亮现在怎么样，卡在哪，下一步怎么走")

        #expect(modelRoute != nil)
        #expect(identity == nil)
        #expect(capability == nil)
        #expect(projectBrief == nil)
    }

    @Test
    func executionIntakeIsPrimedBeforeRemoteMemoryAwareResponse() {
        let manager = SupervisorManager.makeForTesting()

        let preflight = manager.directSupervisorPreflightReplyIfApplicableForTesting("帮我做个贪食蛇游戏")
        manager.primeSupervisorMemoryAwareConversationStateIfNeededForTesting("帮我做个贪食蛇游戏")

        #expect(preflight == nil)
        #expect(manager.pendingSupervisorExecutionIntakeGoalSummaryForTesting()?.contains("贪食蛇") == true)
    }

    @Test
    func capabilityReplyMentionsCanonicalSyncRecovery() {
        let manager = SupervisorManager.makeForTesting()

        let reply = manager.directSupervisorReplyIfApplicableForTesting("你能做什么")

        #expect(reply?.contains("重试 canonical sync") == true)
        #expect(reply?.contains("/doctor") == true)
        #expect(reply?.contains("/xt-ready incidents status") == true)
    }
}
