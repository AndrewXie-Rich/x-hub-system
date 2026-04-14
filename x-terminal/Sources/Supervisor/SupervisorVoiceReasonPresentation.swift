import Foundation

enum SupervisorVoiceReasonPresentation {
    static func displayText(_ raw: String?) -> String? {
        guard let trimmed = normalized(raw) else { return nil }

        if let routeText = XTRouteTruthPresentation.userVisibleReasonText(trimmed) {
            return routeText
        }

        switch normalizedToken(trimmed) {
        case "voice_route_fail_closed":
            return "当前语音链路已进入安全关闭，连续语音对话暂不可用（voice_route_fail_closed）"
        case "wake_phrase_requires_funasr_kws":
            return "当前链路不支持唤醒词，只能按住说话或手动输入（wake_phrase_requires_funasr_kws）"
        case "speech_authorization_denied":
            return "麦克风或语音识别权限尚未授权（speech_authorization_denied）"
        case "system_speech_authorization_pending":
            return "系统语音识别权限仍待确认（system_speech_authorization_pending）"
        case "system_speech_authorization_denied":
            return "系统语音识别权限已被拒绝（system_speech_authorization_denied）"
        case "system_speech_authorization_restricted":
            return "系统语音识别权限当前受限（system_speech_authorization_restricted）"
        case "system_speech_recognizer_unavailable":
            return "系统语音识别引擎当前不可用（system_speech_recognizer_unavailable）"
        case "microphone_or_speech_unauthorized":
            return "麦克风或语音识别权限未就绪，当前语音链路无法启动（microphone_or_speech_unauthorized）"
        case "no_voice_engine_ready":
            return "当前没有可用的实时语音引擎，已回退到非实时链路（no_voice_engine_ready）"
        case "preferred_streaming_ready":
            return "当前优先实时语音链路已就绪（preferred_streaming_ready）"
        case "streaming_unhealthy_fallback_to_local":
            return "实时流式链路不稳定，已回退到本地语音链路（streaming_unhealthy_fallback_to_local）"
        case "system_speech_compatibility_fallback":
            return "当前已回退到系统兼容语音链路（system_speech_compatibility_fallback）"
        case "preferred_route_ready":
            return "当前指定语音链路已就绪（preferred_route_ready）"
        case "preferred_funasr_unavailable":
            return "首选 FunASR 链路当前不可用，已按策略回退（preferred_funasr_unavailable）"
        case "preferred_whisperkit_unavailable":
            return "首选 WhisperKit 链路当前不可用，已按策略回退（preferred_whisperkit_unavailable）"
        case "preferred_system_speech_unavailable":
            return "首选系统语音链路当前不可用，已按策略回退（preferred_system_speech_unavailable）"
        case "preferred_manual_text":
            return "当前使用手动文本链路（preferred_manual_text）"
        case "manual_text_only":
            return "当前链路仅支持手动文本，不支持实时语音（manual_text_only）"
        case "wake_profile_not_required":
            return "当前链路不需要唤醒词配置（wake_profile_not_required）"
        case "wake_profile_waiting_for_pairing":
            return "唤醒词配置还在等待配对链路就绪（wake_profile_waiting_for_pairing）"
        case "wake_profile_local_override_missing":
            return "本地缺少可用的唤醒词覆盖配置（wake_profile_local_override_missing）"
        case "wake_profile_pair_synced":
            return "唤醒词配置已和配对端同步（wake_profile_pair_synced）"
        case "wake_profile_cached_pair_sync":
            return "当前使用最近一次同步下来的唤醒词配置（wake_profile_cached_pair_sync）"
        case "wake_profile_pair_sync_cached_after_remote_failure":
            return "远端同步失败，当前继续使用最近一次同步下来的唤醒词配置（wake_profile_pair_sync_cached_after_remote_failure）"
        case "wake_profile_local_override_active":
            return "当前使用本地唤醒词覆盖配置（wake_profile_local_override_active）"
        case "wake_profile_local_override_fallback":
            return "远端同步不可用，当前回退到本地唤醒词覆盖配置（wake_profile_local_override_fallback）"
        case "wake_profile_stale":
            return "远端唤醒词配置已过期，当前暂时回退到按住说话（wake_profile_stale）"
        case "wake_profile_sync_pending":
            return "唤醒词配置还在等待首次同步（wake_profile_sync_pending）"
        case "voice_wake_profile_sync_unavailable":
            return "唤醒词远端同步当前不可用（voice_wake_profile_sync_unavailable）"
        case "voice_runtime_not_initialized":
            return "语音运行时尚未初始化（voice_runtime_not_initialized）"
        case "voice_transcriber_already_running":
            return "语音识别器已经在运行（voice_transcriber_already_running）"
        case "voice_transcriber_not_authorized":
            return "语音识别器缺少授权，当前不能启动（voice_transcriber_not_authorized）"
        default:
            return nil
        }
    }

    static func displayTextOrRaw(_ raw: String?) -> String? {
        guard let trimmed = normalized(raw) else { return nil }
        return displayText(trimmed) ?? trimmed
    }

    private static func normalized(_ raw: String?) -> String? {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
