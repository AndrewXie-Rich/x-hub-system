import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorCalendarReminderSchedulerTests {

    @Test
    @MainActor
    func headsUpReminderAppearsInsideHeadsUpWindowOnly() throws {
        let meeting = makeMeeting(
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let reminders = SupervisorCalendarReminderScheduler.dueReminders(
            now: try #require(isoDate("2026-03-20T09:47:00+08:00")),
            upcomingMeetings: [meeting],
            preferences: .default(),
            deliveredDedupeKeys: []
        )

        #expect(reminders.map(\.phase) == [.headsUp])
        #expect(
            reminders.first?.dedupeKey ==
                "meeting-1:\(Int64(round(meeting.startAt * 1000.0))):heads_up"
        )
    }

    @Test
    @MainActor
    func finalCallWinsAfterHeadsUpWindowCloses() throws {
        let meeting = makeMeeting(
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let reminders = SupervisorCalendarReminderScheduler.dueReminders(
            now: try #require(isoDate("2026-03-20T09:58:00+08:00")),
            upcomingMeetings: [meeting],
            preferences: .default(),
            deliveredDedupeKeys: []
        )

        #expect(reminders.map(\.phase) == [.finalCall])
    }

    @Test
    @MainActor
    func startNowReminderOnlyAppearsNearMeetingStart() throws {
        let meeting = makeMeeting(
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let reminders = SupervisorCalendarReminderScheduler.dueReminders(
            now: try #require(isoDate("2026-03-20T10:00:20+08:00")),
            upcomingMeetings: [meeting],
            preferences: .default(),
            deliveredDedupeKeys: []
        )

        #expect(reminders.map(\.phase) == [.startNow])
    }

    @Test
    @MainActor
    func deliveredDedupeKeysSuppressRepeatForSamePhase() throws {
        let meeting = makeMeeting(
            title: "Phoenix weekly sync",
            start: try #require(isoDate("2026-03-20T10:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T10:30:00+08:00"))
        )
        let reminders = SupervisorCalendarReminderScheduler.dueReminders(
            now: try #require(isoDate("2026-03-20T09:47:00+08:00")),
            upcomingMeetings: [meeting],
            preferences: .default(),
            deliveredDedupeKeys: [
                "meeting-1:\(Int64(round(meeting.startAt * 1000.0))):heads_up"
            ]
        )

        #expect(reminders.isEmpty)
    }

    @Test
    @MainActor
    func endedAndAllDayEventsDoNotScheduleReminders() throws {
        let endedMeeting = makeMeeting(
            title: "Done",
            start: try #require(isoDate("2026-03-20T08:00:00+08:00")),
            end: try #require(isoDate("2026-03-20T08:30:00+08:00"))
        )
        let allDayMeeting = XTCalendarEventSummary(
            id: "meeting-2",
            source: "eventkit",
            title: "All Day Summit",
            startAt: try #require(isoDate("2026-03-20T00:00:00+08:00")).timeIntervalSince1970,
            endAt: try #require(isoDate("2026-03-21T00:00:00+08:00")).timeIntervalSince1970,
            location: nil,
            joinURL: "https://zoom.example.com/allday",
            isMeeting: true,
            isAllDay: true
        )

        let reminders = SupervisorCalendarReminderScheduler.dueReminders(
            now: try #require(isoDate("2026-03-20T09:47:00+08:00")),
            upcomingMeetings: [endedMeeting, allDayMeeting],
            preferences: .default(),
            deliveredDedupeKeys: []
        )

        #expect(reminders.isEmpty)
    }

    private func makeMeeting(
        title: String,
        start: Date,
        end: Date
    ) -> XTCalendarEventSummary {
        XTCalendarEventSummary(
            id: "meeting-1",
            source: "eventkit",
            title: title,
            startAt: start.timeIntervalSince1970,
            endAt: end.timeIntervalSince1970,
            location: "Zoom",
            joinURL: "https://zoom.example.com/phoenix",
            isMeeting: true,
            isAllDay: false
        )
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
