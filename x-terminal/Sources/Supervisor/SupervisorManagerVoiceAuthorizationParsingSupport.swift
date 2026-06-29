import Foundation

extension SupervisorManager {
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
