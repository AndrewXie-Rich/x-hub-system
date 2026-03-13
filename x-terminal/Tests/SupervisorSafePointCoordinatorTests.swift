import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorSafePointCoordinatorTests {

    @Test
    func preExistingCheckpointGuidanceIsVisibleImmediately() throws {
        let root = try makeProjectRoot(named: "safe-point-preexisting")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-preexisting-1",
                reviewId: "review-preexisting-1",
                projectId: "proj-preexisting-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "在 checkpoint 再重规划。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 100,
                ackUpdatedAtMs: 0,
                auditRef: "audit-preexisting-1"
            ),
            for: ctx
        )

        let state = SupervisorSafePointExecutionState(
            runStartedAtMs: 200,
            flowStep: 1,
            toolResultsCount: 0,
            verifyRunIndex: 0,
            finalizeOnly: false
        )
        let visible = SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: state)
        #expect(visible?.injectionId == "guidance-preexisting-1")
    }

    @Test
    func nextStepBoundaryGuidanceWaitsUntilSecondPlanningStep() throws {
        let root = try makeProjectRoot(named: "safe-point-next-step")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-next-step-1",
                reviewId: "review-next-step-1",
                projectId: "proj-next-step-1",
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一步边界再重排。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 200,
                ackUpdatedAtMs: 0,
                auditRef: "audit-next-step-1"
            ),
            for: ctx
        )

        let firstStep = SupervisorSafePointExecutionState(
            runStartedAtMs: 100,
            flowStep: 1,
            toolResultsCount: 0,
            verifyRunIndex: 0,
            finalizeOnly: false
        )
        let secondStep = SupervisorSafePointExecutionState(
            runStartedAtMs: 100,
            flowStep: 2,
            toolResultsCount: 0,
            verifyRunIndex: 0,
            finalizeOnly: false
        )

        #expect(SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: firstStep) == nil)
        #expect(SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: secondStep)?.injectionId == "guidance-next-step-1")
    }

    @Test
    func checkpointBoundaryGuidanceWaitsForCheckpoint() throws {
        let root = try makeProjectRoot(named: "safe-point-checkpoint")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-checkpoint-1",
                reviewId: "review-checkpoint-1",
                projectId: "proj-checkpoint-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "到 checkpoint 再插入。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 200,
                ackUpdatedAtMs: 0,
                auditRef: "audit-checkpoint-1"
            ),
            for: ctx
        )

        let beforeCheckpoint = SupervisorSafePointExecutionState(
            runStartedAtMs: 100,
            flowStep: 2,
            toolResultsCount: 2,
            verifyRunIndex: 0,
            finalizeOnly: false
        )
        let checkpoint = SupervisorSafePointExecutionState(
            runStartedAtMs: 100,
            flowStep: 2,
            toolResultsCount: 3,
            verifyRunIndex: 0,
            finalizeOnly: false
        )

        #expect(SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: beforeCheckpoint) == nil)
        #expect(SupervisorSafePointCoordinator.deliverablePendingGuidance(for: ctx, state: checkpoint)?.injectionId == "guidance-checkpoint-1")
    }

    @Test
    func nextToolBoundaryGuidancePausesRemainingBatchAfterBoundary() throws {
        let root = try makeProjectRoot(named: "safe-point-next-tool")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-next-tool-1",
                reviewId: "review-next-tool-1",
                projectId: "proj-next-tool-1",
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextToolBoundary,
                guidanceText: "当前工具边界后先暂停。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 200,
                ackUpdatedAtMs: 0,
                auditRef: "audit-next-tool-1"
            ),
            for: ctx
        )

        let state = SupervisorSafePointExecutionState(
            runStartedAtMs: 100,
            flowStep: 1,
            toolResultsCount: 1,
            verifyRunIndex: 0,
            finalizeOnly: false
        )
        let pause = SupervisorSafePointCoordinator.shouldPauseToolBatchAfterBoundary(for: ctx, state: state)
        #expect(pause?.injectionId == "guidance-next-tool-1")
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
