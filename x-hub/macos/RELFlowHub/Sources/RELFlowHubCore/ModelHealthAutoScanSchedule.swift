import Foundation

public enum ModelHealthAutoScanMode: String, Codable, CaseIterable, Sendable {
    case disabled
    case interval
    case dailyTime = "daily_time"
}

public struct ModelHealthAutoScanSchedule: Codable, Equatable, Sendable {
    public static let defaultIntervalHours: Int = 24
    public static let defaultDailyMinuteOfDay: Int = 9 * 60

    public var mode: ModelHealthAutoScanMode
    public var intervalHours: Int
    public var dailyMinuteOfDay: Int
    public var configuredAt: TimeInterval

    public init(
        mode: ModelHealthAutoScanMode = .disabled,
        intervalHours: Int = ModelHealthAutoScanSchedule.defaultIntervalHours,
        dailyMinuteOfDay: Int = ModelHealthAutoScanSchedule.defaultDailyMinuteOfDay,
        configuredAt: TimeInterval = 0
    ) {
        self.mode = mode
        self.intervalHours = intervalHours
        self.dailyMinuteOfDay = dailyMinuteOfDay
        self.configuredAt = configuredAt
    }

    public var isEnabled: Bool {
        mode != .disabled
    }

    public func normalized(now: TimeInterval = Date().timeIntervalSince1970) -> ModelHealthAutoScanSchedule {
        var copy = self
        copy.intervalHours = min(max(1, copy.intervalHours), 24 * 14)
        copy.dailyMinuteOfDay = min(max(0, copy.dailyMinuteOfDay), 23 * 60 + 59)
        if copy.mode != .disabled, copy.configuredAt <= 0 {
            copy.configuredAt = now
        }
        return copy
    }

    public func nextDueAt(
        lastCheckedAt: TimeInterval?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> TimeInterval? {
        let schedule = normalized(now: now)
        guard schedule.isEnabled else { return nil }

        let baseline = max(lastCheckedAt ?? 0, schedule.configuredAt)
        switch schedule.mode {
        case .disabled:
            return nil
        case .interval:
            let dueAt = baseline + Double(schedule.intervalHours) * 3600
            return max(now, dueAt)
        case .dailyTime:
            return nextDailyDueAt(after: max(now, baseline), minuteOfDay: schedule.dailyMinuteOfDay)
        }
    }

    public func isDue(
        lastCheckedAt: TimeInterval?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Bool {
        let schedule = normalized(now: now)
        guard schedule.isEnabled else { return false }

        let baseline = max(lastCheckedAt ?? 0, schedule.configuredAt)
        switch schedule.mode {
        case .disabled:
            return false
        case .interval:
            let dueAt = baseline + Double(schedule.intervalHours) * 3600
            return now >= dueAt
        case .dailyTime:
            let dueAt = nextDailyDueAt(after: baseline, minuteOfDay: schedule.dailyMinuteOfDay)
            return now + 1.0 >= dueAt
        }
    }

    public static func minuteOfDay(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    public static func timeText(from minuteOfDay: Int) -> String {
        let normalized = min(max(0, minuteOfDay), 23 * 60 + 59)
        let hour = normalized / 60
        let minute = normalized % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    private func nextDailyDueAt(after reference: TimeInterval, minuteOfDay: Int) -> TimeInterval {
        let calendar = Calendar.autoupdatingCurrent
        let referenceDate = Date(timeIntervalSince1970: max(0, reference))
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let sameDay = calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? referenceDate
        let nextDate: Date
        if sameDay > referenceDate {
            nextDate = sameDay
        } else {
            nextDate = calendar.date(byAdding: .day, value: 1, to: sameDay) ?? sameDay.addingTimeInterval(24 * 60 * 60)
        }
        return nextDate.timeIntervalSince1970
    }
}
