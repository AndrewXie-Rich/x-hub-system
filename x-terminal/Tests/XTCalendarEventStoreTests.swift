import Foundation
import Testing
@testable import XTerminal

@MainActor
struct XTCalendarEventStoreTests {

    @Test
    func refreshUpcomingMeetingsUsesAuthorizedSnapshotAndFiltersMeetingEvents() {
        let accessClient = MockXTCalendarAuthorizationClient(
            currentStatus: .fullAccess,
            requestedStatus: .fullAccess
        )
        let accessController = XTCalendarAccessController(client: accessClient)
        let now = Date(timeIntervalSince1970: 1_742_451_200)
        let provider = MockXTCalendarEventProvider(
            events: [
                XTCalendarEventSummary(
                    id: "meeting-1",
                    source: "eventkit",
                    title: "Phoenix weekly sync",
                    startAt: now.addingTimeInterval(15 * 60).timeIntervalSince1970,
                    endAt: now.addingTimeInterval(45 * 60).timeIntervalSince1970,
                    location: "Zoom",
                    joinURL: "https://zoom.example.com/phoenix",
                    isMeeting: true,
                    isAllDay: false
                ),
                XTCalendarEventSummary(
                    id: "focus-block",
                    source: "eventkit",
                    title: "Focus block",
                    startAt: now.addingTimeInterval(30 * 60).timeIntervalSince1970,
                    endAt: now.addingTimeInterval(60 * 60).timeIntervalSince1970,
                    location: nil,
                    joinURL: nil,
                    isMeeting: false,
                    isAllDay: false
                ),
            ]
        )
        let store = XTCalendarEventStore(
            accessController: accessController,
            provider: provider
        )

        store.refreshUpcomingMeetings(now: now, lookaheadHours: 12)

        #expect(store.upcomingMeetings.count == 1)
        #expect(store.upcomingMeetings.first?.title == "Phoenix weekly sync")
        #expect(store.statusLine == "1 upcoming meeting in the next 12h")
        #expect(store.lastRefreshedAt == now.timeIntervalSince1970)
    }

    @Test
    func refreshUpcomingMeetingsClearsSnapshotWhenCalendarNotGranted() {
        let accessClient = MockXTCalendarAuthorizationClient(
            currentStatus: .denied,
            requestedStatus: .denied
        )
        let accessController = XTCalendarAccessController(client: accessClient)
        let provider = MockXTCalendarEventProvider(events: [])
        let store = XTCalendarEventStore(
            accessController: accessController,
            provider: provider
        )

        store.refreshUpcomingMeetings()

        #expect(store.upcomingMeetings.isEmpty)
        #expect(store.statusLine.contains("Calendar access is denied"))
        #expect(store.lastRefreshedAt == 0)
    }
}

private struct MockXTCalendarEventProvider: XTCalendarEventProvider {
    let events: [XTCalendarEventSummary]

    func fetchUpcomingEvents(now _: Date, lookaheadHours _: Int) -> [XTCalendarEventSummary] {
        events
    }
}

private final class MockXTCalendarAuthorizationClient: XTCalendarAuthorizationClient {
    var currentStatus: XTCalendarAuthorizationStatus
    var requestedStatus: XTCalendarAuthorizationStatus

    init(
        currentStatus: XTCalendarAuthorizationStatus,
        requestedStatus: XTCalendarAuthorizationStatus
    ) {
        self.currentStatus = currentStatus
        self.requestedStatus = requestedStatus
    }

    func authorizationStatus() -> XTCalendarAuthorizationStatus {
        currentStatus
    }

    func requestAccessIfNeeded() async -> XTCalendarAuthorizationStatus {
        currentStatus = requestedStatus
        return currentStatus
    }
}
