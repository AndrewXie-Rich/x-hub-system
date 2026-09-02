import Foundation

extension SupervisorManager {
    func voiceAuthorizationReasonText(
        for resolution: SupervisorVoiceAuthorizationResolution
    ) -> String? {
        let guidance = SupervisorVoiceAuthorizationGuidancePresentationBuilder.build(
            resolution: resolution,
            challenge: resolution.challenge
        )

        switch resolution.state {
        case .denied:
            return annotatedUserVisibleReason(
                raw: resolution.denyCode,
                display: guidance.summary,
                fallback: guidance.summary
            )
        case .failClosed:
            return annotatedUserVisibleReason(
                raw: resolution.reasonCode,
                display: guidance.summary,
                fallback: guidance.summary
            )
        default:
            return nil
        }
    }

    func messageContainsMeaningfulSearchTerm(
        _ userMessage: String,
        source: String
    ) -> Bool {
        let foldedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let loweredSource = source
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()

        let tokens = loweredSource
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { token in
                guard !token.isEmpty else { return false }
                let isASCIIOnly = token.unicodeScalars.allSatisfy { $0.isASCII }
                return isASCIIOnly ? token.count >= 4 : token.count >= 2
            }

        return tokens.contains { foldedMessage.contains($0) }
    }

    func pendingGrantVoiceAliasTerms(
        for grant: SupervisorPendingGrant
    ) -> [String] {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = "\(capability) \(reason)"
        var aliases: [String] = []

        if combined.contains("web_fetch") || combined.contains("web.fetch") || combined.contains("联网") {
            aliases.append(contentsOf: ["web", "fetch", "browser", "联网"])
        }
        if combined.contains("ai_generate_paid") || combined.contains("ai.generate.paid") || combined.contains("付费") {
            aliases.append(contentsOf: ["paid", "billing", "budget", "付费", "预算"])
        }
        if isLocalAICapabilityToken(combined) || combined.contains("本地") {
            aliases.append(contentsOf: ["local", "本地"])
        }
        if combined.contains("ai_embed_local") || combined.contains("ai.embed.local") || combined.contains("嵌入") || combined.contains("向量") {
            aliases.append(contentsOf: ["embed", "embedding", "vector", "嵌入", "向量"])
        }
        if combined.contains("ai_audio_tts_local") || combined.contains("ai.audio.tts.local") || combined.contains("tts") || combined.contains("语音合成") {
            aliases.append(contentsOf: ["tts", "speech", "voice", "语音", "合成"])
        }
        if combined.contains("ai_audio_local") || combined.contains("ai.audio.local") || combined.contains("转写") || combined.contains("语音识别") {
            aliases.append(contentsOf: ["audio", "speech", "transcribe", "asr", "音频", "转写"])
        }
        if combined.contains("ai_vision_local") || combined.contains("ai.vision.local") || combined.contains("vision") || combined.contains("image") || combined.contains("ocr") || combined.contains("图像") {
            aliases.append(contentsOf: ["vision", "image", "ocr", "图像"])
        }
        if combined.contains("release") || combined.contains("deploy") || combined.contains("production") || combined.contains("上线") || combined.contains("发布") {
            aliases.append(contentsOf: ["release", "deploy", "production", "上线", "发布", "生产"])
        }
        if combined.contains("connector") {
            aliases.append("connector")
        }
        if combined.contains("secret") || combined.contains("credential") || combined.contains("token") {
            aliases.append(contentsOf: ["secret", "credential", "token"])
        }

        return normalizedVoiceLookupTerms(aliases)
    }

    func pendingGrantVoiceAuthorizationRiskTier(
        for grant: SupervisorPendingGrant,
        approve: Bool
    ) -> LaneRiskTier {
        let capability = grant.capability.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let reason = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let combined = "\(capability) \(reason)"

        if combined.contains("web_fetch") ||
            combined.contains("web.fetch") ||
            combined.contains("ai_generate_paid") ||
            combined.contains("ai.generate.paid") ||
            combined.contains("production") ||
            combined.contains("prod") ||
            combined.contains("release") ||
            combined.contains("deploy") ||
            combined.contains("connector") ||
            combined.contains("secret") ||
            combined.contains("token") ||
            combined.contains("上线") ||
            combined.contains("生产") ||
            combined.contains("发布") ||
            combined.contains("联网") {
            return .high
        }

        if isLocalAICapabilityToken(capability) {
            return approve ? .medium : .low
        }

        return approve ? .high : .medium
    }

    func pendingGrantVoiceDecision(in text: String) -> Bool? {
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return nil }
        return pendingGrantDecision(
            in: text,
            excludeGuidanceLikeTexts: false
        )
    }

    func pendingGrantDecision(
        in text: String,
        excludeGuidanceLikeTexts: Bool
    ) -> Bool? {
        let normalized = normalizedLookupKey(text)
        guard !normalized.isEmpty else { return nil }
        if excludeGuidanceLikeTexts,
           normalizedContainsAny(normalized, ["建议", "方案", "方向", "guidance"]) {
            return nil
        }

        let hasApprove = normalizedContainsAny(normalized, pendingGrantApproveTokens())
        let hasDeny = normalizedContainsAny(normalized, pendingGrantDenyTokens())
        guard hasApprove != hasDeny else { return nil }

        let explicitGrantID = explicitPendingGrantRequestId(in: text) != nil
        let hasSubject = normalizedContainsAny(normalized, pendingGrantSubjectTokens())
        let hasDemonstrative = normalizedContainsAny(normalized, pendingGrantDemonstrativeTokens())
        let hasGrantContext = hasRecentSupervisorPendingGrantContext(
            currentUserMessage: text
        )
        guard explicitGrantID || hasSubject || hasDemonstrative || hasGrantContext else { return nil }
        return hasApprove
    }

    func hasRecentSupervisorGuidanceContext(
        currentUserMessage: String
    ) -> Bool {
        recentSupervisorContextMatches(
            [
                "待确认 guidance",
                "这条 guidance",
                "guidance",
                "injection=",
                "review guidance"
            ],
            currentUserMessage: currentUserMessage
        )
    }

    func hasRecentSupervisorPendingGrantContext(
        currentUserMessage: String
    ) -> Bool {
        recentSupervisorContextMatches(
            [
                "Hub grant",
                "Hub 授权",
                "待授权",
                "grant=",
                "grant_request_id",
                "联网访问",
                "web.fetch",
                "web_fetch",
                "付费生成"
            ],
            currentUserMessage: currentUserMessage
        )
    }

    func recentSupervisorContextMatches(
        _ needles: [String],
        currentUserMessage: String,
        maxMessages: Int = 4
    ) -> Bool {
        let currentNormalized = normalizedLookupKey(currentUserMessage)
        let now = Date().timeIntervalSince1970
        var skippedCurrentUserMessage = false
        var inspected = 0

        for message in frontstageConversationMessages.reversed() {
            let messageNormalized = normalizedLookupKey(message.content)
            if messageNormalized.isEmpty {
                continue
            }
            if !skippedCurrentUserMessage,
               message.role == .user,
               messageNormalized == currentNormalized {
                skippedCurrentUserMessage = true
                continue
            }
            if message.role == .user {
                break
            }
            guard message.role == .assistant || message.role == .system else {
                continue
            }
            if now - message.timestamp > supervisorEllipsisContextCarryWindowSec {
                break
            }
            inspected += 1
            if normalizedContainsAny(messageNormalized, needles) {
                return true
            }
            if inspected >= maxMessages {
                break
            }
        }
        return false
    }

    func explicitPendingGrantRequestId(in userMessage: String) -> String? {
        for key in ["grant_request_id", "grant_id"] {
            let value = supervisorTriggerContextValue(key, userMessage: userMessage)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let value, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    func refinedVoicePendingGrantCandidates(
        _ candidates: [SupervisorPendingGrant],
        userMessage: String
    ) -> [SupervisorPendingGrant] {
        let foldedMessage = userMessage
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        let normalizedMessage = normalizedLookupKey(userMessage)

        return candidates.filter { grant in
            let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !grantId.isEmpty, foldedMessage.contains(grantId) {
                return true
            }

            let modelId = grant.modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !modelId.isEmpty, foldedMessage.contains(modelId) {
                return true
            }
            let projectNameKey = normalizedLookupKey(grant.projectName)
            if !projectNameKey.isEmpty, normalizedMessage.contains(projectNameKey) {
                return true
            }
            if normalizedSupervisorProjectAliasTerms(grant.projectName).contains(where: {
                normalizedMessage.contains($0)
            }) {
                return true
            }

            if messageContainsMeaningfulSearchTerm(userMessage, source: grant.reason) {
                return true
            }
            if messageContainsMeaningfulSearchTerm(userMessage, source: grant.capability) {
                return true
            }

            return pendingGrantVoiceAliasTerms(for: grant).contains { term in
                foldedMessage.contains(term)
            } || pendingGrantVoiceSourceAliasTerms(for: grant).contains { term in
                !normalizedMessage.isEmpty && normalizedMessage.contains(term)
            }
        }
    }

    func explicitPendingHubGrantOrdinalCandidate(
        candidates: [SupervisorPendingGrant],
        userMessage: String
    ) -> SupervisorPendingGrant? {
        guard let index = explicitSupervisorOrdinalSelectionIndex(
            in: userMessage,
            maxCount: candidates.count
        ) else {
            return nil
        }
        guard candidates.indices.contains(index) else { return nil }
        return candidates[index]
    }

    func pendingGrantVoiceSourceAliasTerms(
        for grant: SupervisorPendingGrant,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [String] {
        guard let receipt = latestConnectorIngressReceipt(for: grant, now: now) else {
            return []
        }

        let triggerType = hubConnectorIngressTriggerType(for: receipt)
        var aliases = remoteChannelProviderVoiceAliasTerms(receipt.connector)
        aliases.append(hubConnectorIngressDisplayName(receipt, triggerType: triggerType))
        aliases.append(contentsOf: hubConnectorIngressVoiceAliasTerms(receipt, triggerType: triggerType))
        return normalizedVoiceLookupTerms(aliases)
    }

    func makeVoiceAuthorizationRequestForPendingHubGrantAction(
        grant: SupervisorPendingGrant,
        approve: Bool
    ) -> SupervisorVoiceAuthorizationRequest {
        let stableGrantToken = {
            let preferred = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !preferred.isEmpty {
                return normalizedLookupKey(preferred)
            }
            return normalizedLookupKey(grant.id)
        }()
        let actionToken = approve ? "approve" : "deny"
        let capabilityText = grantCapabilityText(capability: grant.capability, modelId: grant.modelId)
        let reasonText = grant.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = pendingGrantSourceSummary(grant) ?? ""
        let scopeFields = [
            "project=\(grant.projectName)",
            "capability=\(capabilityText)",
            sourceText.isEmpty ? "" : "source=\(sourceText)",
            reasonText.isEmpty ? "" : "reason=\(capped(reasonText, maxChars: 96))"
        ]
        .filter { !$0.isEmpty }
        let amountText: String? = {
            if grant.requestedTokenCap > 0 {
                return "token_cap=\(grant.requestedTokenCap)"
            }
            if grant.requestedTtlSec > 0 {
                return "ttl_sec=\(grant.requestedTtlSec)"
            }
            return nil
        }()
        let riskTier = pendingGrantVoiceAuthorizationRiskTier(
            for: grant,
            approve: approve
        )

        return SupervisorVoiceAuthorizationRequest(
            requestId: "voice_pending_grant_\(actionToken)_\(stableGrantToken)",
            projectId: grant.projectId,
            templateId: approve
                ? "voice.grant.pending_hub_grant_approve.v1"
                : "voice.grant.pending_hub_grant_deny.v1",
            actionText: approve
                ? "Approve Hub grant for \(grant.projectName)"
                : "Deny Hub grant for \(grant.projectName)",
            scopeText: scopeFields.joined(separator: "; "),
            amountText: amountText,
            riskTier: riskTier,
            boundDeviceId: preferredVoiceBoundDeviceId(for: grant.projectId),
            mobileTerminalId: nil,
            challengeCode: nil,
            ttlMs: riskTier >= .high ? 180_000 : 120_000
        )
    }

    func renderPendingGrantVoiceAuthorizationReply(
        resolution: SupervisorVoiceAuthorizationResolution,
        grant: SupervisorPendingGrant,
        approve: Bool,
        challengeAlreadyActive: Bool
    ) -> String {
        let actionText = approve ? "批准" : "拒绝"
        let capabilityText = grantCapabilityText(capability: grant.capability, modelId: grant.modelId)
        let challengeToken = resolution.challengeId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "n/a"
        let sourceText = pendingGrantSourceSummary(grant) ?? ""
        let grantSubject = sourceText.isEmpty
            ? grant.projectName
            : "\(grant.projectName)（来源：\(sourceText)）"

        switch resolution.state {
        case .pending:
            if challengeAlreadyActive {
                return "项目 \(grantSubject) 的 \(capabilityText) \(actionText)语音授权仍在等待口令校验（challenge=\(challengeToken)）。"
            }
            return "我已为 \(grantSubject) 的 \(capabilityText) 发起\(actionText)语音授权（challenge=\(challengeToken)）。请继续说出授权短语。"

        case .escalatedToMobile:
            if challengeAlreadyActive {
                return "项目 \(grantSubject) 的 \(capabilityText) \(actionText)语音授权仍等待移动端确认（challenge=\(challengeToken)）。"
            }
            return "我已为 \(grantSubject) 的 \(capabilityText) 发起\(actionText)语音授权（challenge=\(challengeToken)）。先在配对移动端确认，再继续口令校验。"

        case .verified:
            return "语音授权已通过，正在对 \(grantSubject) 执行这笔 Hub 授权的\(actionText)操作。"

        case .denied:
            let denyCode = resolution.denyCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "denied"
            let reasonText = voiceAuthorizationReasonText(for: resolution)
                ?? annotatedUserVisibleReason(raw: denyCode, display: nil, fallback: "语音授权未通过")
            return "这次对 \(grantSubject) 这笔 Hub 授权的\(actionText)语音授权未通过。原因：\(reasonText)。"

        case .failClosed:
            let reasonText = voiceAuthorizationReasonText(for: resolution)
                ?? annotatedUserVisibleReason(raw: resolution.reasonCode, display: nil)
            return "我没有执行 \(grantSubject) 这笔 Hub 授权的\(actionText)操作。语音授权已 fail-closed。原因：\(reasonText)。"
        }
    }

    func renderPendingGrantVoiceAmbiguityReply(
        candidates: [SupervisorPendingGrant],
        focusedProjectName: String?
    ) -> String {
        let header = XTHubGrantPresentation.ambiguityHeader(projectName: focusedProjectName)

        let lines = candidates.prefix(3).enumerated().map { offset, grant in
            let summary = pendingGrantSummaryLine(
                grant,
                includeGrantToken: true,
                includeScope: true,
                includeReason: false,
                includeSource: true
            )
            return "\(offset + 1). \(summary)"
        }

        return ([header] + lines + [
            "如果要指定某一笔，可以直接补授权单号，也可以说“第2个”或补项目名、能力后再说批准或拒绝。"
        ]).joined(separator: "\n")
    }

    func voicePendingGrantPostActionReply(
        grant: SupervisorPendingGrant,
        approve: Bool,
        result: HubIPCClient.PendingGrantActionResult
    ) async -> SupervisorVoicePendingGrantReply {
        let grantId = grant.grantRequestId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !result.ok {
            let replyText = XTHubGrantPresentation.voiceDecisionFailureReply(
                projectName: grant.projectName,
                intent: approve ? .approve : .deny,
                capability: grant.capability,
                modelId: grant.modelId,
                grantRequestId: grantId,
                reasonCode: result.reasonCode
            )
            return SupervisorVoicePendingGrantReply(
                text: replyText,
                spokenOutcome: speakSupervisorVoiceReply(replyText)
            )
        }

        let request = HubIPCClient.SupervisorBriefProjectionRequestPayload(
            requestId: "voice_grant_follow_up_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.lowercased())",
            projectId: grant.projectId,
            runId: nil,
            missionId: nil,
            projectionKind: "progress_brief",
            trigger: "critical_path_changed",
            includeTtsScript: true,
            includeCardSummary: true,
            maxEvidenceRefs: 4
        )
        let fetcher = supervisorBriefProjectionRequestOverride
            ?? { payload in
                await HubIPCClient.requestSupervisorBriefProjection(payload)
            }
        let projectionResult = await fetcher(request)
        if projectionResult.ok, let projection = projectionResult.projection {
            let replyText = renderSupervisorBriefProjectionVoiceReply(
                projection,
                projectName: grant.projectName
            )
            let script = projectionVoiceScript(from: projection)
            let spokenOutcome: SupervisorSpeechSynthesizer.Outcome
            if script.isEmpty {
                spokenOutcome = speakSupervisorVoiceReply(replyText)
            } else {
                let job = SupervisorVoiceTTSJob(
                    trigger: .authorization,
                    priority: .normal,
                    script: script,
                    dedupeKey: "voice-grant-followup:\(projectionVoiceDedupeKey(from: projection))"
                )
                spokenOutcome = dispatchSupervisorVoiceJob(
                    job,
                    preferences: currentVoicePreferences(),
                    source: "pending_grant_follow_up",
                    suppressRapidSameSourceRepeat: false,
                    cancelPendingHeartbeat: true
                )
            }
            return SupervisorVoicePendingGrantReply(
                text: replyText,
                spokenOutcome: spokenOutcome
            )
        }

        let capabilityText = grantCapabilityText(capability: grant.capability, modelId: grant.modelId)
        let actionLine = approve
            ? "已批准 \(grant.projectName) 的 \(capabilityText) Hub 授权。"
            : "已拒绝 \(grant.projectName) 的 \(capabilityText) Hub 授权。"
        let presentation = supervisorBriefProjectionUnavailablePresentation(
            projectName: grant.projectName,
            reasonCode: projectionResult.reasonCode,
            localSignal: heartbeatGovernanceVoicePresentation(),
            contextLines: [actionLine],
            contextScript: [actionLine],
            dedupePrefix: "voice-grant-follow-up"
        )
        return SupervisorVoicePendingGrantReply(
            text: presentation.text,
            spokenOutcome: dispatchSupervisorBriefProjectionUnavailablePresentation(
                presentation,
                trigger: .authorization,
                source: "pending_grant_follow_up"
            )
        )
    }
}
