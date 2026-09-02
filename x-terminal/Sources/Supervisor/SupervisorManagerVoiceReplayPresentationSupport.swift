import Foundation

extension SupervisorManager {
    func replayStateForVoiceDispatch(
        state: String
    ) -> VoiceReplayEventState {
        switch state {
        case "spoken":
            return .spoken
        case "suppressed":
            return .suppressed
        case "cancelled":
            return .cancelled
        case "dropped":
            return .dropped
        default:
            return .spoken
        }
    }

    func replaySummaryForVoiceDispatch(
        source: String,
        state: String
    ) -> String {
        let sourceText = source.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ")
        switch state {
        case "spoken":
            return "语音派发已播报：\(sourceText)"
        case "suppressed":
            return "语音派发被抑制：\(sourceText)"
        case "cancelled":
            return "语音派发已取消：\(sourceText)"
        case "dropped":
            return "语音派发已丢弃：\(sourceText)"
        default:
            return "语音派发：\(sourceText)"
        }
    }

    func replayStateForVoicePlaybackActivity(
        _ state: VoicePlaybackActivityState
    ) -> VoiceReplayEventState? {
        switch state {
        case .idle:
            return nil
        case .played:
            return .spoken
        case .fallbackPlayed:
            return .fallback
        case .suppressed:
            return .suppressed
        case .failed:
            return .failed
        }
    }

    func replaySummaryForVoicePlaybackActivity(
        _ activity: VoicePlaybackActivity
    ) -> String {
        switch activity.state {
        case .idle:
            return "语音播放空闲"
        case .played:
            return "语音播报完成"
        case .fallbackPlayed:
            return "语音已回退播放"
        case .suppressed:
            return "语音播报已抑制"
        case .failed:
            return "语音播报失败"
        }
    }
}
