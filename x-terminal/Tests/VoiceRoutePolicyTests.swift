import Foundation
import Testing
@testable import XTerminal

struct VoiceRoutePolicyTests {

    @Test
    func automaticPrefersProductionRoutesBeforeCompatibilityFallback() {
        let decision = VoiceRoutePolicy.decide(
            preferredRoute: .automatic,
            availability: VoiceRouteAvailability(
                funasr: .ready,
                whisperKit: .ready,
                systemSpeech: .ready
            )
        )

        #expect(decision.route == .funasrStreaming)
        #expect(decision.reasonCode == "preferred_streaming_ready")
        #expect(decision.wakeCapability == "funasr_kws")
    }

    @Test
    func automaticFallsBackToSystemSpeechWhenProductionRoutesAreNotReady() {
        let decision = VoiceRoutePolicy.decide(
            preferredRoute: .automatic,
            availability: VoiceRouteAvailability(
                funasr: .disabled,
                whisperKit: .disabled,
                systemSpeech: .ready
            )
        )

        #expect(decision.route == .systemSpeechCompatibility)
        #expect(decision.reasonCode == "system_speech_compatibility_fallback")
        #expect(decision.wakeCapability == "push_to_talk_only")
    }

    @Test
    func unauthorizedCaptureFailsClosed() {
        let decision = VoiceRoutePolicy.decide(
            preferredRoute: .automatic,
            availability: VoiceRouteAvailability(
                funasr: .disabled,
                whisperKit: .disabled,
                systemSpeech: .unauthorized
            )
        )

        #expect(decision.route == .failClosed)
        #expect(decision.reasonCode == "microphone_or_speech_unauthorized")
    }
}
