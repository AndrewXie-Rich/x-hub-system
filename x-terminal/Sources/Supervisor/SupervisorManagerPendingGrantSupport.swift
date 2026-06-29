import Foundation

extension SupervisorManager {
    func stablePendingGrantKey(
        grantRequestId: String,
        requestId: String,
        projectId: String,
        capability: String,
        createdAtMs: Double
    ) -> String {
        let gid = grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !gid.isEmpty { return "grant:\(gid)" }

        let rid = requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rid.isEmpty { return "request:\(rid)" }

        let cap = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let createdAt = createdAtMs > 0 ? String(Int(createdAtMs)) : "0"
        return "synthetic:\(projectId.lowercased())|\(cap)|\(createdAt)"
    }

    func isLocalAICapabilityToken(_ token: String) -> Bool {
        token.contains("ai_generate_local")
            || token.contains("ai.generate.local")
            || token.contains("ai_embed_local")
            || token.contains("ai.embed.local")
            || token.contains("ai_audio_local")
            || token.contains("ai.audio.local")
            || token.contains("ai_audio_tts_local")
            || token.contains("ai.audio.tts.local")
            || token.contains("ai_vision_local")
            || token.contains("ai.vision.local")
    }

    func pendingGrantPriority(capability: String) -> Int {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return 0
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            return 0
        }
        if isLocalAICapabilityToken(token) {
            return 1
        }
        return 2
    }

    func pendingGrantPriorityReason(capability: String) -> String {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return "涉及联网能力，需先确认来源与访问范围。"
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            return "涉及付费额度，优先处理可减少排队与成本滞留。"
        }
        if isLocalAICapabilityToken(token) {
            return "本地能力风险相对较低，可在高风险授权后处理。"
        }
        return "能力类型不明确，建议先核对权限边界。"
    }

    func pendingGrantNextAction(capability: String, modelId: String, reason: String) -> String {
        let token = capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if token.contains("web_fetch") || token.contains("web.fetch") {
            return "先 Open 核对目标域名，再按最小权限 Approve 或 Deny。"
        }
        if token.contains("ai_generate_paid") || token.contains("ai.generate.paid") {
            if modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "先补齐模型 ID 或降级到本地模型后再审批。"
            }
            return "确认预算后优先审批，避免付费任务长时间阻塞。"
        }
        if !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "根据原因说明核对业务必要性后再执行审批。"
        }
        return "先核对请求上下文，再执行 Approve/Deny。"
    }

    func grantCapabilityText(capability: String, modelId: String) -> String {
        XTHubGrantPresentation.capabilityLabel(
            capability: capability,
            modelId: modelId
        )
    }

    func userFacingRequestIdentifier(_ requestId: String) -> String {
        "请求单号：\(requestId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func userFacingGrantIdentifier(_ grantRequestId: String) -> String {
        "授权单号：\(grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func pendingGrantScopeText(_ grant: SupervisorPendingGrant) -> String? {
        XTHubGrantPresentation.scopeSummary(
            requestedTtlSec: grant.requestedTtlSec,
            requestedTokenCap: grant.requestedTokenCap
        )
    }

    func pendingGrantReasonText(_ grant: SupervisorPendingGrant) -> String? {
        XTHubGrantPresentation.supplementaryReason(
            grant.reason,
            capability: grant.capability,
            modelId: grant.modelId
        )
    }

    func pendingGrantStableToken(_ grant: SupervisorPendingGrant) -> String {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !grantId.isEmpty {
            return grantId
        }
        return grant.id
    }

    func pendingSupervisorSkillApprovalStableToken(
        _ approval: SupervisorPendingSkillApproval
    ) -> String {
        let requestId = approval.requestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requestId.isEmpty {
            return requestId
        }
        return approval.id
    }
}
