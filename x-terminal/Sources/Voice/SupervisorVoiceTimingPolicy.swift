enum SupervisorVoiceTimingPolicy {
    static let maximumResumeDelay: Double = 8
    static let resumeObservationTimeout: Double = maximumResumeDelay + 2

    static func resumeDelay(estimatedPlaybackDuration: Double) -> Double {
        guard estimatedPlaybackDuration.isFinite else { return maximumResumeDelay }
        return min(maximumResumeDelay, max(0.9, estimatedPlaybackDuration + 0.12))
    }
}
