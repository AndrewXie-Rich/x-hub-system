import XCTest
@testable import RELFlowHubCore

final class ModelHealthAutoScanScheduleTests: XCTestCase {
    func testDisabledScheduleHasNoDueDate() {
        let schedule = ModelHealthAutoScanSchedule(mode: .disabled, configuredAt: 100)
        XCTAssertNil(schedule.nextDueAt(lastCheckedAt: nil, now: 200))
    }

    func testIntervalScheduleStartsCountingFromConfigurationTime() {
        let schedule = ModelHealthAutoScanSchedule(
            mode: .interval,
            intervalHours: 24,
            configuredAt: 1_000
        )

        XCTAssertEqual(schedule.nextDueAt(lastCheckedAt: nil, now: 1_100), 1_000 + 24 * 3600)
    }

    func testIntervalScheduleMovesForwardAfterRecentScan() {
        let schedule = ModelHealthAutoScanSchedule(
            mode: .interval,
            intervalHours: 12,
            configuredAt: 1_000
        )

        XCTAssertEqual(
            schedule.nextDueAt(lastCheckedAt: 5_000, now: 6_000),
            5_000 + 12 * 3600
        )
    }

    func testDailyTimeScheduleWaitsForNextMatchingTimeSlot() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 22,
            minute: 30
        ))!.timeIntervalSince1970
        let schedule = ModelHealthAutoScanSchedule(
            mode: .dailyTime,
            dailyMinuteOfDay: 9 * 60,
            configuredAt: now
        )

        let expected = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 9,
            hour: 9,
            minute: 0
        ))!.timeIntervalSince1970

        XCTAssertEqual(schedule.nextDueAt(lastCheckedAt: nil, now: now), expected)
    }

    func testDailyTimeScheduleBecomesDueAtConfiguredMoment() {
        let calendar = Calendar(identifier: .gregorian)
        let configuredAt = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 8,
            minute: 0
        ))!.timeIntervalSince1970
        let dueAt = calendar.date(from: DateComponents(
            year: 2026,
            month: 4,
            day: 8,
            hour: 9,
            minute: 0
        ))!.timeIntervalSince1970
        let schedule = ModelHealthAutoScanSchedule(
            mode: .dailyTime,
            dailyMinuteOfDay: 9 * 60,
            configuredAt: configuredAt
        )

        XCTAssertTrue(schedule.isDue(lastCheckedAt: nil, now: dueAt))
    }

    func testMinuteOfDayParsingAndFormattingRoundTrips() {
        XCTAssertEqual(ModelHealthAutoScanSchedule.minuteOfDay(from: "06:45"), 405)
        XCTAssertEqual(ModelHealthAutoScanSchedule.timeText(from: 405), "06:45")
    }
}
