import Foundation

struct SupervisorSafePointExecutionState: Equatable, Sendable {
    var runStartedAtMs: Int64
    var flowStep: Int
    var toolResultsCount: Int
    var verifyRunIndex: Int
    var finalizeOnly: Bool

    init(
        runStartedAtMs: Int64,
        flowStep: Int,
        toolResultsCount: Int,
        verifyRunIndex: Int,
        finalizeOnly: Bool
    ) {
        self.runStartedAtMs = max(0, runStartedAtMs)
        self.flowStep = max(0, flowStep)
        self.toolResultsCount = max(0, toolResultsCount)
        self.verifyRunIndex = max(0, verifyRunIndex)
        self.finalizeOnly = finalizeOnly
    }

    var checkpointReached: Bool {
        finalizeOnly || verifyRunIndex > 0 || toolResultsCount >= 3 || flowStep > 2
    }
}

enum SupervisorSafePointCoordinator {
    static func deliverablePendingGuidance(
        for ctx: AXProjectContext,
        state: SupervisorSafePointExecutionState? = nil
    ) -> SupervisorGuidanceInjectionRecord? {
        guard let item = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx) else {
            return nil
        }
        guard let state else { return item }
        return isDeliverable(item, state: state) ? item : nil
    }

    static func shouldPauseToolBatchAfterBoundary(
        for ctx: AXProjectContext,
        state: SupervisorSafePointExecutionState
    ) -> SupervisorGuidanceInjectionRecord? {
        guard let item = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx) else {
            return nil
        }
        // Guidance that already existed before this run should already be visible in prompt memory.
        guard item.injectedAtMs > state.runStartedAtMs else { return nil }
        switch item.safePointPolicy {
        case .immediate, .nextToolBoundary:
            return state.toolResultsCount > 0 ? item : nil
        case .nextStepBoundary, .checkpointBoundary:
            return nil
        }
    }

    static func deliverablePendingAutomationGuidance(
        for ctx: AXProjectContext,
        runStartedAtMs: Int64,
        checkpointCount: Int
    ) -> SupervisorGuidanceInjectionRecord? {
        guard let item = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx) else {
            return nil
        }
        if item.injectedAtMs <= 0 || item.injectedAtMs <= runStartedAtMs {
            return item
        }
        guard checkpointCount >= 1 else { return nil }
        switch item.safePointPolicy {
        case .immediate, .nextToolBoundary, .nextStepBoundary, .checkpointBoundary:
            return item
        }
    }

    private static func isDeliverable(
        _ item: SupervisorGuidanceInjectionRecord,
        state: SupervisorSafePointExecutionState
    ) -> Bool {
        if item.injectedAtMs <= 0 || item.injectedAtMs <= state.runStartedAtMs {
            return true
        }
        switch item.safePointPolicy {
        case .immediate:
            return true
        case .nextToolBoundary:
            return state.toolResultsCount > 0
        case .nextStepBoundary:
            return state.flowStep > 1
        case .checkpointBoundary:
            return state.checkpointReached
        }
    }
}
