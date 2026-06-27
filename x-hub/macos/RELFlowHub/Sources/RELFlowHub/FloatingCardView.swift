import SwiftUI
import AppKit
import RELFlowHubCore

struct CardFloatingView: View {
    @EnvironmentObject var store: HubStore
    let summary: SummaryState

    // Drive the card carousel with a GCD timer. In a non-activating floating NSPanel,
    // RunLoop timers and TimelineView ticks can be unreliable depending on tracking modes.
    @State private var seconds: Int = 0
    @State private var ticker: DispatchSourceTimer?

    private let corner: CGFloat = 20

    private var weekday: String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE"
        return f.string(from: Date()).uppercased()
    }

    private var weekdayColor: Color {
        // Sunday only should be red (common calendar convention).
        let w = Calendar.current.component(.weekday, from: Date())
        return (w == 1) ? .red : .primary
    }

    private var specialDayText: String {
        // Show special all-day events (e.g. holiday calendars) only when the card has no other content.
        let items = store.specialDaysToday
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if items.isEmpty { return "" }
        // Keep it short on the card; show at most 1-2 names.
        if items.count == 1 { return items[0] }
        return items.prefix(2).joined(separator: " • ")
    }

    private var lunarText: String {
        let cal = Calendar(identifier: .chinese)
        let dc = cal.dateComponents([.month, .day], from: Date())
        return HubUIStrings.FloatingCard.Lunar.label(
            month: dc.month ?? 0,
            day: dc.day ?? 0
        )
    }

    private var monthDayText: String {
        let f = DateFormatter()
        // Keep it consistent with your request (Jan 30), independent of system locale.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"
        return f.string(from: Date())
    }

    private struct CardItem: Identifiable {
        enum Kind {
            case meeting
            case radar
            case message
            case mail
            case slack
            case other
            case empty
        }

        let id: String
        let kind: Kind
        let tint: Color
        let headerLeft: String
        let headerRight: String
        let line2: String
        let line3: String
        let action: () -> Void
    }

    private struct CardPage: Identifiable {
        enum Kind {
            case meeting
            case radar
            case message
            case mail
            case slack
            case other
        }

        let id: String
        let kind: Kind
        let items: [CardItem]
    }

    private func formatMeetingTimeRange(start: Double, end: Double) -> String {
        let ds = Date(timeIntervalSince1970: start)
        let de = Date(timeIntervalSince1970: end)

        let mer = DateFormatter()
        mer.locale = Locale(identifier: "en_US_POSIX")
        mer.dateFormat = "a"
        let sMer = mer.string(from: ds)
        let eMer = mer.string(from: de)

        let fs = DateFormatter()
        fs.locale = Locale(identifier: "en_US_POSIX")
        fs.dateFormat = (sMer == eMer) ? "h:mm" : "h:mma"

        let fe = DateFormatter()
        fe.locale = Locale(identifier: "en_US_POSIX")
        fe.dateFormat = "h:mma"

        return "\(fs.string(from: ds)) - \(fe.string(from: de))"
    }

    private func meetingCountdownMinutes(startAt: Double, now: Double) -> String {
        let dt = startAt - now
        if dt <= 0 { return HubUIStrings.MainPanel.Meeting.inProgress }
        let mins = max(1, Int(ceil(dt / 60.0)))
        if mins >= 60 {
            let h = mins / 60
            let m = mins % 60
            return m == 0
                ? HubUIStrings.FloatingCard.compactHours(h)
                : HubUIStrings.FloatingCard.compactHoursMinutes(hours: h, minutes: m)
        }
        return HubUIStrings.FloatingCard.compactMinutes(mins)
    }

    private func notificationAgeText(createdAt: Double, now: Double) -> String {
        let dt = max(0, now - createdAt)
        let mins = Int(dt / 60.0)
        if mins >= 120 {
            return HubUIStrings.FloatingCard.compactHours(mins / 60)
        }
        if mins >= 60 {
            return HubUIStrings.FloatingCard.compactHoursMinutes(hours: mins / 60, minutes: mins % 60)
        }
        return HubUIStrings.FloatingCard.compactMinutes(max(1, mins))
    }

    private func notificationsSnapshot() -> [HubNotification] {
        if !store.notifications.isEmpty {
            return store.notifications
        }
        // Fallback: if the in-memory store is empty for any reason, read the persisted file.
        // This makes the card resilient even if it appears before IPC has warmed up.
        // IMPORTANT: don't call ensureHubDirectory() here because it may create/select a
        // different writable directory than the one HubStore persisted to (depending on
        // sandbox/AppGroup flags). Instead, probe all known locations.
        let dirs = SharedPaths.hubDirectoryCandidates()
        for dir in dirs {
            let url = dir.appendingPathComponent("notifications.json")
            if !FileManager.default.fileExists(atPath: url.path) { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            if let arr = try? JSONDecoder().decode([HubNotification].self, from: data) {
                return arr
            }
        }
        return []
    }

    private func openNotificationFromFloating(_ notification: HubNotification) {
        let presentation = hubNotificationPresentation(for: notification)
        switch presentation.primaryAction {
        case .inspect, .none:
            store.presentNotificationInspector(notification)
            store.markRead(notification.id)
        case .openTarget:
            store.openNotificationAction(notification)
            store.markRead(notification.id)
        }
    }

    private func floatingNotificationHeader(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        if let badge = presentation.badge?.trimmingCharacters(in: .whitespacesAndNewlines),
           !badge.isEmpty {
            return badge
        }
        let source = hubNotificationDisplaySource(notification)
        return source.isEmpty ? HubUIStrings.FloatingCard.defaultNotificationHeader : source
    }

    private func floatingNotificationLine2(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        let title = (presentation.displayTitle ?? notification.title).trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            return title
        }
        if !presentation.subline.isEmpty {
            return presentation.subline
        }
        return HubUIStrings.FloatingCard.defaultHubUpdate
    }

    private func floatingNotificationLine3(_ notification: HubNotification) -> String {
        let presentation = hubNotificationPresentation(for: notification)
        if let nextStep = presentation.recommendedNextStep, !nextStep.isEmpty {
            return "\(HubUIStrings.Menu.NotificationRow.nextStepPrefix)\(nextStep)"
        }
        if let executionSurface = presentation.executionSurface, !executionSurface.isEmpty {
            return "\(HubUIStrings.Menu.NotificationRow.executionSurfacePrefix)\(executionSurface)"
        }
        if !presentation.subline.isEmpty {
            return presentation.subline
        }
        if let relevance = presentation.relevance, !relevance.isEmpty {
            return relevance
        }
        return ""
    }

    private func floatingNotificationTint(_ notification: HubNotification) -> Color {
        let presentation = hubNotificationPresentation(for: notification)
        switch presentation.group {
        case .actionRequired:
            return Color(red: 0.30, green: 0.58, blue: 1.0)
        case .advisory:
            return Color(red: 0.23, green: 0.70, blue: 0.74)
        case .background:
            return Color.secondary.opacity(0.72)
        }
    }

    private func cardPages(now: Double) -> [CardPage] {
        // 0) Urgent meeting breaks rotation.
        if let m = store.meetings
            .filter({ $0.isMeeting && !$0.id.isEmpty && !store.isMeetingDismissed($0, now: now) && $0.endAt > now })
            .sorted(by: { $0.startAt < $1.startAt })
            .first
        {
            let mins = Int(ceil(max(0, m.startAt - now) / 60.0))
            if mins <= store.meetingUrgentMinutes {
                let it = CardItem(
                    id: "urgent_\(m.id)|\(Int(m.startAt))",
                    kind: .meeting,
                    tint: Color(red: 1.0, green: 0.32, blue: 0.32),
                    headerLeft: HubUIStrings.MainPanel.Inbox.meetingsSection,
                    headerRight: (now >= m.startAt) ? HubUIStrings.MainPanel.Meeting.inProgress : meetingCountdownMinutes(startAt: m.startAt, now: now),
                    line2: m.title,
                    line3: formatMeetingTimeRange(start: m.startAt, end: m.endAt),
                    action: { store.openMeeting(m) }
                )
                return [CardPage(id: "page_urgent", kind: .meeting, items: [it])]
            }
        }

        var pages: [CardPage] = []

        // Meetings page.
        let ms = store.meetings
            .filter { $0.isMeeting && !$0.id.isEmpty && !store.isMeetingDismissed($0, now: now) && $0.endAt > now }
            .sorted { $0.startAt < $1.startAt }

        func meetingTint(_ m: HubMeeting) -> Color {
            let mins = Int(ceil(max(0, m.startAt - now) / 60.0))
            if now < m.endAt {
                let urgentMin = max(1, store.meetingUrgentMinutes)
                let outerMin = max(urgentMin, store.calendarRemindMinutes)
                let hotMin = min(10, outerMin)
                let base = Color(red: 1.0, green: 0.64, blue: 0.64) // meeting family
                if mins <= urgentMin { return Color(red: 1.0, green: 0.32, blue: 0.32) }
                if mins <= hotMin, hotMin > urgentMin { return Color(red: 1.0, green: 0.48, blue: 0.34) }
                if mins <= outerMin { return base }
                // Still show it's a meeting (but subtle) even when it's far away.
                return base.opacity(0.55)
            }
            return Color.white.opacity(0.55)
        }

        if !ms.isEmpty {
            let items: [CardItem] = ms.prefix(2).map { m in
                CardItem(
                    id: "m_\(m.id)|\(Int(m.startAt))",
                    kind: .meeting,
                    tint: meetingTint(m),
                    headerLeft: HubUIStrings.MainPanel.Inbox.meetingsSection,
                    headerRight: meetingCountdownMinutes(startAt: m.startAt, now: now),
                    line2: m.title,
                    line3: formatMeetingTimeRange(start: m.startAt, end: m.endAt),
                    action: { store.openMeeting(m) }
                )
            }
            pages.append(CardPage(id: "page_meetings", kind: .meeting, items: items))
        }

        // Radar page: Top2 projects (display), click opens ALL today's new radars.
        do {
            let cal = Calendar.current
            let todayStart = cal.startOfDay(for: Date()).timeIntervalSince1970
            let active = notificationsSnapshot().filter { ($0.snoozedUntil ?? 0) <= now }
            // Card is both a reminder and a quick info surface: keep showing today's radars
            // even after they've been opened, but only unread affects tint.
            let allFA = active.filter { store.isFATrackerRadarNotification($0) }

            // Prefer "today" (since midnight). If there are none (e.g. you worked late and
            // the last push was yesterday night), fall back to a rolling 24h window.
            let todayFA = allFA.filter { $0.createdAt >= todayStart }
            let recentFA = allFA.filter { $0.createdAt >= (now - 24 * 3600) }
            let shownFA = !todayFA.isEmpty ? todayFA : recentFA

            struct P { let name: String; let ids: [Int]; let unreadCount: Int }
            var byProject: [String: [Int]] = [:]
            var byProjectUnread: [String: Int] = [:]
            var allIds: [Int] = []
            for n in shownFA {
                let bodyLines = n.body.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
                let pn = (bodyLines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let project = pn.isEmpty ? HubUIStrings.FloatingCard.unnamedProject : pn

                var ids: [Int] = []
                if let s = n.actionURL, let u = URL(string: s), (u.scheme ?? "").lowercased() == "relflowhub" {
                    let items = URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let raw = items.first(where: { $0.name == "radars" })?.value ?? ""
                    ids = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }
                if ids.isEmpty, bodyLines.count >= 2 {
                    // Backward-compatible: the agent writes a plain id list on line 2.
                    ids = bodyLines[1].split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if ids.isEmpty {
                        // Fallback: tolerate whitespace-separated ids or tokens with punctuation.
                        ids = bodyLines[1]
                            .split(whereSeparator: { $0.isWhitespace })
                            .compactMap { tok in
                                let digits = tok.filter { $0.isNumber }
                                guard digits.count >= 5 else { return nil }
                                return Int(digits)
                            }
                    }
                }
                if ids.isEmpty { continue }

                byProject[project, default: []].append(contentsOf: ids)
                if n.unread {
                    byProjectUnread[project, default: 0] += ids.count
                }
                allIds.append(contentsOf: ids)
            }

            // De-dup all ids for click action.
            var seenAll: Set<Int> = []
            allIds = allIds.filter { seenAll.insert($0).inserted }

            // If we fail to parse radar ids for some reason, still show a radar page so the card
            // can rotate and offer a fallback click to open FA Tracker.
            if !byProject.isEmpty || !shownFA.isEmpty {
                var ps: [P] = []
                for (k, v0) in byProject {
                    var seen: Set<Int> = []
                    let ids = v0.filter { seen.insert($0).inserted }
                    ps.append(P(name: k, ids: ids, unreadCount: byProjectUnread[k, default: 0]))
                }
                if ps.isEmpty {
                    // Synthetic bucket with best-effort project name.
                    let firstProj = todayFA.compactMap { n -> String? in
                        let pn = n.body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first
                        let s = String(pn ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return s.isEmpty ? nil : s
                    }.first
                    ps = [P(name: firstProj ?? HubUIStrings.FloatingCard.unnamedProject, ids: [], unreadCount: shownFA.filter { $0.unread }.count)]
                }
                ps.sort { a, b in
                    if a.ids.count != b.ids.count { return a.ids.count > b.ids.count }
                    return a.name < b.name
                }
                let shown = Array(ps.prefix(2))
                let items: [CardItem] = shown.map { p in
                    let total = p.ids.count
                    let shownIds = p.ids.prefix(5).map { String($0) }.joined(separator: ", ")
                    let idsText: String = {
                        if p.ids.isEmpty {
                            return HubUIStrings.FloatingCard.openFATracker
                        }
                        return (total <= 5) ? shownIds : "\(shownIds)  +\(total - 5)"
                    }()
                    let baseTint = Color(red: 1.0, green: 0.784, blue: 0.341) // #FFC857
                    // Keep family color even after "read" so the page type is obvious.
                    let tint = (p.unreadCount > 0) ? baseTint : baseTint.opacity(0.55)
                    return CardItem(
                        id: "rad_\(p.name)",
                        kind: .radar,
                        tint: tint,
                        headerLeft: HubUIStrings.FloatingCard.radarHeader,
                        headerRight: (p.unreadCount > 0) ? "\(p.unreadCount)" : (total > 0 ? "\(total)" : ""),
                        line2: p.name,
                        line3: idsText,
                        action: {
                            if !allIds.isEmpty {
                                store.openFATrackerForRadars(allIds, projectId: nil, fallbackURL: allIds.first.map { "rdar://\($0)" })
                            } else {
                                _ = store.openFATracker()
                            }
                            // Opening from the card counts as "seen".
                            for n in shownFA where n.unread {
                                store.markRead(n.id)
                            }
                        }
                    )
                }
                pages.append(CardPage(id: "page_radar", kind: .radar, items: items))
            }
        }

        // Messages/Mail/Slack/Other pages are driven by local push notifications.
        // For counts-only notifications (Mail/Messages/Slack), keep showing the card even after
        // the user opened the target app. This makes the card behave like a status dashboard.
        let activeNotifs = notificationsSnapshot().filter {
            guard ($0.snoozedUntil ?? 0) <= now else { return false }
            let key = $0.dedupeKey ?? ""
            let isCountsOnly = (key == "mail_unread" || key == "messages_unread" || key == "slack_updates")
            return $0.unread || isCountsOnly
        }
        func notifPage(source: String, kind: CardPage.Kind, tint: Color) -> CardPage? {
            let rows = activeNotifs.filter { $0.source == source }
            if rows.isEmpty { return nil }
            let items: [CardItem] = rows.prefix(2).map { n in
                let isCountsOnly = (n.dedupeKey == "mail_unread" || n.dedupeKey == "messages_unread" || n.dedupeKey == "slack_updates")
                let presentation = hubNotificationPresentation(for: n)
                let headerRight = isCountsOnly ? n.body : notificationAgeText(createdAt: n.createdAt, now: now)
                let line2 = isCountsOnly
                    ? HubUIStrings.FloatingCard.openSource(source)
                    : ((presentation.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
                        ? presentation.displayTitle!.trimmingCharacters(in: .whitespacesAndNewlines)
                        : n.title)
                let line3 = isCountsOnly
                    ? ""
                    : floatingNotificationSummaryLine(
                        subline: presentation.subline,
                        nextStep: presentation.recommendedNextStep,
                        fallbackBody: n.body
                    )
                return CardItem(
                    id: "n_\(n.id)",
                    kind: (source == "Messages" ? .message : (source == "Mail" ? .mail : .slack)),
                    tint: tint,
                    headerLeft: source.uppercased(),
                    headerRight: headerRight,
                    line2: line2,
                    line3: line3,
                    action: { openNotificationFromFloating(n) }
                )
            }
            return CardPage(id: "page_\(source)", kind: kind, items: items)
        }

        if let p = notifPage(source: "Messages", kind: .message, tint: Color(red: 0.62, green: 0.90, blue: 0.62)) {
            pages.append(p)
        }
        if let p = notifPage(source: "Mail", kind: .mail, tint: Color(red: 0.35, green: 0.66, blue: 1.00)) {
            pages.append(p)
        }
        if let p = notifPage(source: "Slack", kind: .slack, tint: Color(red: 0.55, green: 0.45, blue: 1.0)) {
            pages.append(p)
        }

        // Other unread notifications (excluding FAtracker + Messages/Mail/Slack).
        let otherPresented = activeNotifs
            .filter { !["FAtracker", "Messages", "Mail", "Slack"].contains($0.source) }
            .map { ($0, hubNotificationPresentation(for: $0)) }
            .sorted { lhs, rhs in
                let lGroup = lhs.1.group
                let rGroup = rhs.1.group
                let rank: (HubNotificationPresentationGroup) -> Int = { group in
                    switch group {
                    case .actionRequired:
                        return 0
                    case .advisory:
                        return 1
                    case .background:
                        return 2
                    }
                }
                if rank(lGroup) != rank(rGroup) {
                    return rank(lGroup) < rank(rGroup)
                }
                return lhs.0.createdAt > rhs.0.createdAt
            }

        let priorityOther = otherPresented.filter { $0.1.group != .background }
        let backgroundOther = otherPresented.filter { $0.1.group == .background }
        let shownOther = priorityOther.isEmpty ? Array(backgroundOther.prefix(1)) : Array(priorityOther.prefix(2))

        if !shownOther.isEmpty {
            let items: [CardItem] = shownOther.map { entry in
                let n = entry.0
                return CardItem(
                    id: "n2_\(n.id)",
                    kind: .other,
                    tint: floatingNotificationTint(n),
                    headerLeft: floatingNotificationHeader(n),
                    headerRight: notificationAgeText(createdAt: n.createdAt, now: now),
                    line2: floatingNotificationLine2(n),
                    line3: floatingNotificationLine3(n),
                    action: { openNotificationFromFloating(n) }
                )
            }
            pages.append(CardPage(id: "page_other", kind: .other, items: items))
        }

        if pages.isEmpty {
            // Keep a stable empty state.
            let it = CardItem(
                id: "empty",
                kind: .empty,
                tint: .secondary,
                headerLeft: "",
                headerRight: "",
                line2: HubUIStrings.FloatingCard.allClear,
                line3: "",
                action: { NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil) }
            )
            pages = [CardPage(id: "page_empty", kind: .other, items: [it])]
        }

        return pages
    }

    private func floatingNotificationSummaryLine(
        subline: String,
        nextStep: String?,
        fallbackBody: String
    ) -> String {
        let trimmedSubline = subline.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSubline.isEmpty {
            return trimmedSubline
        }

        let trimmedNextStep = (nextStep ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNextStep.isEmpty {
            return trimmedNextStep
        }

        return fallbackBody
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func itemBox(_ item: CardItem) -> some View {
        // Use a subtle tinted background so different pages are visually distinguishable
        // (Meeting/Radar/Mail/Slack etc.) while keeping the overall widget-like material.
        // Slightly stronger tint so the page type reads at a glance.
        let bgA: Double = (item.kind == .empty) ? 0.06 : 0.22
        let borderA: Double = (item.kind == .empty) ? 0.12 : 0.40
        let tintBg = item.tint.opacity(bgA)
        return Button {
            item.action()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                if item.kind == .empty {
                    Spacer(minLength: 0)
                    Text(item.line2)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                } else {
                    HStack(spacing: 8) {
                        Text(item.headerLeft)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(item.tint)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.headerRight)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(item.tint)
                            .lineLimit(1)
                    }
                    Text(item.line2)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    if !item.line3.isEmpty {
                        Text(item.line3)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tintBg, tintBg.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(item.tint.opacity(borderA), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: 56)
    }

    var body: some View {
        let _ = seconds // force periodic re-render
        let now = Date().timeIntervalSince1970
        let pages = cardPages(now: now)
        let pagesKey = pages.map { $0.id }.joined(separator: "|")

        let step = max(0, seconds / 6)
        let safeIdx = pages.isEmpty ? 0 : (step % pages.count)
        let page = pages[safeIdx]

        // Show special day only when there are no non-meeting pages (no unread counts, no radars, etc.).
        let showSpecialDay = !specialDayText.isEmpty && pages.allSatisfy { $0.kind == .meeting }

        return VStack(alignment: .leading, spacing: 8) {
                // Header row: weekday + lunar, right side month+day (same size)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(weekday)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(weekdayColor)
                    if !lunarText.isEmpty {
                        Text(lunarText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer()
                    Text(monthDayText)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
                .frame(height: 24, alignment: .top)

                if (showSpecialDay || (page.items.count == 1 && page.items[0].kind == .empty)) && !specialDayText.isEmpty {
                    Text(specialDayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    if page.items.count == 1 {
                        Spacer(minLength: 0)
                        itemBox(page.items[0])
                        Spacer(minLength: 0)
                    } else {
                        ForEach(page.items.prefix(2)) { it in
                            itemBox(it)
                        }
                    }
                }
            }
            .padding(10)
            .frame(width: FloatingMode.card.panelSize.width, height: FloatingMode.card.panelSize.height)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Tap any empty area of the card to open the main app.
            // Item boxes are Buttons and should win the gesture competition.
            .onTapGesture {
                NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
            }
            // Only the header opens the main window; item boxes stay fully clickable.
            .overlay(alignment: .top) {
                Color.clear
                    .frame(height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .relflowhubOpenMain, object: nil)
                    }
            }
            .onAppear {
                if ticker == nil {
                    let t = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
                    t.schedule(deadline: .now() + 1.0, repeating: 1.0)
                    t.setEventHandler {
                        seconds &+= 1
                    }
                    t.resume()
                    ticker = t
                }
            }
            .onDisappear {
                ticker?.cancel()
                ticker = nil
            }
            // When the page set changes (meetings appear/disappear, radars updated), restart at the first page.
            .onChange(of: pagesKey) { _ in
                seconds = 0
            }
    }
}
