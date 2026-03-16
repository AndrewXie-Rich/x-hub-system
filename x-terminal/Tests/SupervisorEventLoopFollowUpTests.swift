import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorEventLoopFollowUpTests {
    actor Recorder {
        private var values: [String] = []

        func append(_ value: String) {
            values.append(value)
        }

        func snapshot() -> [String] {
            values
        }
    }

    @Test
    func queuedFollowUpsDrainInOrderWithoutDroppingEarlierTriggers() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            let marker = supervisorEventLoopLineValue("summary", in: userMessage)
            await recorder.append("\(triggerSource):\(marker)")
            try? await Task.sleep(nanoseconds: 20_000_000)
            return "handled \(marker)"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Alpha
project_id=project-alpha
summary=alpha
""",
            triggerSource: "skill_callback",
            dedupeKey: "event-loop-alpha"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Beta
project_id=project-beta
summary=beta
""",
            triggerSource: "incident",
            dedupeKey: "event-loop-beta"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Gamma
project_id=project-gamma
summary=gamma
""",
            triggerSource: "grant_resolution",
            dedupeKey: "event-loop-gamma"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await recorder.snapshot() == [
            "skill_callback:alpha",
            "incident:beta",
            "grant_resolution:gamma"
        ])

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter { $0.dedupeKey.hasPrefix("event-loop-") && $0.status != "deduped" }
        #expect(activities.count == 3)
        #expect(activities.map(\.status) == ["completed", "completed", "completed"])
        #expect(activities.map(\.triggerSummary) == ["alpha", "beta", "gamma"])
        #expect(activities.map(\.resultSummary) == ["handled alpha", "handled beta", "handled gamma"])
        #expect(manager.supervisorEventLoopStatusLine == "idle · recent activity")
    }

    @Test
    func duplicateDedupeKeyDoesNotReexecuteButLeavesAuditTrace() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )
        let recorder = Recorder()

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, _ in
            let marker = supervisorEventLoopLineValue("summary", in: userMessage)
            await recorder.append(marker)
            try? await Task.sleep(nanoseconds: 10_000_000)
            return "handled \(marker)"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Delta
project_id=project-delta
summary=delta
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-delta"
        )
        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Delta
project_id=project-delta
summary=delta duplicate
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-delta"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await recorder.snapshot() == ["delta"])

        let activities = manager.recentSupervisorEventLoopActivitiesForTesting()
            .filter { $0.dedupeKey == "event-loop-delta" }
        #expect(activities.count == 2)
        #expect(activities.contains(where: { $0.status == "completed" }))
        let deduped = activities.first(where: { $0.status == "deduped" })
        #expect(deduped?.reasonCode == "duplicate_trigger")
        #expect(deduped?.triggerSummary == "delta duplicate")
        #expect(deduped?.resultSummary.isEmpty == true)
    }

    @Test
    func queuedFollowUpCarriesPolicySummaryWhenGovernanceHintsArePresent() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            "handled policy-carry"
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Sigma
project_id=project-sigma
summary=sigma follow-up
review_trigger=blocker_detected
event_followup_rhythm=cadence=active · blocker cooldown≈180s
effective_supervisor_tier=s3_strategic_coach
effective_work_order_depth=execution_ready
project_ai_strength_band=capable
""",
            triggerSource: "heartbeat",
            dedupeKey: "event-loop-sigma"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-sigma" && $0.status == "completed" }) else {
            Issue.record("Expected a completed supervisor event-loop activity for event-loop-sigma.")
            return
        }

        #expect(activity.policySummary.contains("review=Blocker Detected"))
        #expect(activity.policySummary.contains("cadence=active"))
        #expect(activity.policySummary.contains("tier=S3 Strategic Coach"))
        #expect(activity.policySummary.contains("depth=Execution Ready"))
        #expect(activity.policySummary.contains("strength=Capable"))
        #expect(activity.triggerSummary == "blocker_detected · sigma follow-up")
        #expect(activity.resultSummary == "handled policy-carry")
    }

    @Test
    func completedFollowUpPreservesTriggerSummaryAndStoresResultSummarySeparately() async {
        let manager = SupervisorManager.makeForTesting(
            enableSupervisorEventLoopAutoFollowUp: true
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { _, _ in
            """
handled strategic reroute
queued next review
"""
        }

        manager.queueSupervisorEventLoopTurnForTesting(
            userMessage: """
project_ref=Project Omega
project_id=project-omega
summary=omega queue drift detected
""",
            triggerSource: "incident",
            dedupeKey: "event-loop-omega"
        )

        await manager.waitForSupervisorEventLoopForTesting()

        guard let activity = manager.recentSupervisorEventLoopActivitiesForTesting()
            .last(where: { $0.dedupeKey == "event-loop-omega" && $0.status == "completed" }) else {
            Issue.record("Expected a completed supervisor event-loop activity for event-loop-omega.")
            return
        }

        #expect(activity.triggerSummary == "omega queue drift detected")
        #expect(activity.resultSummary == "handled strategic reroute\nqueued next review")
    }
}

private func supervisorEventLoopLineValue(
    _ key: String,
    in text: String
) -> String {
    let needle = key + "="
    for rawLine in text.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix(needle) else { continue }
        return String(line.dropFirst(needle.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return ""
}
