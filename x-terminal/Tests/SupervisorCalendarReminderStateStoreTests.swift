import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorCalendarReminderStateStoreTests {

    @Test
    func conversationDeferredReminderProducesInlineCue() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-1",
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let reminder = makeReminder(meeting: meeting, phase: .headsUp)
        let store = SupervisorCalendarReminderStateStore()

        store.registerConversationDeferredReminder(reminder, now: now)

        let cue = store.nextInlineCue(
            upcomingMeetings: [meeting],
            settings: enabledSettings(),
            now: now
        )
        #expect(store.pendingInlineCueCount == 1)
        #expect(cue?.eventID == meeting.id)
        #expect(cue?.source == .conversationDeferred)
        #expect(cue?.minutesUntilStart == 13)
    }

    @Test
    func snoozeSuppressesInlineCueUntilDelayExpires() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-2",
            title: "Launch prep",
            start: try #require(isoDate("2026-03-20T10:10:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:40:00+08:00"))
        )
        let store = SupervisorCalendarReminderStateStore()

        let initialCue = store.nextInlineCue(
            upcomingMeetings: [meeting],
            settings: enabledSettings(),
            now: now
        )
        #expect(initialCue?.eventID == meeting.id)
        #expect(initialCue?.source == .proactiveContext)

        store.applySnooze(
            eventID: meeting.id,
            until: now.addingTimeInterval(10 * 60),
            now: now
        )

        let suppressedCue = store.nextInlineCue(
            upcomingMeetings: [meeting],
            settings: enabledSettings(),
            now: now.addingTimeInterval(5 * 60)
        )
        #expect(suppressedCue == nil)

        let resumedCue = store.nextInlineCue(
            upcomingMeetings: [meeting],
            settings: enabledSettings(),
            now: now.addingTimeInterval(11 * 60)
        )
        #expect(resumedCue?.eventID == meeting.id)
    }

    @Test
    func presentedInlineCueTemporarilySuppressesStandaloneReminderDelivery() throws {
        let now = try #require(isoDate("2026-03-20T09:47:00+08:00"))
        let meeting = makeMeeting(
            id: "meeting-3",
            title: "Investor check-in",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let store = SupervisorCalendarReminderStateStore(
            proactiveLeadMinutes: 30,
            inlineCueCooldownSec: 8 * 60,
            pendingCueHoldWindowSec: 2 * 60
        )
        let reminder = makeReminder(meeting: meeting, phase: .headsUp)
        let cue = try #require(
            store.nextInlineCue(
                upcomingMeetings: [meeting],
                settings: enabledSettings(),
                now: now
            )
        )

        store.recordInlineCuePresentation(cue, now: now)

        #expect(
            store.suppressesReminderDelivery(
                for: reminder,
                now: now.addingTimeInterval(60)
            ) == true
        )
        #expect(
            store.suppressesReminderDelivery(
                for: reminder,
                now: now.addingTimeInterval(9 * 60)
            ) == false
        )
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

    private func makeMeeting(
        id: String,
        title: String,
        start: Date,
        end: Date
    ) -> XTCalendarEventSummary {
        XTCalendarEventSummary(
            id: id,
            source: "eventkit",
            title: title,
            startAt: start.timeIntervalSince1970,
            endAt: end.timeIntervalSince1970,
            location: "Zoom",
            joinURL: "https://zoom.example.com/\(id)",
            isMeeting: true,
            isAllDay: false
        )
    }

    private func makeReminder(
        meeting: XTCalendarEventSummary,
        phase: SupervisorCalendarReminderPhase
    ) -> SupervisorCalendarReminder {
        SupervisorCalendarReminder(
            eventID: meeting.id,
            eventTitle: meeting.title,
            phase: phase,
            fireAt: meeting.startDate.addingTimeInterval(-15 * 60).timeIntervalSince1970,
            validUntil: meeting.startDate.addingTimeInterval(-3 * 60).timeIntervalSince1970,
            eventStartAt: meeting.startAt,
            dedupeKey: "\(meeting.id):\(Int64(round(meeting.startAt * 1000.0))):\(phase.rawValue)",
            notificationIdentifier: "x_terminal_supervisor_calendar_\(meeting.id)"
        )
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
