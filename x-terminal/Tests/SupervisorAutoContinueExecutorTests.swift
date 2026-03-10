import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorAutoContinueExecutorTests {

    @Test
    func dependencyReadyResumesBlockedLane() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "AutoContinue Dependency",
            taskDescription: "dependency-driven resume",
            modelName: "claude-sonnet-4.6"
        )

        var upstream = DecomposedTask(
            description: "Upstream lane task",
            type: .development,
            complexity: .simple,
            estimatedEffort: 60,
            priority: 7
        )
        upstream.metadata["lane_id"] = "lane-upstream"

        var downstream = DecomposedTask(
            description: "Downstream lane task",
            type: .deployment,
            complexity: .moderate,
            estimatedEffort: 120,
            priority: 8
        )
        downstream.metadata["lane_id"] = "lane-downstream"
        downstream.metadata["depends_on"] = "lane-upstream"

        await monitor.startMonitoring(
            upstream,
            in: project,
            initialStatus: .running
        )
        await monitor.startMonitoring(
            downstream,
            in: project,
            initialStatus: .blocked,
            blockedReason: .dependencyBlocked
        )

        try await Task.sleep(nanoseconds: 1_200_000_000)
        let before = try #require(monitor.laneStates["lane-downstream"])
        #expect(before.status == .blocked)
        #expect(before.blockedReason == .dependencyBlocked)

        await monitor.updateState(upstream.id, status: .completed, note: "upstream_done")
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let after = try #require(monitor.laneStates["lane-downstream"])
        #expect(after.status == .running)
        #expect(after.blockedReason == nil)
    }

    @Test
    func grantPendingGatePreventsWrongAutoClaim() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "AutoContinue Gate",
            taskDescription: "gate-protected blocked wait",
            modelName: "claude-sonnet-4.6"
        )

        var upstream = DecomposedTask(
            description: "Upstream lane task",
            type: .development,
            complexity: .simple,
            estimatedEffort: 60,
            priority: 7
        )
        upstream.metadata["lane_id"] = "lane-gate-upstream"

        var downstream = DecomposedTask(
            description: "Downstream lane task",
            type: .deployment,
            complexity: .moderate,
            estimatedEffort: 120,
            priority: 9
        )
        downstream.metadata["lane_id"] = "lane-gate-downstream"
        downstream.metadata["depends_on"] = "lane-gate-upstream"
        downstream.metadata["blocked_reason"] = LaneBlockedReason.grantPending.rawValue

        await monitor.startMonitoring(
            upstream,
            in: project,
            initialStatus: .running
        )
        await monitor.startMonitoring(
            downstream,
            in: project,
            initialStatus: .blocked,
            blockedReason: .grantPending
        )

        await monitor.updateState(upstream.id, status: .completed, note: "upstream_done")
        try await Task.sleep(nanoseconds: 1_200_000_000)

        let lane = try #require(monitor.laneStates["lane-gate-downstream"])
        #expect(lane.status == .blocked)
        #expect(lane.blockedReason == .grantPending)

        let state = try #require(monitor.taskStates[downstream.id])
        #expect(state.currentStatus == .blocked)
        #expect(state.task.metadata["blocked_reason"] == LaneBlockedReason.grantPending.rawValue)
    }
}
