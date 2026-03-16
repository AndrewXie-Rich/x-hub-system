import Foundation
import AVFoundation

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
    private let stopPlaybackSink: () -> Bool
    private let calendar: Calendar

    init(
        deduper: SupervisorVoiceBriefDeduper? = nil,
        calendar: Calendar = .current,
        speakSink: ((String) -> Void)? = nil,
        interruptSink: (() -> Bool)? = nil
    ) {
        self.deduper = deduper ?? SupervisorVoiceBriefDeduper()
        self.calendar = calendar
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
                    persona: preferences.persona
                )
                for segment in segments {
                    let utterance = AVSpeechUtterance(string: segment.text)
                    utterance.voice = voice
                    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * segment.rateMultiplier
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
        let lines = job.script
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else {
            return .suppressed("empty_script")
        }

        guard shouldSpeak(trigger: job.trigger, preferences: preferences) else {
            return .suppressed("auto_report_mode_suppressed")
        }

        guard !isQuietHoursSuppressed(preferences: preferences, now: now) else {
            return .suppressed("quiet_hours_suppressed")
        }

        guard deduper.shouldEmit(key: job.dedupeKey, now: now) else {
            return .suppressed("duplicate_suppressed")
        }

        let segments = speechSegments(for: lines, job: job, preferences: preferences)
        guard !segments.isEmpty else {
            return .suppressed("empty_script")
        }

        segmentedSpeakSink(segments, preferences)
        return .spoken
    }

    @discardableResult
    func interruptCurrentPlayback() -> Bool {
        stopPlaybackSink()
    }

    func estimatedPlaybackDuration(
        job: SupervisorVoiceTTSJob,
        preferences: VoiceRuntimePreferences
    ) -> TimeInterval {
        let lines = job.script
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let segments = speechSegments(for: lines, job: job, preferences: preferences)
        guard !segments.isEmpty else { return 0.6 }

        let locale = preferences.localeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usesChineseLocale = locale.hasPrefix("zh")
        return max(
            0.6,
            segments.reduce(0) { partial, segment in
                partial + estimatedSegmentDuration(segment, usesChineseLocale: usesChineseLocale)
            }
        )
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

        return lines.enumerated().map { index, line in
            SpeechSegment(
                text: line,
                rateMultiplier: max(0.4, style.baseRate - (index == 0 ? 0 : style.followupRateDelta)),
                pitchMultiplier: min(1.2, max(0.8, style.basePitch)),
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
        usesChineseLocale: Bool
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
        let rateFactor = max(0.35, Double(segment.rateMultiplier) / 0.5)
        let speechBody = max(0.45, scalarUnits / (baselineUnitsPerSecond * rateFactor))
        return segment.preDelay + speechBody + segment.postDelay
    }

    private static func resolveVoice(
        localeIdentifier: String,
        persona: VoicePersonaPreset
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
            voiceRank($0, normalizedLocale: normalizedLocale, persona: persona) <
                voiceRank($1, normalizedLocale: normalizedLocale, persona: persona)
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
        persona: VoicePersonaPreset
    ) -> Int {
        let language = voice.language.lowercased()
        let baseLanguage = normalizedLocale.split(separator: "-").first.map(String.init) ?? normalizedLocale
        let metadata = "\(voice.identifier) \(voice.name)".lowercased()
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
        return score
    }
}
