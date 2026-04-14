import Foundation
import Testing
@testable import XTerminal

struct XTAutomationRunCoordinatorTests {
    private static let runtimeGate = HubGlobalStateTestGate.shared

    @Test
    func prepareActiveRunPersistsLaunchRefAndBootstrapCheckpoint() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let recipe = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_000))
        )
        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let rawLog = try rawLogEntries(for: ctx)

        #expect(prepared.recipeRef == recipe.ref)
        #expect(prepared.launchRef == reloaded.lastAutomationLaunchRef)
        #expect(prepared.verticalSlice.eventRunner.launchDecision.decision == .run)
        #expect(prepared.currentCheckpoint.runID == prepared.launchRef)
        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(prepared.currentCheckpoint.currentStepID == "collect_context")
        #expect(prepared.currentCheckpoint.currentStepTitle == "Collect context")
        #expect(prepared.currentCheckpoint.currentStepState == .pending)
        #expect(prepared.currentCheckpoint.currentStepSummary == "waiting_to_start_first_action")
        #expect(rawLog.contains {
            ($0["type"] as? String) == "automation_run_launch"
                && ($0["run_id"] as? String) == prepared.launchRef
                && ($0["external_trigger_ingress_schema_version"] as? String) == XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion
        })
        #expect(rawLog.contains {
            ($0["type"] as? String) == "automation_run_launch"
                && ($0["run_id"] as? String) == prepared.launchRef
                && ($0["delivery_ref"] as? String) == "build/reports/xt_w3_25_delivery_card.v1.json"
        })
        #expect(rawLog.contains { ($0["type"] as? String) == "automation_checkpoint" && ($0["run_id"] as? String) == prepared.launchRef })
        }
    }

    @Test
    func recoverLatestRunReplaysPersistedCheckpointAcrossCoordinatorInstances() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_100))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 90,
            currentStepID: "verify_smoke",
            currentStepTitle: "Verify smoke tests",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting before retrying the reduced verify set.",
            for: ctx,
            auditRef: "audit-xt-auto-blocked-001",
            now: Date(timeIntervalSince1970: 1_773_100_101)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .takeover,
            for: ctx,
            auditRef: "audit-xt-auto-takeover-001",
            now: Date(timeIntervalSince1970: 1_773_100_102)
        )

        let freshCoordinator = XTAutomationRunCoordinator()
        let latestRecovery = try freshCoordinator.recoverLatestRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-001"
        )
        let recovered = try #require(latestRecovery)

        #expect(recovered.decision == .resume)
        #expect(recovered.recoveredState == .takeover)
        #expect(recovered.runID == prepared.launchRef)
        #expect(recovered.stableIdentityPass)

        let latestCheckpoint = try freshCoordinator.latestCheckpoint(
            for: prepared.launchRef,
            in: ctx
        )
        #expect(latestCheckpoint.currentStepID == "verify_smoke")
        #expect(latestCheckpoint.currentStepTitle == "Verify smoke tests")
        #expect(latestCheckpoint.currentStepState == .blocked)
        #expect(latestCheckpoint.currentStepSummary == "Waiting before retrying the reduced verify set.")
        }
    }

    @Test
    func recoverLatestRunFallsBackToPersistedCheckpointWhenConfigLaunchRefDrifts() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_120))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-fallback-001",
            now: Date(timeIntervalSince1970: 1_773_100_121)
        )

        var drifted = try AXProjectStore.loadOrCreateConfig(for: ctx)
        drifted.lastAutomationLaunchRef = "run-missing-from-config"
        try AXProjectStore.saveConfig(drifted, for: ctx)

        let recovered = try #require(
            try XTAutomationRunCoordinator().recoverLatestRun(
                for: ctx,
                checkpointAgeSeconds: 0,
                auditRef: "audit-xt-auto-recover-config-drift"
            )
        )

        #expect(recovered.decision == .resume)
        #expect(recovered.runID == prepared.launchRef)
        #expect(recovered.recoveredState == .blocked)
        }
    }

    @Test
    func latestPersistedRunIDFallsBackToLatestAllowedStateWhenPreferredRunIsNoLongerMutable() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let deliveredRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_130))
        )
        _ = try coordinator.advanceRun(
            deliveredRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-preferred-stale",
            now: Date(timeIntervalSince1970: 1_773_100_131)
        )

        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_132))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-latest-allowed",
            now: Date(timeIntervalSince1970: 1_773_100_133)
        )

        let latestMutableRun = coordinator.latestPersistedRunID(
            for: ctx,
            preferredRunID: deliveredRun.launchRef,
            allowedStates: [.blocked, .takeover, .downgraded]
        )

        #expect(latestMutableRun == blockedRun.launchRef)
        }
    }

    @Test
    func latestPersistedRunIDDoesNotReuseOlderMutableRunWhenNewerVisibleRunIsDelivered() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_134))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-older-not-current",
            now: Date(timeIntervalSince1970: 1_773_100_135)
        )

        let deliveredRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_136))
        )
        _ = try coordinator.advanceRun(
            deliveredRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-newer-visible",
            now: Date(timeIntervalSince1970: 1_773_100_137)
        )

        let latestMutableRun = coordinator.latestPersistedRunID(
            for: ctx,
            preferredRunID: blockedRun.launchRef,
            allowedStates: [.queued, .running, .blocked, .takeover, .downgraded]
        )

        #expect(latestMutableRun == nil)
        }
    }

    @Test
    func latestPersistedRunIDIgnoresOlderPreferredRunWhenNewerPersistedRunExists() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let deliveredRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_135))
        )
        _ = try coordinator.advanceRun(
            deliveredRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-older-preferred",
            now: Date(timeIntervalSince1970: 1_773_100_136)
        )

        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_137))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-newer-visible",
            now: Date(timeIntervalSince1970: 1_773_100_138)
        )

        let latestVisibleRun = coordinator.latestPersistedRunID(
            for: ctx,
            preferredRunID: deliveredRun.launchRef
        )

        #expect(latestVisibleRun == blockedRun.launchRef)
        }
    }

    @Test
    func latestPersistedRunIDKeepsCancelledRunVisibleButExcludesItFromMutableSelection() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_140))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-cancelled-visible",
            now: Date(timeIntervalSince1970: 1_773_100_141)
        )
        try coordinator.cancelRun(
            prepared.launchRef,
            for: ctx,
            auditRef: "audit-xt-auto-cancelled-visible",
            now: Date(timeIntervalSince1970: 1_773_100_142)
        )

        let latestVisibleRun = coordinator.latestPersistedRunID(
            for: ctx,
            preferredRunID: prepared.launchRef
        )
        let latestMutableRun = coordinator.latestPersistedRunID(
            for: ctx,
            preferredRunID: prepared.launchRef,
            allowedStates: [.queued, .running, .blocked, .takeover, .downgraded],
            excludeCancelled: true
        )

        #expect(latestVisibleRun == prepared.launchRef)
        #expect(latestMutableRun == nil)
        }
    }

    @Test
    func recoverLatestRunIgnoresOlderConfigLaunchRefWhenNewerPersistedRunExists() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let deliveredRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_150))
        )
        _ = try coordinator.advanceRun(
            deliveredRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-recover-config-stale",
            now: Date(timeIntervalSince1970: 1_773_100_151)
        )

        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_152))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-recover-latest",
            now: Date(timeIntervalSince1970: 1_773_100_153)
        )

        var drifted = try AXProjectStore.loadOrCreateConfig(for: ctx)
        drifted.lastAutomationLaunchRef = deliveredRun.launchRef
        try AXProjectStore.saveConfig(drifted, for: ctx)

        let recovered = try #require(
            try XTAutomationRunCoordinator().recoverLatestRun(
                for: ctx,
                checkpointAgeSeconds: 0,
                auditRef: "audit-xt-auto-recover-valid-but-stale-config"
            )
        )

        #expect(recovered.runID == blockedRun.launchRef)
        #expect(recovered.decision == .resume)
        #expect(recovered.recoveredState == .blocked)
        }
    }

    @Test
    func recoverLatestRunPrefersOlderUnsupersededBlockedRunOverNewerUnrelatedDeliveredRun() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_154))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-older-unsuperseded",
            now: Date(timeIntervalSince1970: 1_773_100_155)
        )

        let deliveredRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_156))
        )
        _ = try coordinator.advanceRun(
            deliveredRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-newer-unrelated-for-recover-latest",
            now: Date(timeIntervalSince1970: 1_773_100_157)
        )

        let recovered = try #require(
            try coordinator.recoverLatestRun(
                for: ctx,
                now: 1_773_100_158,
                recoveryMode: .automatic,
                auditRef: "audit-xt-auto-recover-older-unsuperseded-latest"
            )
        )

        #expect(recovered.runID == blockedRun.launchRef)
        #expect(recovered.decision == .resume)
        #expect(recovered.recoveredState == .blocked)
        }
    }

    @Test
    func recoverLatestRunDoesNotReviveSupersededBlockedRunWhenNewerSameLineageRunExists() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let sourceRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_159))
        )
        _ = try coordinator.advanceRun(
            sourceRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-source-superseded",
            now: Date(timeIntervalSince1970: 1_773_100_160)
        )

        let retryChildRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(
                now: Date(timeIntervalSince1970: 1_773_100_161),
                lineage: sourceRun.lineage.retryChild(parentRunID: sourceRun.launchRef)
            )
        )
        _ = try coordinator.advanceRun(
            retryChildRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-retry-child-supersedes-source",
            now: Date(timeIntervalSince1970: 1_773_100_162)
        )

        let recovered = try #require(
            try coordinator.recoverLatestRun(
                for: ctx,
                now: 1_773_100_163,
                recoveryMode: .operatorOverride,
                auditRef: "audit-xt-auto-recover-do-not-revive-superseded"
            )
        )

        #expect(recovered.runID == retryChildRun.launchRef)
        #expect(recovered.decision == .hold)
        #expect(recovered.holdReason == "run_already_delivered")
        #expect(recovered.recoveredState == .delivered)
        }
    }

    @Test
    func latestRecoveryCandidateReportsSupersededRecoverableRunWhenFallbackSelectsLatestVisibleCheckpoint() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let sourceRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_164))
        )
        _ = try coordinator.advanceRun(
            sourceRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-source-candidate-superseded",
            now: Date(timeIntervalSince1970: 1_773_100_165)
        )

        let retryChildRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(
                now: Date(timeIntervalSince1970: 1_773_100_166),
                lineage: sourceRun.lineage.retryChild(parentRunID: sourceRun.launchRef)
            )
        )
        _ = try coordinator.advanceRun(
            retryChildRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-retry-child-candidate-fallback",
            now: Date(timeIntervalSince1970: 1_773_100_167)
        )

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_177
            )
        )

        #expect(candidate.runID == retryChildRun.launchRef)
        #expect(candidate.state == .delivered)
        #expect(candidate.selection == .latestVisibleCheckpoint)
        #expect(candidate.reason == .noRecoverableUnsupersededRun)
        #expect(candidate.latestVisibleRunID == retryChildRun.launchRef)
        #expect(candidate.latestVisibleState == .delivered)
        #expect(candidate.supersededRunID == sourceRun.launchRef)
        #expect(candidate.supersededByRunID == retryChildRun.launchRef)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "run_already_delivered")
        }
    }

    @Test
    func latestRecoveryCandidateDoesNotReportUnrelatedSupersededRunWhenFallbackSelectsDifferentLatestVisibleCheckpoint() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let sourceRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_168))
        )
        _ = try coordinator.advanceRun(
            sourceRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-source-unrelated-fallback",
            now: Date(timeIntervalSince1970: 1_773_100_169)
        )

        let retryChildRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(
                now: Date(timeIntervalSince1970: 1_773_100_170),
                lineage: sourceRun.lineage.retryChild(parentRunID: sourceRun.launchRef)
            )
        )
        _ = try coordinator.advanceRun(
            retryChildRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-retry-child-unrelated-fallback",
            now: Date(timeIntervalSince1970: 1_773_100_171)
        )

        let unrelatedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_172))
        )
        _ = try coordinator.advanceRun(
            unrelatedRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-unrelated-latest-visible",
            now: Date(timeIntervalSince1970: 1_773_100_173)
        )

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_177
            )
        )

        #expect(candidate.runID == unrelatedRun.launchRef)
        #expect(candidate.state == .delivered)
        #expect(candidate.selection == .latestVisibleCheckpoint)
        #expect(candidate.reason == .noRecoverableUnsupersededRun)
        #expect(candidate.latestVisibleRunID == unrelatedRun.launchRef)
        #expect(candidate.latestVisibleState == .delivered)
        #expect(candidate.supersededRunID == nil)
        #expect(candidate.supersededByRunID == nil)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "run_already_delivered")
        }
    }

    @Test
    func latestRecoveryCandidatePrefersLatestVisibleQueuedRunOverOlderUnrelatedRecoverableRun() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let blockedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_174))
        )
        _ = try coordinator.advanceRun(
            blockedRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 0,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-source-active-visible",
            now: Date(timeIntervalSince1970: 1_773_100_175)
        )

        let queuedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_176))
        )

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_177
            )
        )

        #expect(candidate.runID == queuedRun.launchRef)
        #expect(candidate.state == .queued)
        #expect(candidate.selection == .latestVisibleCheckpoint)
        #expect(candidate.reason == .latestVisibleActiveRun)
        #expect(candidate.latestVisibleRunID == queuedRun.launchRef)
        #expect(candidate.latestVisibleState == .queued)
        #expect(candidate.supersededRunID == nil)
        #expect(candidate.supersededByRunID == nil)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "state_not_restartable")
        }
    }

    @Test
    func latestRecoveryCandidateProjectsAutomaticBackoffHoldAndRemainingSeconds() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_190))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: ctx,
            auditRef: "audit-xt-auto-candidate-backoff-blocked",
            now: Date(timeIntervalSince1970: 1_773_100_191)
        )

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_251
            )
        )

        #expect(candidate.runID == prepared.launchRef)
        #expect(candidate.state == .blocked)
        #expect(candidate.selection == .latestRecoverableUnsuperseded)
        #expect(candidate.reason == .latestVisibleRetryWait)
        #expect(candidate.checkpointAgeSeconds == 60)
        #expect(candidate.retryAfterSeconds == 120)
        #expect(candidate.retryAfterRemainingSeconds == 60)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "retry_after_not_elapsed")
        }
    }

    @Test
    func latestRecoveryCandidateProjectsRetryBudgetExhaustedReasonWhenAttemptsExceeded() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_195))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-budget-running-1",
            now: Date(timeIntervalSince1970: 1_773_100_196)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-budget-blocked-1",
            now: Date(timeIntervalSince1970: 1_773_100_197)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-budget-running-2",
            now: Date(timeIntervalSince1970: 1_773_100_198)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-budget-blocked-2",
            now: Date(timeIntervalSince1970: 1_773_100_199)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-budget-running-3",
            now: Date(timeIntervalSince1970: 1_773_100_200)
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-budget-blocked-3",
            now: Date(timeIntervalSince1970: 1_773_100_201)
        )

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_202
            )
        )

        #expect(candidate.runID == prepared.launchRef)
        #expect(candidate.state == .blocked)
        #expect(candidate.reason == .latestVisibleRetryBudgetExhausted)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "retry_budget_exhausted")
        }
    }

    @Test
    func latestRecoveryCandidateKeepsLatestVisibleStableIdentityFailureOverOlderRecoverableRun() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let olderStableLineage = XTAutomationRunLineage.root(runID: "run-stable-older")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_100_198,
                "run_id": "run-stable-older",
                "delivery_ref": "build/reports/xt_auto_stable_delivery.v1.json",
                "lineage_id": olderStableLineage.lineageID,
                "root_run_id": olderStableLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": olderStableLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_100_199,
                "run_id": "run-stable-older",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-stable-older",
                "checkpoint_ref": "checkpoint-run-stable-older",
                "stable_identity": true,
                "audit_ref": "audit-run-stable-older-checkpoint"
            ],
            for: ctx
        )
        let latestLineage = XTAutomationRunLineage.root(runID: "run-identity-drift")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_100_200,
                "run_id": "run-identity-drift",
                "delivery_ref": "build/reports/xt_auto_identity_drift_delivery.v1.json",
                "lineage_id": latestLineage.lineageID,
                "root_run_id": latestLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": latestLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_100_201,
                "run_id": "run-identity-drift",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-identity-drift",
                "checkpoint_ref": "checkpoint-run-identity-drift",
                "stable_identity": false,
                "audit_ref": "audit-run-identity-drift-checkpoint"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = "run-identity-drift"
        try AXProjectStore.saveConfig(config, for: ctx)

        let candidate = try #require(
            try XTAutomationRunCoordinator().latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_205
            )
        )

        #expect(candidate.runID == "run-identity-drift")
        #expect(candidate.selection == .latestVisibleCheckpoint)
        #expect(candidate.reason == .latestVisibleStableIdentityFailed)
        #expect(candidate.automaticDecision == .hold)
        #expect(candidate.automaticHoldReason == "stable_identity_failed")
        }
    }

    @Test
    func latestRecoveryCandidateProjectsRetryPackageResumeModeWhenHandoffArtifactIsAvailable() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_205))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            for: ctx,
            auditRef: "audit-xt-auto-candidate-retry-package-blocked",
            now: Date(timeIntervalSince1970: 1_773_100_206)
        )

        let handoff = XTAutomationRunHandoffArtifact(
            schemaVersion: XTAutomationRunHandoffArtifact.currentSchemaVersion,
            generatedAt: 1_773_100_207,
            runID: prepared.launchRef,
            lineage: prepared.lineage,
            recipeRef: prepared.recipeRef,
            finalState: .blocked,
            holdReason: "automation_verify_failed",
            detail: "SmokeTests failed",
            actionResults: [
                XTAutomationActionExecutionOutcome(
                    actionID: "collect_context",
                    title: "Collect context",
                    tool: .project_snapshot,
                    ok: true,
                    denyCode: "",
                    detail: "root=/tmp/project",
                    expectationMet: true,
                    continuedAfterFailure: false
                )
            ],
            verificationReport: XTAutomationVerificationReport(
                required: true,
                executed: true,
                commandCount: 1,
                passedCommandCount: 0,
                holdReason: "automation_verify_failed",
                detail: "SmokeTests failed",
                commandResults: [
                    XTAutomationVerificationCommandOutcome(
                        commandID: "verify-1",
                        command: "swift test --filter SmokeTests",
                        ok: false,
                        detail: "exit: 1"
                    )
                ]
            ),
            workspaceDiffReport: XTAutomationWorkspaceDiffReport(
                attempted: true,
                captured: true,
                fileCount: 1,
                diffChars: 5,
                detail: "diff_captured:1_files",
                excerpt: "+hello"
            ),
            suggestedNextActions: ["rerun_focused_verification"]
        )
        let handoffURL = root.appendingPathComponent(
            xtAutomationHandoffArtifactRelativePath(for: prepared.launchRef)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try SupervisorStoreWriteSupport.writeSnapshotData(encoder.encode(handoff), to: handoffURL)

        let candidate = try #require(
            try coordinator.latestRecoveryCandidate(
                for: ctx,
                now: 1_773_100_265
            )
        )

        #expect(candidate.runID == prepared.launchRef)
        #expect(candidate.automaticDecision == .resume)
        #expect(candidate.automaticResumeMode == .retryPackage)
        #expect(candidate.automaticRetryStrategy == "verify_failed_retry")
        #expect(candidate.automaticRetryReason == "automation_verify_failed")
        #expect(candidate.automaticRetryPlanningMode == "verify_only_retry")
        #expect(
            candidate.automaticRetrySourceHandoffArtifactPath
                == xtAutomationHandoffArtifactRelativePath(for: prepared.launchRef)
        )
        }
    }

    @Test
    func automaticRecoveryHoldsBlockedRunUntilRetryAfterElapses() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_150))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-backoff-001",
            now: Date(timeIntervalSince1970: 1_773_100_151)
        )

        let restartedCoordinator = XTAutomationRunCoordinator()
        let recoveredAutomatic = try restartedCoordinator.recoverLatestRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-backoff-automatic"
        )
        let automatic = try #require(
            recoveredAutomatic
        )
        let recoveredOperatorOverride = try restartedCoordinator.recoverLatestRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            recoveryMode: .operatorOverride,
            auditRef: "audit-xt-auto-recover-backoff-override"
        )
        let operatorOverride = try #require(
            recoveredOperatorOverride
        )

        #expect(automatic.decision == .hold)
        #expect(automatic.holdReason == "retry_after_not_elapsed")
        #expect(operatorOverride.decision == .resume)
        #expect(operatorOverride.runID == prepared.launchRef)
        }
    }

    @Test
    func recoveryFailsClosedForCancelledAndStaleRuns() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_200))
        )
        _ = try coordinator.advanceRun(
            prepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-002",
            now: Date(timeIntervalSince1970: 1_773_100_201)
        )

        try coordinator.cancelRun(
            prepared.launchRef,
            for: ctx,
            auditRef: "audit-xt-auto-cancel-001",
            now: Date(timeIntervalSince1970: 1_773_100_202)
        )
        let cancelled = try coordinator.recoverRun(
            prepared.launchRef,
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-recover-cancelled"
        )

        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")

        let staleRoot = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: staleRoot) }

        let staleCtx = AXProjectContext(root: staleRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: staleCtx)

        let staleCoordinator = XTAutomationRunCoordinator()
        let stalePrepared = try staleCoordinator.prepareActiveRun(
            for: staleCtx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_300))
        )
        _ = try staleCoordinator.advanceRun(
            stalePrepared.launchRef,
            to: .blocked,
            retryAfterSeconds: 120,
            for: staleCtx,
            auditRef: "audit-xt-auto-blocked-stale",
            now: Date(timeIntervalSince1970: 1_773_100_301)
        )
        let stale = try staleCoordinator.recoverRun(
            stalePrepared.launchRef,
            for: staleCtx,
            checkpointAgeSeconds: 3_600,
            auditRef: "audit-xt-auto-recover-stale"
        )

        #expect(stale.decision == .scavenged)
        #expect(stale.holdReason == "stale_run_scavenged")
        }
    }

    @Test
    func recoverLatestRunFailsClosedWhenPersistedCheckpointStableIdentityIsFalse() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let lineage = XTAutomationRunLineage.root(runID: "run-identity-drift")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_100_250,
                "run_id": "run-identity-drift",
                "delivery_ref": "build/reports/xt_auto_identity_drift_delivery.v1.json",
                "lineage_id": lineage.lineageID,
                "root_run_id": lineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": lineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_100_251,
                "run_id": "run-identity-drift",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-identity-drift",
                "checkpoint_ref": "checkpoint-run-identity-drift",
                "stable_identity": false,
                "current_step_id": "step-verify",
                "current_step_title": "Verify smoke tests",
                "current_step_state": XTAutomationRunStepState.blocked.rawValue,
                "current_step_summary": "Persisted recovery detected identity drift.",
                "audit_ref": "audit-run-identity-drift-checkpoint"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = "run-identity-drift"
        try AXProjectStore.saveConfig(config, for: ctx)

        let recovered = try #require(
            try XTAutomationRunCoordinator().recoverLatestRun(
                for: ctx,
                checkpointAgeSeconds: 0,
                auditRef: "audit-xt-auto-recover-identity-drift"
            )
        )

        #expect(recovered.runID == "run-identity-drift")
        #expect(recovered.decision == .hold)
        #expect(recovered.holdReason == "stable_identity_failed")
        #expect(!recovered.stableIdentityPass)
        }
    }

    @Test
    func recoverRunNowUsesSpecificRunCheckpointAgeInsteadOfNewestProjectCheckpoint() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let coordinator = XTAutomationRunCoordinator()
        let olderRecoverableRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_400))
        )
        _ = try coordinator.advanceRun(
            olderRecoverableRun.launchRef,
            to: .blocked,
            retryAfterSeconds: 20,
            for: ctx,
            auditRef: "audit-xt-auto-blocked-older-specific-age",
            now: Date(timeIntervalSince1970: 1_773_100_401)
        )

        let newerUnrelatedRun = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_418))
        )
        _ = try coordinator.advanceRun(
            newerUnrelatedRun.launchRef,
            to: .delivered,
            for: ctx,
            auditRef: "audit-xt-auto-delivered-newer-unrelated",
            now: Date(timeIntervalSince1970: 1_773_100_419)
        )

        let recovered = try coordinator.recoverRun(
            olderRecoverableRun.launchRef,
            for: ctx,
            now: 1_773_100_426,
            recoveryMode: .automatic,
            auditRef: "audit-xt-auto-recover-specific-age"
        )

        #expect(recovered.runID == olderRecoverableRun.launchRef)
        #expect(recovered.decision == .resume)
        #expect(recovered.recoveredState == .blocked)
        }
    }

    @Test
    func prepareRunFailsClosedWithoutActiveReadyRecipe() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        let coordinator = XTAutomationRunCoordinator()

        do {
            _ = try coordinator.prepareActiveRun(
                for: ctx,
                request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_400))
            )
            Issue.record("Expected activeRecipeMissing error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .activeRecipeMissing)
        }
        }
    }

    @Test
    func prepareRunFailsClosedWhenNonManualTriggerIsNotDeclaredByRecipe() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "webhook/rogue",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/rogue",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:rogue"
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_450)
        )

        do {
            _ = try coordinator.prepareActiveRun(for: ctx, request: request)
            Issue.record("Expected triggerIngressNotAllowed error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .triggerIngressNotAllowed("webhook/rogue"))
        }
        }
    }

    @Test
    func prepareRunFailsClosedWhenNonManualReplayDedupeCollides() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let duplicateKey = "sha256:duplicate-webhook"
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-001",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: duplicateKey
                ),
                XTAutomationTriggerSeed(
                    triggerID: "webhook/github_pr",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/20260310-002",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: duplicateKey
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_460)
        )

        do {
            _ = try coordinator.prepareActiveRun(for: ctx, request: request)
            Issue.record("Expected triggerIngressReplayDetected error")
        } catch let error as XTAutomationRunCoordinatorError {
            #expect(error == .triggerIngressReplayDetected(duplicateKey))
        }
        }
    }

    @Test
    func prepareRunAllowsManualTriggerOutsideRecipeAllowlist() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()
        let request = XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/recover",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://supervisor/recover/project-a",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "manual|project-a|recover"
                )
            ],
            now: Date(timeIntervalSince1970: 1_773_100_470)
        )

        let prepared = try coordinator.prepareActiveRun(for: ctx, request: request)
        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(prepared.verticalSlice.eventRunner.launchDecision.decision == .run)
        }
    }

    @Test
    func advanceRunHoldsAtSafePointWhenPendingGuidanceExists() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_500))
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-automation-safe-point-1",
                reviewId: "review-automation-safe-point-1",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "在 automation checkpoint 先暂停，重新评估。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_100_500_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-automation-safe-point-1"
            ),
            for: ctx
        )

        let checkpoint = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-001",
            now: Date(timeIntervalSince1970: 1_773_100_501)
        )
        let rawLog = try rawLogEntries(for: ctx)

        #expect(checkpoint.state == .blocked)
        #expect(rawLog.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-automation-safe-point-1"
        })
        }
    }

    @Test
    func automationSafePointHoldDoesNotLoopForeverForSameGuidance() async throws {
        try await Self.runtimeGate.run {
        let root = try makeProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let coordinator = XTAutomationRunCoordinator()

        let prepared = try coordinator.prepareActiveRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_100_600))
        )
        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-automation-safe-point-2",
                reviewId: "review-automation-safe-point-2",
                projectId: AXProjectRegistryStore.projectId(forRoot: ctx.root),
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .nextStepBoundary,
                guidanceText: "下一 automation step 再切换方向。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_100_600_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-automation-safe-point-2"
            ),
            for: ctx
        )

        let first = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-002a",
            now: Date(timeIntervalSince1970: 1_773_100_601)
        )
        let second = try coordinator.advanceRun(
            prepared.launchRef,
            to: .running,
            for: ctx,
            auditRef: "audit-xt-auto-safe-point-hold-002b",
            now: Date(timeIntervalSince1970: 1_773_100_602)
        )
        let rawLog = try rawLogEntries(for: ctx)
        let holdCount = rawLog.filter {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["injection_id"] as? String) == "guidance-automation-safe-point-2"
        }.count

        #expect(first.state == .blocked)
        #expect(second.state == .running)
        #expect(holdCount == 1)
        }
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-automation-run-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-pr-review",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "nightly triage + code review + summary delivery",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly",
                "xt.automation_trigger_envelope.v1:webhook/github_pr"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l2,
            laneStrategy: .adaptive,
            requiredToolGroups: ["group:full", "group:device_automation"],
            actionGraph: [
                XTAutomationRecipeAction(
                    actionID: "collect_context",
                    title: "Collect context",
                    tool: .project_snapshot
                )
            ],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_100_000_000,
            lastEditAuditRef: "audit-xt-auto-bind-001",
            lastLaunchRef: ""
        )
    }

    private func makeRequest(
        now: Date,
        lineage: XTAutomationRunLineage? = nil
    ) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-001",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:schedule-nightly-20260310"
                ),
                XTAutomationTriggerSeed(
                    triggerID: "webhook/github_pr",
                    triggerType: .webhook,
                    source: .github,
                    payloadRef: "local://trigger-payload/20260310-002",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:webhook-github-pr-20260310"
                )
            ],
            lineage: lineage,
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx", "XT-Wy"],
            additionalEvidenceRefs: [
                "build/reports/xt_w3_25_hub_dependency_readiness.v1.json"
            ],
            now: now
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        let data = try Data(contentsOf: ctx.rawLogURL)
        let text = try #require(String(data: data, encoding: .utf8))
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                    return nil
                }
                return object
            }
    }
}
