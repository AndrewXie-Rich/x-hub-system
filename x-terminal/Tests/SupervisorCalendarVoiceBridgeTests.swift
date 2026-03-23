import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorCalendarVoiceBridgeTests {

    @Test
    func deliverUsesVoiceWhenRouteIsSafe() throws {
        var spokenScripts: [String] = []
        var notificationBodies: [String] = []
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { script in
                spokenScripts.append(script)
                return .spoken
            },
            notificationSink: { _, _, body in
                notificationBodies.append(body)
                return true
            },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )

        let outcome = bridge.deliver(
            reminder: makeReminder(),
            settings: enabledSettings(),
            now: try #require(isoDate("2026-03-20T09:47:00+08:00"))
        )

        #expect(outcome.spoken == true)
        #expect(outcome.notificationFallbackSent == false)
        #expect(spokenScripts.count == 1)
        #expect(notificationBodies.isEmpty)
    }

    @Test
    func deliverFallsBackToNotificationDuringQuietHours() throws {
        var spokenScripts: [String] = []
        var notificationBodies: [String] = []
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { script in
                spokenScripts.append(script)
                return .spoken
            },
            notificationSink: { _, _, body in
                notificationBodies.append(body)
                return true
            },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )

        let voice = VoiceRuntimePreferences(
            preferredRoute: .automatic,
            playbackPreference: .automatic,
            wakeMode: .pushToTalk,
            autoReportMode: .summary,
            persona: .conversational,
            timbre: .neutral,
            preferredHubVoicePackID: "",
            speechRateMultiplier: 1.0,
            interruptOnSpeech: true,
            quietHours: VoiceQuietHours(
                enabled: true,
                fromLocal: "22:00",
                toLocal: "08:00"
            ),
            localeIdentifier: VoiceSupportedLocale.chineseMainland.rawValue,
            funASR: .default()
        )
        let settings = enabledSettings().setting(voice: voice)

        let outcome = bridge.deliver(
            reminder: makeReminder(),
            settings: settings,
            now: try #require(isoDate("2026-03-20T07:30:00+08:00"))
        )

        #expect(outcome.spoken == false)
        #expect(outcome.notificationFallbackSent == true)
        #expect(spokenScripts.isEmpty)
        #expect(notificationBodies.count == 1)
    }

    @Test
    func deliverFallsBackToNotificationWhenSpeechIsSuppressed() throws {
        var notificationBodies: [String] = []
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { _ in
                .suppressed("playback_unavailable")
            },
            notificationSink: { _, _, body in
                notificationBodies.append(body)
                return true
            },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )

        let outcome = bridge.deliver(
            reminder: makeReminder(),
            settings: enabledSettings(),
            now: try #require(isoDate("2026-03-20T09:47:00+08:00"))
        )

        #expect(outcome.spoken == false)
        #expect(outcome.notificationFallbackSent == true)
        #expect(outcome.reasonCode == "notification_fallback_playback_unavailable")
        #expect(notificationBodies.count == 1)
    }

    @Test
    func deliverDefersWhenConversationIsActiveAndFallbackIsDisabled() throws {
        var speechCount = 0
        var notificationCount = 0
        let stateStore = SupervisorCalendarReminderStateStore()
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { _ in
                speechCount += 1
                return .spoken
            },
            notificationSink: { _, _, _ in
                notificationCount += 1
                return true
            },
            conversationActiveProvider: { true },
            reminderStateStore: stateStore,
            calendar: shanghaiCalendar()
        )
        let settings = enabledSettings().setting(
            supervisorCalendarReminders: SupervisorCalendarReminderPreferences(
                enabled: true,
                headsUpMinutes: 15,
                finalCallMinutes: 3,
                notificationFallbackEnabled: false
            )
        )

        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let outcome = bridge.deliver(
            reminder: makeReminder(),
            settings: settings,
            now: now
        )

        #expect(outcome.spoken == false)
        #expect(outcome.notificationFallbackSent == false)
        #expect(outcome.reasonCode == "inline_conversation_deferred")
        #expect(speechCount == 0)
        #expect(notificationCount == 0)
        #expect(stateStore.pendingInlineCueCount == 1)
        let cue = stateStore.nextInlineCue(
            upcomingMeetings: [makeMeeting()],
            settings: settings,
            now: now
        )
        #expect(cue?.eventID == "meeting-1")
        #expect(cue?.source == .conversationDeferred)
    }

    @Test
    func deliverCanBreakIntoActiveConversationAtMeetingStartWhenRequested() throws {
        var spokenScripts: [String] = []
        var notificationBodies: [String] = []
        let stateStore = SupervisorCalendarReminderStateStore()
        let reminder = makeReminder(phase: .startNow)
        let now = reminder.eventStartDate
        stateStore.setConversationInterruptPreference(
            eventID: reminder.eventID,
            enabledUntil: now.addingTimeInterval(30 * 60),
            now: now.addingTimeInterval(-10 * 60)
        )

        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { script in
                spokenScripts.append(script)
                return .spoken
            },
            notificationSink: { _, _, body in
                notificationBodies.append(body)
                return true
            },
            conversationActiveProvider: { true },
            reminderStateStore: stateStore,
            calendar: shanghaiCalendar()
        )

        let outcome = bridge.deliver(
            reminder: reminder,
            settings: enabledSettings(),
            now: now
        )

        #expect(outcome.spoken == true)
        #expect(outcome.notificationFallbackSent == false)
        #expect(outcome.reasonCode == "spoken")
        #expect(spokenScripts.count == 1)
        #expect(notificationBodies.isEmpty)
        #expect(stateStore.pendingInlineCueCount == 0)
    }

    @Test
    func previewSpeechTextUsesExactHeadsUpTemplate() throws {
        let bridge = makeBridge()

        let text = bridge.previewSpeechText(
            phase: .headsUp,
            eventTitle: "Phoenix weekly sync",
            settings: enabledSettings(),
            referenceDate: try #require(isoDate("2026-03-20T09:45:00+08:00"))
        )

        #expect(text == "10:00 的Phoenix weekly sync还有 15 分钟开始。")
    }

    @Test
    func previewSpeechTextUsesExactFinalCallTemplate() throws {
        let bridge = makeBridge()

        let text = bridge.previewSpeechText(
            phase: .finalCall,
            eventTitle: "Phoenix weekly sync",
            settings: enabledSettings(),
            referenceDate: try #require(isoDate("2026-03-20T09:57:00+08:00"))
        )

        #expect(text == "Phoenix weekly sync还有 3 分钟开始，记得切到会议窗口。")
    }

    @Test
    func previewSpeechTextUsesExactStartNowTemplateForEnglishLocale() throws {
        let bridge = makeBridge()
        let settings = enabledSettings().setting(
            voice: VoiceRuntimePreferences(
                preferredRoute: .automatic,
                playbackPreference: .automatic,
                wakeMode: .pushToTalk,
                autoReportMode: .summary,
                persona: .conversational,
                timbre: .neutral,
                preferredHubVoicePackID: "",
                speechRateMultiplier: 1.0,
                interruptOnSpeech: true,
                quietHours: .default(),
                localeIdentifier: VoiceSupportedLocale.englishUS.rawValue,
                funASR: .default()
            )
        )

        let text = bridge.previewSpeechText(
            phase: .startNow,
            eventTitle: "Phoenix weekly sync",
            settings: settings,
            referenceDate: try #require(isoDate("2026-03-20T10:00:00+08:00"))
        )

        #expect(text == "Phoenix weekly sync is starting now.")
    }

    @Test
    func sendPreviewNotificationUsesExactFinalCallPayload() throws {
        var recordedTitle = ""
        var recordedBody = ""
        var recordedReminderID = ""
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { _ in .spoken },
            notificationSink: { reminder, title, body in
                recordedReminderID = reminder.notificationIdentifier
                recordedTitle = title
                recordedBody = body
                return true
            },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )

        let sent = bridge.sendPreviewNotification(
            phase: .finalCall,
            eventTitle: "Phoenix weekly sync",
            settings: enabledSettings(),
            referenceDate: try #require(isoDate("2026-03-20T09:57:00+08:00"))
        )

        #expect(sent == true)
        #expect(recordedReminderID == "x_terminal_supervisor_calendar_preview_final_call")
        #expect(recordedTitle == "Supervisor 会议提醒")
        #expect(recordedBody == "Phoenix weekly sync还有 3 分钟开始，记得切到会议窗口。")
    }

    @Test
    func simulatePreviewDeliveryUsesVoicePathWhenLiveRouteIsSafe() throws {
        var spokenScripts: [String] = []
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { script in
                spokenScripts.append(script)
                return .spoken
            },
            notificationSink: { _, _, _ in false },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )

        let outcome = bridge.simulatePreviewDelivery(
            phase: .finalCall,
            eventTitle: "Phoenix weekly sync",
            settings: enabledSettings(),
            referenceDate: try #require(isoDate("2026-03-20T09:57:00+08:00"))
        )

        #expect(outcome.spoken == true)
        #expect(outcome.notificationFallbackSent == false)
        #expect(outcome.reasonCode == "spoken")
        #expect(spokenScripts == ["Phoenix weekly sync还有 3 分钟开始，记得切到会议窗口。"])
    }

    @Test
    func simulatePreviewDeliveryFallsBackToNotificationDuringQuietHours() throws {
        var notificationBodies: [String] = []
        let bridge = SupervisorCalendarVoiceBridge(
            speechSink: { _ in .spoken },
            notificationSink: { _, _, body in
                notificationBodies.append(body)
                return true
            },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )
        let voice = VoiceRuntimePreferences(
            preferredRoute: .automatic,
            playbackPreference: .automatic,
            wakeMode: .pushToTalk,
            autoReportMode: .summary,
            persona: .conversational,
            timbre: .neutral,
            preferredHubVoicePackID: "",
            speechRateMultiplier: 1.0,
            interruptOnSpeech: true,
            quietHours: VoiceQuietHours(
                enabled: true,
                fromLocal: "22:00",
                toLocal: "08:00"
            ),
            localeIdentifier: VoiceSupportedLocale.chineseMainland.rawValue,
            funASR: .default()
        )
        let settings = enabledSettings().setting(voice: voice)

        let outcome = bridge.simulatePreviewDelivery(
            phase: .headsUp,
            eventTitle: "Phoenix weekly sync",
            settings: settings,
            referenceDate: try #require(isoDate("2026-03-20T07:45:00+08:00"))
        )

        #expect(outcome.spoken == false)
        #expect(outcome.notificationFallbackSent == true)
        #expect(outcome.reasonCode == "notification_fallback_quiet_hours")
        #expect(notificationBodies == ["08:00 的Phoenix weekly sync还有 15 分钟开始。"])
    }

    private func enabledSettings() -> XTerminalSettings {
        XTerminalSettings.default().setting(
            supervisorCalendarReminders: SupervisorCalendarReminderPreferences(
                enabled: true,
                headsUpMinutes: 15,
                finalCallMinutes: 3,
                notificationFallbackEnabled: true
            )
        )
    }

    private func makeBridge() -> SupervisorCalendarVoiceBridge {
        SupervisorCalendarVoiceBridge(
            speechSink: { _ in .spoken },
            notificationSink: { _, _, _ in false },
            conversationActiveProvider: { false },
            calendar: shanghaiCalendar()
        )
    }

    private func makeReminder(
        phase: SupervisorCalendarReminderPhase = .headsUp
    ) -> SupervisorCalendarReminder {
        let start = ISO8601DateFormatter().date(from: "2026-03-20T10:00:00+08:00") ?? Date()
        let fireAt: TimeInterval
        let validUntil: TimeInterval
        switch phase {
        case .headsUp:
            fireAt = start.addingTimeInterval(-15 * 60).timeIntervalSince1970
            validUntil = start.addingTimeInterval(-3 * 60).timeIntervalSince1970
        case .finalCall:
            fireAt = start.addingTimeInterval(-3 * 60).timeIntervalSince1970
            validUntil = start.timeIntervalSince1970
        case .startNow:
            fireAt = start.timeIntervalSince1970
            validUntil = start.addingTimeInterval(60).timeIntervalSince1970
        }
        return SupervisorCalendarReminder(
            eventID: "meeting-1",
            eventTitle: "Phoenix weekly sync",
            phase: phase,
            fireAt: fireAt,
            validUntil: validUntil,
            eventStartAt: start.timeIntervalSince1970,
            dedupeKey: "meeting-1:\(Int64(round(start.timeIntervalSince1970 * 1000.0))):\(phase.rawValue)",
            notificationIdentifier: "x_terminal_supervisor_calendar_meeting_1"
        )
    }

    private func makeMeeting() -> XTCalendarEventSummary {
        XTCalendarEventSummary(
            id: "meeting-1",
            source: "eventkit",
            title: "Phoenix weekly sync",
            startAt: ISO8601DateFormatter().date(from: "2026-03-20T10:00:00+08:00")?.timeIntervalSince1970 ?? 0,
            endAt: ISO8601DateFormatter().date(from: "2026-03-20T10:30:00+08:00")?.timeIntervalSince1970 ?? 0,
            location: "Zoom",
            joinURL: "https://zoom.example.com/phoenix",
            isMeeting: true,
            isAllDay: false
        )
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }

    private func shanghaiCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60) ?? .current
        return calendar
    }
}
