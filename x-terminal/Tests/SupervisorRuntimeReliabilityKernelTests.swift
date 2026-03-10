import Foundation
import Combine
import Testing
@testable import XTerminal

@MainActor
struct SupervisorRuntimeReliabilityKernelTests {

    @Test
    func parentForkOverflowBlocksLaneAndEmitsContextOverflow() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Overflow Guard",
            taskDescription: "runtime guard test",
            modelName: "claude-sonnet-4.6"
        )
        var task = DecomposedTask(
            description: "Run high-context skill lane",
            type: .development,
            complexity: .moderate,
            estimatedEffort: 600,
            priority: 6
        )
        task.metadata["lane_id"] = "lane-overflow"
        task.metadata["parent_fork_tokens"] = "4096"
        task.metadata["parent_fork_max_tokens"] = "1024"
        task.metadata["parent_fork_started_at_ms"] = "1000"

        await monitor.startMonitoring(task, in: project)

        let lane = try #require(monitor.laneStates["lane-overflow"])
        #expect(lane.status == .blocked)
        #expect(lane.blockedReason == .contextOverflow)

        let snapshot = monitor.runtimeReliabilitySnapshot(
            now: Date(timeIntervalSince1970: 1_730_000_060)
        )
        #expect(snapshot.parentForkOverflowBlocked == 1)
        #expect(snapshot.parentForkOverflowSilentFail == 0)
    }

    @Test
    func crossChannelFallbackIsHardBlocked() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Fallback Guard",
            taskDescription: "fallback guard test",
            modelName: "claude-sonnet-4.6"
        )
        var task = DecomposedTask(
            description: "Run skill lane with invalid cross-channel fallback",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 900,
            priority: 8
        )
        task.metadata["lane_id"] = "lane-fallback-blocked"
        task.metadata["route_origin_channel"] = "grpc"
        task.metadata["route_fallback_channel"] = "file"

        await monitor.startMonitoring(task, in: project)

        let lane = try #require(monitor.laneStates["lane-fallback-blocked"])
        #expect(lane.status == .blocked)
        #expect(lane.blockedReason == .routeOriginUnavailable)

        let snapshot = monitor.runtimeReliabilitySnapshot(
            now: Date(timeIntervalSince1970: 1_730_000_061)
        )
        #expect(snapshot.routeOriginFallbackViolations == 1)
        #expect(snapshot.routeFallbackCrossChannelBlocked == 1)
    }

    @Test
    func sameChannelFallbackRemainsRunnable() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Fallback Allow",
            taskDescription: "same-channel fallback test",
            modelName: "claude-sonnet-4.6"
        )
        var task = DecomposedTask(
            description: "Run skill lane with same-channel fallback",
            type: .development,
            complexity: .moderate,
            estimatedEffort: 600,
            priority: 5
        )
        task.metadata["lane_id"] = "lane-fallback-allowed"
        task.metadata["route_origin_channel"] = "grpc"
        task.metadata["route_fallback_channel"] = "grpc"

        await monitor.startMonitoring(task, in: project)

        let lane = try #require(monitor.laneStates["lane-fallback-allowed"])
        #expect(lane.status == .running)
        #expect(lane.blockedReason == nil)

        let snapshot = monitor.runtimeReliabilitySnapshot(
            now: Date(timeIntervalSince1970: 1_730_000_062)
        )
        #expect(snapshot.routeFallbackSameChannelAllowed == 1)
        #expect(snapshot.routeOriginFallbackViolations == 0)
    }

    @Test
    func cancelPathAlwaysRunsCleanupAndConvergesTerminal() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Cleanup Cancel",
            taskDescription: "cancel cleanup test",
            modelName: "claude-sonnet-4.6"
        )
        let task = DecomposedTask(
            description: "Run cancellable skill lane",
            type: .development,
            complexity: .simple,
            estimatedEffort: 600,
            priority: 4,
            metadata: ["lane_id": "lane-cancel"]
        )

        await monitor.startMonitoring(task, in: project)
        await monitor.updateState(task.id, status: .cancelled, note: "user_cancelled")

        let snapshot = monitor.runtimeReliabilitySnapshot(
            now: Date(timeIntervalSince1970: 1_730_000_063)
        )
        #expect(snapshot.cleanupCancelCount == 1)
        #expect(snapshot.dispatchIdleStuckIncidents == 0)

        let cleanup = try #require(snapshot.cleanupLedger.first(where: { $0.laneID == "lane-cancel" }))
        #expect(cleanup.outcome == .cancel)
        #expect(cleanup.dispatchIdleCleanupExecuted)
        #expect(cleanup.typingCleanupExecuted)
        #expect(monitor.taskStates[task.id] == nil)
    }

    @Test
    func failedPathInfersRouteOriginUnavailableAndRunsCleanup() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Cleanup Fail",
            taskDescription: "failed cleanup test",
            modelName: "claude-sonnet-4.6"
        )
        let task = DecomposedTask(
            description: "Run failing skill lane",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 600,
            priority: 7,
            metadata: ["lane_id": "lane-fail"]
        )

        await monitor.startMonitoring(task, in: project)
        await monitor.updateState(task.id, status: .failed, note: "cross_channel_blocked by origin-safe fallback")

        let lane = try #require(monitor.laneStates["lane-fail"])
        #expect(lane.status == .failed)
        #expect(lane.blockedReason == .routeOriginUnavailable)

        let snapshot = monitor.runtimeReliabilitySnapshot(
            now: Date(timeIntervalSince1970: 1_730_000_064)
        )
        #expect(snapshot.cleanupFailCount == 1)
    }

    @Test
    func completionAdapterEmitsMachineEventAndExportsKpis() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "Completion Adapter",
            taskDescription: "completion machine event export test",
            modelName: "claude-sonnet-4.6"
        )
        let task = DecomposedTask(
            description: "Emit completion machine event",
            type: .development,
            complexity: .simple,
            estimatedEffort: 60,
            priority: 3,
            metadata: ["lane_id": "lane-completion-adapter"]
        )

        var capturedEvents: [SupervisorLaneCompletionDetectedEvent] = []
        var cancellables = Set<AnyCancellable>()
        AXEventBus.shared.eventPublisher
            .sink { event in
                guard case .supervisorLaneCompletionDetected(let payload) = event else { return }
                capturedEvents.append(payload)
            }
            .store(in: &cancellables)

        await monitor.startMonitoring(task, in: project)
        await monitor.updateState(task.id, status: .completed, note: "completion_probe")

        #expect(capturedEvents.count == 1)
        let completionEvent = try #require(capturedEvents.first)
        #expect(completionEvent.eventType == "supervisor.lane.completion.detected_machine_event")
        #expect(completionEvent.laneID == "lane-completion-adapter")
        #expect(completionEvent.completionSource == "task_status")
        #expect(completionEvent.confidence == 1.0)

        let snapshot = monitor.completionAdapterSnapshot()
        #expect(snapshot.eventType == "supervisor.lane.completion.detected_machine_event")
        #expect(snapshot.completionDetectLatencyP95Ms >= 0)
        #expect(snapshot.duplicateCompletionActions == 0)
        #expect(snapshot.emittedEventsCount == 1)

        let exported = monitor.exportLaneCompletionDetectedMachineEvents()
        #expect(exported.count == 1)
    }
}
