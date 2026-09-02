import Foundation

extension SupervisorManager {
    func makeVoiceAuthorizationManagerFailureResolution(
        requestId: String,
        projectId: String?,
        templateId: String,
        riskTier: LaneRiskTier,
        reasonCode: String,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    ) -> SupervisorVoiceAuthorizationResolution {
        let normalizedTemplate = templateId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTemplate = normalizedTemplate.isEmpty ? "voice.grant.v1" : normalizedTemplate
        let requiresMobileConfirm = challenge?.requiresMobileConfirm ?? (riskTier >= .high)
        let allowVoiceOnly = challenge?.allowVoiceOnly ?? (riskTier < .high)
        let policyRef = [
            "schema=\(SupervisorVoiceAuthorizationResolution.currentSchemaVersion)",
            "state=\(SupervisorVoiceAuthorizationResolution.State.failClosed.rawValue)",
            "risk_tier=\(riskTier.rawValue)",
            "requires_mobile_confirm=\(requiresMobileConfirm ? "true" : "false")",
            "allow_voice_only=\(allowVoiceOnly ? "true" : "false")",
            "reason_code=\(reasonCode)"
        ].joined(separator: ";")

        let nextAction: String = {
            switch reasonCode {
            case "voice_authorization_not_started":
                return "issue a new voice challenge before attempting verify"
            case "voice_authorization_inflight":
                return "wait for the current voice authorization round to finish"
            case "user_cancelled":
                return "reissue the challenge if authorization is still required"
            case "hub_env_missing":
                return "repair Hub pairing/runtime profile before retrying voice authorization"
            default:
                return "hold the gated action and repair the voice authorization path first"
            }
        }()

        return SupervisorVoiceAuthorizationResolution(
            schemaVersion: SupervisorVoiceAuthorizationResolution.currentSchemaVersion,
            state: .failClosed,
            ok: false,
            requestId: requestId.trimmingCharacters(in: .whitespacesAndNewlines),
            projectId: {
                let token = projectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return token.isEmpty ? nil : token
            }(),
            templateId: fallbackTemplate,
            riskTier: riskTier.rawValue,
            challengeId: challenge?.challengeId,
            challenge: challenge,
            verified: false,
            requiresMobileConfirm: requiresMobileConfirm,
            allowVoiceOnly: allowVoiceOnly,
            denyCode: nil,
            reasonCode: reasonCode,
            transcriptHash: nil,
            semanticMatchScore: nil,
            policyRef: policyRef,
            nextAction: nextAction
        )
    }

    func replayStateForVoiceAuthorizationResolution(
        resolution: SupervisorVoiceAuthorizationResolution,
        forceCancel: Bool
    ) -> VoiceReplayEventState {
        if forceCancel {
            return .cancelled
        }

        switch resolution.state {
        case .pending:
            return .pending
        case .escalatedToMobile:
            return .escalated
        case .verified:
            return .verified
        case .denied:
            return .denied
        case .failClosed:
            return .failClosed
        }
    }

    func replaySummaryForVoiceAuthorizationResolution(
        resolution: SupervisorVoiceAuthorizationResolution,
        challengeToken: String,
        forceCancel: Bool
    ) -> String {
        if forceCancel {
            return "授权挑战已取消"
        }

        switch resolution.state {
        case .pending:
            return "授权挑战已发起（\(challengeToken)）"
        case .escalatedToMobile:
            return "授权已升级到移动端确认（\(challengeToken)）"
        case .verified:
            return "口头授权已验证通过（\(challengeToken)）"
        case .denied:
            return "语音授权已被拒绝（\(challengeToken)）"
        case .failClosed:
            return "语音授权保持 fail-closed（\(challengeToken)）"
        }
    }

    func conciseVoiceAuthorizationScript(
        resolution: SupervisorVoiceAuthorizationResolution,
        challengeToken: String
    ) -> String {
        switch resolution.state {
        case .pending:
            return "已发出语音授权挑战（Voice authorization challenge issued）。Challenge \(challengeToken)。"
        case .escalatedToMobile:
            return "语音授权需要移动端确认（Voice authorization requires mobile confirmation）。Challenge \(challengeToken)。"
        case .verified:
            return "语音授权已验证通过（Voice authorization verified）。Challenge \(challengeToken)。"
        case .denied:
            let deny = resolution.denyCode ?? "denied"
            return "语音授权已拒绝（Voice authorization denied）。Reason \(deny)。"
        case .failClosed:
            let reason = resolution.reasonCode ?? "unknown"
            return "语音授权已进入失败闭锁（Voice authorization failed closed）。Reason \(reason)。"
        }
    }

    func shouldCancelActiveVoiceAuthorization(from text: String) -> Bool {
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return false }
        let cancelTokens = [
            "取消",
            "取消授权",
            "停止授权",
            "cancel",
            "abort",
            "stop"
        ]
        return cancelTokens.contains { normalized.contains(normalizedLookupKey($0)) }
    }

    func shouldRepeatActiveVoiceAuthorizationPrompt(for text: String) -> Bool {
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return false }
        let tokens = [
            "再说一遍",
            "重复一下",
            "怎么说",
            "提示",
            "help",
            "repeat",
            "challenge",
            "状态",
            "status",
            "what do i say"
        ]
        return tokens.contains { normalized.contains(normalizedLookupKey($0)) }
    }

    func parseVoiceAuthorizationPromptScope(
        _ scopeText: String
    ) -> VoiceAuthorizationPromptScopeSummary {
        let normalized = scopeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return VoiceAuthorizationPromptScopeSummary(fields: [:], freeformSegments: [])
        }

        var fields: [String: String] = [:]
        var freeformSegments: [String] = []
        let segments = normalized
            .replacingOccurrences(of: "\n", with: ";")
            .split(separator: ";")

        for rawSegment in segments {
            let segment = String(rawSegment).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !segment.isEmpty else { continue }
            if let separator = segment.firstIndex(of: "=") {
                let key = String(segment[..<separator])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let value = String(segment[segment.index(after: separator)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty, !value.isEmpty {
                    fields[key] = value
                    continue
                }
            }
            freeformSegments.append(segment)
        }

        if fields.isEmpty, freeformSegments.isEmpty {
            freeformSegments.append(normalized)
        }

        return VoiceAuthorizationPromptScopeSummary(
            fields: fields,
            freeformSegments: freeformSegments
        )
    }

    func voiceAuthorizationRiskSpeechText(_ riskTier: LaneRiskTier) -> String {
        switch riskTier {
        case .low:
            return "低风险"
        case .medium:
            return "中风险"
        case .high:
            return "高风险"
        case .critical:
            return "关键风险"
        }
    }

    func voiceAuthorizationPromptHeadline(
        request: SupervisorVoiceAuthorizationRequest,
        scopeSummary: VoiceAuthorizationPromptScopeSummary
    ) -> String {
        let project = scopeSummary.project.map { capped($0, maxChars: 32) }
        let capability = scopeSummary.capability.map { capped($0, maxChars: 40) }
        let source = scopeSummary.source.map { capped($0, maxChars: 36) }
        let goal = scopeSummary.goal.map { capped($0, maxChars: 48) }
        let rawScope = scopeSummary.rawScope.map { capped($0, maxChars: 48) }
        let actionText = request.actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.isEmpty ? nil : capped(actionText, maxChars: 48)

        let summary: String
        if let project, let capability {
            summary = "\(project) 现在要处理一笔 \(capability) 授权"
        } else if let capability {
            summary = "现在要处理一笔 \(capability) 授权"
        } else if let project {
            summary = "\(project) 现在有一笔待确认授权"
        } else if let goal {
            summary = "当前要确认的一次受治理执行，目标是 \(goal)"
        } else if let action {
            summary = "当前要确认的动作是 \(action)"
        } else if let rawScope {
            summary = "当前要确认一笔语音授权：\(rawScope)"
        } else {
            summary = "当前有一笔待确认语音授权"
        }

        let sourceSuffix = source.map { "，来源是 \($0)" } ?? ""
        return "这是一笔\(voiceAuthorizationRiskSpeechText(request.riskTier))语音授权。\(summary)\(sourceSuffix)。"
    }

    func voiceAuthorizationPromptInstructionLine(
        challengeCode: String,
        requiresMobileConfirm: Bool,
        mobileConfirmed: Bool
    ) -> String {
        let normalizedCode = challengeCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let instruction = normalizedCode.isEmpty
            ? "继续说授权短语即可"
            : "说授权短语 \(normalizedCode)"

        if requiresMobileConfirm {
            if mobileConfirmed {
                return "移动端确认已记录，现在直接\(instruction)。"
            }
            return "先在手机上确认，再\(instruction)。"
        }
        return "现在直接\(instruction)。"
    }

    func renderActiveVoiceAuthorizationPrompt(
        request: SupervisorVoiceAuthorizationRequest
    ) -> String {
        let actionText = request.actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let challengeToken = activeVoiceChallenge?.challengeId.trimmingCharacters(in: .whitespacesAndNewlines) ?? "n/a"
        let challengeCode = activeVoiceChallenge?.challengeCode.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let requiresMobileConfirm = voiceAuthorizationResolution?.requiresMobileConfirm ?? false
        let scopeSummary = parseVoiceAuthorizationPromptScope(request.scopeText)
        let actionUsedAsHeadlineFallback =
            scopeSummary.project == nil &&
            scopeSummary.capability == nil &&
            scopeSummary.goal == nil &&
            scopeSummary.rawScope == nil

        var lines: [String] = []
        lines.append(
            voiceAuthorizationPromptHeadline(
                request: request,
                scopeSummary: scopeSummary
            )
        )
        lines.append(
            voiceAuthorizationPromptInstructionLine(
                challengeCode: challengeCode,
                requiresMobileConfirm: requiresMobileConfirm,
                mobileConfirmed: voiceAuthorizationMobileConfirmationLatched
            )
        )
        if let reason = scopeSummary.reason {
            lines.append("原因：\(capped(reason, maxChars: 96))")
        }
        let amountText = request.amountText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !amountText.isEmpty {
            lines.append("约束：\(capped(amountText, maxChars: 96))")
        }
        if !actionText.isEmpty, !actionUsedAsHeadlineFallback {
            lines.append("目标动作：\(capped(actionText, maxChars: 96))")
        }
        if challengeToken != "n/a" {
            lines.append("challenge=\(challengeToken)")
        }
        return lines.joined(separator: "\n")
    }

    func shouldPreserveVoiceAuthorizationMobileConfirmationLatch(
        resolution: SupervisorVoiceAuthorizationResolution,
        request: SupervisorVoiceAuthorizationRequest?,
        previousChallengeId: String,
        previousRequestId: String
    ) -> Bool {
        let nextChallengeId = (resolution.challengeId ?? resolution.challenge?.challengeId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let nextRequestId = (request?.requestId ?? resolution.requestId)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousChallengeId.isEmpty,
              !nextChallengeId.isEmpty,
              !previousRequestId.isEmpty,
              !nextRequestId.isEmpty else {
            return false
        }
        return previousChallengeId == nextChallengeId && previousRequestId == nextRequestId
    }

    func shouldPreserveActiveVoiceAuthorizationStateAfterFailClosed(
        _ resolution: SupervisorVoiceAuthorizationResolution,
        preserveRequested: Bool
    ) -> Bool {
        guard preserveRequested, resolution.state == .failClosed else { return false }
        switch HubRouteStateMachine.normalizedReasonToken(resolution.reasonCode) {
        case "challenge_expired",
             "challenge_missing",
             "replay_detected",
             "voice_authorization_not_started",
             "request_id_empty",
             "template_id_empty",
             "challenge_id_empty",
             "verify_nonce_empty",
             "user_cancelled":
            return false
        default:
            return true
        }
    }

    func inferredMobileConfirmationState(
        from text: String,
        requiresMobileConfirm: Bool
    ) -> Bool {
        guard requiresMobileConfirm else { return false }
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return false }
        let tokens = [
            "手机已确认",
            "移动端已确认",
            "已经确认",
            "已确认",
            "mobile confirmed",
            "confirmed on phone",
            "phone confirmed"
        ]
        return tokens.contains { normalized.contains(normalizedLookupKey($0)) }
    }

    func isStandaloneMobileConfirmationUtterance(
        _ text: String,
        requiresMobileConfirm: Bool
    ) -> Bool {
        guard requiresMobileConfirm else { return false }
        var remainder = normalizedLookupKey(text)
        guard !remainder.isEmpty else { return false }

        let fragments = [
            "手机已确认",
            "移动端已确认",
            "mobile confirmed",
            "confirmed on phone",
            "phone confirmed",
            "paired mobile confirmation",
            "手机",
            "移动端",
            "mobile",
            "phone",
            "paired",
            "terminal",
            "确认",
            "已确认",
            "已经确认",
            "confirmed",
            "confirm",
            "already",
            "done",
            "ok",
            "okay",
            "好了",
            "已经",
            "已",
            "了",
            "在",
            "上",
            "我",
            "现在"
        ]

        for fragment in fragments.sorted(by: { $0.count > $1.count }) {
            let normalizedFragment = normalizedLookupKey(fragment)
            guard !normalizedFragment.isEmpty else { continue }
            remainder = remainder.replacingOccurrences(of: normalizedFragment, with: "")
        }

        return remainder.isEmpty
    }

    func inferredVoiceAuthorizationSemanticMatchScore(
        from text: String,
        mobileConfirmed: Bool
    ) -> Double {
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return 0.95 }
        if mobileConfirmed {
            return 0.99
        }
        if normalized.count >= 20 {
            return 0.99
        }
        return 0.97
    }

    func renderActiveVoiceAuthorizationVerificationReply(
        resolution: SupervisorVoiceAuthorizationResolution,
        request: SupervisorVoiceAuthorizationRequest
    ) -> String {
        let actionText = request.actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let challengeToken = resolution.challengeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "n/a"

        switch resolution.state {
        case .pending:
            return "语音授权挑战仍在等待校验（challenge=\(challengeToken)）。"
        case .escalatedToMobile:
            return "语音授权仍需移动端确认（challenge=\(challengeToken)）。完成确认后继续口述授权短语。"
        case .verified:
            if actionText.isEmpty {
                return "语音授权已验证通过。"
            }
            return "语音授权已验证通过，正在继续执行：\(actionText)"
        case .denied:
            let deny = resolution.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "denied"
            let reasonText = voiceAuthorizationReasonText(for: resolution)
                ?? annotatedUserVisibleReason(raw: deny, display: nil, fallback: "语音授权未通过")
            return "语音授权被拒绝（challenge=\(challengeToken)）。原因：\(reasonText)。"
        case .failClosed:
            let reasonText = voiceAuthorizationReasonText(for: resolution)
                ?? annotatedUserVisibleReason(raw: resolution.reasonCode, display: nil)
            return "语音授权已失败闭锁（challenge=\(challengeToken)）。原因：\(reasonText)。"
        }
    }

    func pendingGrantApproveTokens() -> [String] {
        [
            "批准",
            "通过",
            "准了",
            "approve",
            "allow",
            "authorize",
            "批了",
            "批一下",
            "放行",
            "给过",
            "放过去"
        ]
    }

    func pendingGrantDenyTokens() -> [String] {
        [
            "拒绝",
            "驳回",
            "否决",
            "deny",
            "reject",
            "block",
            "别批",
            "先别批",
            "不要批",
            "别给过",
            "先别放行",
            "拦下",
            "拦一下"
        ]
    }

    func pendingGrantSubjectTokens() -> [String] {
        [
            "grant",
            "授权",
            "权限",
            "审批",
            "release",
            "deploy",
            "上线",
            "生产"
        ]
    }

    func pendingGrantDemonstrativeTokens() -> [String] {
        [
            "this",
            "这个",
            "当前",
            "这项",
            "这笔"
        ]
    }

    func normalizedVoiceLookupTerms(_ aliases: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        for alias in aliases {
            let normalized = normalizedLookupKey(alias)
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                out.append(normalized)
            }
        }
        return out
    }
}
