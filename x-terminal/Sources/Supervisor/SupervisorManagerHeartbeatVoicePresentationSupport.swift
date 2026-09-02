import Foundation

extension SupervisorManager {
    @discardableResult
    func speakSupervisorVoiceReply(
        _ text: String,
        personaSlot: SupervisorPersonaSlot? = nil
    ) -> SupervisorSpeechSynthesizer.Outcome {
        let script = conciseVoiceReplyScript(text)
        guard !script.isEmpty else { return .suppressed("empty_script") }
        let dedupeKey = "voice-reply:\(capped(script.joined(separator: "|"), maxChars: 96))"
        let job = SupervisorVoiceTTSJob(
            trigger: .userQueryReply,
            priority: .normal,
            script: script,
            dedupeKey: dedupeKey
        )
        return dispatchSupervisorVoiceJob(
            job,
            preferences: currentVoicePreferences(personaSlot: personaSlot),
            source: "user_query_reply",
            suppressRapidSameSourceRepeat: false,
            cancelPendingHeartbeat: true
        )
    }

    func heartbeatVoiceReadinessContentLine(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
        return "• \(capped(signal.overallSummary, maxChars: 120))\(actionSuffix)"
    }

    func heartbeatVoiceReadinessTopBoardIcon(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return signal.readyForFirstTask ? "🔗" : "⚠️"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return signal.readyForFirstTask ? "🎙️" : "⚠️"
        }
    }

    func heartbeatVoiceReadinessTopBoardLabel(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return "Hub Pairing"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "Supervisor Voice"
        }
    }

    func heartbeatVoiceReadinessCountLabel(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return "配对续连项"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "语音修复项"
        }
    }

    func heartbeatVoiceReadinessSectionTitle(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return "配对续连："
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "语音就绪："
        }
    }

    func heartbeatVoiceReadinessStateText(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            let headline = signal.headline.trimmingCharacters(in: .whitespacesAndNewlines)
            return headline.isEmpty
                ? "配对续连仍需确认"
                : capped(headline, maxChars: 36)
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return signal.readyForFirstTask ? "首个语音任务已就绪" : "语音链路失败闭锁"
        }
    }

    func heartbeatVoiceReadinessNotificationTitle(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return signal.readyForFirstTask
                ? "🔗 Supervisor 心跳：配对续连仍需确认"
                : "🔗 Supervisor 心跳：配对续连待修复"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return signal.readyForFirstTask
                ? "🎙️ Supervisor 心跳：语音首个任务已就绪，但仍有修复项"
                : "🎙️ Supervisor 心跳：语音链路待修复"
        }
    }

    func heartbeatVoiceReadinessWhyImportantText(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return "这说明同网首配之外的正式异网入口还没完全确认，切网或换环境后可能断开。"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "语音链路还不稳定，相关任务可能 fail-closed 或退化。"
        }
    }

    func heartbeatVoiceReadinessDefaultNextStepText(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        switch signal.kind {
        case .pairingValidity:
            return "打开 Hub 配对并继续核对正式异网入口。"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "打开 Hub Recovery 并继续排查语音链路。"
        }
    }

    func heartbeatVoiceReadinessNextStepLine(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
        let prefix: String = {
            switch signal.kind {
            case .pairingValidity:
                return signal.readyForFirstTask ? "配对续连" : "配对续连待修复"
            case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                    .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
                return signal.readyForFirstTask ? "语音修复" : "语音 fail-closed"
            }
        }()
        return "\(prefix)：\(capped(signal.overallSummary, maxChars: 72))；\(heartbeatVoiceReadinessRecommendationLine(signal))\(actionSuffix)"
    }

    func heartbeatVoiceReadinessDestinationLabel(
        _ repairEntry: UITroubleshootDestination
    ) -> String {
        switch repairEntry {
        case .xtPairHub:
            return "连接 Hub"
        case .xtChooseModel:
            return "AI 模型"
        case .xtDiagnostics:
            return "XT Diagnostics"
        case .xtExternalTerminals:
            return "非 XT Terminal 访问"
        case .hubLAN:
            return "Hub 网络"
        case .hubPairing:
            return "Hub 配对"
        case .hubProviderKeys:
            return "Hub Provider Keys"
        case .hubModels:
            return "Hub 模型"
        case .hubGrants:
            return "Hub 授权"
        case .hubSecurity:
            return "Hub 安全边界"
        case .hubDiagnostics:
            return "Hub Recovery"
        case .systemPermissions:
            return "系统权限"
        case .homeSupervisor:
            return "Supervisor 首页"
        }
    }

    func heartbeatVoiceReadinessRecommendationLine(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        let label = heartbeatVoiceReadinessDestinationLabel(signal.repairEntry)
        guard !label.isEmpty else {
            switch signal.kind {
            case .pairingValidity:
                return "建议先核对正式异网入口"
            case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                    .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
                return "建议先处理语音修复"
            }
        }
        return "建议先查看 \(label)"
    }

    func heartbeatVoiceReadinessOperationHint(
        _ signal: HeartbeatVoiceReadinessSignal
    ) -> String {
        let label = heartbeatVoiceReadinessDestinationLabel(signal.repairEntry)
        guard !label.isEmpty else {
            switch signal.kind {
            case .pairingValidity:
                return "点开这条提醒会直接进入配对或连接相关设置，先核对正式异网入口。"
            case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                    .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
                return "点开这条提醒会直接进入语音运行时相关设置或诊断页。"
            }
        }
        switch signal.kind {
        case .pairingValidity:
            return "点开这条提醒会直接进入 \(label)，先按当前配对续连建议逐项核对。"
        case .modelRouteReadiness, .bridgeToolReadiness, .sessionRuntimeReadiness,
                .wakeProfileReadiness, .talkLoopReadiness, .ttsReadiness:
            return "点开这条提醒会直接进入 \(label)，先按当前语音修复建议逐项核对。"
        }
    }
}
