import Foundation
import AVFoundation

struct VoicePlaybackDeliveryMetadata: Equatable, Sendable {
    var actualSource: VoicePlaybackSource
    var provider: String
    var modelID: String
    var engineName: String
    var speakerId: String
    var deviceBackend: String
    var nativeTTSUsed: Bool?
    var fallbackMode: String
    var fallbackReasonCode: String
    var audioFormat: String
    var voiceName: String
    var reasonCode: String
    var detail: String
    var auditLine: String

    init(
        actualSource: VoicePlaybackSource,
        provider: String,
        modelID: String,
        engineName: String,
        speakerId: String,
        deviceBackend: String,
        nativeTTSUsed: Bool? = nil,
        fallbackMode: String,
        fallbackReasonCode: String,
        audioFormat: String,
        voiceName: String,
        reasonCode: String,
        detail: String,
        auditLine: String = ""
    ) {
        self.actualSource = actualSource
        self.provider = provider
        self.modelID = modelID
        self.engineName = engineName
        self.speakerId = speakerId
        self.deviceBackend = deviceBackend
        self.nativeTTSUsed = nativeTTSUsed
        self.fallbackMode = fallbackMode
        self.fallbackReasonCode = fallbackReasonCode
        self.audioFormat = audioFormat
        self.voiceName = voiceName
        self.reasonCode = reasonCode
        self.detail = detail
        self.auditLine = auditLine
    }
}

enum VoicePlaybackDeliveryResult: Equatable, Sendable {
    case spoken(VoicePlaybackDeliveryMetadata)
    case unavailable(reasonCode: String, detail: String)
}

enum SupervisorVoiceJobTrigger: String, Codable, Equatable {
    case blocked
    case completed
    case authorization
    case userQueryReply = "user_query_reply"
}

enum SupervisorVoiceJobPriority: String, Codable, Equatable {
    case interrupt
    case normal
    case quiet
}

struct SupervisorVoiceTTSJob: Codable, Equatable {
    var jobId: String
    var trigger: SupervisorVoiceJobTrigger
    var priority: SupervisorVoiceJobPriority
    var script: [String]
    var dedupeKey: String

    init(
        jobId: String = UUID().uuidString.lowercased(),
        trigger: SupervisorVoiceJobTrigger,
        priority: SupervisorVoiceJobPriority = .normal,
        script: [String],
        dedupeKey: String
    ) {
        self.jobId = jobId
        self.trigger = trigger
        self.priority = priority
        self.script = script
        self.dedupeKey = dedupeKey
    }
}

@MainActor
final class SupervisorVoiceBriefDeduper {
    private var lastSeenAtByKey: [String: Date] = [:]
    private let cooldown: TimeInterval

    init(cooldown: TimeInterval = 8) {
        self.cooldown = cooldown
    }

    func shouldEmit(key: String, now: Date) -> Bool {
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return true }
        if let lastSeen = lastSeenAtByKey[cleaned],
           now.timeIntervalSince(lastSeen) < cooldown {
            return false
        }
        lastSeenAtByKey[cleaned] = now
        return true
    }
}

@MainActor
final class SupervisorSpeechSynthesizer {
    enum Outcome: Equatable {
        case spoken
        case suppressed(String)
    }

    private struct ActivePlaybackState {
        var fingerprint: String
        var expiresAt: Date
    }

    private struct SpeechStyleProfile {
        var baseRate: Float
        var followupRateDelta: Float
        var basePitch: Float
        var interSegmentDelay: TimeInterval
        var tailDelay: TimeInterval
    }

    private struct SpeechSegment {
        var text: String
        var rateMultiplier: Float
        var pitchMultiplier: Float
        var preDelay: TimeInterval
        var postDelay: TimeInterval
    }

    private let deduper: SupervisorVoiceBriefDeduper
    private let segmentedSpeakSink: ([SpeechSegment], VoiceRuntimePreferences) -> Void
    private let hubVoicePackSpeakSink: (([String], VoiceRuntimePreferences, VoicePlaybackResolution) -> VoicePlaybackDeliveryResult)?
    private let playbackResolutionResolver: ((VoiceRuntimePreferences) -> VoicePlaybackResolution)?
    private let hubVoicePackReadinessEvaluator: ((VoiceRuntimePreferences) -> Bool)?
    private let hubVoicePackInterruptSink: (() -> Bool)?
    private let stopPlaybackSink: () -> Bool
    private let calendar: Calendar
    private var activePlaybackState: ActivePlaybackState?
    var playbackActivitySink: ((VoicePlaybackActivity) -> Void)?

    init(
        deduper: SupervisorVoiceBriefDeduper? = nil,
        calendar: Calendar = .current,
        speakSink: ((String) -> Void)? = nil,
        interruptSink: (() -> Bool)? = nil,
        hubVoicePackSpeakSink: (([String], VoiceRuntimePreferences, VoicePlaybackResolution) -> VoicePlaybackDeliveryResult)? = nil,
        playbackResolutionResolver: ((VoiceRuntimePreferences) -> VoicePlaybackResolution)? = nil,
        hubVoicePackReadinessEvaluator: ((VoiceRuntimePreferences) -> Bool)? = nil,
        hubVoicePackInterruptSink: (() -> Bool)? = nil
    ) {
        self.deduper = deduper ?? SupervisorVoiceBriefDeduper()
        self.calendar = calendar
        self.hubVoicePackSpeakSink = hubVoicePackSpeakSink
        self.playbackResolutionResolver = playbackResolutionResolver
        self.hubVoicePackReadinessEvaluator = hubVoicePackReadinessEvaluator
        self.hubVoicePackInterruptSink = hubVoicePackInterruptSink
        if let speakSink {
            self.segmentedSpeakSink = { segments, _ in
                speakSink(segments.map(\.text).joined(separator: " "))
            }
            self.stopPlaybackSink = interruptSink ?? { false }
        } else {
            let synthesizer = AVSpeechSynthesizer()
            self.segmentedSpeakSink = { segments, preferences in
                let voice = Self.resolveVoice(
                    localeIdentifier: preferences.localeIdentifier,
                    persona: preferences.persona,
                    timbre: preferences.timbre
                )
                let speechRateMultiplier = Self.normalizedSpeechRateMultiplier(preferences.speechRateMultiplier)
                for segment in segments {
                    let utterance = AVSpeechUtterance(string: segment.text)
                    utterance.voice = voice
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * segment.rateMultiplier * speechRateMultiplier
                    utterance.pitchMultiplier = segment.pitchMultiplier
                    utterance.preUtteranceDelay = segment.preDelay
                    utterance.postUtteranceDelay = segment.postDelay
                    utterance.prefersAssistiveTechnologySettings = false
                    utterance.volume = 1.0
                    synthesizer.speak(utterance)
                }
            }
            self.stopPlaybackSink = interruptSink ?? {
                guard synthesizer.isSpeaking || synthesizer.isPaused else { return false }
                return synthesizer.stopSpeaking(at: .immediate)
            }
        }
    }

    func speak(
        job: SupervisorVoiceTTSJob,
        preferences: VoiceRuntimePreferences,
        now: Date = Date()
    ) -> Outcome {
        pruneExpiredPlaybackState(now: now)
        let playbackResolution = playbackResolution(for: preferences)
        let lines = job.script
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "empty_script",
                detail: ""
            )
            return .suppressed("empty_script")
        }

        guard shouldSpeak(trigger: job.trigger, preferences: preferences) else {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "auto_report_mode_suppressed",
                detail: ""
            )
            return .suppressed("auto_report_mode_suppressed")
        }

        guard !isQuietHoursSuppressed(preferences: preferences, now: now) else {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "quiet_hours_suppressed",
                detail: ""
            )
            return .suppressed("quiet_hours_suppressed")
        }

        guard deduper.shouldEmit(key: job.dedupeKey, now: now) else {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "duplicate_suppressed",
                detail: ""
            )
            return .suppressed("duplicate_suppressed")
        }

        let segments = speechSegments(for: lines, job: job, preferences: preferences)
        guard !segments.isEmpty else {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "empty_script",
                detail: ""
            )
            return .suppressed("empty_script")
        }

        let fingerprint = scriptFingerprint(for: lines)
        let activePlaybackStatus = activePlaybackStatus(
            fingerprint: fingerprint,
            now: now
        )
        if activePlaybackStatus == .sameFingerprint {
            publishPlaybackActivity(
                state: .suppressed,
                configuredResolution: playbackResolution,
                actualSource: nil,
                reasonCode: "inflight_duplicate_suppressed",
                detail: ""
            )
            return .suppressed("inflight_duplicate_suppressed")
        }

        if activePlaybackStatus == .differentFingerprint || job.priority == .interrupt {
            _ = interruptCurrentPlayback()
        }

        let estimatedDuration = estimatedPlaybackDuration(
            segments: segments,
            localeIdentifier: preferences.localeIdentifier,
            speechRateMultiplier: preferences.speechRateMultiplier
        )

        if playbackResolution.resolvedSource == .hubVoicePack,
           let hubVoicePackSpeakSink {
            switch hubVoicePackSpeakSink(lines, preferences, playbackResolution) {
            case .spoken(let metadata):
                markPlaybackActive(
                    fingerprint: fingerprint,
                    now: now,
                    estimatedDuration: estimatedDuration
                )
                publishPlaybackActivity(
                    state: .played,
                    configuredResolution: playbackResolution,
                    actualSource: metadata.actualSource,
                    reasonCode: metadata.reasonCode,
                    detail: metadata.detail,
                    provider: metadata.provider,
                    modelID: metadata.modelID,
                    engineName: metadata.engineName,
                    speakerId: metadata.speakerId,
                    deviceBackend: metadata.deviceBackend,
                    nativeTTSUsed: metadata.nativeTTSUsed,
                    fallbackMode: metadata.fallbackMode,
                    fallbackReasonCode: metadata.fallbackReasonCode,
                    audioFormat: metadata.audioFormat,
                    voiceName: metadata.voiceName,
                    auditLine: metadata.auditLine
                )
                return .spoken
            case .unavailable(let reasonCode, let detail):
                segmentedSpeakSink(segments, preferences)
                publishPlaybackActivity(
                    state: .fallbackPlayed,
                    configuredResolution: playbackResolution,
                    actualSource: .systemSpeech,
                    reasonCode: reasonCode,
                    detail: detail,
                    provider: "hub_voice_pack",
                    modelID: playbackResolution.resolvedHubVoicePackID,
                    deviceBackend: "system_speech",
                    fallbackMode: "hub_voice_pack_unavailable",
                    fallbackReasonCode: reasonCode
                )
                markPlaybackActive(
                    fingerprint: fingerprint,
                    now: now,
                    estimatedDuration: estimatedDuration
                )
                return .spoken
            }
        }

        segmentedSpeakSink(segments, preferences)
        markPlaybackActive(
            fingerprint: fingerprint,
            now: now,
            estimatedDuration: estimatedDuration
        )
        publishPlaybackActivity(
            state: .played,
            configuredResolution: playbackResolution,
            actualSource: .systemSpeech,
            reasonCode: playbackResolution.reasonCode,
            detail: "",
            deviceBackend: "system_speech"
        )
        return .spoken
    }

    @discardableResult
    func interruptCurrentPlayback() -> Bool {
        activePlaybackState = nil
        let hubInterrupted = hubVoicePackInterruptSink?() ?? false
        let systemInterrupted = stopPlaybackSink()
        return hubInterrupted || systemInterrupted
    }

    func playbackResolution(for preferences: VoiceRuntimePreferences) -> VoicePlaybackResolution {
        if let playbackResolutionResolver {
            return playbackResolutionResolver(preferences)
        }
        return SupervisorSpeechPlaybackRouting.resolve(
            preferences: preferences,
            hubVoicePackReady: hubVoicePackReady(for: preferences)
        )
    }

    func estimatedPlaybackDuration(
        job: SupervisorVoiceTTSJob,
        preferences: VoiceRuntimePreferences
    ) -> TimeInterval {
        let lines = job.script
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let segments = speechSegments(for: lines, job: job, preferences: preferences)
        return estimatedPlaybackDuration(
            segments: segments,
            localeIdentifier: preferences.localeIdentifier,
            speechRateMultiplier: preferences.speechRateMultiplier
        )
    }

    private func estimatedPlaybackDuration(
        segments: [SpeechSegment],
        localeIdentifier: String,
        speechRateMultiplier: Float
    ) -> TimeInterval {
        guard !segments.isEmpty else { return 0.6 }

        let locale = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usesChineseLocale = locale.hasPrefix("zh")
        return max(
            0.6,
            segments.reduce(0) { partial, segment in
                partial + estimatedSegmentDuration(
                    segment,
                    usesChineseLocale: usesChineseLocale,
                    speechRateMultiplier: speechRateMultiplier
                )
            }
        )
    }

    private func activePlaybackStatus(
        fingerprint: String,
        now: Date
    ) -> PlaybackConflictStatus {
        pruneExpiredPlaybackState(now: now)
        guard let activePlaybackState else { return .none }
        if activePlaybackState.fingerprint == fingerprint {
            return .sameFingerprint
        }
        return .differentFingerprint
    }

    private func markPlaybackActive(
        fingerprint: String,
        now: Date,
        estimatedDuration: TimeInterval
    ) {
        activePlaybackState = ActivePlaybackState(
            fingerprint: fingerprint,
            expiresAt: now.addingTimeInterval(max(0.6, estimatedDuration))
        )
    }

    private func pruneExpiredPlaybackState(now: Date) {
        guard let activePlaybackState,
              now >= activePlaybackState.expiresAt else {
            return
        }
        self.activePlaybackState = nil
    }

    private enum PlaybackConflictStatus {
        case none
        case sameFingerprint
        case differentFingerprint
    }

    private func scriptFingerprint(for lines: [String]) -> String {
        SupervisorVoiceFingerprint.normalized(lines: lines)
    }

    private func shouldSpeak(
        trigger: SupervisorVoiceJobTrigger,
        preferences: VoiceRuntimePreferences
    ) -> Bool {
        switch preferences.autoReportMode {
        case .silent:
            return false
        case .blockersOnly:
            return trigger == .blocked || trigger == .authorization || trigger == .userQueryReply
        case .summary, .full:
            return true
        }
    }

    private func hubVoicePackReady(for preferences: VoiceRuntimePreferences) -> Bool {
        guard hubVoicePackSpeakSink != nil else { return false }
        if let hubVoicePackReadinessEvaluator {
            return hubVoicePackReadinessEvaluator(preferences)
        }
        return true
    }

    private func publishPlaybackActivity(
        state: VoicePlaybackActivityState,
        configuredResolution: VoicePlaybackResolution?,
        actualSource: VoicePlaybackSource?,
        reasonCode: String,
        detail: String,
        provider: String = "",
        modelID: String = "",
        engineName: String = "",
        speakerId: String = "",
        deviceBackend: String = "",
        nativeTTSUsed: Bool? = nil,
        fallbackMode: String = "",
        fallbackReasonCode: String = "",
        audioFormat: String = "",
        voiceName: String = "",
        auditLine: String = ""
    ) {
        playbackActivitySink?(
            VoicePlaybackActivity(
                state: state,
                configuredResolution: configuredResolution,
                actualSource: actualSource,
                reasonCode: reasonCode,
                detail: detail,
                provider: provider,
                modelID: modelID,
                engineName: engineName,
                speakerId: speakerId,
                deviceBackend: deviceBackend,
                nativeTTSUsed: nativeTTSUsed,
                fallbackMode: fallbackMode,
                fallbackReasonCode: fallbackReasonCode,
                audioFormat: audioFormat,
                voiceName: voiceName,
                auditLine: auditLine,
                updatedAt: Date().timeIntervalSince1970
            )
        )
    }

    private func isQuietHoursSuppressed(
        preferences: VoiceRuntimePreferences,
        now: Date
    ) -> Bool {
        guard preferences.quietHours.enabled else { return false }
        guard let from = parseHourMinute(preferences.quietHours.fromLocal),
              let to = parseHourMinute(preferences.quietHours.toLocal) else {
            return false
        }

        let components = calendar.dateComponents([.hour, .minute], from: now)
        let current = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let fromMin = from.hour * 60 + from.minute
        let toMin = to.hour * 60 + to.minute

        if fromMin == toMin { return true }
        if fromMin < toMin {
            return current >= fromMin && current < toMin
        }
        return current >= fromMin || current < toMin
    }

    private func parseHourMinute(_ text: String) -> (hour: Int, minute: Int)? {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0..<24).contains(hour),
              (0..<60).contains(minute) else {
            return nil
        }
        return (hour, minute)
    }

    private func speechSegments(
        for lines: [String],
        job: SupervisorVoiceTTSJob,
        preferences: VoiceRuntimePreferences
    ) -> [SpeechSegment] {
        let locale = preferences.localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesChineseLocale = locale.lowercased().hasPrefix("zh")
        let style = speechStyle(
            for: job,
            persona: preferences.persona,
            usesChineseLocale: usesChineseLocale
        )
        let timbrePitchAdjustment = pitchAdjustment(for: preferences.timbre)

        return lines.enumerated().map { index, line in
            SpeechSegment(
                text: line,
                rateMultiplier: max(0.4, style.baseRate - (index == 0 ? 0 : style.followupRateDelta)),
                pitchMultiplier: min(1.25, max(0.78, style.basePitch + timbrePitchAdjustment)),
                preDelay: index == 0 ? 0 : 0.02,
                postDelay: index == lines.count - 1 ? style.tailDelay : style.interSegmentDelay
            )
        }
    }

    private func speechStyle(
        for job: SupervisorVoiceTTSJob,
        persona: VoicePersonaPreset,
        usesChineseLocale: Bool
    ) -> SpeechStyleProfile {
        let priorityRateBoost: Float
        switch job.priority {
        case .interrupt:
            priorityRateBoost = usesChineseLocale ? 0.03 : 0.02
        case .normal:
            priorityRateBoost = 0
        case .quiet:
            priorityRateBoost = usesChineseLocale ? -0.02 : -0.015
        }

        let triggerPitchBoost: Float
        switch job.trigger {
        case .authorization:
            triggerPitchBoost = 0.03
        case .blocked:
            triggerPitchBoost = 0.01
        case .completed, .userQueryReply:
            triggerPitchBoost = 0
        }

        switch persona {
        case .briefing:
            return SpeechStyleProfile(
                baseRate: (usesChineseLocale ? 0.53 : 0.49) + priorityRateBoost,
                followupRateDelta: 0.012,
                basePitch: 0.99 + triggerPitchBoost,
                interSegmentDelay: 0.1,
                tailDelay: 0.07
            )
        case .conversational:
            return SpeechStyleProfile(
                baseRate: (usesChineseLocale ? 0.5 : 0.47) + priorityRateBoost,
                followupRateDelta: 0.01,
                basePitch: 1.02 + triggerPitchBoost,
                interSegmentDelay: 0.14,
                tailDelay: 0.1
            )
        case .calm:
            return SpeechStyleProfile(
                baseRate: (usesChineseLocale ? 0.47 : 0.44) + priorityRateBoost,
                followupRateDelta: 0.008,
                basePitch: 0.96 + triggerPitchBoost,
                interSegmentDelay: 0.18,
                tailDelay: 0.12
            )
        }
    }

    private func estimatedSegmentDuration(
        _ segment: SpeechSegment,
        usesChineseLocale: Bool,
        speechRateMultiplier: Float
    ) -> TimeInterval {
        let scalarUnits = segment.text.unicodeScalars.reduce(0.0) { partial, scalar in
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return partial
            }
            if CharacterSet.punctuationCharacters.contains(scalar) {
                return partial + 0.35
            }
            if scalar.properties.isIdeographic {
                return partial + 1.0
            }
            return partial + 0.55
        }
        let baselineUnitsPerSecond = usesChineseLocale ? 6.8 : 13.5
        let effectiveRateMultiplier = segment.rateMultiplier * Self.normalizedSpeechRateMultiplier(speechRateMultiplier)
        let rateFactor = max(0.35, Double(effectiveRateMultiplier) / 0.5)
        let speechBody = max(0.45, scalarUnits / (baselineUnitsPerSecond * rateFactor))
        return segment.preDelay + speechBody + segment.postDelay
    }

    private static func resolveVoice(
        localeIdentifier: String,
        persona: VoicePersonaPreset,
        timbre: VoiceTimbrePreset
    ) -> AVSpeechSynthesisVoice? {
        let trimmed = localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLocale = trimmed.lowercased()
        let baseLanguage = normalizedLocale.split(separator: "-").first.map(String.init) ?? normalizedLocale
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let candidates = voices.filter { voice in
            let language = voice.language.lowercased()
            return language == normalizedLocale || language.hasPrefix(baseLanguage)
        }
        if let ranked = candidates.max(by: {
            voiceRank($0, normalizedLocale: normalizedLocale, persona: persona, timbre: timbre) <
                voiceRank($1, normalizedLocale: normalizedLocale, persona: persona, timbre: timbre)
        }) {
            return ranked
        }
        if let exact = AVSpeechSynthesisVoice(language: trimmed) {
            return exact
        }
        if trimmed.lowercased().hasPrefix("zh") {
            return AVSpeechSynthesisVoice(language: "zh-CN")
        }
        if trimmed.lowercased().hasPrefix("en") {
            return AVSpeechSynthesisVoice(language: "en-US")
        }
        return AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
    }

    private static func voiceRank(
        _ voice: AVSpeechSynthesisVoice,
        normalizedLocale: String,
        persona: VoicePersonaPreset,
        timbre: VoiceTimbrePreset
    ) -> Int {
        voiceRank(
            language: voice.language,
            name: voice.name,
            identifier: voice.identifier,
            normalizedLocale: normalizedLocale,
            persona: persona,
            timbre: timbre
        )
    }

    static func voiceRank(
        language rawLanguage: String,
        name rawName: String,
        identifier rawIdentifier: String,
        normalizedLocale: String,
        persona: VoicePersonaPreset,
        timbre: VoiceTimbrePreset
    ) -> Int {
        let language = rawLanguage.lowercased()
        let baseLanguage = normalizedLocale.split(separator: "-").first.map(String.init) ?? normalizedLocale
        let metadata = "\(rawIdentifier) \(rawName)".lowercased()
        var score = 0
        if language == normalizedLocale {
            score += 100
        } else if language.hasPrefix(baseLanguage) {
            score += 40
        }
        if metadata.contains("premium") {
            score += 20
        }
        if metadata.contains("enhanced") {
            score += 12
        }
        if metadata.contains("siri") {
            score += 8
        }
        if metadata.contains("eloquence") {
            score -= 40
        }
        if metadata.contains("speech.synthesis.voice") {
            score -= 80
        }
        switch persona {
        case .briefing:
            if metadata.contains("premium") || metadata.contains("siri") {
                score += 2
            }
        case .conversational:
            if metadata.contains("enhanced") || metadata.contains("siri") {
                score += 3
            }
        case .calm:
            if metadata.contains("premium") {
                score += 4
            }
        }
        switch timbre {
        case .neutral:
            break
        case .warm:
            if metadata.contains("premium") {
                score += 8
            }
            if metadata.contains("enhanced") {
                score += 5
            }
        case .clear:
            if metadata.contains("siri") {
                score += 8
            }
            if metadata.contains("premium") {
                score += 4
            }
        case .bright:
            if metadata.contains("siri") {
                score += 10
            }
            if metadata.contains("enhanced") {
                score += 4
            }
        case .calm:
            if metadata.contains("premium") {
                score += 10
            }
            if metadata.contains("siri") {
                score -= 2
            }
        }
        return score
    }

    private func pitchAdjustment(for timbre: VoiceTimbrePreset) -> Float {
        switch timbre {
        case .neutral:
            return 0
        case .warm:
            return -0.03
        case .clear:
            return 0.015
        case .bright:
            return 0.04
        case .calm:
            return -0.05
        }
    }

    private static func normalizedSpeechRateMultiplier(_ value: Float) -> Float {
        min(1.35, max(0.75, value))
    }
}
