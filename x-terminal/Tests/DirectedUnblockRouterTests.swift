import Foundation
import Testing
@testable import XTerminal

struct DirectedUnblockRouterTests {

    @MainActor
    @Test
    func executionMonitorResumesOnlyDependencyBlockedLaneViaDirectedBaton() async throws {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "directed unblock",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )

        let blockerTask = makeTask(laneID: "XT-W3-26-E", metadata: ["task_id": "XT-W3-26-E"])
        let dependencyBlockedTask = makeTask(
            laneID: "XT-W3-26-F",
            metadata: [
                "task_id": "XT-W3-26-F",
                "depends_on": "XT-W3-26-E",
                "blocked_reason": LaneBlockedReason.dependencyBlocked.rawValue
            ]
        )
        let grantBlockedTask = makeTask(
            laneID: "XT-W3-26-G",
            metadata: [
                "task_id": "XT-W3-26-G",
                "depends_on": "XT-W3-26-E",
                "blocked_reason": LaneBlockedReason.grantPending.rawValue,
                "grant_required": "1"
            ]
        )

        await monitor.startMonitoring(
            dependencyBlockedTask,
            in: project,
            laneID: "XT-W3-26-F",
            initialStatus: .blocked,
            blockedReason: .dependencyBlocked
        )
        await monitor.startMonitoring(
            grantBlockedTask,
            in: project,
            laneID: "XT-W3-26-G",
            initialStatus: .blocked,
            blockedReason: .grantPending
        )
        await monitor.startMonitoring(
            blockerTask,
            in: project,
            laneID: "XT-W3-26-E",
            initialStatus: .running
        )

        await monitor.updateState(blockerTask.id, status: .completed, note: "grant_chain_ready")

        let baton = try #require(monitor.directedUnblockBatons.first)
        #expect(monitor.directedUnblockBatons.count == 1)
        #expect(baton.blockedLane == "XT-W3-26-F")
        #expect(baton.resumeScope == .continueCurrentTaskOnly)
        #expect(baton.mustNotDo.contains("scope_expand"))

        let resumedState = try #require(monitor.taskStates.values.first(where: {
            $0.task.metadata["lane_id"] == "XT-W3-26-F"
        }))
        #expect(resumedState.currentStatus == .inProgress)
        #expect(resumedState.task.metadata["last_unblock_baton_edge_id"] == baton.edgeID)

        let stillBlockedState = try #require(monitor.taskStates.values.first(where: {
            $0.task.metadata["lane_id"] == "XT-W3-26-G"
        }))
        #expect(stillBlockedState.currentStatus == .blocked)
        #expect(stillBlockedState.task.metadata["blocked_reason"] == LaneBlockedReason.grantPending.rawValue)
    }

    @MainActor
    @Test
    func directedUnblockEvidenceSnapshotRemainsDirectedOnly() async {
        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "directed snapshot",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )

        let blockerTask = makeTask(laneID: "XT-W3-26-E2")
        let waitingTask = makeTask(
            laneID: "XT-W3-26-F2",
            metadata: [
                "depends_on": "XT-W3-26-E2",
                "blocked_reason": LaneBlockedReason.dependencyBlocked.rawValue
            ]
        )

        await monitor.startMonitoring(
            waitingTask,
            in: project,
            laneID: "XT-W3-26-F2",
            initialStatus: .blocked,
            blockedReason: .dependencyBlocked
        )
        await monitor.startMonitoring(
            blockerTask,
            in: project,
            laneID: "XT-W3-26-E2",
            initialStatus: .running
        )

        await monitor.updateState(blockerTask.id, status: .completed, note: "dependency_resolved")

        let snapshot = monitor.directedUnblockEvidence(now: Date(timeIntervalSince1970: 1_773_000_500))
        #expect(snapshot.schemaVersion == "xt.w3_26.directed_unblock_evidence.v1")
        #expect(snapshot.directedOnly)
        #expect(snapshot.emittedBatonCount == 1)
        #expect(snapshot.blockedToDirectedResumeP95Ms <= 3000)
    }

    @MainActor
    @Test
    func xtW326FCaptureEmitsMachineReadableDirectedUnblockEvidence() async throws {
        guard ProcessInfo.processInfo.environment["XT_W3_26_F_CAPTURE"] == "1" else { return }

        let monitor = ExecutionMonitor()
        let project = ProjectModel(
            name: "XT-W3-26 Runtime",
            taskDescription: "capture directed unblock",
            modelName: "gpt-4.1",
            autonomyLevel: .auto
        )
        let blockerTask = makeTask(laneID: "XT-W3-26-E3")
        let waitingTask = makeTask(
            laneID: "XT-W3-26-F3",
            metadata: [
                "depends_on": "XT-W3-26-E3",
                "blocked_reason": LaneBlockedReason.dependencyBlocked.rawValue,
                "evidence_refs": "build/reports/xt_w3_26_d_run_state_machine_evidence.v1.json"
            ]
        )

        await monitor.startMonitoring(
            waitingTask,
            in: project,
            laneID: "XT-W3-26-F3",
            initialStatus: .blocked,
            blockedReason: .dependencyBlocked
        )
        await monitor.startMonitoring(
            blockerTask,
            in: project,
            laneID: "XT-W3-26-E3",
            initialStatus: .running
        )
        await monitor.updateState(blockerTask.id, status: .completed, note: "grant_chain_ready")

        let capture = XTW326FDirectedUnblockCapture(
            schemaVersion: "xt.w3_26.directed_unblock_capture.v1",
            snapshot: monitor.directedUnblockEvidence(now: Date(timeIntervalSince1970: 1_773_000_600)),
            sourceRefs: [
                "x-terminal/Sources/Supervisor/DirectedUnblockRouter.swift",
                "x-terminal/Sources/Supervisor/TaskDecomposition/ExecutionMonitor.swift",
                "x-terminal/Tests/DirectedUnblockRouterTests.swift"
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try String(decoding: encoder.encode(capture), as: UTF8.self)
        print("XT_W3_26_F_CAPTURE_JSON=\(json)")
    }

    private func makeTask(
        laneID: String,
        metadata: [String: String] = [:]
    ) -> DecomposedTask {
        DecomposedTask(
            description: laneID,
            type: .development,
            complexity: .moderate,
            estimatedEffort: 600,
            status: .ready,
            priority: 7,
            metadata: metadata.merging(["lane_id": laneID]) { _, new in new }
        )
    }
}

private struct XTW326FDirectedUnblockCapture: Codable {
    let schemaVersion: String
    let snapshot: DirectedUnblockEvidence
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case snapshot
        case sourceRefs = "source_refs"
    }
}
