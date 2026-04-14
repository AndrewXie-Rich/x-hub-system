import Foundation
import Testing
@testable import XTerminal

struct XTAutomationRunCheckpointStoreTests {
    @Test
    func checkpointStorePreservesRunIdentityAcrossRecoverableStates() {
        let store = XTAutomationRunCheckpointStore()

        _ = store.bootstrap(
            runID: "run-20260310-001",
            recipeID: "xt-auto-pr-review",
            initialState: .queued,
            auditRef: "audit-xt-auto-checkpoint-001"
        )
        _ = store.transition(to: .running, auditRef: "audit-xt-auto-checkpoint-002")
        _ = store.transition(to: .blocked, retryAfterSeconds: 90, auditRef: "audit-xt-auto-checkpoint-003")
        _ = store.transition(to: .takeover, auditRef: "audit-xt-auto-checkpoint-004")
        _ = store.transition(to: .downgraded, retryAfterSeconds: 30, auditRef: "audit-xt-auto-checkpoint-005")

        #expect(store.history.map(\.state) == [.queued, .running, .blocked, .takeover, .downgraded])
        #expect(store.history.allSatisfy { $0.runID == "run-20260310-001" && $0.stableIdentity })
        #expect(store.history[0].attempt == 1)
        #expect(store.history[1].attempt == 2)
        #expect(store.history[2].attempt == 2)
        #expect(store.latestRecoverableCheckpoint?.state == .downgraded)
        #expect(store.latestRecoverableCheckpoint?.retryAfterSeconds == 30)
    }

    @Test
    func restartRecoverySuppressesCancelledRunsAndBoundsRetryBudget() {
        let store = XTAutomationRunCheckpointStore(maxAttempts: 3)

        let blocked = store.bootstrap(
            runID: "run-20260310-002",
            recipeID: "xt-auto-pr-review",
            initialState: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-checkpoint-101"
        )
        store.markCancelled(auditRef: "audit-xt-auto-cancel-001")

        let cancelled = store.recoverAfterRestart(
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-001"
        )
        let retryExhausted = XTAutomationRunCheckpointStore.recoveryDecision(
            for: XTAutomationRunCheckpoint(
                schemaVersion: blocked.schemaVersion,
                runID: blocked.runID,
                recipeID: blocked.recipeID,
                state: blocked.state,
                attempt: 4,
                lastTransition: blocked.lastTransition,
                retryAfterSeconds: blocked.retryAfterSeconds,
                resumeToken: blocked.resumeToken,
                checkpointRef: blocked.checkpointRef,
                stableIdentity: blocked.stableIdentity,
                auditRef: blocked.auditRef
            ),
            wasCancelled: false,
            checkpointAgeSeconds: 60,
            maxAttempts: 3,
            auditRef: "audit-xt-auto-recover-002"
        )

        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")
        #expect(retryExhausted.decision == .hold)
        #expect(retryExhausted.holdReason == "retry_budget_exhausted")
    }

    @Test
    func restartRecoveryScavengesStaleRunsAndResumesFreshRecoverableCheckpoint() {
        let store = XTAutomationRunCheckpointStore()

        _ = store.bootstrap(
            runID: "run-20260310-003",
            recipeID: "xt-auto-pr-review",
            initialState: .blocked,
            retryAfterSeconds: 45,
            auditRef: "audit-xt-auto-checkpoint-201"
        )

        let pending = store.recoverAfterRestart(
            checkpointAgeSeconds: 30,
            auditRef: "audit-xt-auto-recover-100"
        )
        let fresh = store.recoverAfterRestart(
            checkpointAgeSeconds: 45,
            auditRef: "audit-xt-auto-recover-101"
        )
        let operatorOverride = store.recoverAfterRestart(
            checkpointAgeSeconds: 30,
            recoveryMode: .operatorOverride,
            auditRef: "audit-xt-auto-recover-101b"
        )
        let stale = store.recoverAfterRestart(
            checkpointAgeSeconds: 3_600,
            auditRef: "audit-xt-auto-recover-102"
        )

        #expect(pending.decision == .hold)
        #expect(pending.holdReason == "retry_after_not_elapsed")
        #expect(fresh.decision == .resume)
        #expect(fresh.recoveredState == .blocked)
        #expect(fresh.stableIdentityPass)
        #expect(operatorOverride.decision == .resume)
        #expect(stale.decision == .scavenged)
        #expect(stale.holdReason == "stale_run_scavenged")
    }

    @Test
    func restartRecoveryFailsClosedWhenStableIdentityDoesNotPass() {
        let checkpoint = XTAutomationRunCheckpoint(
            schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
            runID: "run-20260402-identity-drift",
            recipeID: "xt-auto-pr-review",
            state: .blocked,
            attempt: 2,
            lastTransition: "running_to_blocked",
            retryAfterSeconds: 0,
            resumeToken: "resume-run-20260402-identity-drift",
            checkpointRef: "checkpoint-identity-drift",
            stableIdentity: false,
            auditRef: "audit-xt-auto-checkpoint-identity-drift"
        )

        let automatic = XTAutomationRunCheckpointStore.recoveryDecision(
            for: checkpoint,
            wasCancelled: false,
            checkpointAgeSeconds: 30,
            recoveryMode: .automatic,
            auditRef: "audit-xt-auto-recover-identity-automatic"
        )
        let operatorOverride = XTAutomationRunCheckpointStore.recoveryDecision(
            for: checkpoint,
            wasCancelled: false,
            checkpointAgeSeconds: 30,
            recoveryMode: .operatorOverride,
            auditRef: "audit-xt-auto-recover-identity-override"
        )

        #expect(automatic.decision == .hold)
        #expect(automatic.holdReason == "stable_identity_failed")
        #expect(!automatic.stableIdentityPass)
        #expect(operatorOverride.decision == .hold)
        #expect(operatorOverride.holdReason == "stable_identity_failed")
        #expect(!operatorOverride.stableIdentityPass)
    }

    @Test
    func checkpointStoreCarriesStepContextAcrossRetryAndCompletionStates() {
        let store = XTAutomationRunCheckpointStore()

        _ = store.bootstrap(
            runID: "run-20260331-step-001",
            recipeID: "xt-auto-runtime",
            initialState: .queued,
            currentStepID: "step-1",
            currentStepTitle: "Run focused tests",
            auditRef: "audit-step-001"
        )
        let running = store.transition(
            to: .running,
            currentStepSummary: "Executing `swift test --filter Smoke`",
            auditRef: "audit-step-002"
        )
        let blocked = store.transition(
            to: .blocked,
            retryAfterSeconds: 45,
            auditRef: "audit-step-003"
        )
        let delivered = store.transition(
            to: .delivered,
            auditRef: "audit-step-004"
        )

        #expect(running.currentStepID == "step-1")
        #expect(running.currentStepTitle == "Run focused tests")
        #expect(running.currentStepState == .inProgress)
        #expect(running.currentStepSummary == "Executing `swift test --filter Smoke`")
        #expect(blocked.currentStepState == .retryWait)
        #expect(blocked.currentStepSummary == "Executing `swift test --filter Smoke`")
        #expect(delivered.currentStepState == .done)
        #expect(delivered.currentStepTitle == "Run focused tests")
    }
}
