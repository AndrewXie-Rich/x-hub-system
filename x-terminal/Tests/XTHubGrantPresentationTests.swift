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
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "browser.control",
                modelId: ""
            ) == "浏览器控制"
        )
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "ai.embed.local",
                modelId: "qwen3-embedding"
            ) == "本地向量模型调用（qwen3-embedding）"
        )
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "ai.audio.tts.local",
                modelId: "kokoro"
            ) == "本地语音合成调用（kokoro）"
        )
        #expect(
            XTHubGrantPresentation.capabilityLabel(
                capability: "ai.vision.local",
                modelId: "qwen2-vl"
            ) == "本地图像理解调用（qwen2-vl）"
        )
    }

    @Test
    func awaitingSummaryUsesCapabilityLabel() {
        let summary = XTHubGrantPresentation.awaitingSummary(
            capability: "ai.generate.local",
            modelId: "llama"
        )

        #expect(summary.contains("等待 Hub 授权后才能继续"))
        #expect(summary.contains("本地文本模型调用（llama）"))
    }

    @Test
    func awaitingStateSummaryIncludesHumanCapabilityAndGrantToken() {
        let summary = XTHubGrantPresentation.awaitingStateSummary(
            capability: "web.fetch",
            modelId: "",
            grantRequestId: "grant-123"
        )

        #expect(summary.contains("等待 Hub 授权"))
        #expect(summary.contains("联网访问"))
        #expect(summary.contains("授权单号：grant-123"))
    }

    @Test
    func deniedStateSummaryIncludesHumanCapability() {
        let summary = XTHubGrantPresentation.deniedStateSummary(
            capability: "ai.generate.local",
            modelId: "llama",
            deniedByUser: true
        )

        #expect(summary.contains("Hub 授权已被你拒绝"))
        #expect(summary.contains("本地文本模型调用（llama）"))
    }

    @Test
    func emptyAndAmbiguityRepliesRespectProjectContext() {
        #expect(
            XTHubGrantPresentation.emptyPendingReply(projectName: nil) == "当前没有待处理的 Hub 授权。"
        )
        #expect(
            XTHubGrantPresentation.emptyPendingReply(projectName: "Project Alpha") == "项目 Project Alpha 当前没有待处理的 Hub 授权。"
        )
        #expect(
            XTHubGrantPresentation.ambiguityHeader(projectName: nil) == "当前有多笔待处理的 Hub 授权，我不能替你盲选。"
        )
        #expect(
            XTHubGrantPresentation.ambiguityHeader(projectName: "Project Alpha") == "项目 Project Alpha 还有多笔待处理的 Hub 授权，我不能替你盲选。"
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
        #expect(reply.contains("本地文本模型调用（llama）"))
        #expect(reply.contains("授权单号：grant-local-1"))
        #expect(reply.contains("原因：hub_busy"))
    }

    @Test
    func supplementaryReasonDropsGenericGrantCopy() {
        let reason = XTHubGrantPresentation.supplementaryReason(
            "waiting for Hub grant approval",
            capability: "web.fetch",
            modelId: ""
        )
        let reasonWithCapability = XTHubGrantPresentation.supplementaryReason(
            "等待 Hub 授权 · 联网访问 · 授权单号：grant-123",
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
        #expect(approveDraft.contains("原因：quota_denied"))
        #expect(denyDraft.contains("付费模型调用（gpt-5.4）"))
        #expect(denyDraft.contains("拒绝未完成"))
    }
}
