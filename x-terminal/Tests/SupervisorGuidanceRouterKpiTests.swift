import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorGuidanceRouterKpiTests {

    @Test
    func criticalNotifyLatencyP95WithinThreshold() {
        let notifyLatenciesMs: [Int64] = [900, 600, 1_100, 1_200, 1_000]
        let p95 = percentile95(notifyLatenciesMs)
        #expect(p95 <= 1_500)
    }

    @Test
    func notificationDedupHitRateWithinThreshold() {
        let laneID = "lane-guidance-router-dedupe"
        let taskID = UUID()

        let lane = LaneRuntimeState(
            laneID: laneID,
            taskId: taskID,
            projectId: UUID(),
            agentProfile: "trusted_high",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "notify_user"
        )

        var task = DecomposedTask(
            id: taskID,
            description: "Guidance router dedupe probe",
            type: .deployment,
            complexity: .moderate,
            estimatedEffort: 120,
            dependencies: [],
            status: .blocked,
            priority: 8
        )
        task.metadata["lane_id"] = laneID
        task.metadata["risk_tier"] = LaneRiskTier.high.rawValue

        let taskState = TaskExecutionState(
            task: task,
            projectId: lane.projectId ?? UUID(),
            startedAt: Date(timeIntervalSince1970: 1_730_120_000),
            lastUpdateAt: Date(timeIntervalSince1970: 1_730_120_000),
            progress: 0.1,
            currentStatus: .blocked,
            attempts: 0,
            errors: [],
            logs: []
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 5_000)
        let t0 = Date(timeIntervalSince1970: 1_730_120_010)
        let first = arbiter.evaluate(
            laneStates: [laneID: lane],
            taskStates: [taskID: taskState],
            now: t0
        )
        #expect(first.count == 1)
        #expect(first.first?.action == .notifyUser)

        let duplicateAttempts = 100
        var dedupeHits = 0
        for i in 0..<duplicateAttempts {
            let now = t0.addingTimeInterval(Double(i + 1) / 1_000.0)
            let decisions = arbiter.evaluate(
                laneStates: [laneID: lane],
                taskStates: [taskID: taskState],
                now: now
            )
            if decisions.isEmpty {
                dedupeHits += 1
            }
        }

        let dedupHitRate = (Double(dedupeHits) / Double(duplicateAttempts)) * 100.0
        #expect(dedupHitRate >= 95.0)
    }

    private func percentile95(_ samples: [Int64]) -> Int64 {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rawIndex = Int((Double(sorted.count - 1) * 0.95).rounded(.up))
        let index = max(0, min(sorted.count - 1, rawIndex))
        return sorted[index]
    }
}
