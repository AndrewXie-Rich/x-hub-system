import Foundation

struct SupervisorVoiceAuthorizationGuidancePresentation: Equatable {
    var summary: String
    var instructions: [String]
    var caution: String?
}

enum SupervisorVoiceAuthorizationGuidancePresentationBuilder {
    static func build(
        resolution: SupervisorVoiceAuthorizationResolution,
        challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    ) -> SupervisorVoiceAuthorizationGuidancePresentation {
        let activeChallenge = challenge ?? resolution.challenge
        let phraseInstruction = verifyPhraseInstruction(for: activeChallenge)

        switch resolution.state {
        case .pending:
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 challenge 已发出，Hub 正在等待这次口令核验。",
                instructions: [phraseInstruction],
                caution: "在口令核验通过前，受控动作会继续保持阻塞。"
            )
        case .escalatedToMobile:
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前挑战已经发出，但这条链路还差一次配对手机确认。",
                instructions: [
                    "先在配对手机上完成确认，再回来做语音核验。",
                    phraseInstruction
                ],
                caution: "在 mobile confirmation 完成前，XT 不会放行这次受控动作。"
            )
        case .verified:
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "Hub 已完成这次 spoken challenge 的核验，可以从中断点继续执行。",
                instructions: [
                    "继续当前受控动作即可；后续若再次触发高风险动作，系统会重新发起新的 challenge。"
                ],
                caution: nil
            )
        case .denied:
            return deniedPresentation(
                denyCode: normalized(resolution.denyCode),
                phraseInstruction: phraseInstruction
            )
        case .failClosed:
            return failClosedPresentation(
                reasonCode: normalized(resolution.reasonCode),
                phraseInstruction: phraseInstruction
            )
        }
    }

    private static func deniedPresentation(
        denyCode: String?,
        phraseInstruction: String
    ) -> SupervisorVoiceAuthorizationGuidancePresentation {
        switch denyCode {
        case "voice_only_forbidden":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前风险档禁止只靠语音直接放行。",
                instructions: [
                    "先在配对手机上完成确认。",
                    "然后重新发起新的 challenge，再做语音核验。"
                ],
                caution: "这次被拒绝的 challenge 已不可复用。"
            )
        case "mobile_confirmation_required":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 challenge 明确要求先完成移动端确认。",
                instructions: [
                    "先在配对手机上完成确认。",
                    "确认完成后，重新发起新的 challenge。"
                ],
                caution: "旧 challenge 已进入 denied 状态，不要继续复用。"
            )
        case "challenge_missing":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "这次 spoken response 没有对上一个有效 challenge。",
                instructions: [
                    "重新发起新的 challenge。",
                    "拿到新口令后，再重新说授权短语。"
                ],
                caution: "旧 challenge 和旧口令都不要继续复用。"
            )
        case "semantic_ambiguous":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "Hub 收到了口令，但语义摘要还不够清楚，所以拒绝了这次授权。",
                instructions: [
                    "把授权动作和范围说得更完整、更清楚一些。",
                    "然后重新发起新的 challenge，再重新核验。"
                ],
                caution: "一旦返回 denied，旧 challenge 会失效，不能直接重试同一个 challenge。"
            )
        case "device_not_bound":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "这次口令回复不是从预期绑定设备上完成的。",
                instructions: [
                    "切回已绑定的语音设备。",
                    "然后重新发起新的 challenge，再重新核验。"
                ],
                caution: "旧 challenge 已失效，满足设备前置条件后也需要重新发起。"
            )
        case "challenge_expired":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 challenge 在核验前已经过期。",
                instructions: [
                    "重新发起新的 challenge。",
                    "拿到新口令后，再重新说授权短语。"
                ],
                caution: "过期的 challenge 和旧口令都不能再继续使用。"
            )
        case "replay_detected":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "Hub 把这次核验视为重复/重放，当前 challenge 已被终止。",
                instructions: [
                    "重新发起新的 challenge。",
                    "下一次核验必须使用新的 verify nonce。"
                ],
                caution: "任何继续复用旧 challenge 的做法都会再次被拒绝。"
            )
        default:
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "Hub 已拒绝这次语音授权。",
                instructions: [
                    "先修复当前拒绝原因对应的前置条件。",
                    "然后重新发起新的 challenge，再重新核验。"
                ],
                caution: "被拒绝的 challenge 不会在后台自动恢复。"
            )
        }
    }

    private static func failClosedPresentation(
        reasonCode: String?,
        phraseInstruction: String
    ) -> SupervisorVoiceAuthorizationGuidancePresentation {
        switch reasonCode {
        case "challenge_expired":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "旧 challenge 已过期，并已按 fail-closed 规则清理。",
                instructions: [
                    "重新发起新的 challenge。",
                    "拿到新口令后，再重新说授权短语。"
                ],
                caution: "过期 challenge、旧口令和旧 verify nonce 都不要再复用。"
            )
        case "challenge_missing":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 challenge 已不存在，或者这条授权上下文已经失效。",
                instructions: [
                    "重新发起新的语音授权 challenge。"
                ],
                caution: "没有有效 challenge 时，XT 会持续保持 fail-closed。"
            )
        case "replay_detected":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 challenge 已进入 replay/fail-closed 处理，不能从原状态继续恢复。",
                instructions: [
                    "清理旧状态并重新发起新的 challenge。",
                    "下一次核验必须使用新的 verify nonce。"
                ],
                caution: "旧 challenge 不允许从中断点继续恢复。"
            )
        case "mobile_confirmation_missing":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "这条链路保持 fail-closed，因为移动端确认还没完成。",
                instructions: [
                    "先在配对手机上完成确认。",
                    phraseInstruction
                ],
                caution: "当前 challenge 仍保留，完成 mobile confirmation 后可以继续核验。"
            )
        case "voice_authorization_not_started":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前没有活动中的语音挑战。",
                instructions: [
                    "先重新发起新的语音授权 challenge。"
                ],
                caution: "没有活动 challenge 时，XT 不会隐式恢复执行。"
            )
        case "request_id_empty", "template_id_empty", "challenge_id_empty", "verify_nonce_empty":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "语音授权上下文不完整，当前记录不能安全继续。",
                instructions: [
                    "清理当前授权状态。",
                    "然后重新发起新的 challenge。"
                ],
                caution: "不要尝试继续复用当前 challenge 记录。"
            )
        case "user_cancelled":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "这次 challenge 已被明确取消。",
                instructions: [
                    "如果还要继续，请重新发起新的语音授权。"
                ],
                caution: "取消后的 challenge 不会再被复用。"
            )
        case "hub_env_missing":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "Hub pairing/runtime profile 当前不完整，语音授权链路没有安全完成。",
                instructions: [
                    "先修复 Hub pairing 或运行时配置。",
                    "修复后重新发起新的 challenge。"
                ],
                caution: "在 Hub 路由恢复前，XT 会继续保持 fail-closed。"
            )
        case "voice_grant_file_ipc_not_supported":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "当前 transport 还停在 file IPC，而这条链路不支持语音授权。",
                instructions: [
                    "先切到 remote/grpc Hub transport。",
                    "然后重新发起新的 challenge。"
                ],
                caution: "在 transport 修好之前，继续点核验没有意义。"
            )
        case "node_missing":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "本地运行时依赖缺失，Hub 侧语音授权不能完整执行。",
                instructions: [
                    "先修复本地运行时依赖。",
                    "修复后重新发起新的 challenge。"
                ],
                caution: "依赖未恢复前，XT 会继续保持 fail-closed。"
            )
        case "remote_voice_grant_challenge_failed", "remote_voice_grant_verify_failed":
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "远端 Hub 的语音授权路由没有成功返回可用结果。",
                instructions: [
                    "先修复 pairing、transport 或 Hub runtime。",
                    "然后重新发起新的 challenge。"
                ],
                caution: "远端路由恢复前，XT 不会放行高风险动作。"
            )
        default:
            return SupervisorVoiceAuthorizationGuidancePresentation(
                summary: "这条语音授权链路没有安全完成，所以 XT 继续保持 fail-closed。",
                instructions: [
                    "优先修复当前上游 voice authorization route。",
                    "修复后重新发起新的 challenge。"
                ],
                caution: "在修复完成前，受控动作不会被假装恢复。"
            )
        }
    }

    private static func verifyPhraseInstruction(
        for challenge: HubIPCClient.VoiceGrantChallengeSnapshot?
    ) -> String {
        if let challengeCode = normalized(challenge?.challengeCode) {
            return "核验时请重复你刚才说出的授权短语，并包含当前口令 \(challengeCode)。"
        }
        return "核验时请重复你刚才说出的授权短语，并使用当前 challenge。"
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = String(value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
