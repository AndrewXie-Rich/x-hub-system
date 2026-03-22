import Foundation

struct SupervisorCalendarInlineCue: Equatable, Sendable {
    enum Source: String, Codable, Equatable, Sendable {
        case conversationDeferred = "conversation_deferred"
        case proactiveContext = "proactive_context"
    }

    var eventID: String
    var title: String
    var eventStartAt: TimeInterval
    var minutesUntilStart: Int
    var source: Source

    var eventStartDate: Date {
        Date(timeIntervalSince1970: eventStartAt)
    }
}

private struct SupervisorCalendarPendingInlineCue: Equatable {
    var reminder: SupervisorCalendarReminder
    var queuedAt: TimeInterval
}

@MainActor
final class SupervisorCalendarReminderStateStore: ObservableObject {
    static let shared = SupervisorCalendarReminderStateStore()

    @Published private(set) var pendingInlineCueCount: Int = 0

    private let proactiveLeadMinutes: Int
    private let inlineCueCooldownSec: TimeInterval
    private let pendingCueHoldWindowSec: TimeInterval
    private var pendingInlineCuesByEventID: [String: SupervisorCalendarPendingInlineCue] = [:]
    private var snoozedUntilByEventID: [String: TimeInterval] = [:]
    private var interruptConversationUntilByEventID: [String: TimeInterval] = [:]
    private var lastInlineCueAtByEventID: [String: TimeInterval] = [:]

    init(
        proactiveLeadMinutes: Int = 30,
        inlineCueCooldownSec: TimeInterval = 8 * 60,
        pendingCueHoldWindowSec: TimeInterval = 2 * 60
    ) {
        self.proactiveLeadMinutes = max(5, proactiveLeadMinutes)
        self.inlineCueCooldownSec = max(30, inlineCueCooldownSec)
        self.pendingCueHoldWindowSec = max(30, pendingCueHoldWindowSec)
    }

    func registerConversationDeferredReminder(
        _ reminder: SupervisorCalendarReminder,
        now: Date = Date()
    ) {
        cleanup(now: now, upcomingMeetings: [])
        pendingInlineCuesByEventID[reminder.eventID] = SupervisorCalendarPendingInlineCue(
            reminder: reminder,
            queuedAt: now.timeIntervalSince1970
        )
        publishPendingCueCount()
    }

    func suppressesReminderDelivery(
        for reminder: SupervisorCalendarReminder,
        now: Date = Date()
    ) -> Bool {
        cleanup(now: now, upcomingMeetings: [])
        return isSnoozed(eventID: reminder.eventID, now: now) ||
            hasFreshPendingInlineCue(eventID: reminder.eventID, now: now) ||
            wasInlineCuePresentedRecently(eventID: reminder.eventID, now: now)
    }

    func nextInlineCue(
        upcomingMeetings: [XTCalendarEventSummary],
        settings: XTerminalSettings,
        now: Date = Date()
    ) -> SupervisorCalendarInlineCue? {
        let preferences = settings.supervisorCalendarReminders.normalized()
        guard preferences.enabled else { return nil }

        cleanup(now: now, upcomingMeetings: upcomingMeetings)

        if let cue = pendingInlineCue(
            upcomingMeetings: upcomingMeetings,
            now: now
        ) {
            return cue
        }

        return proactiveInlineCue(
            upcomingMeetings: upcomingMeetings,
            now: now
        )
    }

    func recordInlineCuePresentation(
        _ cue: SupervisorCalendarInlineCue,
        now: Date = Date()
    ) {
        cleanup(now: now, upcomingMeetings: [])
        lastInlineCueAtByEventID[cue.eventID] = now.timeIntervalSince1970
        pendingInlineCuesByEventID.removeValue(forKey: cue.eventID)
        publishPendingCueCount()
    }

    func nextSnoozeableMeeting(
        upcomingMeetings: [XTCalendarEventSummary],
        now: Date = Date()
    ) -> XTCalendarEventSummary? {
        cleanup(now: now, upcomingMeetings: upcomingMeetings)

        if let pending = pendingInlineCue(
            upcomingMeetings: upcomingMeetings,
            now: now
        ),
           let meeting = upcomingMeetings.first(where: { $0.id == pending.eventID }) {
            return meeting
        }

        return upcomingMeetings
            .filter { meeting in
                meeting.isMeeting &&
                    !meeting.isAllDay &&
                    meeting.startDate > now &&
                    meeting.endDate > now &&
                    meeting.startDate.timeIntervalSince(now) <= Double(proactiveLeadMinutes) * 60.0 &&
                    !isSnoozed(eventID: meeting.id, now: now)
            }
            .sorted { lhs, rhs in
                lhs.startAt < rhs.startAt
            }
            .first
    }

    func applySnooze(
        eventID: String,
        until: Date,
        now: Date = Date()
    ) {
        cleanup(now: now, upcomingMeetings: [])
        if until > now {
            snoozedUntilByEventID[eventID] = until.timeIntervalSince1970
        } else {
            snoozedUntilByEventID.removeValue(forKey: eventID)
        }
        pendingInlineCuesByEventID.removeValue(forKey: eventID)
        lastInlineCueAtByEventID.removeValue(forKey: eventID)
        publishPendingCueCount()
    }

    func setConversationInterruptPreference(
        eventID: String,
        enabledUntil: Date?,
        now: Date = Date()
    ) {
        cleanup(now: now, upcomingMeetings: [])
        guard let enabledUntil,
              enabledUntil > now else {
            interruptConversationUntilByEventID.removeValue(forKey: eventID)
            return
        }
        interruptConversationUntilByEventID[eventID] = enabledUntil.timeIntervalSince1970
    }

    func shouldInterruptConversation(
        for reminder: SupervisorCalendarReminder,
        now: Date = Date()
    ) -> Bool {
        cleanup(now: now, upcomingMeetings: [])
        guard reminder.phase == .startNow,
              let enabledUntil = interruptConversationUntilByEventID[reminder.eventID] else {
            return false
        }
        return enabledUntil > now.timeIntervalSince1970
    }

    func resetForTesting() {
        pendingInlineCuesByEventID = [:]
        snoozedUntilByEventID = [:]
        interruptConversationUntilByEventID = [:]
        lastInlineCueAtByEventID = [:]
        publishPendingCueCount()
    }

    private func pendingInlineCue(
        upcomingMeetings: [XTCalendarEventSummary],
        now: Date
    ) -> SupervisorCalendarInlineCue? {
        let meetingsByID = Dictionary(
            upcomingMeetings.map { meeting in
                (meeting.id, meeting)
            },
            uniquingKeysWith: { lhs, _ in lhs }
        )

        let candidates = pendingInlineCuesByEventID.values
            .filter { candidate in
                now.timeIntervalSince1970 - candidate.queuedAt <= pendingCueHoldWindowSec
            }
            .compactMap { candidate -> SupervisorCalendarInlineCue? in
                guard let meeting = meetingsByID[candidate.reminder.eventID],
                      meeting.startDate > now,
                      meeting.endDate > now,
                      !isSnoozed(eventID: meeting.id, now: now) else {
                    return nil
                }
                return SupervisorCalendarInlineCue(
                    eventID: meeting.id,
                    title: meeting.title,
                    eventStartAt: meeting.startAt,
                    minutesUntilStart: max(
                        1,
                        Int(ceil(meeting.startDate.timeIntervalSince(now) / 60.0))
                    ),
                    source: .conversationDeferred
                )
            }
            .sorted { lhs, rhs in
                if lhs.eventStartAt == rhs.eventStartAt {
                    return lhs.eventID < rhs.eventID
                }
                return lhs.eventStartAt < rhs.eventStartAt
            }

        return candidates.first
    }

    private func proactiveInlineCue(
        upcomingMeetings: [XTCalendarEventSummary],
        now: Date
    ) -> SupervisorCalendarInlineCue? {
        let maxLeadSeconds = Double(proactiveLeadMinutes) * 60.0
        return upcomingMeetings
            .filter { meeting in
                meeting.isMeeting &&
                    !meeting.isAllDay &&
                    meeting.startDate > now &&
                    meeting.endDate > now &&
                    meeting.startDate.timeIntervalSince(now) <= maxLeadSeconds &&
                    !isSnoozed(eventID: meeting.id, now: now) &&
                    !wasInlineCuePresentedRecently(eventID: meeting.id, now: now)
            }
            .sorted { lhs, rhs in
                if lhs.startAt == rhs.startAt {
                    return lhs.id < rhs.id
                }
                return lhs.startAt < rhs.startAt
            }
            .first
            .map { meeting in
                SupervisorCalendarInlineCue(
                    eventID: meeting.id,
                    title: meeting.title,
                    eventStartAt: meeting.startAt,
                    minutesUntilStart: max(
                        1,
                        Int(ceil(meeting.startDate.timeIntervalSince(now) / 60.0))
                    ),
                    source: .proactiveContext
                )
            }
    }

    private func cleanup(
        now: Date,
        upcomingMeetings: [XTCalendarEventSummary]
    ) {
        let nowTs = now.timeIntervalSince1970
        let activeEventIDs = Set(
            upcomingMeetings
                .filter { $0.endDate > now }
                .map(\.id)
        )

        pendingInlineCuesByEventID = pendingInlineCuesByEventID.filter { eventID, candidate in
            if nowTs - candidate.queuedAt > pendingCueHoldWindowSec {
                return false
            }
            if activeEventIDs.isEmpty {
                return candidate.reminder.validUntil >= nowTs
            }
            return activeEventIDs.contains(eventID)
        }
        snoozedUntilByEventID = snoozedUntilByEventID.filter { _, value in
            value > nowTs
        }
        interruptConversationUntilByEventID = interruptConversationUntilByEventID.filter { eventID, value in
            guard value > nowTs else {
                return false
            }
            if activeEventIDs.isEmpty {
                return true
            }
            return activeEventIDs.contains(eventID)
        }
        let inlineCueRetentionWindow = nowTs - (6 * 60 * 60)
        lastInlineCueAtByEventID = lastInlineCueAtByEventID.filter { _, value in
            value >= inlineCueRetentionWindow
        }
        publishPendingCueCount()
    }

    private func publishPendingCueCount() {
        pendingInlineCueCount = pendingInlineCuesByEventID.count
    }

    private func isSnoozed(eventID: String, now: Date) -> Bool {
        guard let snoozedUntil = snoozedUntilByEventID[eventID] else {
            return false
        }
        return snoozedUntil > now.timeIntervalSince1970
    }

    private func hasFreshPendingInlineCue(
        eventID: String,
        now: Date
    ) -> Bool {
        guard let pending = pendingInlineCuesByEventID[eventID] else {
            return false
        }
        return now.timeIntervalSince1970 - pending.queuedAt <= pendingCueHoldWindowSec
    }

    private func wasInlineCuePresentedRecently(
        eventID: String,
        now: Date
    ) -> Bool {
        guard let lastPresentedAt = lastInlineCueAtByEventID[eventID] else {
            return false
        }
        return now.timeIntervalSince1970 - lastPresentedAt < inlineCueCooldownSec
    }
}
