import Foundation
import EventKit
@preconcurrency import UserNotifications

// Keep EventKit authorization request outside @MainActor isolation.
// On macOS 26, EKEventStore's completion handler may be invoked off the main queue.
// If the closure is inferred as @MainActor (because it was created inside a @MainActor
// context), Swift Concurrency will trap with a dispatch_assert_queue failure.
private enum CalendarAuthorization {
    static func requestEventAccess() async -> Bool {
        await withCheckedContinuation { cont in
            // macOS 14+ split calendar permissions into full-access vs write-only.
            // In practice, some systems can be slow to transition TCC state, so we keep
            // this request logic conservative and include a legacy fallback.
            let store = EKEventStore()
            var resumed = false
            func resumeOnce(_ v: Bool) {
                guard !resumed else { return }
                resumed = true
                cont.resume(returning: v)
            }

            if #available(macOS 14.0, *) {
                store.requestFullAccessToEvents { granted, _ in
                    if granted {
                        resumeOnce(true)
                        return
                    }
                    // Fallback: older API sometimes succeeds on machines where the new
                    // full-access prompt returns without updating status immediately.
                    store.requestAccess(to: .event) { granted2, _ in
                        resumeOnce(granted2)
                    }
                }
            } else {
                store.requestAccess(to: .event) { granted, _ in
                    resumeOnce(granted)
                }
            }
        }
    }
}

struct HubMeeting: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var title: String
    var startAt: Double
    var endAt: Double
    var location: String?
    var joinURL: String?
    var isMeeting: Bool

    var startDate: Date { Date(timeIntervalSince1970: startAt) }
    var endDate: Date { Date(timeIntervalSince1970: endAt) }
}

@MainActor
final class CalendarPipeline {
    private let ekStore = EKEventStore()
    private var storeChangedObs: NSObjectProtocol?

    private var timer: Timer?
    private var lastScheduleKey: String = ""
    private(set) var remindMinutesBefore: Int

    init(remindMinutesBefore: Int) {
        self.remindMinutesBefore = remindMinutesBefore

        // Refresh quickly when calendar changes.
        storeChangedObs = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: ekStore,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Force reschedule on next poll.
            Task { @MainActor in
                self.lastScheduleKey = ""
            }
        }
    }

    func updateRemindMinutes(_ minutes: Int) {
        remindMinutesBefore = max(1, min(180, minutes))
        lastScheduleKey = "" // force reschedule next refresh
    }

    func currentStatusText() -> String {
        let st = EKEventStore.authorizationStatus(for: .event)

        if #available(macOS 14.0, *) {
            switch st {
            case .notDetermined:
                return "Calendar: not enabled"
            case .restricted:
                return "Calendar: restricted"
            case .denied:
                return "Calendar: denied"
            case .authorized, .fullAccess:
                return "Calendar: enabled"
            case .writeOnly:
                return "Calendar: write-only"
            default:
                return "Calendar: enabled?"
            }
        }

        switch st {
        case .notDetermined:
            return "Calendar: not enabled"
        case .restricted:
            return "Calendar: restricted"
        case .denied:
            return "Calendar: denied"
        case .authorized:
            return "Calendar: enabled"
        default:
            return "Calendar: enabled?"
        }
    }

    func requestAccessIfNeeded() async -> Bool {
        let st = EKEventStore.authorizationStatus(for: .event)
        if hasReadAccess(status: st) {
            return true
        }
        if st == .denied || st == .restricted {
            return false
        }
        // .notDetermined -> request.
        let ok = await requestAccess()
        // On some systems, the authorization status update can lag behind the completion handler.
        // Re-check with a short retry window.
        if ok {
            for _ in 0..<24 {
                let st2 = EKEventStore.authorizationStatus(for: .event)
                if hasReadAccess(status: st2) {
                    // The event store instance may have been created before permission was granted.
                    // Reset it so calendars/events become visible without requiring an app restart.
                    ekStore.reset()
                    return true
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        let final = hasReadAccess(status: EKEventStore.authorizationStatus(for: .event))
        if final {
            ekStore.reset()
        }
        return final
    }

    func startPolling(refresh: @MainActor @Sendable @escaping ([HubMeeting], [String]) -> Void) {
        stopPolling()

        // Poll every 15s to reflect near-term changes quickly without heavy cost.
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { _ in
            Task { @MainActor in
                let meetings = self.fetchNext12HoursMeetings()
                let specialDays = self.fetchTodaySpecialDays()
                refresh(meetings, specialDays)
                await self.rescheduleMeetingNotificationsIfNeeded(meetings: meetings)
            }
        }
        // immediate
        let meetings = fetchNext12HoursMeetings()
        let specialDays = fetchTodaySpecialDays()
        refresh(meetings, specialDays)
        Task { @MainActor in
            await self.rescheduleMeetingNotificationsIfNeeded(meetings: meetings)
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    /// Fetch today's remaining (and in-progress) events.
    ///
    /// We intentionally fetch a "today" window instead of a fixed 12h window so users
    /// can always see the rest of today's schedule after enabling Calendar.
    func fetchNext12HoursMeetings() -> [HubMeeting] {
        let st = EKEventStore.authorizationStatus(for: .event)
        guard hasReadAccess(status: st) else {
            return []
        }

        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        // End-of-day (23:59:59 local time).
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? startOfDay.addingTimeInterval(24 * 3600 - 1)

        // Use day window so we can include in-progress events that started earlier today.
        let pred = ekStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = ekStore.events(matching: pred)

        let meetings: [HubMeeting] = events
            .filter { !$0.isAllDay }
            // Only show events that haven't ended.
            .filter { ($0.endDate > now) }
            .sorted(by: { $0.startDate < $1.startDate })
            .map { e in
                let join = extractJoinURL(from: e)
                // Detect meetings more broadly so widget/card doesn't miss common conference events.
                let blob = [e.title, e.location, e.notes, e.url?.absoluteString, e.structuredLocation?.title]
                    .compactMap { $0 }
                    .joined(separator: "\n")
                    .lowercased()
                let looksLikeConf = blob.contains("webex") || blob.contains("zoom") || blob.contains("meet.google") || blob.contains("teams")
                let isMeeting = (join != nil) || (e.hasAttendees) || looksLikeConf
                return HubMeeting(
                    id: e.eventIdentifier ?? UUID().uuidString,
                    title: e.title ?? "(No title)",
                    startAt: e.startDate.timeIntervalSince1970,
                    endAt: e.endDate.timeIntervalSince1970,
                    location: e.location,
                    joinURL: join,
                    isMeeting: isMeeting
                )
            }

        return meetings
    }

    /// Fetch all-day "special day" entries for today (e.g. Holiday calendars).
    ///
    /// This is used by the floating card when there are no other alerts.
    func fetchTodaySpecialDays() -> [String] {
        let st = EKEventStore.authorizationStatus(for: .event)
        guard hasReadAccess(status: st) else {
            return []
        }

        let now = Date()
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)
        let endOfDay = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now) ?? startOfDay.addingTimeInterval(24 * 3600 - 1)

        let pred = ekStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = ekStore.events(matching: pred)

        var out: [String] = []
        out.reserveCapacity(8)
        var seen: Set<String> = []

        for e in events {
            if !e.isAllDay { continue }
            let t = (e.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if seen.contains(t) { continue }
            seen.insert(t)
            out.append(t)
        }

        // Keep stable ordering.
        return out
    }

    private func extractJoinURL(from event: EKEvent) -> String? {
        if let url = event.url?.absoluteString, !url.isEmpty {
            return url
        }

        var candidates: [String] = []
        if let s = event.location, !s.isEmpty { candidates.append(s) }
        if let s = event.notes, !s.isEmpty { candidates.append(s) }
        if let s = event.structuredLocation?.title, !s.isEmpty { candidates.append(s) }

        return firstURL(in: candidates)
    }

    private func firstURL(in texts: [String]) -> String? {
        guard !texts.isEmpty else { return nil }

        let joined = texts.joined(separator: "\n")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let ns = joined as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = detector.matches(in: joined, options: [], range: range)
        if let m = matches.first, let url = m.url {
            return url.absoluteString
        }

        // Heuristic: some calendar clients store conference links without a scheme.
        // Try to recover common cases like "meet.example.webex.com/meet/...".
        let lower = joined.lowercased()
        if lower.contains("webex") || lower.contains("zoom") || lower.contains("meet.google") || lower.contains("teams") {
            let seps = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
            for raw in joined.components(separatedBy: seps) {
                let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                if t.contains("://") {
                    if let u = URL(string: t) { return u.absoluteString }
                    continue
                }
                // No scheme: add https:// and re-try if it looks like a host/path.
                if (t.contains(".") && t.contains("/")) || t.contains("webex") {
                    let cand = "https://" + t
                    if let u = URL(string: cand) {
                        return u.absoluteString
                    }
                }
            }
        }
        return nil
    }

    private func requestAccess() async -> Bool {
        await CalendarAuthorization.requestEventAccess()
    }

    private func hasReadAccess(status: EKAuthorizationStatus) -> Bool {
        if #available(macOS 14.0, *) {
            if status == .fullAccess { return true }
            if status == .authorized { return true }
            return false
        }
        if status == .authorized { return true }
        return false
    }

    private func scheduleKey(for meetings: [HubMeeting]) -> String {
        // Keep this stable across refresh cycles.
        let ids = meetings.map { "\($0.id):\(Int($0.startAt))" }.joined(separator: ",")
        return "r=\(remindMinutesBefore)|m=\(ids)"
    }

    private func meetingNotifId(_ m: HubMeeting) -> String {
        "relflowhub.meeting.\(m.id).\(Int(m.startAt))"
    }

    private func rescheduleMeetingNotificationsIfNeeded(meetings: [HubMeeting]) async {
        guard NotificationSupport.isAvailable else { return }
        let key = scheduleKey(for: meetings)
        if key == lastScheduleKey {
            return
        }
        lastScheduleKey = key

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            return
        }

        // Remove prior meeting reminders and rebuild from current calendar snapshot.
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending
            .map { $0.identifier }
            .filter { $0.hasPrefix("relflowhub.meeting.") }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }

        let now = Date()
        for m in meetings {
            let fire = m.startDate.addingTimeInterval(-Double(remindMinutesBefore) * 60.0)
            if fire <= now {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = m.title
            content.body = "Starts at \(timeText(m.startDate))"
            content.sound = .default
            if let url = m.joinURL {
                content.userInfo["action_url"] = url
            }

            let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)
            let req = UNNotificationRequest(identifier: meetingNotifId(m), content: content, trigger: trigger)
            try? await center.add(req)
        }
    }

    private func timeText(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
}
