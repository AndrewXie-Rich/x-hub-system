import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorIncidentArbiterTests {

    @Test
    func failedLaneWithoutTaskStateStillEmitsRuntimeIncident() {
        let taskID = UUID()
        let projectID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-runtime",
            taskId: taskID,
            projectId: projectID,
            agentProfile: "trusted_high",
            status: .failed,
            blockedReason: .runtimeError,
            nextActionRecommendation: "pause_lane"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 300)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-runtime": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_000)
        )

        #expect(decisions.count == 1)
        let decision = decisions[0]
        #expect(decision.taskID == taskID)
        #expect(decision.action == .pauseLane)
        #expect(decision.incident.incidentCode == LaneBlockedReason.runtimeError.rawValue)
        #expect(decision.incident.projectID == projectID)
    }

    @Test
    func grantPendingWithoutTaskStateFallsBackToNotifyUser() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-grant",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "notify_user"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 300)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-grant": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_001)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].action == .notifyUser)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.grantPending.rawValue)
    }

    @Test
    func terminalLaneIncidentIsNotRepeatedAfterDedupeWindow() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-terminal",
            taskId: taskID,
            projectId: nil,
            agentProfile: "trusted_high",
            status: .failed,
            blockedReason: .runtimeError,
            nextActionRecommendation: "pause_lane"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let first = arbiter.evaluate(
            laneStates: ["lane-terminal": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_010)
        )
        let second = arbiter.evaluate(
            laneStates: ["lane-terminal": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_020)
        )

        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test
    func blockedPermissionIncidentIsNotRepeatedWhileReasonUnchanged() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-grant-sticky",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "notify_user"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 100)
        let first = arbiter.evaluate(
            laneStates: ["lane-grant-sticky": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_011)
        )
        let second = arbiter.evaluate(
            laneStates: ["lane-grant-sticky": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_021)
        )

        #expect(first.count == 1)
        #expect(second.isEmpty)
    }

    @Test
    func blockedPermissionIncidentEmitsAgainAfterRecoveryAndReblock() {
        let taskID = UUID()
        let blocked = LaneRuntimeState(
            laneID: "lane-grant-reenter",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "notify_user"
        )
        let running = LaneRuntimeState(
            laneID: "lane-grant-reenter",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .running,
            blockedReason: nil,
            nextActionRecommendation: "continue"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 100)
        let first = arbiter.evaluate(
            laneStates: ["lane-grant-reenter": blocked],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_031)
        )
        _ = arbiter.evaluate(
            laneStates: ["lane-grant-reenter": running],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_032)
        )
        let second = arbiter.evaluate(
            laneStates: ["lane-grant-reenter": blocked],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_033)
        )

        #expect(first.count == 1)
        #expect(second.count == 1)
    }

    @Test
    func failedLaneWithoutReasonDefaultsToRuntimeIncident() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-failed-unknown",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .failed,
            blockedReason: .unknown,
            nextActionRecommendation: "inspect"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-failed-unknown": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_030)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.runtimeError.rawValue)
        #expect(decisions[0].action == .pauseLane)
    }

    @Test
    func allocationBlockedFailureDoesNotEmitRuntimeIncident() {
        let taskID = UUID()
        var lane = LaneRuntimeState(
            laneID: "lane-allocation-blocked",
            taskId: taskID,
            projectId: nil,
            agentProfile: nil,
            status: .failed,
            blockedReason: .unknown,
            nextActionRecommendation: "replan"
        )
        lane.lastNote = "lane=lane-allocation-blocked, blocked=allocation_blocked, reason=risk_profile_mismatch"

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-allocation-blocked": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_040)
        )

        #expect(decisions.isEmpty)
    }

    @Test
    func contextOverflowBlockedLaneEmitsRuntimeIncidentAndReplan() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-context-overflow",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .blocked,
            blockedReason: .contextOverflow,
            nextActionRecommendation: "trim_context"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-context-overflow": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_050)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.contextOverflow.rawValue)
        #expect(decisions[0].action == .replan)
    }

    @Test
    func routeOriginUnavailableBlockedLaneEmitsReplanIncident() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-route-origin",
            taskId: taskID,
            projectId: nil,
            agentProfile: "balanced",
            status: .blocked,
            blockedReason: .routeOriginUnavailable,
            nextActionRecommendation: "fallback_same_origin"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-route-origin": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_051)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.routeOriginUnavailable.rawValue)
        #expect(decisions[0].action == .replan)
    }

    @Test
    func dispatchIdleTimeoutFailureEmitsPauseLaneCriticalIncident() {
        let taskID = UUID()
        let lane = LaneRuntimeState(
            laneID: "lane-cleanup-timeout",
            taskId: taskID,
            projectId: nil,
            agentProfile: "trusted_high",
            status: .failed,
            blockedReason: .dispatchIdleTimeout,
            nextActionRecommendation: "restart_dispatch"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 200)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-cleanup-timeout": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_052)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.dispatchIdleTimeout.rawValue)
        #expect(decisions[0].action == .pauseLane)
        #expect(decisions[0].incident.severity == .critical)
    }

    @Test
    func skillPreflightBlockedLaneMapsToAwaitingInstructionIncident() {
        let lane = LaneRuntimeState(
            laneID: "lane-skill-preflight",
            taskId: UUID(),
            projectId: UUID(),
            agentProfile: "balanced_general_skill_deployment",
            status: .blocked,
            blockedReason: .skillPreflightFailed,
            nextActionRecommendation: "notify_user"
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 300)
        let decisions = arbiter.evaluate(
            laneStates: ["lane-skill-preflight": lane],
            taskStates: [:],
            now: Date(timeIntervalSince1970: 1_730_000_053)
        )

        #expect(decisions.count == 1)
        #expect(decisions[0].incident.incidentCode == LaneBlockedReason.awaitingInstruction.rawValue)
        #expect(decisions[0].incident.denyCode == LaneBlockedReason.awaitingInstruction.rawValue)
        #expect(decisions[0].action == .notifyUser)
        #expect(decisions[0].incident.detail.contains("skill_preflight_failed"))
    }

    @Test
    func skillRuntimeErrorRetriesOnceThenPauses() {
        let taskID = UUID()
        let projectID = UUID()
        let blockedLane = LaneRuntimeState(
            laneID: "lane-skill-runtime",
            taskId: taskID,
            projectId: projectID,
            agentProfile: "trusted_high_skill_deployment",
            status: .blocked,
            blockedReason: .skillRuntimeError,
            nextActionRecommendation: "auto_retry"
        )
        let runningLane = LaneRuntimeState(
            laneID: "lane-skill-runtime",
            taskId: taskID,
            projectId: projectID,
            agentProfile: "trusted_high_skill_deployment",
            status: .running,
            blockedReason: nil,
            nextActionRecommendation: "continue"
        )

        var task = DecomposedTask(
            id: taskID,
            description: "Skill runtime failure",
            type: .deployment,
            complexity: .complex,
            estimatedEffort: 2_000,
            dependencies: [],
            status: .blocked,
            priority: 9
        )
        task.metadata["lane_id"] = "lane-skill-runtime"

        let firstState = TaskExecutionState(
            task: task,
            projectId: projectID,
            startedAt: Date(timeIntervalSince1970: 1_730_000_054),
            lastUpdateAt: Date(timeIntervalSince1970: 1_730_000_054),
            progress: 0.1,
            currentStatus: .blocked,
            attempts: 0,
            errors: [],
            logs: []
        )
        let secondState = TaskExecutionState(
            task: task,
            projectId: projectID,
            startedAt: Date(timeIntervalSince1970: 1_730_000_054),
            lastUpdateAt: Date(timeIntervalSince1970: 1_730_000_055),
            progress: 0.1,
            currentStatus: .blocked,
            attempts: 1,
            errors: [],
            logs: []
        )

        let arbiter = IncidentArbiter(dedupeWindowMs: 100)
        let first = arbiter.evaluate(
            laneStates: ["lane-skill-runtime": blockedLane],
            taskStates: [taskID: firstState],
            now: Date(timeIntervalSince1970: 1_730_000_056)
        )
        #expect(first.count == 1)
        #expect(first[0].incident.incidentCode == LaneBlockedReason.runtimeError.rawValue)
        #expect(first[0].action == .autoRetry)

        _ = arbiter.evaluate(
            laneStates: ["lane-skill-runtime": runningLane],
            taskStates: [taskID: secondState],
            now: Date(timeIntervalSince1970: 1_730_000_057)
        )
        let second = arbiter.evaluate(
            laneStates: ["lane-skill-runtime": blockedLane],
            taskStates: [taskID: secondState],
            now: Date(timeIntervalSince1970: 1_730_000_058)
        )
        #expect(second.count == 1)
        #expect(second[0].action == .pauseLane)
    }
}
