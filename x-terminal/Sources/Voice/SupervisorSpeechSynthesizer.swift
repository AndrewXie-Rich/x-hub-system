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

    private let deduper: SupervisorVoiceBriefDeduper
    private let speakSink: (String) -> Void
    private let calendar: Calendar

    init(
        deduper: SupervisorVoiceBriefDeduper? = nil,
        calendar: Calendar = .current,
        speakSink: ((String) -> Void)? = nil
    ) {
        self.deduper = deduper ?? SupervisorVoiceBriefDeduper()
        self.calendar = calendar
        if let speakSink {
            self.speakSink = speakSink
        } else {
            let synthesizer = AVSpeechSynthesizer()
            self.speakSink = { text in
                let utterance = AVSpeechUtterance(string: text)
                utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
                utterance.prefersAssistiveTechnologySettings = true
                synthesizer.speak(utterance)
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

        speakSink(lines.joined(separator: " "))
        return .spoken
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
}
