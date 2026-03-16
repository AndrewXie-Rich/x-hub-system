import Foundation
import Testing
@testable import XTerminal

struct XTHubGrantPresentationTests {

    @Test
    func capabilityLabelHumanizesKnownCapabilities() {
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "web.fetch",
                modelId: ""
            ) == "联网访问"
        )
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "ai.generate.paid",
                modelId: "gpt-5.4"
            ) == "付费模型调用（gpt-5.4）"
        )
    }

    @Test
    func awaitingSummaryUsesCapabilityLabel() {
        let summary = XTHubGrantPresentation.awaitingSummary(
            capability: "ai.generate.local",
            modelId: "llama"
        )

        #expect(summary.contains("等待 Hub 授权后才能继续"))
        #expect(summary.contains("本地模型调用（llama）"))
    }

    @Test
    func awaitingStateSummaryIncludesHumanCapabilityAndGrantToken() {
        let summary = XTHubGrantPresentation.awaitingStateSummary(
            capability: "web.fetch",
            modelId: "",
            grantRequestId: "grant-123"
        )

        #expect(summary.contains("waiting for Hub grant approval"))
        #expect(summary.contains("联网访问"))
        #expect(summary.contains("grant=grant-123"))
    }

    @Test
    func deniedStateSummaryIncludesHumanCapability() {
        let summary = XTHubGrantPresentation.deniedStateSummary(
            capability: "ai.generate.local",
            modelId: "llama",
            deniedByUser: true
        )

        #expect(summary.contains("Hub grant denied by user"))
        #expect(summary.contains("本地模型调用（llama）"))
    }

    @Test
    func emptyAndAmbiguityRepliesRespectProjectContext() {
        #expect(
            XTHubGrantPresentation.emptyPendingReply(projectName: nil) == "当前没有待处理的 Hub grant。"
        )
        #expect(
            XTHubGrantPresentation.emptyPendingReply(projectName: "Project Alpha") == "项目 Project Alpha 当前没有待处理的 Hub grant。"
        )
        #expect(
            XTHubGrantPresentation.ambiguityHeader(projectName: nil) == "当前有多个待处理 Hub grant，我不能替你盲选。"
        )
        #expect(
            XTHubGrantPresentation.ambiguityHeader(projectName: "Project Alpha") == "项目 Project Alpha 还有多个待处理 Hub grant，我不能替你盲选。"
        )
    }

    @Test
    func voiceDecisionFailureReplyUsesHumanCapabilityLabel() {
        let reply = XTHubGrantPresentation.voiceDecisionFailureReply(
            projectName: "Local Runtime",
            intent: .deny,
            capability: "ai.generate.local",
            modelId: "llama",
            grantRequestId: "grant-local-1",
            reasonCode: "hub_busy"
        )

        #expect(reply.contains("语音授权已验证"))
        #expect(reply.contains("《Local Runtime》"))
        #expect(reply.contains("本地模型调用（llama）"))
        #expect(reply.contains("grant=grant-local-1"))
        #expect(reply.contains("reason=hub_busy"))
    }

    @Test
    func supplementaryReasonDropsGenericGrantCopy() {
        let reason = XTHubGrantPresentation.supplementaryReason(
            "waiting for Hub grant approval",
            capability: "web.fetch",
            modelId: ""
        )
        let reasonWithCapability = XTHubGrantPresentation.supplementaryReason(
            "waiting for Hub grant approval · 联网访问 · grant=grant-123",
            capability: "web.fetch",
            modelId: ""
        )

        #expect(reason == nil)
        #expect(reasonWithCapability == nil)
    }

    @Test
    func scopeSummaryIncludesTtlAndTokenCap() {
        let summary = XTHubGrantPresentation.scopeSummary(
            requestedTtlSec: 900,
            requestedTokenCap: 4000
        )

        #expect(summary == "授权范围：TTL 15 分钟 · token 上限 4000")
    }

    @Test
    func decisionFailureDraftUsesHumanCapabilityLabel() {
        let approveDraft = XTHubGrantPresentation.decisionFailureDraft(
            intent: .approve,
            capability: "web.fetch",
            modelId: "",
            grantRequestId: "grant-123",
            reasonCode: "quota_denied"
        )
        let denyDraft = XTHubGrantPresentation.decisionFailureDraft(
            intent: .deny,
            capability: "ai.generate.paid",
            modelId: "gpt-5.4",
            grantRequestId: "grant-456",
            reasonCode: nil
        )

        #expect(approveDraft.contains("联网访问"))
        #expect(approveDraft.contains("放行未完成"))
        #expect(approveDraft.contains("reason=quota_denied"))
        #expect(denyDraft.contains("付费模型调用（gpt-5.4）"))
        #expect(denyDraft.contains("拒绝未完成"))
    }
}
