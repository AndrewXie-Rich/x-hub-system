import Foundation

enum VoiceRoutePolicy {
    static func decide(
        preferredRoute: VoicePreferredRoute,
        availability: VoiceRouteAvailability
    ) -> VoiceRouteDecision {
        switch preferredRoute {
        case .automatic:
            return automaticDecision(availability: availability)
        case .funasrStreaming:
            return preferredDecision(
                preferred: .funasrStreaming,
                fallbackReason: "preferred_funasr_unavailable",
                availability: availability
            )
        case .whisperKitLocal:
            return preferredDecision(
                preferred: .whisperKitLocal,
                fallbackReason: "preferred_whisperkit_unavailable",
                availability: availability
            )
        case .systemSpeechCompatibility:
            return preferredDecision(
                preferred: .systemSpeechCompatibility,
                fallbackReason: "preferred_system_speech_unavailable",
                availability: availability
            )
        case .manualText:
            return manualTextDecision(reasonCode: "preferred_manual_text", availability: availability)
        }
    }

    private static func automaticDecision(
        availability: VoiceRouteAvailability
    ) -> VoiceRouteDecision {
        if availability.funasr == .ready {
            return decision(
                route: .funasrStreaming,
                reasonCode: "preferred_streaming_ready",
                availability: availability
            )
        }
        if availability.whisperKit == .ready {
            return decision(
                route: .whisperKitLocal,
                reasonCode: "streaming_unhealthy_fallback_to_local",
                availability: availability
            )
        }
        if availability.systemSpeech == .ready {
            return decision(
                route: .systemSpeechCompatibility,
                reasonCode: "system_speech_compatibility_fallback",
                availability: availability
            )
        }
        if availability.funasr == .unauthorized ||
            availability.whisperKit == .unauthorized ||
            availability.systemSpeech == .unauthorized {
            return decision(
                route: .failClosed,
                reasonCode: "microphone_or_speech_unauthorized",
                availability: availability
            )
        }
        return manualTextDecision(reasonCode: "no_voice_engine_ready", availability: availability)
    }

    private static func preferredDecision(
        preferred: VoiceRouteMode,
        fallbackReason: String,
        availability: VoiceRouteAvailability
    ) -> VoiceRouteDecision {
        let health = health(for: preferred, availability: availability)
        if health == .ready {
            return decision(
                route: preferred,
                reasonCode: "preferred_route_ready",
                availability: availability
            )
        }
        return automaticDecision(availability: availability).withReasonCode(fallbackReason)
    }

    private static func manualTextDecision(
        reasonCode: String,
        availability: VoiceRouteAvailability
    ) -> VoiceRouteDecision {
        decision(
            route: .manualText,
            reasonCode: reasonCode,
            availability: availability
        )
    }

    private static func decision(
        route: VoiceRouteMode,
        reasonCode: String,
        availability: VoiceRouteAvailability
    ) -> VoiceRouteDecision {
        VoiceRouteDecision(
            route: route,
            reasonCode: reasonCode,
            funasrHealth: availability.funasr,
            whisperKitHealth: availability.whisperKit,
            systemSpeechHealth: availability.systemSpeech,
            wakeCapability: wakeCapability(route: route, availability: availability)
        )
    }

    private static func health(
        for route: VoiceRouteMode,
        availability: VoiceRouteAvailability
    ) -> VoiceEngineHealth {
        switch route {
        case .funasrStreaming:
            return availability.funasr
        case .whisperKitLocal:
            return availability.whisperKit
        case .systemSpeechCompatibility:
            return availability.systemSpeech
        case .manualText:
            return .ready
        case .failClosed:
            return .unavailable
        }
    }

    private static func wakeCapability(
        route: VoiceRouteMode,
        availability: VoiceRouteAvailability
    ) -> String {
        if route == .funasrStreaming && availability.funasr == .ready {
            return "funasr_kws"
        }
        if route.supportsLiveCapture {
            return "push_to_talk_only"
        }
        return "none"
    }
}

private extension VoiceRouteDecision {
    func withReasonCode(_ reasonCode: String) -> VoiceRouteDecision {
        VoiceRouteDecision(
            route: route,
            reasonCode: reasonCode,
            funasrHealth: funasrHealth,
            whisperKitHealth: whisperKitHealth,
            systemSpeechHealth: systemSpeechHealth,
            wakeCapability: wakeCapability
        )
    }
}
