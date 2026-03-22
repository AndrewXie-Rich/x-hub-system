import Foundation
import Testing
@testable import XTerminal

struct SupervisorPersonalReviewSchedulerTests {

    @Test
    func scheduleSummaryReflectsNormalizedPolicy() {
        let policy = SupervisorPersonalPolicy(
            relationshipMode: .operatorPartner,
            briefingStyle: .balanced,
            riskTolerance: .balanced,
            interruptionTolerance: .balanced,
            reminderAggressiveness: .balanced,
            preferredMorningBriefTime: " 08:30 ",
            preferredEveningWrapUpTime: " 18:45 ",
            weeklyReviewDay: " Friday "
        )

        let summary = SupervisorPersonalReviewScheduler.scheduleSummary(policy: policy)

        #expect(summary == "morning 08:30 · evening 18:45 · weekly Friday 18:45")
    }

    @Test
    func dueItemsSurfaceMorningAndEveningReviewsAfterConfiguredTimes() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(isoDate("2026-03-16T19:10:00+08:00"))

        let dueItems = SupervisorPersonalReviewScheduler.dueItems(
            now: now,
            timeZone: timeZone,
            policy: SupervisorPersonalPolicy(
                relationshipMode: .operatorPartner,
                briefingStyle: .balanced,
                riskTolerance: .balanced,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .balanced,
                preferredMorningBriefTime: "08:30",
                preferredEveningWrapUpTime: "18:00",
                weeklyReviewDay: "Friday"
            ),
            completionState: .default(),
            calendar: calendar
        )

        #expect(dueItems.map(\.type) == [.morningBrief, .eveningWrapUp])
        #expect(dueItems[0].overdue)
        #expect(dueItems[1].overdue)
    }

    @Test
    func completedMorningReviewDoesNotReappearSameDay() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let calendar = Calendar(identifier: .gregorian)
        let now = try #require(isoDate("2026-03-16T10:00:00+08:00"))

        let dueItems = SupervisorPersonalReviewScheduler.dueItems(
            now: now,
            timeZone: timeZone,
            policy: .default(),
            completionState: SupervisorPersonalReviewCompletionState(
                schemaVersion: SupervisorPersonalReviewCompletionState.currentSchemaVersion,
                lastCompletedAnchorByType: [
                    SupervisorPersonalReviewType.morningBrief.rawValue: "2026-03-16"
                ]
            ),
            calendar: calendar
        )

        #expect(dueItems.map(\.type) == [])
    }

    @Test
    func weeklyReviewOnlyAppearsOnConfiguredDayAfterEveningTime() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let calendar = Calendar(identifier: .gregorian)
        let fridayEvening = try #require(isoDate("2026-03-20T19:30:00+08:00"))

        let dueItems = SupervisorPersonalReviewScheduler.dueItems(
            now: fridayEvening,
            timeZone: timeZone,
            policy: SupervisorPersonalPolicy(
                relationshipMode: .chiefOfStaff,
                briefingStyle: .proactive,
                riskTolerance: .balanced,
                interruptionTolerance: .balanced,
                reminderAggressiveness: .assertive,
                preferredMorningBriefTime: "08:30",
                preferredEveningWrapUpTime: "18:30",
                weeklyReviewDay: "Friday"
            ),
            completionState: SupervisorPersonalReviewCompletionState(
                schemaVersion: SupervisorPersonalReviewCompletionState.currentSchemaVersion,
                lastCompletedAnchorByType: [
                    SupervisorPersonalReviewType.morningBrief.rawValue: "2026-03-20",
                    SupervisorPersonalReviewType.eveningWrapUp.rawValue: "2026-03-20"
                ]
            ),
            calendar: calendar
        )

        #expect(dueItems.map(\.type) == [.weeklyReview])
        #expect(dueItems[0].overdue == false)
    }

    private func isoDate(_ raw: String) -> Date? {
        ISO8601DateFormatter().date(from: raw)
    }
}
