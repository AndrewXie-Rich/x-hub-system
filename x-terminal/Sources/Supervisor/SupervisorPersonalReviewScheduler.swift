import Foundation

enum SupervisorPersonalReviewType: String, Codable, CaseIterable, Sendable {
    case morningBrief = "morning_brief"
    case eveningWrapUp = "evening_wrap_up"
    case weeklyReview = "weekly_review"

    var displayName: String {
        switch self {
        case .morningBrief:
            return "Morning Brief"
        case .eveningWrapUp:
            return "Evening Wrap-Up"
        case .weeklyReview:
            return "Weekly Review"
        }
    }

    var iconToken: String {
        switch self {
        case .morningBrief:
            return "sun.max.fill"
        case .eveningWrapUp:
            return "moon.stars.fill"
        case .weeklyReview:
            return "calendar.badge.clock"
        }
    }
}

struct SupervisorPersonalReviewCompletionState: Equatable, Codable, Sendable {
    static let currentSchemaVersion = "xt.supervisor_personal_review_completion.v1"

    var schemaVersion: String
    var lastCompletedAnchorByType: [String: String]

    static func `default`() -> SupervisorPersonalReviewCompletionState {
        SupervisorPersonalReviewCompletionState(
            schemaVersion: currentSchemaVersion,
            lastCompletedAnchorByType: [:]
        )
    }

    func normalized() -> SupervisorPersonalReviewCompletionState {
        SupervisorPersonalReviewCompletionState(
            schemaVersion: schemaVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? Self.currentSchemaVersion
                : schemaVersion,
            lastCompletedAnchorByType: lastCompletedAnchorByType
        )
    }

    func lastCompletedAnchor(for type: SupervisorPersonalReviewType) -> String? {
        normalized().lastCompletedAnchorByType[type.rawValue]
    }
}

struct SupervisorPersonalReviewDueItem: Equatable, Sendable {
    var type: SupervisorPersonalReviewType
    var scheduledAt: Date
    var overdue: Bool
}

enum SupervisorPersonalReviewScheduler {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func scheduleSummary(policy: SupervisorPersonalPolicy) -> String {
        let normalized = policy.normalized()
        return "morning \(normalized.preferredMorningBriefTime) · evening \(normalized.preferredEveningWrapUpTime) · weekly \(normalized.weeklyReviewDay) \(normalized.preferredEveningWrapUpTime)"
    }

    static func dueItems(
        now: Date,
        timeZone: TimeZone,
        policy: SupervisorPersonalPolicy,
        completionState: SupervisorPersonalReviewCompletionState = .default(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> [SupervisorPersonalReviewDueItem] {
        let normalizedPolicy = policy.normalized()
        let normalizedState = completionState.normalized()
        var resolvedCalendar = calendar
        resolvedCalendar.timeZone = timeZone

        var items: [SupervisorPersonalReviewDueItem] = []

        if let scheduledAt = scheduledDate(
            on: now,
            timeString: normalizedPolicy.preferredMorningBriefTime,
            calendar: resolvedCalendar
        ),
           now >= scheduledAt,
           normalizedState.lastCompletedAnchor(for: .morningBrief) != completionAnchor(
            for: .morningBrief,
            at: now,
            calendar: resolvedCalendar
           ) {
            items.append(
                SupervisorPersonalReviewDueItem(
                    type: .morningBrief,
                    scheduledAt: scheduledAt,
                    overdue: now.timeIntervalSince(scheduledAt) >= 60 * 60
                )
            )
        }

        if let scheduledAt = scheduledDate(
            on: now,
            timeString: normalizedPolicy.preferredEveningWrapUpTime,
            calendar: resolvedCalendar
        ),
           now >= scheduledAt,
           normalizedState.lastCompletedAnchor(for: .eveningWrapUp) != completionAnchor(
            for: .eveningWrapUp,
            at: now,
            calendar: resolvedCalendar
           ) {
            items.append(
                SupervisorPersonalReviewDueItem(
                    type: .eveningWrapUp,
                    scheduledAt: scheduledAt,
                    overdue: now.timeIntervalSince(scheduledAt) >= 60 * 60
                )
            )
        }

        if weekdayMatches(
            now: now,
            target: normalizedPolicy.weeklyReviewDay,
            calendar: resolvedCalendar
        ),
           let scheduledAt = scheduledDate(
            on: now,
           timeString: normalizedPolicy.preferredEveningWrapUpTime,
            calendar: resolvedCalendar
           ),
           now >= scheduledAt,
           normalizedState.lastCompletedAnchor(for: .weeklyReview) != completionAnchor(
            for: .weeklyReview,
            at: now,
            calendar: resolvedCalendar
           ) {
            items.append(
                SupervisorPersonalReviewDueItem(
                    type: .weeklyReview,
                    scheduledAt: scheduledAt,
                    overdue: now.timeIntervalSince(scheduledAt) >= 6 * 60 * 60
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.scheduledAt == rhs.scheduledAt {
                return lhs.type.rawValue < rhs.type.rawValue
            }
            return lhs.scheduledAt < rhs.scheduledAt
        }
    }

    static func completionAnchor(
        for type: SupervisorPersonalReviewType,
        at date: Date,
        timeZone: TimeZone? = nil,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> String {
        var resolvedCalendar = calendar
        if let timeZone {
            resolvedCalendar.timeZone = timeZone
        }
        switch type {
        case .morningBrief, .eveningWrapUp:
            return dayAnchor(for: date, calendar: resolvedCalendar)
        case .weeklyReview:
            return weekAnchor(for: date, calendar: resolvedCalendar)
        }
    }

    private static func scheduledDate(
        on date: Date,
        timeString: String,
        calendar: Calendar
    ) -> Date? {
        let trimmed = timeString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = timeFormatter.date(from: trimmed) else { return nil }
        let parsedComponents = calendar.dateComponents([.hour, .minute], from: parsed)
        var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        dateComponents.hour = parsedComponents.hour
        dateComponents.minute = parsedComponents.minute
        dateComponents.second = 0
        return calendar.date(from: dateComponents)
    }

    private static func dayAnchor(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func weekAnchor(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
    }

    private static func weekdayMatches(
        now: Date,
        target: String,
        calendar: Calendar
    ) -> Bool {
        guard let expectedWeekday = normalizedWeekday(target) else { return false }
        return calendar.component(.weekday, from: now) == expectedWeekday
    }

    private static func normalizedWeekday(_ raw: String) -> Int? {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "sunday", "sun", "星期日", "星期天", "周日", "周天":
            return 1
        case "monday", "mon", "星期一", "周一":
            return 2
        case "tuesday", "tue", "tues", "星期二", "周二":
            return 3
        case "wednesday", "wed", "星期三", "周三":
            return 4
        case "thursday", "thu", "thur", "thurs", "星期四", "周四":
            return 5
        case "friday", "fri", "星期五", "周五":
            return 6
        case "saturday", "sat", "星期六", "周六":
            return 7
        default:
            return nil
        }
    }
}
