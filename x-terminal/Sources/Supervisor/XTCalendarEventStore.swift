import Combine
import Foundation
@preconcurrency import EventKit

struct XTCalendarEventSummary: Identifiable, Codable, Equatable, Sendable {
    static let schemaVersion = "xt.supervisor_calendar_event.v1"

    var schemaVersion: String = XTCalendarEventSummary.schemaVersion
    var id: String
    var source: String
    var title: String
    var startAt: TimeInterval
    var endAt: TimeInterval
    var location: String?
    var joinURL: String?
    var isMeeting: Bool
    var isAllDay: Bool

    var startDate: Date {
        Date(timeIntervalSince1970: startAt)
    }

    var endDate: Date {
        Date(timeIntervalSince1970: endAt)
    }
}

protocol XTCalendarEventProvider {
    func fetchUpcomingEvents(now: Date, lookaheadHours: Int) -> [XTCalendarEventSummary]
}

struct XTEventKitCalendarEventProvider: XTCalendarEventProvider {
    private let eventStore = EKEventStore()

    func fetchUpcomingEvents(now: Date, lookaheadHours: Int) -> [XTCalendarEventSummary] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard hasReadAccess(status: status) else {
            return []
        }

        eventStore.reset()

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = now.addingTimeInterval(Double(max(1, lookaheadHours)) * 3600.0)
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = eventStore.events(matching: predicate)

        return events
            .filter { !$0.isAllDay }
            .filter { $0.endDate > now }
            .sorted { lhs, rhs in
                lhs.startDate < rhs.startDate
            }
            .map { event in
                let joinURL = extractJoinURL(from: event)
                let blob = [
                    event.title,
                    event.location,
                    event.notes,
                    event.url?.absoluteString,
                    event.structuredLocation?.title,
                ]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                    .lowercased()
                let looksLikeConference = blob.contains("webex") ||
                    blob.contains("zoom") ||
                    blob.contains("meet.google") ||
                    blob.contains("teams")
                let isMeeting = joinURL != nil || event.hasAttendees || looksLikeConference

                return XTCalendarEventSummary(
                    id: event.eventIdentifier ?? UUID().uuidString.lowercased(),
                    source: "eventkit",
                    title: (event.title ?? "(No title)").trimmingCharacters(in: .whitespacesAndNewlines),
                    startAt: event.startDate.timeIntervalSince1970,
                    endAt: event.endDate.timeIntervalSince1970,
                    location: event.location,
                    joinURL: joinURL,
                    isMeeting: isMeeting,
                    isAllDay: event.isAllDay
                )
            }
    }

    private func extractJoinURL(from event: EKEvent) -> String? {
        if let url = event.url?.absoluteString, !url.isEmpty {
            return url
        }

        var candidates: [String] = []
        if let location = event.location, !location.isEmpty {
            candidates.append(location)
        }
        if let notes = event.notes, !notes.isEmpty {
            candidates.append(notes)
        }
        if let structuredLocation = event.structuredLocation?.title, !structuredLocation.isEmpty {
            candidates.append(structuredLocation)
        }

        return firstURL(in: candidates)
    }

    private func firstURL(in texts: [String]) -> String? {
        guard !texts.isEmpty else {
            return nil
        }

        let joined = texts.joined(separator: "\n")
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let ns = joined as NSString
            let matches = detector.matches(
                in: joined,
                options: [],
                range: NSRange(location: 0, length: ns.length)
            )
            if let url = matches.first?.url {
                return url.absoluteString
            }
        }

        let lower = joined.lowercased()
        if lower.contains("webex") || lower.contains("zoom") || lower.contains("meet.google") || lower.contains("teams") {
            let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            for token in joined.components(separatedBy: separators) {
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    continue
                }
                if trimmed.contains("://"), let url = URL(string: trimmed) {
                    return url.absoluteString
                }
                if trimmed.contains(".") && trimmed.contains("/") {
                    let candidate = "https://" + trimmed
                    if let url = URL(string: candidate) {
                        return url.absoluteString
                    }
                }
            }
        }

        return nil
    }

    private func hasReadAccess(status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            return status == .authorized || status == .fullAccess
        }
        return status == .authorized
    }
}

@MainActor
final class XTCalendarEventStore: ObservableObject {
    static let shared = XTCalendarEventStore()

    @Published private(set) var upcomingMeetings: [XTCalendarEventSummary] = []
    @Published private(set) var statusLine: String = "Calendar reminders are off"
    @Published private(set) var lastRefreshedAt: TimeInterval = 0

    private let accessController: XTCalendarAccessController
    private let provider: any XTCalendarEventProvider
    private var upcomingMeetingsOverrideForTesting: [XTCalendarEventSummary]?

    init(
        accessController: XTCalendarAccessController? = nil,
        provider: any XTCalendarEventProvider = XTEventKitCalendarEventProvider()
    ) {
        self.accessController = accessController ?? .shared
        self.provider = provider
    }

    func refreshUpcomingMeetings(now: Date = Date(), lookaheadHours: Int = 12) {
        guard accessController.authorizationStatus.canReadEvents else {
            clearSnapshot(reason: accessController.authorizationStatus.guidanceText)
            return
        }

        if let override = upcomingMeetingsOverrideForTesting {
            applyMeetingSnapshot(
                override.filter { $0.isMeeting && !$0.isAllDay && $0.endDate > now },
                now: now,
                lookaheadHours: lookaheadHours
            )
            return
        }

        let events = provider.fetchUpcomingEvents(now: now, lookaheadHours: lookaheadHours)
        let meetings = events.filter { $0.isMeeting }
        applyMeetingSnapshot(meetings, now: now, lookaheadHours: lookaheadHours)
    }

    func clearSnapshot(reason: String = "Calendar reminders are off") {
        upcomingMeetings = []
        statusLine = reason
        lastRefreshedAt = 0
    }

    func installUpcomingMeetingsOverrideForTesting(
        _ meetings: [XTCalendarEventSummary]?
    ) {
        upcomingMeetingsOverrideForTesting = meetings
    }

    private func applyMeetingSnapshot(
        _ meetings: [XTCalendarEventSummary],
        now: Date,
        lookaheadHours: Int
    ) {
        upcomingMeetings = meetings
        lastRefreshedAt = now.timeIntervalSince1970

        if meetings.isEmpty {
            statusLine = "No upcoming meetings in the next \(lookaheadHours)h"
        } else if meetings.count == 1 {
            statusLine = "1 upcoming meeting in the next \(lookaheadHours)h"
        } else {
            statusLine = "\(meetings.count) upcoming meetings in the next \(lookaheadHours)h"
        }
    }
}

extension XTCalendarEventSummary {
    func relativeStartText(now: Date = Date()) -> String {
        if now >= startDate && now < endDate {
            return "Now"
        }

        let delta = startDate.timeIntervalSince(now)
        if delta <= 0 {
            return "Soon"
        }

        let minutes = Int(ceil(delta / 60.0))
        if minutes >= 120 {
            return "in \(minutes / 60)h"
        }
        if minutes >= 60 {
            return "in \(minutes / 60)h \(minutes % 60)m"
        }
        return "in \(max(1, minutes))m"
    }

    var startTimeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startDate)
    }
}
