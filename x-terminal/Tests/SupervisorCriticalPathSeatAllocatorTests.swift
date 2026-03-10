import Foundation
import Testing
@testable import XTerminal

struct SupervisorCriticalPathSeatAllocatorTests {

    @Test
    func criticalPathSeatAllocatorPreemptsNonCriticalLaneAndRecoversOverflow() {
        let allocator = CriticalPathSeatAllocator(maxActiveSeats: 3)
        let result = allocator.allocate(lanes: makeDynamicSeatSampleLanes())

        #expect(result.activeLaneCountViolations == 0)
        #expect(result.activeOverflowRecovered)
        #expect(result.releaseBlockerProtected)
        #expect(result.criticalPathPreemptSuccessRate >= 0.98)
        #expect(result.queueStarvationIncidents == 0)
        #expect(result.seatAfter["lane-release"] == .active)
        #expect(result.seatAfter["lane-critical"] == .active)
        #expect(result.seatAfter["lane-idle"] == .standby)
        #expect(result.downgradedNonCriticalLaneIDs.contains("lane-bg"))
    }

    @Test
    func allocatorAutoReleasesSeatAfterTwoZeroDeltaWindows() throws {
        let allocator = CriticalPathSeatAllocator(maxActiveSeats: 3)
        let result = allocator.allocate(lanes: makeDynamicSeatSampleLanes())

        #expect(result.autoReleasedLaneIDs.contains("lane-idle"))
        let idleAudit = try #require(result.audits.first(where: { $0.laneID == "lane-idle" }))
        #expect(idleAudit.seatBefore == .active)
        #expect(idleAudit.seatAfter == .standby)
        #expect(idleAudit.preemptReason == "two_windows_no_increment_auto_release")
    }

    @Test
    func lowPriorityLaneCannotPreemptReleaseBlocker() throws {
        let allocator = CriticalPathSeatAllocator(maxActiveSeats: 3)
        let result = allocator.allocate(lanes: makeReleaseProtectionSampleLanes())

        #expect(result.releaseBlockerProtected)
        #expect(result.seatAfter["lane-release"] == .active)
        #expect(result.seatAfter["lane-low"] == .standby)
        let releaseAudit = try #require(result.audits.first(where: { $0.laneID == "lane-low" }))
        #expect(releaseAudit.preemptReason == "downgraded_non_critical_for_critical_path")
    }

    @Test
    func allocatorFlagsStarvationWhenCriticalDemandExceedsSeats() {
        let allocator = CriticalPathSeatAllocator(maxActiveSeats: 3)
        let result = allocator.allocate(lanes: makeStarvationSampleLanes())

        #expect(result.activeLaneCountViolations == 0)
        #expect(result.queueStarvationIncidents == 1)
        #expect(result.releaseBlockerProtected)
    }

    @Test
    func seatAllocatorCaptureEmitsMachineReadableAudit() throws {
        let allocator = CriticalPathSeatAllocator(maxActiveSeats: 3)
        let dynamic = allocator.allocate(lanes: makeDynamicSeatSampleLanes())
        let protection = allocator.allocate(lanes: makeReleaseProtectionSampleLanes())

        #expect(dynamic.activeLaneCountViolations == 0)
        #expect(dynamic.criticalPathPreemptSuccessRate >= 0.98)
        #expect(dynamic.queueStarvationIncidents == 0)
        #expect(dynamic.releaseBlockerProtected)
        #expect(protection.releaseBlockerProtected)

        if ProcessInfo.processInfo.environment["XT_W2_25_B_CAPTURE"] == "1" {
            let payload = SeatAllocatorRuntimeCapture(
                schemaVersion: "xterminal.xt_w2_25_b.active3_dynamic_seat_capture.v1",
                sampleWindow: "xt_w2_25_b_g3_g4_first_probe_v1",
                activeLaneCountViolations: dynamic.activeLaneCountViolations,
                criticalPathPreemptSuccessRate: dynamic.criticalPathPreemptSuccessRate,
                queueStarvationIncidents: dynamic.queueStarvationIncidents,
                releaseBlockerProtected: dynamic.releaseBlockerProtected,
                activeOverflowRecovered: dynamic.activeOverflowRecovered,
                downgradedNonCriticalLaneIDs: dynamic.downgradedNonCriticalLaneIDs,
                autoReleasedLaneIDs: dynamic.autoReleasedLaneIDs,
                seatAudits: dynamic.audits,
                seatBefore: dynamic.seatBefore,
                seatAfter: dynamic.seatAfter,
                protectionSeatAfter: protection.seatAfter,
                sourceRefs: [
                    "x-terminal/Sources/Supervisor/CriticalPathSeatAllocator.swift",
                    "x-terminal/Tests/SupervisorCriticalPathSeatAllocatorTests.swift"
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let json = try String(decoding: encoder.encode(payload), as: UTF8.self)
            print("XT_W2_25_B_CAPTURE_JSON=\(json)")
        }
    }

    private func makeDynamicSeatSampleLanes() -> [CriticalPathLaneSnapshot] {
        [
            lane(
                laneID: "lane-release",
                taskID: "XT-W2-25-B-release",
                seatState: .active,
                criticalPathRank: 1,
                blockRiskScore: 0.99,
                requiresActiveSeat: true,
                isReleaseBlocker: true,
                priorityLabel: "P0",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-critical",
                taskID: "XT-W2-25-B-critical",
                seatState: .standby,
                criticalPathRank: 2,
                blockRiskScore: 0.97,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P0",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-steady",
                taskID: "XT-W2-25-B-steady",
                seatState: .active,
                criticalPathRank: 3,
                blockRiskScore: 0.92,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P0",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-idle",
                taskID: "XT-W2-25-B-idle",
                seatState: .active,
                criticalPathRank: 9,
                blockRiskScore: 0.21,
                requiresActiveSeat: false,
                isReleaseBlocker: false,
                priorityLabel: "P2",
                status: .running,
                progressWindows: [0, 0]
            ),
            lane(
                laneID: "lane-bg",
                taskID: "XT-W2-25-B-bg",
                seatState: .active,
                criticalPathRank: 8,
                blockRiskScore: 0.33,
                requiresActiveSeat: false,
                isReleaseBlocker: false,
                priorityLabel: "P2",
                status: .waiting,
                progressWindows: [0, 1]
            )
        ]
    }

    private func makeReleaseProtectionSampleLanes() -> [CriticalPathLaneSnapshot] {
        [
            lane(
                laneID: "lane-release",
                taskID: "XT-W2-25-B-release",
                seatState: .active,
                criticalPathRank: 1,
                blockRiskScore: 0.99,
                requiresActiveSeat: true,
                isReleaseBlocker: true,
                priorityLabel: "P0",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-support-a",
                taskID: "XT-W2-25-B-support-a",
                seatState: .active,
                criticalPathRank: 2,
                blockRiskScore: 0.70,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P1",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-support-b",
                taskID: "XT-W2-25-B-support-b",
                seatState: .active,
                criticalPathRank: 3,
                blockRiskScore: 0.68,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P1",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-low",
                taskID: "XT-W2-25-B-low",
                seatState: .active,
                criticalPathRank: 9,
                blockRiskScore: 0.10,
                requiresActiveSeat: false,
                isReleaseBlocker: false,
                priorityLabel: "P2",
                status: .running,
                progressWindows: [0, 1]
            )
        ]
    }

    private func makeStarvationSampleLanes() -> [CriticalPathLaneSnapshot] {
        [
            lane(
                laneID: "lane-release",
                taskID: "XT-W2-25-B-release",
                seatState: .active,
                criticalPathRank: 1,
                blockRiskScore: 0.99,
                requiresActiveSeat: true,
                isReleaseBlocker: true,
                priorityLabel: "P0",
                status: .running,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-c1",
                taskID: "XT-W2-25-B-c1",
                seatState: .standby,
                criticalPathRank: 2,
                blockRiskScore: 0.95,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P0",
                status: .blocked,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-c2",
                taskID: "XT-W2-25-B-c2",
                seatState: .standby,
                criticalPathRank: 3,
                blockRiskScore: 0.93,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P0",
                status: .blocked,
                progressWindows: [1, 1]
            ),
            lane(
                laneID: "lane-c3",
                taskID: "XT-W2-25-B-c3",
                seatState: .standby,
                criticalPathRank: 4,
                blockRiskScore: 0.92,
                requiresActiveSeat: true,
                isReleaseBlocker: false,
                priorityLabel: "P0",
                status: .blocked,
                progressWindows: [1, 1]
            )
        ]
    }

    private func lane(
        laneID: String,
        taskID: String,
        seatState: SeatState,
        criticalPathRank: Int,
        blockRiskScore: Double,
        requiresActiveSeat: Bool,
        isReleaseBlocker: Bool,
        priorityLabel: String,
        status: LaneHealthStatus,
        progressWindows: [Int]
    ) -> CriticalPathLaneSnapshot {
        CriticalPathLaneSnapshot(
            laneID: laneID,
            taskID: taskID,
            seatState: seatState,
            criticalPathRank: criticalPathRank,
            blockRiskScore: blockRiskScore,
            requiresActiveSeat: requiresActiveSeat,
            isReleaseBlocker: isReleaseBlocker,
            priorityLabel: priorityLabel,
            status: status,
            blockedReason: status == .blocked ? .queueStarvation : nil,
            progressWindows: progressWindows.enumerated().map { index, delta in
                SeatProgressWindow(windowID: "window-\(index + 1)", deltaCount: delta)
            }
        )
    }
}

private struct SeatAllocatorRuntimeCapture: Codable {
    let schemaVersion: String
    let sampleWindow: String
    let activeLaneCountViolations: Int
    let criticalPathPreemptSuccessRate: Double
    let queueStarvationIncidents: Int
    let releaseBlockerProtected: Bool
    let activeOverflowRecovered: Bool
    let downgradedNonCriticalLaneIDs: [String]
    let autoReleasedLaneIDs: [String]
    let seatAudits: [SeatAssignmentAudit]
    let seatBefore: [String: SeatState]
    let seatAfter: [String: SeatState]
    let protectionSeatAfter: [String: SeatState]
    let sourceRefs: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sampleWindow = "sample_window"
        case activeLaneCountViolations = "active_lane_count_violations"
        case criticalPathPreemptSuccessRate = "critical_path_preempt_success_rate"
        case queueStarvationIncidents = "queue_starvation_incidents"
        case releaseBlockerProtected = "release_blocker_protected"
        case activeOverflowRecovered = "active_overflow_recovered"
        case downgradedNonCriticalLaneIDs = "downgraded_non_critical_lane_ids"
        case autoReleasedLaneIDs = "auto_released_lane_ids"
        case seatAudits = "seat_audits"
        case seatBefore = "seat_before"
        case seatAfter = "seat_after"
        case protectionSeatAfter = "protection_seat_after"
        case sourceRefs = "source_refs"
    }
}
