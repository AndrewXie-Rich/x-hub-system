import Foundation
import UserNotifications

struct SupervisorCalendarReminderDeliveryOutcome: Equatable, Sendable {
    var spoken: Bool
    var notificationFallbackSent: Bool
    var reasonCode: String

    var recordsDelivery: Bool {
        spoken || notificationFallbackSent
    }
}

@MainActor
final class SupervisorCalendarVoiceBridge {
    private let speechSink: (String) -> SupervisorSpeechSynthesizer.Outcome
    private let notificationSink: (SupervisorCalendarReminder, String, String) -> Bool
    private let conversationActiveProvider: () -> Bool
    private let reminderStateStore: SupervisorCalendarReminderStateStore
    private let calendar: Calendar

    init(
        speechSink: @escaping (String) -> SupervisorSpeechSynthesizer.Outcome,
        notificationSink: @escaping (SupervisorCalendarReminder, String, String) -> Bool,
        conversationActiveProvider: @escaping () -> Bool,
        reminderStateStore: SupervisorCalendarReminderStateStore? = nil,
        calendar: Calendar = .current
    ) {
        self.speechSink = speechSink
        self.notificationSink = notificationSink
        self.conversationActiveProvider = conversationActiveProvider
        self.reminderStateStore = reminderStateStore ?? .shared
        self.calendar = calendar
    }

    static func live() -> SupervisorCalendarVoiceBridge {
        SupervisorCalendarVoiceBridge(
            speechSink: { script in
                SupervisorManager.shared.speakSupervisorVoiceText(script)
            },
            notificationSink: { reminder, title, body in
                livePostLocalNotification(reminder: reminder, title: title, body: body)
            },
            conversationActiveProvider: {
                SupervisorConversationSessionController.shared.snapshot.isConversing
            }
        )
    }

    func deliver(
        reminder: SupervisorCalendarReminder,
        settings: XTerminalSettings,
        now: Date = Date()
    ) -> SupervisorCalendarReminderDeliveryOutcome {
        let locale = VoiceSupportedLocale(rawValue: settings.voice.localeIdentifier) ?? .chineseMainland
        let shouldInterruptConversation = reminderStateStore.shouldInterruptConversation(
            for: reminder,
            now: now
        )

        if conversationActiveProvider() && !shouldInterruptConversation {
            reminderStateStore.registerConversationDeferredReminder(
                reminder,
                now: now
            )
            return SupervisorCalendarReminderDeliveryOutcome(
                spoken: false,
                notificationFallbackSent: false,
                reasonCode: "inline_conversation_deferred"
            )
        }

        if isQuietHoursSuppressed(preferences: settings.voice, now: now) {
            return fallbackIfNeeded(
                reminder: reminder,
                locale: locale,
                settings: settings,
                now: now,
                reasonCode: "quiet_hours"
            )
        }

        let script = reminderSpeechText(reminder: reminder, locale: locale, now: now)
        switch speechSink(script) {
        case .spoken:
            return SupervisorCalendarReminderDeliveryOutcome(
                spoken: true,
                notificationFallbackSent: false,
                reasonCode: "spoken"
            )
        case .suppressed(let reason):
            return fallbackIfNeeded(
                reminder: reminder,
                locale: locale,
                settings: settings,
                now: now,
                reasonCode: reason
            )
        }
    }

    func previewSpeechText(
        phase: SupervisorCalendarReminderPhase,
        eventTitle: String,
        settings: XTerminalSettings,
        referenceDate: Date = Date()
    ) -> String {
        let locale = VoiceSupportedLocale(rawValue: settings.voice.localeIdentifier) ?? .chineseMainland
        let reminder = previewReminder(
            phase: phase,
            eventTitle: eventTitle,
            settings: settings,
            referenceDate: referenceDate
        )
        return reminderSpeechText(
            reminder: reminder,
            locale: locale,
            now: referenceDate
        )
    }

    @discardableResult
    func sendPreviewNotification(
        phase: SupervisorCalendarReminderPhase,
        eventTitle: String,
        settings: XTerminalSettings,
        referenceDate: Date = Date()
    ) -> Bool {
        let locale = VoiceSupportedLocale(rawValue: settings.voice.localeIdentifier) ?? .chineseMainland
        let reminder = previewReminder(
            phase: phase,
            eventTitle: eventTitle,
            settings: settings,
            referenceDate: referenceDate
        )
        let payload = reminderNotificationPayload(
            reminder: reminder,
            locale: locale,
            now: referenceDate
        )
        return notificationSink(reminder, payload.title, payload.body)
    }

    func simulatePreviewDelivery(
        phase: SupervisorCalendarReminderPhase,
        eventTitle: String,
        settings: XTerminalSettings,
        referenceDate: Date = Date()
    ) -> SupervisorCalendarReminderDeliveryOutcome {
        let reminder = previewReminder(
            phase: phase,
            eventTitle: eventTitle,
            settings: settings,
            referenceDate: referenceDate
        )
        return deliver(
            reminder: reminder,
            settings: settings,
            now: referenceDate
        )
    }

    private func fallbackIfNeeded(
        reminder: SupervisorCalendarReminder,
        locale: VoiceSupportedLocale,
        settings: XTerminalSettings,
        now: Date,
        reasonCode: String
    ) -> SupervisorCalendarReminderDeliveryOutcome {
        guard settings.supervisorCalendarReminders.notificationFallbackEnabled else {
            return SupervisorCalendarReminderDeliveryOutcome(
                spoken: false,
                notificationFallbackSent: false,
                reasonCode: reasonCode
            )
        }

        let payload = reminderNotificationPayload(
            reminder: reminder,
            locale: locale,
            now: now
        )
        let sent = notificationSink(reminder, payload.title, payload.body)
        return SupervisorCalendarReminderDeliveryOutcome(
            spoken: false,
            notificationFallbackSent: sent,
            reasonCode: sent ? "notification_fallback_\(reasonCode)" : reasonCode
        )
    }

    private func previewReminder(
        phase: SupervisorCalendarReminderPhase,
        eventTitle: String,
        settings: XTerminalSettings,
        referenceDate: Date
    ) -> SupervisorCalendarReminder {
        let preferences = settings.supervisorCalendarReminders.normalized()
        let leadMinutes: Int
        switch phase {
        case .headsUp:
            leadMinutes = preferences.headsUpMinutes
        case .finalCall:
            leadMinutes = preferences.finalCallMinutes
        case .startNow:
            leadMinutes = 0
        }

        let startDate = referenceDate.addingTimeInterval(Double(leadMinutes) * 60.0)
        return SupervisorCalendarReminder(
            eventID: "calendar-preview-\(phase.rawValue)",
            eventTitle: eventTitle,
            phase: phase,
            fireAt: referenceDate.timeIntervalSince1970,
            validUntil: startDate.addingTimeInterval(60).timeIntervalSince1970,
            eventStartAt: startDate.timeIntervalSince1970,
            dedupeKey: "calendar-preview-\(phase.rawValue)",
            notificationIdentifier: "x_terminal_supervisor_calendar_preview_\(phase.rawValue)"
        )
    }

    private func reminderSpeechText(
        reminder: SupervisorCalendarReminder,
        locale: VoiceSupportedLocale,
        now: Date
    ) -> String {
        let title = normalizedTitle(reminder.eventTitle, locale: locale)
        let timeText = startTimeText(for: reminder.eventStartDate)
        let remainingMinutes = max(
            1,
            Int(ceil(reminder.eventStartDate.timeIntervalSince(now) / 60.0))
        )

        switch locale {
        case .englishUS:
            switch reminder.phase {
            case .headsUp:
                return "\(title) starts in \(remainingMinutes) minutes at \(timeText)."
            case .finalCall:
                return "\(title) starts in \(remainingMinutes) minutes. Switch to the meeting window now."
            case .startNow:
                return "\(title) is starting now."
            }
        case .chineseMainland:
            switch reminder.phase {
            case .headsUp:
                return "\(timeText) 的\(title)还有 \(remainingMinutes) 分钟开始。"
            case .finalCall:
                return "\(title)还有 \(remainingMinutes) 分钟开始，记得切到会议窗口。"
            case .startNow:
                return "\(title)已经开始。"
            }
        }
    }

    private func reminderNotificationPayload(
        reminder: SupervisorCalendarReminder,
        locale: VoiceSupportedLocale,
        now: Date
    ) -> (title: String, body: String) {
        let title = normalizedTitle(reminder.eventTitle, locale: locale)
        let timeText = startTimeText(for: reminder.eventStartDate)
        let remainingMinutes = max(
            1,
            Int(ceil(reminder.eventStartDate.timeIntervalSince(now) / 60.0))
        )

        switch locale {
        case .englishUS:
            switch reminder.phase {
            case .headsUp:
                return (
                    title,
                    "Starts in \(remainingMinutes) minutes at \(timeText)."
                )
            case .finalCall:
                return (
                    title,
                    "Starts in \(remainingMinutes) minutes. Switch to the meeting window now."
                )
            case .startNow:
                return (
                    title,
                    "Starting now."
                )
            }
        case .chineseMainland:
            switch reminder.phase {
            case .headsUp:
                return (
                    "Supervisor 会议提醒",
                    "\(timeText) 的\(title)还有 \(remainingMinutes) 分钟开始。"
                )
            case .finalCall:
                return (
                    "Supervisor 会议提醒",
                    "\(title)还有 \(remainingMinutes) 分钟开始，记得切到会议窗口。"
                )
            case .startNow:
                return (
                    "Supervisor 会议提醒",
                    "\(title)已经开始。"
                )
            }
        }
    }

    private func normalizedTitle(
        _ raw: String,
        locale: VoiceSupportedLocale
    ) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            switch locale {
            case .englishUS:
                return "Meeting"
            case .chineseMainland:
                return "会议"
            }
        }
        return trimmed
    }

    private func startTimeText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
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
        let fromMinutes = from.hour * 60 + from.minute
        let toMinutes = to.hour * 60 + to.minute

        if fromMinutes == toMinutes {
            return true
        }
        if fromMinutes < toMinutes {
            return current >= fromMinutes && current < toMinutes
        }
        return current >= fromMinutes || current < toMinutes
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

    private static func livePostLocalNotification(
        reminder: SupervisorCalendarReminder,
        title: String,
        body: String
    ) -> Bool {
        guard canPostLocalSupervisorNotifications() else { return false }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "x_terminal_supervisor_calendar_reminders"
        content.userInfo = [
            "phase": reminder.phase.rawValue,
            "event_id": reminder.eventID,
            "source": "xt_supervisor_calendar_reminder",
        ]

        let request = UNNotificationRequest(
            identifier: reminder.notificationIdentifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Supervisor calendar reminder notification error: \(error)")
            }
        }
        return true
    }

    private static func canPostLocalSupervisorNotifications() -> Bool {
        let bundleURL = Bundle.main.bundleURL.path.lowercased()
        if bundleURL.contains("/swift/pm") || bundleURL.contains(".xctest") {
            return false
        }
        return true
    }
}
