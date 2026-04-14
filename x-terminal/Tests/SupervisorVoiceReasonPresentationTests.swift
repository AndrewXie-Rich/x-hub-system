import Foundation
import Testing
@testable import XTerminal

struct SupervisorVoiceReasonPresentationTests {

    @Test
    func humanizesVoiceRouteAndReadinessReasons() {
        #expect(
            SupervisorVoiceReasonPresentation.displayText("voice_route_fail_closed")
                == "当前语音链路已进入安全关闭，连续语音对话暂不可用（voice_route_fail_closed）"
        )
        #expect(
            SupervisorVoiceReasonPresentation.displayText("microphone_or_speech_unauthorized")
                == "麦克风或语音识别权限未就绪，当前语音链路无法启动（microphone_or_speech_unauthorized）"
        )
        #expect(
            SupervisorVoiceReasonPresentation.displayText("system_speech_recognizer_unavailable")
                == "系统语音识别引擎当前不可用（system_speech_recognizer_unavailable）"
        )
    }

    @Test
    func humanizesWakeProfileAndEngineReasons() {
        #expect(
            SupervisorVoiceReasonPresentation.displayText("wake_profile_pair_sync_cached_after_remote_failure")
                == "远端同步失败，当前继续使用最近一次同步下来的唤醒词配置（wake_profile_pair_sync_cached_after_remote_failure）"
        )
        #expect(
            SupervisorVoiceReasonPresentation.displayText("wake_profile_stale")
                == "远端唤醒词配置已过期，当前暂时回退到按住说话（wake_profile_stale）"
        )
        #expect(
            SupervisorVoiceReasonPresentation.displayText("voice_transcriber_not_authorized")
                == "语音识别器缺少授权，当前不能启动（voice_transcriber_not_authorized）"
        )
    }

    @Test
    func reusesRouteTruthHumanizationForStructuredRouteReasons() {
        #expect(
            SupervisorVoiceReasonPresentation.displayTextOrRaw("deny_code=policy_remote_denied")
                == "当前策略不允许远端执行（policy_remote_denied）"
        )
        #expect(
            SupervisorVoiceReasonPresentation.displayTextOrRaw("fallback_reason_code=provider_not_ready;deny_code=policy_remote_denied")
                == "provider 尚未 ready（provider_not_ready）"
        )
    }

    @Test
    func fallsBackToRawForUnknownReasons() {
        #expect(SupervisorVoiceReasonPresentation.displayText(nil) == nil)
        #expect(SupervisorVoiceReasonPresentation.displayText("custom_reason_code") == nil)
        #expect(
            SupervisorVoiceReasonPresentation.displayTextOrRaw("custom_reason_code")
                == "custom_reason_code"
        )
    }
}
