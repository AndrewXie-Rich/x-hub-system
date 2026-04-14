import Foundation
import Testing
@testable import XTerminal

@Suite(.serialized)
@MainActor
struct SupervisorManagerAutomationRuntimeTests {
    private static let runtimeGate = HubGlobalStateTestGate.shared
    private static let gate = TrustedAutomationPermissionTestGate.shared

    actor ToolCallCounter {
        private var counts: [ToolName: Int] = [:]

        func increment(_ tool: ToolName) {
            counts[tool, default: 0] += 1
        }

        func count(for tool: ToolName) -> Int {
            counts[tool, default: 0]
        }
    }

    @Test
    func managerPrepareAdvanceAndRecoverAutomationRunUpdatesPublishedState() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_000))
        )
        #expect(manager.automationPreparedRun?.launchRef == prepared.launchRef)
        #expect(prepared.lineage.rootRunID == prepared.launchRef)
        #expect(prepared.lineage.parentRunID.isEmpty)
        #expect(prepared.lineage.retryDepth == 0)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationStatusLine.contains(prepared.launchRef))

        let blocked = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-manager-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_001)
        )
        #expect(blocked.state == .blocked)
        #expect(manager.automationCurrentCheckpoint?.state == .blocked)

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-xt-auto-manager-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationStatusLine.contains("resume"))
    }

    @Test
    func managerCancelAutomationRunMarksSuppressedRecovery() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_100))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 90,
            auditRef: "audit-xt-auto-manager-blocked-2",
            now: Date(timeIntervalSince1970: 1_773_200_101)
        )

        let cancelled = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-cancel",
            now: Date(timeIntervalSince1970: 1_773_200_102)
        )

        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")
        #expect(manager.automationRecoveryDecision?.decision == .suppressed)
        #expect(manager.automationStatusLine.contains("manual_cancelled"))
    }

    @Test
    func managerAutomaticRecoveryHoldsWhenRetryBackoffIsStillPending() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow - 1,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        _ = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-manager-backoff-blocked",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            recoveryMode: .automatic,
            auditRef: "audit-xt-auto-manager-backoff-recover"
        )
        let recovered = try #require(recovery)

        #expect(recovered.decision == .hold)
        #expect(recovered.holdReason == "retry_after_not_elapsed")
        #expect(manager.automationRecoveryDecision?.decision == .hold)
        #expect(manager.automationLatestRetryPackage == nil)
        #expect(manager.automationStatusLine.contains("retry_after_not_elapsed"))

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        #expect(statusText.contains("recovery: hold (retry_after_not_elapsed)"))
        #expect(statusText.contains("recovery_candidate_automatic_decision: hold"))
        #expect(statusText.contains("recovery_candidate_automatic_hold_reason: retry_after_not_elapsed"))
        #expect(statusText.contains("recovery_candidate_retry_after_seconds: 120"))
    }

    @Test
    func automationRecoverCommandFailsClosedWhenPersistedCheckpointStableIdentityFails() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let olderStableRunID = "run-stable-older"
        let olderStableLineage = XTAutomationRunLineage.root(runID: olderStableRunID)
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": baseNow - 12,
                "run_id": olderStableRunID,
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
                "created_at": baseNow - 11,
                "run_id": olderStableRunID,
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-stable-older",
                "checkpoint_ref": "checkpoint-run-stable-older",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify smoke tests",
                "current_step_state": XTAutomationRunStepState.blocked.rawValue,
                "current_step_summary": "Older stable blocked run that should not steal recovery focus.",
                "audit_ref": "audit-run-stable-older-checkpoint"
            ],
            for: ctx
        )

        let runID = "run-identity-drift"
        let lineage = XTAutomationRunLineage.root(runID: runID)
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": baseNow - 10,
                "run_id": runID,
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
                "created_at": baseNow - 9,
                "run_id": runID,
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
                "current_step_summary": "Identity drift detected before restart recovery.",
                "audit_ref": "audit-run-identity-drift-checkpoint"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = runID
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(statusText.contains("recovery_candidate_run: \(runID)"))
        #expect(statusText.contains("recovery_candidate_selection: latest_visible_checkpoint"))
        #expect(statusText.contains("recovery_candidate_reason: latest_visible_stable_identity_failed"))
        #expect(statusText.contains("recovery_candidate_automatic_decision: hold"))
        #expect(statusText.contains("recovery_candidate_automatic_hold_reason: stable_identity_failed"))
        #expect(recoveryText.contains("run_id: \(runID)"))
        #expect(recoveryText.contains("decision: hold"))
        #expect(recoveryText.contains("hold_reason: stable_identity_failed"))
        #expect(recoveryText.contains("candidate_selection: latest_visible_checkpoint"))
        #expect(recoveryText.contains("candidate_reason: latest_visible_stable_identity_failed"))
        #expect(recoveryText.contains("candidate_automatic_decision: hold"))
        #expect(recoveryText.contains("candidate_automatic_hold_reason: stable_identity_failed"))
        #expect(manager.automationRecoveryDecision?.decision == .hold)
        #expect(manager.automationRecoveryDecision?.holdReason == "stable_identity_failed")
        #expect(manager.automationRecoveryDecision?.stableIdentityPass == false)
        #expect(manager.automationLatestRetryPackage == nil)
        #expect(manager.automationStatusLine.contains("stable_identity_failed"))

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_run_recovery"
                && ($0["run_id"] as? String) == runID
                && ($0["schema_version"] as? String) == XTAutomationRestartRecoveryDecision.currentSchemaVersion
        })
    }

    @Test
    func automationRecoverCommandSurfacesAutomaticBackoffEvenWhenOperatorOverrideResumes() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: prepared.launchRef,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-manager-recover-backoff-override",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("candidate_reason: latest_visible_retry_wait"))
        #expect(recoveryText.contains("candidate_automatic_decision: hold"))
        #expect(recoveryText.contains("candidate_automatic_hold_reason: retry_after_not_elapsed"))
        #expect(recoveryText.contains("candidate_retry_after_seconds: 120"))
        #expect(manager.automationRecoveryDecision?.runID == prepared.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .resume)
    }

    @Test
    func automationRecoverCommandSurfacesRetryBudgetExhaustedCandidateReason() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 12))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-running-1",
            now: Date(timeIntervalSince1970: baseNow - 11)
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-blocked-1",
            now: Date(timeIntervalSince1970: baseNow - 10)
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-running-2",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-blocked-2",
            now: Date(timeIntervalSince1970: baseNow - 8)
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-running-3",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-manager-budget-blocked-3",
            now: Date(timeIntervalSince1970: baseNow - 6)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: hold"))
        #expect(recoveryText.contains("hold_reason: retry_budget_exhausted"))
        #expect(recoveryText.contains("candidate_reason: latest_visible_retry_budget_exhausted"))
        #expect(recoveryText.contains("candidate_automatic_decision: hold"))
        #expect(recoveryText.contains("candidate_automatic_hold_reason: retry_budget_exhausted"))
        #expect(manager.automationRecoveryDecision?.runID == prepared.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .hold)
    }

    @Test
    func prepareAutomationRunClearsStaleExecutionReportFromPreviousRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let sourceRoot = try makeRegistryVisibleProjectRoot()
        let targetRoot = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceCtx = AXProjectContext(root: sourceRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: sourceCtx)
        try armRepoAutomationGovernance(for: sourceCtx)

        _ = try manager.startAutomationRun(
            for: sourceCtx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_200))
        )

        try await waitUntil("source automation run delivered before preparing target run") {
            manager.automationLatestExecutionReport?.finalState == .delivered
        }

        let previousRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let targetCtx = AXProjectContext(root: targetRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: targetCtx)

        let prepared = try manager.prepareAutomationRun(
            for: targetCtx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_201))
        )

        #expect(manager.automationPreparedRun?.launchRef == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationLatestExecutionReport == nil)
        #expect(manager.automationStatusLine.contains(prepared.launchRef))
        #expect(manager.automationStatusLine.contains("排队中"))
        #expect(!manager.automationStatusLine.contains(previousRunID))
    }

    @Test
    func syncAutomationRuntimeSnapshotClearsStaleExecutionReportWhenHydratingQueuedRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        let hydrator = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        hydrator.resetAutomationRuntimeState()

        let sourceRoot = try makeRegistryVisibleProjectRoot()
        let targetRoot = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            hydrator.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }

        let sourceCtx = AXProjectContext(root: sourceRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: sourceCtx)
        try armRepoAutomationGovernance(for: sourceCtx)

        _ = try manager.startAutomationRun(
            for: sourceCtx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_300))
        )

        try await waitUntil("source automation run delivered before queued hydration") {
            manager.automationLatestExecutionReport?.finalState == .delivered
        }

        let targetCtx = AXProjectContext(root: targetRoot)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: targetCtx)
        let prepared = try hydrator.prepareAutomationRun(
            for: targetCtx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_301))
        )

        let targetProject = makeProjectEntry(root: targetRoot)
        manager.syncAutomationRuntimeSnapshot(forSelectedProject: targetProject)

        #expect(manager.automationPreparedRun?.launchRef == nil)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationLatestExecutionReport == nil)
        #expect(manager.automationLatestRetryPackage == nil)
        #expect(manager.automationStatusLine.contains(prepared.launchRef))
        #expect(manager.automationStatusLine.contains("排队中"))
    }

    @Test
    func syncAutomationRuntimeSnapshotFallsBackToPersistedCheckpointWhenLaunchRefIsMissing() async throws {
        let manager = SupervisorManager.makeForTesting()
        let hydrator = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        hydrator.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            hydrator.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let prepared = try hydrator.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_302))
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = ""
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        manager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationLatestExecutionReport == nil)
        #expect(manager.automationStatusLine.contains(prepared.launchRef))
        #expect(manager.automationStatusLine.contains("排队中"))
    }

    @Test
    func automationStatusContinuityDoesNotReuseSourceExecutionWhenRetryChildIsQueued() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_302,
                "run_id": "run-source",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "lineage_id": sourceLineage.lineageID,
                "root_run_id": sourceLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": sourceLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_303,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 45,
                "resume_token": "resume-run-source",
                "checkpoint_ref": "checkpoint-run-source",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retry child launch.",
                "audit_ref": "audit-run-source-checkpoint"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_304,
                "run_id": "run-source",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 1,
                    "passed_command_count": 0,
                    "hold_reason": "automation_verify_failed",
                    "detail": "source verification failed"
                ],
                "audit_ref": "audit-run-source-execution"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_305,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "source_hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_306,
                "run_id": "run-retry-child",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_307,
                "run_id": "run-retry-child",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.queued.rawValue,
                "attempt": 1,
                "last_transition": "prepared_to_queued",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-retry-child",
                "checkpoint_ref": "checkpoint-run-retry-child",
                "stable_identity": true,
                "current_step_id": "step-retry-prepare",
                "current_step_title": "Prepare retry child launch",
                "current_step_state": XTAutomationRunStepState.pending.rawValue,
                "current_step_summary": "Retry child queued and waiting to start.",
                "audit_ref": "audit-run-retry-child-checkpoint"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = "run-retry-child"
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        manager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(manager.automationCurrentCheckpoint?.runID == "run-retry-child")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationLatestExecutionReport == nil)

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("continuity_context_source: checkpoint+retry_package"))
        #expect(!statusText.contains("continuity_context_source: checkpoint+execution_report+retry_package"))
        #expect(statusText.contains("continuity_effective_run_id: run-retry-child"))
        #expect(statusText.contains("delivery_closure_run_id: run-retry-child"))
        #expect(statusText.contains("delivery_closure_source: retry_package"))
        #expect(!statusText.contains("last_execution_state:"))
    }

    @Test
    func automationStatusContinuityIgnoresUnrelatedRetryPackageWhenNewerRunIsActive() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")
        let newerLineage = XTAutomationRunLineage.root(runID: "run-newer")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_311,
                "run_id": "run-source",
                "delivery_ref": "build/reports/xt_auto_source_delivery.v1.json",
                "lineage_id": sourceLineage.lineageID,
                "root_run_id": sourceLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": sourceLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_312,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 45,
                "resume_token": "resume-run-source",
                "checkpoint_ref": "checkpoint-run-source",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retry child launch.",
                "audit_ref": "audit-run-source-checkpoint-unrelated"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_313,
                "run_id": "run-source",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "audit_ref": "audit-run-source-execution-unrelated"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_314,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_source_delivery.v1.json"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_315,
                "run_id": "run-newer",
                "delivery_ref": "build/reports/xt_auto_newer_delivery.v1.json",
                "lineage_id": newerLineage.lineageID,
                "root_run_id": newerLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": newerLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_316,
                "run_id": "run-newer",
                "recipe_id": "recipe-runtime-2",
                "state": XTAutomationRunState.queued.rawValue,
                "attempt": 1,
                "last_transition": "prepared_to_queued",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-newer",
                "checkpoint_ref": "checkpoint-run-newer",
                "stable_identity": true,
                "current_step_id": "step-collect-context",
                "current_step_title": "Collect context",
                "current_step_state": XTAutomationRunStepState.pending.rawValue,
                "current_step_summary": "waiting_to_start_first_action",
                "audit_ref": "audit-run-newer-checkpoint"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = "run-newer"
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        manager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(manager.automationCurrentCheckpoint?.runID == "run-newer")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.automationLatestExecutionReport == nil)
        #expect(manager.automationLatestRetryPackage == nil)

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("continuity_context_source: checkpoint"))
        #expect(!statusText.contains("continuity_context_source: checkpoint+retry_package"))
        #expect(statusText.contains("continuity_effective_run_id: run-newer"))
        #expect(statusText.contains("delivery_closure_run_id: run-newer"))
        #expect(statusText.contains("delivery_closure_source: launch"))
        #expect(!statusText.contains("retry_run_id: run-retry-child"))
        #expect(!statusText.contains("last_execution_state:"))
    }

    @Test
    func automationStatusContinuityIgnoresUnrelatedPersistedRecoveryActionWhenNewerRunIsActive() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")
        let newerLineage = XTAutomationRunLineage.root(runID: "run-newer")
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_317,
                "run_id": "run-source",
                "delivery_ref": "build/reports/xt_auto_source_delivery.v1.json",
                "lineage_id": sourceLineage.lineageID,
                "root_run_id": sourceLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": sourceLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_318,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "state": XTAutomationRunState.blocked.rawValue,
                "attempt": 2,
                "last_transition": "running_to_blocked",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-source",
                "checkpoint_ref": "checkpoint-run-source",
                "stable_identity": true,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.blocked.rawValue,
                "current_step_summary": "Verification failed and recovery handoff was recorded.",
                "audit_ref": "audit-run-source-checkpoint-recovery-unrelated"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_319,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "recovered_state": XTAutomationRunState.blocked.rawValue,
                "decision": XTAutomationRestartRecoveryAction.resume.rawValue,
                "hold_reason": NSNull(),
                "stable_identity_pass": true,
                "checkpoint_ref": "checkpoint-run-source",
                "resume_token": "resume-run-source",
                "recovery_mode": XTAutomationRestartRecoveryMode.operatorOverride.rawValue,
                "resume_mode": XTAutomationRecoveryResumeMode.retryPackage.rawValue,
                "retry_run_id": "run-retry-child",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_source_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "audit_ref": "audit-recovery-row-unrelated"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_320,
                "run_id": "run-newer",
                "delivery_ref": "build/reports/xt_auto_newer_delivery.v1.json",
                "lineage_id": newerLineage.lineageID,
                "root_run_id": newerLineage.rootRunID,
                "parent_run_id": NSNull(),
                "retry_depth": newerLineage.retryDepth
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": 1_773_200_321,
                "run_id": "run-newer",
                "recipe_id": "recipe-runtime-newer",
                "state": XTAutomationRunState.queued.rawValue,
                "attempt": 1,
                "last_transition": "prepared_to_queued",
                "retry_after_seconds": 0,
                "resume_token": "resume-run-newer",
                "checkpoint_ref": "checkpoint-run-newer",
                "stable_identity": true,
                "current_step_id": "step-collect-context",
                "current_step_title": "Collect context",
                "current_step_state": XTAutomationRunStepState.pending.rawValue,
                "current_step_summary": "waiting_to_start_first_action",
                "audit_ref": "audit-run-newer-checkpoint-recovery-unrelated"
            ],
            for: ctx
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = "run-newer"
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        manager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(manager.automationCurrentCheckpoint?.runID == "run-newer")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("continuity_context_source: checkpoint"))
        #expect(statusText.contains("continuity_effective_run_id: run-newer"))
        #expect(statusText.contains("delivery_closure_run_id: run-newer"))
        #expect(statusText.contains("delivery_closure_source: launch"))
        #expect(!statusText.contains("last_recovery_run_id: run-source"))
        #expect(!statusText.contains("last_recovery_retry_run_id: run-retry-child"))
        #expect(!statusText.contains("last_recovery_delivery_closure_run_id: run-retry-child"))
    }

    @Test
    func automationStatusFallsBackToLatestPersistedRunWhenConfigLaunchRefIsOlderButStillValid() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)

        let delivered = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_302))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: delivered.launchRef,
            auditRef: "audit-xt-auto-status-older-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_303)
        )

        let blocked = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_304))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blocked.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-status-newer-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_305)
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = delivered.launchRef
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_306,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        #expect(statusText.contains("last_launch: \(blocked.launchRef)"))
        #expect(statusText.contains("last_launch_source: checkpoint_fallback"))
        #expect(statusText.contains("state: blocked"))
    }

    @Test
    func syncAutomationRuntimeSnapshotRehydratesManualCancelledRecoveryState() throws {
        let manager = SupervisorManager.makeForTesting()
        let restartedManager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        restartedManager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            restartedManager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_303))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-hydrate-cancel-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_304)
        )
        let cancelled = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-hydrate-cancelled",
            now: Date(timeIntervalSince1970: 1_773_200_305)
        )
        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")

        let project = makeProjectEntry(root: root)
        restartedManager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(restartedManager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(restartedManager.automationCurrentCheckpoint?.state == .blocked)
        #expect(restartedManager.automationRecoveryDecision?.decision == .suppressed)
        #expect(restartedManager.automationRecoveryDecision?.holdReason == "manual_cancelled")
        #expect(restartedManager.automationStatusLine.contains("manual_cancelled"))

        let statusText = try #require(
            restartedManager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        #expect(statusText.contains("last_recovery_run_id: \(prepared.launchRef)"))
        #expect(statusText.contains("last_recovery_decision: suppressed"))
        #expect(statusText.contains("last_recovery_mode: automatic"))
        #expect(statusText.contains("last_recovery_hold_reason: manual_cancelled"))
        #expect(statusText.contains("recovery: suppressed (manual_cancelled)"))
    }

    @Test
    func syncAutomationRuntimeSnapshotRehydratesRetryAfterHoldRecoveryState() throws {
        let manager = SupervisorManager.makeForTesting()
        let restartedManager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        restartedManager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            restartedManager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let now = Date()
        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: now.addingTimeInterval(-12))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-hydrate-backoff-blocked",
            now: now.addingTimeInterval(-11)
        )

        let project = makeProjectEntry(root: root)
        restartedManager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        #expect(restartedManager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(restartedManager.automationCurrentCheckpoint?.state == .blocked)
        #expect(restartedManager.automationRecoveryDecision?.decision == .hold)
        #expect(restartedManager.automationRecoveryDecision?.holdReason == "retry_after_not_elapsed")
        #expect(restartedManager.automationStatusLine.contains("retry_after_not_elapsed"))

        let statusText = try #require(
            restartedManager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        #expect(statusText.contains("recovery: hold (retry_after_not_elapsed)"))
    }

    @Test
    func automationStatusUsesSyncedSelectedProjectWhenRegistryFallbackDisabled() throws {
        let manager = SupervisorManager.makeForTesting()
        let restartedManager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        restartedManager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            restartedManager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_306))
        )

        let project = makeProjectEntry(root: root)
        restartedManager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        let statusText = try #require(restartedManager.performAutomationRuntimeCommand("/automation status"))
        #expect(statusText.contains("项目: \(project.displayName)"))
        #expect(statusText.contains("last_launch: \(prepared.launchRef)"))
        #expect(statusText.contains("state: queued"))
    }

    @Test
    func automationCtxRuntimeSystemMessagesUseFriendlyProjectDisplayName() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Supervisor 耳机项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_150,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_150,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_151)),
            emitSystemMessage: true
        )
        _ = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-friendly-name-cancel",
            now: Date(timeIntervalSince1970: 1_773_200_152),
            emitSystemMessage: true
        )

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 已准备：\(friendlyName) -> \(prepared.launchRef)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 已取消：\(friendlyName) -> \(prepared.launchRef)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
    }

    @Test
    func automationSafePointSystemMessageUsesFriendlyProjectDisplayName() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "亮亮"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_180,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_180,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)
        manager.clearMessages()

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-friendly-safe-point-1",
                reviewId: "review-friendly-safe-point-1",
                projectId: projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "先暂停，让 supervisor 再看一遍。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_180_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-friendly-safe-point-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_181)),
            emitSystemMessage: true
        )

        try await waitUntil("friendly project safe point hold") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 在 safe point 暂停") &&
                $0.content.contains("项目: \(friendlyName)") &&
                !$0.content.contains("项目: \(root.lastPathComponent)")
        }))
    }

    @Test
    func automationSafePointSystemMessageDoesNotLeakOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Safe Point Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_185,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_185,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_185).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("project_ref=\(friendlyName)"))
            #expect(userMessage.contains("requested_state=running"))
            #expect(userMessage.contains("injection_id=guidance-hidden-safe-point-no-leak-1"))
            #expect(userMessage.contains("guidance_summary=hidden 项目先不要把 safe point 细节暴露到前台。"))
            #expect(!userMessage.contains("guidance_text="))
            #expect(!userMessage.contains(root.lastPathComponent))
            return """
            1. 先解释 hidden 项目为什么在当前 safe point 暂停。
            2. 再决定要继续复核还是直接让 coder 改计划。
            """
        }

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-hidden-safe-point-no-leak-1",
                reviewId: "review-hidden-safe-point-no-leak-1",
                projectId: projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "hidden 项目先不要把 safe point 细节暴露到前台。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_185_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-hidden-safe-point-no-leak-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_186)),
            emitSystemMessage: true
        )

        try await waitUntil("hidden project safe point hold without visible leak") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await followUpFlag.value())
        #expect(manager.messages.contains(where: {
            $0.role == .assistant &&
                $0.content.contains("先解释 hidden 项目为什么在当前 safe point 暂停") &&
                !$0.content.contains(root.lastPathComponent)
        }))
        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("automation 在 safe point 暂停")
        }) == false)

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-hidden-safe-point-no-leak-1"
        })
    }

    @Test
    func automationAutomaticSelfIterateSystemMessageUsesFriendlyProjectDisplayName() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        config.automationSelfIterateEnabled = true
        config.automationMaxAutoRetryDepth = 1
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "亮亮"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_190,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_190,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_191)),
            emitSystemMessage: true
        )

        try await waitUntil("friendly project automatic self iterate system message", timeoutMs: 10_000) {
            manager.messages.contains(where: {
                $0.role == .system && $0.content.contains("automation 自动迭代已继续")
            })
        }

        let retryRunID = try #require(manager.automationLatestRetryPackage?.retryRunID)
        try await waitUntil("friendly project automatic self iterate retry settles", timeoutMs: 10_000) {
            manager.automationCurrentCheckpoint?.runID == retryRunID &&
                manager.automationCurrentCheckpoint?.state == .blocked &&
                manager.automationLatestExecutionReport?.runID == retryRunID
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 自动迭代已继续") &&
                $0.content.contains("项目: \(friendlyName)") &&
                !$0.content.contains("项目: \(root.lastPathComponent)")
        }))
    }

    @Test
    func automationAutomaticSelfIterateSystemMessageDoesNotLeakOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        config.automationSelfIterateEnabled = true
        config.automationMaxAutoRetryDepth = 1
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Auto Retry Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_195,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_195,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_195).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )
        manager.clearMessages()

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_196)),
            emitSystemMessage: true
        )

        try await waitUntil("hidden automatic self-iterate retry launch without visible leak") {
            let retryRunID = manager.automationLatestRetryPackage?.retryRunID ?? ""
            return !retryRunID.isEmpty &&
                manager.automationRetryTriggerForTesting() == "automatic"
        }

        let sourceRunID = try #require(manager.automationLatestRetryPackage?.sourceRunID)
        let retryRunID = try #require(manager.automationLatestRetryPackage?.retryRunID)
        try await waitUntil("hidden automatic self-iterate retry settles", timeoutMs: 10_000) {
            manager.automationCurrentCheckpoint?.runID == retryRunID &&
                manager.automationCurrentCheckpoint?.state == .blocked &&
                manager.automationLatestExecutionReport?.runID == retryRunID
        }
        #expect(sourceRunID != retryRunID)
        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("automation 自动迭代已继续")
        }) == false)

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_retry" &&
            ($0["status"] as? String) == "pending" &&
            ($0["source_run_id"] as? String) == sourceRunID
        })
    }

    @Test
    func automationExecutionSummaryKeepsCapturedFriendlyProjectDisplayNameWhenRegistryChangesMidRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "外出采购项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_195,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_195,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)
        manager.clearMessages()

        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, rootURL in
                try await Task.sleep(nanoseconds: 250_000_000)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=\(rootURL.path); tool=\(call.tool.rawValue)")
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_196)),
            emitSystemMessage: true
        )

        try await waitUntil("automation running before registry drift") {
            manager.automationCurrentCheckpoint?.state == .running
        }

        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_197,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: []
        )
        appModel.selectedProjectId = nil

        try await waitUntil("friendly project execution summary after registry drift", timeoutMs: 10_000) {
            manager.messages.contains(where: {
                $0.role == .system && $0.content.contains("⚙️ automation 自动执行完成")
            })
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("⚙️ automation 自动执行完成") &&
                $0.content.contains("项目: \(friendlyName)") &&
                !$0.content.contains("项目: \(root.lastPathComponent)")
        }))
    }

    @Test
    func automationPrepareAndCancelSystemMessagesDoNotLeakOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Prepare Cancel Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_198,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_198,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_198).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )
        manager.clearMessages()

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_199)),
            emitSystemMessage: true
        )
        _ = try manager.cancelAutomationRun(
            for: ctx,
            runID: prepared.launchRef,
            auditRef: "audit-hidden-prepare-cancel-no-leak",
            now: Date(timeIntervalSince1970: 1_773_200_200),
            emitSystemMessage: true
        )

        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("automation 已准备")
        }) == false)
        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("automation 已取消")
        }) == false)
        #expect(manager.recentEventsForTesting().contains(where: {
            $0.contains("automation prepared") || $0.contains("automation cancelled")
        }) == false)
    }

    @Test
    func automationRecoverySystemMessageDoesNotLeakOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Recovery Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_201,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_201,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        appModel.selectedProjectId = projectId
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_201).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )
        manager.clearMessages()

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_202))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-hidden-recovery-no-leak-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_203)
        )

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 60,
            auditRef: "audit-hidden-recovery-no-leak",
            emitSystemMessage: true
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("automation 已恢复判定")
        }) == false)
        #expect(manager.recentEventsForTesting().contains(where: {
            $0.contains("automation prepared")
                || $0.contains("automation advanced")
                || $0.contains("automation recovered")
        }) == false)
    }

    @Test
    func automationExecutionSummaryDoesNotLeakWhenProjectLeavesJurisdictionMidRun() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Midflight Summary Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_205,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_205,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, rootURL in
                try await Task.sleep(nanoseconds: 250_000_000)
                return ToolResult(
                    id: call.id,
                    tool: call.tool,
                    ok: true,
                    output: "root=\(rootURL.path); tool=\(call.tool.rawValue)"
                )
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_206)),
            emitSystemMessage: true
        )

        try await waitUntil("automation running before hidden summary guard") {
            manager.automationCurrentCheckpoint?.state == .running
        }

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_207).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        try await waitUntil("hidden project execution completes without visible summary", timeoutMs: 30_000) {
            manager.automationLatestExecutionReport?.finalState == .delivered
        }

        #expect(manager.messages.contains(where: {
            $0.role == .system && $0.content.contains("⚙️ automation 自动执行完成")
        }) == false)
    }

    @Test
    func managerProjectEntryWrappersResolveContextAndPrepareRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: root.lastPathComponent,
            lastOpenedAt: 1_773_200_200,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let prepared = try manager.prepareAutomationRun(
            for: project,
            request: makeRequest(now: Date(timeIntervalSince1970: 1_773_200_200))
        )

        #expect(prepared.currentCheckpoint.state == .queued)
        #expect(manager.automationPreparedRun?.launchRef == prepared.launchRef)
    }

    @Test
    func automationCommandsRouteToManagerRuntimeEntryPoints() async throws {
        try await Self.gate.run {
            let manager = SupervisorManager.makeForTesting()
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
                AXTrustedAutomationPermissionOwnerReadiness(
                    schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                    ownerID: "owner-xt",
                    ownerType: "xterminal_app",
                    bundleID: "com.xterminal.app",
                    installState: "ready",
                    mode: "managed_or_prompted",
                    accessibility: .granted,
                    automation: .missing,
                    screenRecording: .missing,
                    fullDiskAccess: .missing,
                    inputMonitoring: .missing,
                    canPromptUser: true,
                    managedByMDM: false,
                    overallState: "partial",
                    openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                    auditRef: "audit-xt-auto-manager-command"
                )
            }

            let root = try makeRegistryVisibleProjectRoot()
            defer {
                manager.resetAutomationRuntimeState()
                AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = makeTestingAppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: Date().timeIntervalSince1970,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: nil,
                projects: [project]
            )
            manager.setAppModel(appModel)

            let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
            #expect(startText.contains("run_id:"))
            #expect(manager.automationCurrentCheckpoint?.state == .queued)

            let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
            #expect(statusText.contains("state: queued"))
            #expect(statusText.contains(project.projectId))
            #expect(statusText.contains("required_device_tool_groups: device.ui.observe,device.ui.act"))

            let advancedText = try #require(manager.performAutomationRuntimeCommand("/automation advance blocked \(project.projectId)"))
            #expect(advancedText.contains("state: blocked"))
            #expect(manager.automationCurrentCheckpoint?.state == .blocked)

            let recoveryText = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))
            #expect(recoveryText.contains("decision: resume"))
            #expect(manager.automationRecoveryDecision?.decision == .resume)

            let cancelText = try #require(manager.performAutomationRuntimeCommand("/automation cancel \(project.projectId)"))
            #expect(cancelText.contains("manual_cancelled"))
            #expect(manager.automationRecoveryDecision?.decision == .suppressed)
        }
    }

    @Test
    @MainActor
    func heartbeatAutoProgressKickstartsPausedReadyProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Heartbeat Kickstart",
            lastOpenedAt: 1_773_201_400,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "启动自动项目快照",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_000,
            lastEventAt: 1_773_201_000
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_500)
        )
        #expect(actions.count == 1)
        #expect(actions[0].contains("主动启动"))
        #expect(actions[0].contains("Heartbeat Kickstart"))

        try await waitUntil("heartbeat kickstart launch ref persisted") {
            let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
            let runID = config?.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !runID.isEmpty
        }
    }

    @Test
    func automationRecoverCommandUsesActualCheckpointAgeAndScavengesStaleRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_000))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 30,
            auditRef: "audit-xt-auto-stale-command-recover-blocked",
            now: Date(timeIntervalSince1970: 1_773_200_001)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: scavenged"))
        #expect(recoveryText.contains("hold_reason: stale_run_scavenged"))
        #expect(manager.automationRecoveryDecision?.decision == .scavenged)
        #expect(manager.automationRecoveryDecision?.holdReason == "stale_run_scavenged")
        #expect(manager.automationLatestRetryPackage == nil)
    }

    @Test
    func automationRecoverCommandPrefersOlderUnsupersededBlockedRunOverNewerUnrelatedDeliveredRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let blockedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blockedRun.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-manager-older-blocked-recover-candidate",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let deliveredRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 8))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: deliveredRun.launchRef,
            auditRef: "audit-xt-auto-manager-newer-delivered-unrelated",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(statusText.contains("last_launch: \(deliveredRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_run: \(blockedRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_state: blocked"))
        #expect(statusText.contains("recovery_candidate_selection: latest_recoverable_unsuperseded"))
        #expect(statusText.contains("recovery_candidate_reason: latest_visible_not_recoverable"))
        #expect(statusText.contains("recovery_candidate_automatic_decision: resume"))
        #expect(statusText.contains("recovery_candidate_resume_mode: in_place"))
        #expect(statusText.contains("recovery_visible_latest_run: \(deliveredRun.launchRef)"))
        #expect(statusText.contains("recovery_visible_latest_state: delivered"))
        #expect(recoveryText.contains("run_id: \(blockedRun.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("candidate_run_id: \(blockedRun.launchRef)"))
        #expect(recoveryText.contains("candidate_state: blocked"))
        #expect(recoveryText.contains("candidate_selection: latest_recoverable_unsuperseded"))
        #expect(recoveryText.contains("candidate_reason: latest_visible_not_recoverable"))
        #expect(recoveryText.contains("candidate_automatic_decision: resume"))
        #expect(recoveryText.contains("candidate_resume_mode: in_place"))
        #expect(recoveryText.contains("visible_latest_run_id: \(deliveredRun.launchRef)"))
        #expect(recoveryText.contains("visible_latest_state: delivered"))
        #expect(manager.automationRecoveryDecision?.runID == blockedRun.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == blockedRun.launchRef)
    }

    @Test
    func automationRecoverCommandKeepsLatestVisibleQueuedRunAsRecoveryCandidateWhenOlderUnrelatedBlockedRunExists() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let blockedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blockedRun.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-manager-older-blocked-active-visible",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let queuedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 8))
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(statusText.contains("last_launch: \(queuedRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_run: \(queuedRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_state: queued"))
        #expect(statusText.contains("recovery_candidate_selection: latest_visible_checkpoint"))
        #expect(statusText.contains("recovery_candidate_reason: latest_visible_active_run"))
        #expect(statusText.contains("recovery_candidate_automatic_decision: hold"))
        #expect(statusText.contains("recovery_candidate_automatic_hold_reason: state_not_restartable"))
        #expect(!statusText.contains("recovery_visible_latest_run:"))
        #expect(recoveryText.contains("run_id: \(queuedRun.launchRef)"))
        #expect(recoveryText.contains("decision: hold"))
        #expect(recoveryText.contains("hold_reason: state_not_restartable"))
        #expect(recoveryText.contains("candidate_run_id: \(queuedRun.launchRef)"))
        #expect(recoveryText.contains("candidate_state: queued"))
        #expect(recoveryText.contains("candidate_selection: latest_visible_checkpoint"))
        #expect(recoveryText.contains("candidate_reason: latest_visible_active_run"))
        #expect(recoveryText.contains("candidate_automatic_decision: hold"))
        #expect(recoveryText.contains("candidate_automatic_hold_reason: state_not_restartable"))
        #expect(manager.automationRecoveryDecision?.runID == queuedRun.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .hold)
        #expect(manager.automationRecoveryDecision?.holdReason == "state_not_restartable")
        #expect(manager.automationCurrentCheckpoint?.runID == queuedRun.launchRef)
    }

    @Test
    func automationCancelAndAdvanceCommandsDoNotTargetOlderBlockedRunWhenNewerVisibleRunIsDelivered() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let blockedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blockedRun.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-manager-older-blocked-command-target",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let deliveredRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 8))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: deliveredRun.launchRef,
            auditRef: "audit-xt-auto-manager-newer-delivered-command-target",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = deliveredRun.launchRef
        try AXProjectStore.saveConfig(config, for: ctx)

        let rowsBefore = try rawLogEntries(for: ctx)
        let cancelText = try #require(
            manager.performAutomationRuntimeCommand("/automation cancel \(project.projectId)")
        )
        let advanceText = try #require(
            manager.performAutomationRuntimeCommand("/automation advance blocked \(project.projectId)")
        )
        let rowsAfter = try rawLogEntries(for: ctx)

        #expect(cancelText.contains("run_id=active"))
        #expect(advanceText.contains("run_id=active"))
        #expect(rowsAfter.count == rowsBefore.count)
        #expect(
            xtAutomationPersistedCheckpointSummary(
                for: blockedRun.launchRef,
                from: rowsAfter
            )?.checkpoint.state == .blocked
        )
        #expect(
            xtAutomationPersistedCheckpointSummary(
                for: deliveredRun.launchRef,
                from: rowsAfter
            )?.checkpoint.state == .delivered
        )
    }

    @Test
    func automationRecoverCommandReportsSupersededRecoverableRunWhenLatestVisibleDeliveredRunWins() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let sourceRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: sourceRun.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-manager-blocked-source-superseded",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let retryChildRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(
                now: Date(timeIntervalSince1970: baseNow - 8),
                lineage: sourceRun.lineage.retryChild(parentRunID: sourceRun.launchRef)
            )
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: retryChildRun.launchRef,
            auditRef: "audit-xt-auto-manager-delivered-retry-child-supersedes",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(statusText.contains("recovery_candidate_run: \(retryChildRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_selection: latest_visible_checkpoint"))
        #expect(statusText.contains("recovery_candidate_reason: no_recoverable_unsuperseded_run"))
        #expect(statusText.contains("recovery_candidate_automatic_decision: hold"))
        #expect(statusText.contains("recovery_candidate_automatic_hold_reason: run_already_delivered"))
        #expect(statusText.contains("recovery_superseded_run: \(sourceRun.launchRef)"))
        #expect(statusText.contains("recovery_superseded_by_run: \(retryChildRun.launchRef)"))
        #expect(recoveryText.contains("run_id: \(retryChildRun.launchRef)"))
        #expect(recoveryText.contains("decision: hold"))
        #expect(recoveryText.contains("hold_reason: run_already_delivered"))
        #expect(recoveryText.contains("candidate_selection: latest_visible_checkpoint"))
        #expect(recoveryText.contains("candidate_reason: no_recoverable_unsuperseded_run"))
        #expect(recoveryText.contains("candidate_automatic_decision: hold"))
        #expect(recoveryText.contains("candidate_automatic_hold_reason: run_already_delivered"))
        #expect(recoveryText.contains("candidate_superseded_run_id: \(sourceRun.launchRef)"))
        #expect(recoveryText.contains("candidate_superseded_by_run_id: \(retryChildRun.launchRef)"))
        #expect(manager.automationRecoveryDecision?.runID == retryChildRun.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .hold)
    }

    @Test
    func automationRecoverCommandDoesNotReportUnrelatedSupersededRunWhenDifferentLatestVisibleRunWinsFallback() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let sourceRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 12))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: sourceRun.launchRef,
            retryAfterSeconds: 0,
            auditRef: "audit-xt-auto-manager-blocked-source-unrelated-fallback",
            now: Date(timeIntervalSince1970: baseNow - 11)
        )

        let retryChildRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(
                now: Date(timeIntervalSince1970: baseNow - 10),
                lineage: sourceRun.lineage.retryChild(parentRunID: sourceRun.launchRef)
            )
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: retryChildRun.launchRef,
            auditRef: "audit-xt-auto-manager-delivered-retry-child-unrelated-fallback",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let unrelatedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 8))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: unrelatedRun.launchRef,
            auditRef: "audit-xt-auto-manager-delivered-unrelated-latest-visible",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(statusText.contains("recovery_candidate_run: \(unrelatedRun.launchRef)"))
        #expect(statusText.contains("recovery_candidate_selection: latest_visible_checkpoint"))
        #expect(statusText.contains("recovery_candidate_reason: no_recoverable_unsuperseded_run"))
        #expect(!statusText.contains("recovery_superseded_run:"))
        #expect(!statusText.contains("recovery_superseded_by_run:"))
        #expect(recoveryText.contains("run_id: \(unrelatedRun.launchRef)"))
        #expect(recoveryText.contains("decision: hold"))
        #expect(recoveryText.contains("hold_reason: run_already_delivered"))
        #expect(recoveryText.contains("candidate_selection: latest_visible_checkpoint"))
        #expect(recoveryText.contains("candidate_reason: no_recoverable_unsuperseded_run"))
        #expect(!recoveryText.contains("candidate_superseded_run_id:"))
        #expect(!recoveryText.contains("candidate_superseded_by_run_id:"))
        #expect(manager.automationRecoveryDecision?.runID == unrelatedRun.launchRef)
        #expect(manager.automationRecoveryDecision?.decision == .hold)
    }

    @Test
    @MainActor
    func heartbeatAutoProgressDoesNotKickstartAgainWhenConfigLaunchRefDriftsButPersistedRunExists() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Heartbeat Drift Guard",
            lastOpenedAt: 1_773_201_510,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "等待 heartbeat",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_000,
            lastEventAt: 1_773_201_000
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_511))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            auditRef: "audit-xt-auto-heartbeat-drift-guard",
            now: Date(timeIntervalSince1970: 1_773_201_512)
        )

        var driftedConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        driftedConfig.lastAutomationLaunchRef = ""
        try AXProjectStore.saveConfig(driftedConfig, for: ctx)

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_700)
        )

        #expect(actions.isEmpty)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .delivered)
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(config.lastAutomationLaunchRef.isEmpty)
    }

    @Test
    @MainActor
    func automationRuntimeExplicitProjectRefStillWorksOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        try armTrustedAutomation(for: ctx)
        let project = makeProjectEntry(root: root, displayName: "Hidden Automation Command")
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_460).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))
        #expect(!startText.contains("project_not_found"))

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains(project.projectId))
        #expect(statusText.contains("state: queued"))
    }

    @Test
    @MainActor
    func heartbeatAutoProgressKickstartsHiddenPausedReadyProject() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Hidden Heartbeat Kickstart",
            lastOpenedAt: 1_773_201_520,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "启动自动项目快照",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_020,
            lastEventAt: 1_773_201_020
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_201_530).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_600)
        )
        #expect(actions.count == 1)
        #expect(actions[0].contains("主动启动"))
        #expect(actions[0].contains("Hidden Heartbeat Kickstart"))

        try await waitUntil("hidden heartbeat kickstart launch ref persisted") {
            let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
            let runID = config?.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !runID.isEmpty
        }
    }

    @Test
    @MainActor
    func heartbeatAutoProgressKickstartsHiddenPausedReadyProjectWithoutVisibleHeartbeatLeak() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Heartbeat Kickstart Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: baseNow - 10,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "暂停中",
            nextStepSummary: "等待自动项目快照启动",
            blockerSummary: nil,
            lastSummaryAt: baseNow - 60,
            lastEventAt: baseNow - 60
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdictionNow = baseNow - 9
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.emitHeartbeatCycleForTesting(force: true, reason: "timer")

        #expect(manager.heartbeatHistory.isEmpty)
        try await waitUntil("hidden heartbeat kickstart launch ref persisted without visible leak") {
            let config = try? AXProjectStore.loadOrCreateConfig(for: ctx)
            let runID = config?.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !runID.isEmpty
        }
    }

    @Test
    func heartbeatRecordsProjectCreationStatusWithoutProjects() throws {
        let manager = SupervisorManager.makeForTesting()

        let intakeReply = try #require(
            manager.directSupervisorReplyIfApplicableForTesting(
                "我要做个贪食蛇游戏，你能做个详细工单发给project AI去推进吗"
            )
        )
        #expect(intakeReply.contains("按默认方案建项目"))

        manager.emitHeartbeatCycleForTesting(force: true, reason: "timer")

        let heartbeat = try #require(manager.latestHeartbeat)
        let actionURL = try #require(manager.heartbeatFocusActionURLForTesting(reason: "timer"))
        #expect(heartbeat.projectCount == 0)
        #expect(heartbeat.reason == "timer")
        #expect(heartbeat.content.contains("重点看板："))
        #expect(heartbeat.content.contains("• Supervisor：📁 项目创建还差一句触发。"))
        #expect(heartbeat.content.contains("项目创建："))
        #expect(heartbeat.content.contains("已锁定《贪食蛇游戏》"))
        #expect(heartbeat.content.contains("贪食蛇游戏"))
        #expect(heartbeat.content.contains("可直接说：“立项” / “创建一个project” / “按默认方案建项目”"))
        #expect(
            actionURL == XTDeepLinkURLBuilder.supervisorURL(
                focusTarget: .projectCreationBoard
            )?.absoluteString
        )
        #expect(heartbeat.focusActionURL == actionURL)
    }

    @Test
    func heartbeatGovernedReviewRecordsRuntimeGovernanceTruthWhenQueued() async throws {
        let manager = SupervisorManager.makeForTesting()

        let root = try makeRegistryVisibleProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 60,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: []
        )
        try AXProjectStore.saveConfig(config, for: ctx)
        _ = try SupervisorReviewScheduleStore.touchHeartbeat(
            for: ctx,
            config: config,
            nowMs: 1_773_384_000_000
        )
        _ = try SupervisorReviewScheduleStore.markReview(
            for: ctx,
            config: config,
            trigger: .periodicPulse,
            runKind: .pulse,
            nowMs: 1_773_384_000_000
        )

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Governed Review Runtime",
            lastOpenedAt: 1_773_384_120,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "running",
            currentStateSummary: "正常推进中",
            nextStepSummary: "等待 periodic review",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_060,
            lastEventAt: 1_773_384_060
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("review_trigger=periodic_pulse"))
            #expect(userMessage.contains("governance_reason=当前项目治理要求按固定脉冲周期补做 review，heartbeat 已自动排队。"))
            #expect(userMessage.contains("governance_truth=治理真相：当前生效 A2/S2 · 审查 Periodic · 节奏 心跳 10m / 脉冲 1m / 脑暴 1h。"))
            return ""
        }

        _ = await manager.emitHeartbeatForTesting(
            force: true,
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_120)
        )
        await manager.waitForSupervisorEventLoopForTesting()
        try await waitUntil("governed review runtime activity queued", timeoutMs: 5_000) {
            manager.runtimeActivityEntries.contains(where: {
                $0.projectId == project.projectId
                    && $0.text.contains("heartbeat_governed_review status=queued")
            })
        }

        let entry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == project.projectId
                && $0.text.contains("heartbeat_governed_review status=queued")
        }))
        #expect(entry.projectName == project.displayName)
        #expect(entry.text.contains("review_trigger=periodic_pulse"))
        #expect(entry.text.contains("review_run_kind=pulse"))
        #expect(entry.text.contains("policy_reason=pulse_review_due"))
        #expect(entry.text.contains("governance_reason=当前项目治理要求按固定脉冲周期补做 review，heartbeat 已自动排队。"))
        #expect(entry.text.contains("governance_truth=治理真相：当前生效 A2/S2 · 审查 Periodic · 节奏 心跳 10m / 脉冲 1m / 脑暴 1h。"))
    }

    @Test
    func heartbeatGovernedReviewPrefersHigherPortfolioPriorityProjectWhenCandidatePriorityMatches() async throws {
        let manager = SupervisorManager.makeForTesting()

        let routineRoot = try makeRegistryVisibleProjectRoot()
        let urgentRoot = try makeRegistryVisibleProjectRoot()
        defer {
            try? FileManager.default.removeItem(at: routineRoot)
            try? FileManager.default.removeItem(at: urgentRoot)
        }

        let reviewDueAtMs: Int64 = 1_773_384_000_000
        let configs = [
            AXProjectContext(root: routineRoot),
            AXProjectContext(root: urgentRoot)
        ]
        for ctx in configs {
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s2PeriodicReview,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 600,
                reviewPulseSeconds: 60,
                brainstormReviewSeconds: 0,
                eventDrivenReviewEnabled: false,
                eventReviewTriggers: []
            )
            try AXProjectStore.saveConfig(config, for: ctx)
            _ = try SupervisorReviewScheduleStore.touchHeartbeat(
                for: ctx,
                config: config,
                nowMs: reviewDueAtMs
            )
            _ = try SupervisorReviewScheduleStore.markReview(
                for: ctx,
                config: config,
                trigger: .periodicPulse,
                runKind: .pulse,
                nowMs: reviewDueAtMs
            )
        }

        let routineProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: routineRoot),
            rootPath: routineRoot.path,
            displayName: "Routine Review Runtime",
            lastOpenedAt: 1_773_384_120,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "running",
            currentStateSummary: "正常推进中",
            nextStepSummary: "执行验证补丁",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_060,
            lastEventAt: 1_773_384_060
        )
        let urgentProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: urgentRoot),
            rootPath: urgentRoot.path,
            displayName: "Grant Review Runtime",
            lastOpenedAt: 1_773_384_120,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "grant_pending",
            currentStateSummary: "等待授权",
            nextStepSummary: "补齐 grant 后恢复执行",
            blockerSummary: nil,
            lastSummaryAt: 1_773_382_000,
            lastEventAt: 1_773_382_000
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: urgentProject.projectId,
            projects: [routineProject, urgentProject]
        )
        appModel.selectedProjectId = urgentProject.projectId
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("project_ref=\(urgentProject.displayName)"))
            #expect(userMessage.contains("project_id=\(urgentProject.projectId)"))
            #expect(userMessage.contains("review_trigger=periodic_pulse"))
            #expect(userMessage.contains("portfolio_priority_band=critical"))
            #expect(userMessage.contains("portfolio_priority_why=待授权会直接卡住推进"))
            return "selected higher portfolio priority project"
        }

        _ = await manager.emitHeartbeatForTesting(
            force: true,
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_120)
        )
        await manager.waitForSupervisorEventLoopForTesting()

        try await waitUntil("higher priority governed review runtime activity queued", timeoutMs: 5_000) {
            manager.runtimeActivityEntries.contains(where: {
                $0.projectId == urgentProject.projectId
                    && $0.text.contains("heartbeat_governed_review status=queued")
            })
        }

        let selectedEntry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == urgentProject.projectId
                && $0.text.contains("heartbeat_governed_review status=queued")
        }))
        #expect(selectedEntry.text.contains("portfolio_priority_band=critical"))
        #expect(selectedEntry.text.contains("portfolio_priority_score=8"))
        #expect(selectedEntry.text.contains("portfolio_priority_why=待授权会直接卡住推进"))
        #expect(!manager.runtimeActivityEntries.contains(where: {
            $0.projectId == routineProject.projectId
                && $0.text.contains("heartbeat_governed_review status=queued")
        }))

        let activity = try #require(manager.recentSupervisorEventLoopActivitiesForTesting().last(where: {
            $0.dedupeKey.hasPrefix("governed_review:")
                && $0.status == "completed"
        }))
        #expect(activity.projectId == urgentProject.projectId)
        #expect(activity.projectName == urgentProject.displayName)
    }

    @Test
    func heartbeatRecoveryGrantFollowUpQueuesEventLoopWithRuntimeGovernanceTruth() async throws {
        let manager = SupervisorManager.makeForTesting()

        let root = try makeRegistryVisibleProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_800,
            brainstormReviewSeconds: 3_600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Grant Recovery Runtime",
            lastOpenedAt: 1_773_384_220,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待 grant 跟进",
            nextStepSummary: "补齐 grant 后恢复执行",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_180,
            lastEventAt: 1_773_384_180
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .grantPending,
                nextActionRecommendation: "request_grant_follow_up"
            )
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("recovery_action=request_grant_follow_up"))
            #expect(userMessage.contains("reason_code=grant_follow_up_required"))
            #expect(userMessage.contains("policy_reason=当前 heartbeat 检测到 grant 相关阻塞，系统已自动排队 grant 跟进。"))
            #expect(userMessage.contains("governance_truth=治理真相：当前生效 A2/S3"))
            return "handled grant recovery"
        }

        _ = await manager.emitHeartbeatForTesting(
            force: true,
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_220)
        )
        await manager.waitForSupervisorEventLoopForTesting()
        try await waitUntil("grant recovery runtime activity queued", timeoutMs: 5_000) {
            manager.runtimeActivityEntries.contains(where: {
                $0.projectId == project.projectId
                    && $0.text.contains("heartbeat_recovery_follow_up status=queued")
                    && $0.text.contains("recovery_action=request_grant_follow_up")
            })
        }

        let activity = try #require(manager.recentSupervisorEventLoopActivitiesForTesting().last(where: {
            $0.dedupeKey.hasPrefix("heartbeat_recovery_follow_up:")
                && $0.status == "completed"
        }))
        #expect(activity.projectId == project.projectId)
        #expect(activity.projectName == project.displayName)
        #expect(activity.triggerSource == "heartbeat")
        #expect(activity.triggerSummary.contains("需要 grant / 授权跟进"))
        #expect(activity.resultSummary == "handled grant recovery")
        #expect(activity.policySummary.contains("cadence="))
        #expect(activity.governanceTruth.contains("治理真相：当前生效 A2/S3"))

        let entry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == project.projectId
                && $0.text.contains("heartbeat_recovery_follow_up status=queued")
        }))
        #expect(entry.projectName == project.displayName)
        #expect(entry.text.contains("recovery_action=request_grant_follow_up"))
        #expect(entry.text.contains("reason_code=grant_follow_up_required"))
        #expect(entry.text.contains("governance_reason=当前 heartbeat 检测到 grant 相关阻塞，系统已自动排队 grant 跟进。"))
        #expect(entry.text.contains("governance_truth=治理真相：当前生效 A2/S3"))
    }

    @Test
    func heartbeatRecoveryFollowUpPrefersHigherPortfolioPriorityProjectWhenRecoveryPriorityMatches() async throws {
        let manager = SupervisorManager.makeForTesting()

        let routineRoot = try makeRegistryVisibleProjectRoot()
        let urgentRoot = try makeRegistryVisibleProjectRoot()
        defer {
            try? FileManager.default.removeItem(at: routineRoot)
            try? FileManager.default.removeItem(at: urgentRoot)
        }

        for ctx in [AXProjectContext(root: routineRoot), AXProjectContext(root: urgentRoot)] {
            var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
            config = config.settingProjectGovernance(
                executionTier: .a2RepoAuto,
                supervisorInterventionTier: .s3StrategicCoach,
                reviewPolicyMode: .periodic,
                progressHeartbeatSeconds: 600,
                reviewPulseSeconds: 1_800,
                brainstormReviewSeconds: 3_600,
                eventDrivenReviewEnabled: true,
                eventReviewTriggers: [.blockerDetected]
            )
            try AXProjectStore.saveConfig(config, for: ctx)
        }

        let routineProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: routineRoot),
            rootPath: routineRoot.path,
            displayName: "Routine Grant Recovery Runtime",
            lastOpenedAt: 1_773_384_220,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "running",
            currentStateSummary: "等待恢复",
            nextStepSummary: "补齐 grant 后恢复执行",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_180,
            lastEventAt: 1_773_384_180
        )
        let urgentProject = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: urgentRoot),
            rootPath: urgentRoot.path,
            displayName: "Priority Grant Recovery Runtime",
            lastOpenedAt: 1_773_384_220,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "grant_pending",
            currentStateSummary: "等待授权",
            nextStepSummary: "补齐 grant 后恢复执行",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_180,
            lastEventAt: 1_773_384_180
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: urgentProject.projectId,
            projects: [routineProject, urgentProject]
        )
        appModel.selectedProjectId = urgentProject.projectId
        manager.setAppModel(appModel)

        let routineLane = makeHeartbeatRecoveryLaneSnapshot(
            projectId: routineProject.projectId,
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "request_grant_follow_up",
            laneID: "lane-routine-grant"
        )
        let urgentLane = makeHeartbeatRecoveryLaneSnapshot(
            projectId: urgentProject.projectId,
            status: .blocked,
            blockedReason: .grantPending,
            nextActionRecommendation: "request_grant_follow_up",
            laneID: "lane-urgent-grant"
        )
        manager.setLaneHealthSnapshotForTesting(
            SupervisorLaneHealthSnapshot(
                generatedAtMs: urgentLane.generatedAtMs,
                summary: LaneHealthSummary(
                    total: routineLane.lanes.count + urgentLane.lanes.count,
                    running: 0,
                    blocked: routineLane.lanes.count + urgentLane.lanes.count,
                    stalled: 0,
                    failed: 0,
                    waiting: 0,
                    recovering: 0,
                    completed: 0
                ),
                lanes: routineLane.lanes + urgentLane.lanes
            )
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("project_ref=\(urgentProject.displayName)"))
            #expect(userMessage.contains("project_id=\(urgentProject.projectId)"))
            #expect(userMessage.contains("recovery_action=request_grant_follow_up"))
            #expect(userMessage.contains("portfolio_priority_band=critical"))
            #expect(userMessage.contains("portfolio_priority_score=8"))
            #expect(userMessage.contains("portfolio_priority_why=待授权会直接卡住推进"))
            return "selected higher portfolio priority recovery"
        }

        _ = await manager.emitHeartbeatForTesting(
            force: true,
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_220)
        )
        await manager.waitForSupervisorEventLoopForTesting()

        try await waitUntil("higher priority recovery runtime activity queued", timeoutMs: 5_000) {
            manager.runtimeActivityEntries.contains(where: {
                $0.projectId == urgentProject.projectId
                    && $0.text.contains("heartbeat_recovery_follow_up status=queued")
            })
        }

        let selectedEntry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == urgentProject.projectId
                && $0.text.contains("heartbeat_recovery_follow_up status=queued")
        }))
        #expect(selectedEntry.text.contains("portfolio_priority_band=critical"))
        #expect(selectedEntry.text.contains("portfolio_priority_score=8"))
        #expect(selectedEntry.text.contains("portfolio_priority_why=待授权会直接卡住推进"))
        #expect(!manager.runtimeActivityEntries.contains(where: {
            $0.projectId == routineProject.projectId
                && $0.text.contains("heartbeat_recovery_follow_up status=queued")
        }))

        let activity = try #require(manager.recentSupervisorEventLoopActivitiesForTesting().last(where: {
            $0.dedupeKey.hasPrefix("heartbeat_recovery_follow_up:")
                && $0.status == "completed"
        }))
        #expect(activity.projectId == urgentProject.projectId)
        #expect(activity.projectName == urgentProject.displayName)
    }

    @Test
    func heartbeatRecoveryReplayFollowUpQueuesEventLoopWithRuntimeGovernanceTruth() async throws {
        let manager = SupervisorManager.makeForTesting()

        let root = try makeRegistryVisibleProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a3DeliverAuto,
            supervisorInterventionTier: .s3StrategicCoach,
            reviewPolicyMode: .hybrid,
            progressHeartbeatSeconds: 600,
            reviewPulseSeconds: 1_200,
            brainstormReviewSeconds: 3_600,
            eventDrivenReviewEnabled: true,
            eventReviewTriggers: [.blockerDetected, .failureStreak]
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Replay Recovery Runtime",
            lastOpenedAt: 1_773_384_320,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "stalled",
            currentStateSummary: "当前 drain 结束后需要续跑",
            nextStepSummary: "重放 follow-up / 续跑链",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_280,
            lastEventAt: 1_773_384_280
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .restartDrain,
                nextActionRecommendation: "wait_drain_recover"
            )
        )

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            #expect(triggerSource == "heartbeat")
            #expect(userMessage.contains("recovery_action=replay_follow_up"))
            #expect(userMessage.contains("reason_code=restart_drain_requires_follow_up_replay"))
            #expect(userMessage.contains("policy_reason=当前 heartbeat 检测到 drain 收口后仍需续跑，系统已自动排队 replay follow-up。"))
            #expect(userMessage.contains("governance_truth=治理真相：当前生效 A3/S3"))
            return "handled replay recovery"
        }

        _ = await manager.emitHeartbeatForTesting(
            force: true,
            reason: "timer",
            now: Date(timeIntervalSince1970: 1_773_384_320)
        )
        await manager.waitForSupervisorEventLoopForTesting()
        try await waitUntil("replay recovery runtime activity queued", timeoutMs: 5_000) {
            manager.runtimeActivityEntries.contains(where: {
                $0.projectId == project.projectId
                    && $0.text.contains("heartbeat_recovery_follow_up status=queued")
                    && $0.text.contains("recovery_action=replay_follow_up")
            })
        }

        let activity = try #require(manager.recentSupervisorEventLoopActivitiesForTesting().last(where: {
            $0.dedupeKey.hasPrefix("heartbeat_recovery_follow_up:")
                && $0.status == "completed"
        }))
        #expect(activity.projectId == project.projectId)
        #expect(activity.projectName == project.displayName)
        #expect(activity.triggerSource == "heartbeat")
        #expect(activity.triggerSummary.contains("需要重放 follow-up / 续跑链"))
        #expect(activity.resultSummary == "handled replay recovery")
        #expect(activity.policySummary.contains("cadence="))
        #expect(activity.governanceTruth.contains("治理真相：当前生效 A3/S3"))

        let entry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == project.projectId
                && $0.text.contains("heartbeat_recovery_follow_up status=queued")
        }))
        #expect(entry.projectName == project.displayName)
        #expect(entry.text.contains("recovery_action=replay_follow_up"))
        #expect(entry.text.contains("reason_code=restart_drain_requires_follow_up_replay"))
        #expect(entry.text.contains("governance_reason=当前 heartbeat 检测到 drain 收口后仍需续跑，系统已自动排队 replay follow-up。"))
        #expect(entry.text.contains("governance_truth=治理真相：当前生效 A3/S3"))
    }

    @Test
    func heartbeatHistoryHumanizesLaneHealthHotspotsForFrontstageCopy() throws {
        let manager = SupervisorManager.makeForTesting()

        let root = try makeRegistryVisibleProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: "Lane Runtime",
            lastOpenedAt: 1_773_384_320,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "当前泳道待处理",
            nextStepSummary: "查看泳道健康",
            blockerSummary: nil,
            lastSummaryAt: 1_773_384_280,
            lastEventAt: 1_773_384_280
        )
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setLaneHealthSnapshotForTesting(
            makeHeartbeatRecoveryLaneSnapshot(
                projectId: project.projectId,
                status: .blocked,
                blockedReason: .grantPending,
                nextActionRecommendation: "notify_user"
            )
        )

        manager.emitHeartbeatCycleForTesting(force: true, reason: "project_updated")

        let heartbeat = try #require(manager.latestHeartbeat)
        #expect(heartbeat.reason == "project_updated")
        #expect(heartbeat.content.contains("Lane 健康巡检："))
        #expect(heartbeat.content.contains("Lane Runtime"))
        #expect(heartbeat.content.contains("原因：等待授权"))
        #expect(!heartbeat.content.contains("reason="))
        #expect(!heartbeat.content.contains("action="))
        #expect(!heartbeat.content.contains("grant_pending"))
    }

    @Test
    func heartbeatGovernanceRepairRecordsRuntimeGovernanceTruthOncePerStableSignalSet() throws {
        let manager = SupervisorManager.makeForTesting()

        let root = try makeRegistryVisibleProjectRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a1Plan,
            supervisorInterventionTier: .s2PeriodicReview,
            reviewPolicyMode: .periodic,
            progressHeartbeatSeconds: 900,
            reviewPulseSeconds: 1_800,
            brainstormReviewSeconds: 0,
            eventDrivenReviewEnabled: false,
            eventReviewTriggers: []
        )
        try AXProjectStore.saveConfig(config, for: ctx)

        let project = makeProjectEntry(root: root, displayName: "Governance Repair Runtime")
        try SupervisorProjectSkillCallStore.upsert(
            SupervisorSkillCallRecord(
                schemaVersion: SupervisorSkillCallRecord.currentSchemaVersion,
                requestId: "skill-governance-runtime-1",
                projectId: project.projectId,
                jobId: "job-governance-runtime-1",
                planId: "plan-governance-runtime-1",
                stepId: "step-governance-runtime-1",
                skillId: "agent-browser",
                toolName: ToolName.deviceBrowserControl.rawValue,
                status: .blocked,
                payload: [
                    "action": .string("open_url"),
                    "url": .string("https://example.com")
                ],
                currentOwner: "supervisor",
                resultSummary: "browser automation blocked by governance",
                denyCode: "governance_capability_denied",
                policySource: "project_governance",
                policyReason: "execution_tier_missing_browser_runtime",
                resultEvidenceRef: nil,
                requiredCapability: nil,
                grantRequestId: nil,
                grantId: nil,
                createdAtMs: 1_000,
                updatedAtMs: 2_000,
                auditRef: "audit-governance-runtime-1"
            ),
            for: ctx
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)

        manager.emitHeartbeatCycleForTesting(force: true, reason: "project_created")

        let firstEntry = try #require(manager.runtimeActivityEntries.first(where: {
            $0.projectId == project.projectId
                && $0.text.contains("heartbeat_governance_repair status=attention")
        }))
        #expect(firstEntry.projectName == project.displayName)
        #expect(firstEntry.text.contains("trigger=heartbeat"))
        #expect(firstEntry.text.contains("repair_count=1"))
        #expect(firstEntry.text.contains("repair_destination=execution_tier"))
        #expect(firstEntry.text.contains("policy_reason=execution_tier_missing_browser_runtime"))
        #expect(firstEntry.text.contains("governance_reason=当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(firstEntry.text.contains("blocked_summary=当前项目 A-Tier 不允许浏览器自动化。"))
        #expect(firstEntry.text.contains("governance_truth=治理真相：当前生效 A1/S2 · 审查 Periodic · 节奏 心跳 15m / 脉冲 30m / 脑暴 off。"))

        manager.emitHeartbeatCycleForTesting(force: true, reason: "project_created")

        let repairEntries = manager.runtimeActivityEntries.filter {
            $0.projectId == project.projectId
                && $0.text.contains("heartbeat_governance_repair status=attention")
        }
        #expect(repairEntries.count == 1)
    }

    @Test
    func heartbeatAutoProgressRecoversBlockedAutomationRun() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "我的世界还原项目"
        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_600))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 30,
            auditRef: "audit-xt-auto-heartbeat-blocked",
            now: Date(timeIntervalSince1970: 1_773_201_601)
        )

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_700)
        )

        #expect(actions.count == 1)
        #expect(actions[0].contains("主动恢复"))
        #expect(actions[0].contains(project.displayName))
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
    }

    @Test
    func heartbeatAutoProgressRecoversBlockedAutomationRunOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Blocked Recovery"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_201_720,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: "自动化执行中",
            nextStepSummary: "等待下一次 heartbeat",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_220,
            lastEventAt: 1_773_201_220
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_201_721).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_722))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 30,
            auditRef: "audit-xt-auto-heartbeat-hidden-blocked",
            now: Date(timeIntervalSince1970: 1_773_201_723)
        )

        let actions = manager.runHeartbeatAutoProgressForTesting(
            now: Date(timeIntervalSince1970: 1_773_201_800)
        )

        #expect(actions.count == 1)
        #expect(actions[0].contains("主动恢复"))
        #expect(actions[0].contains(friendlyName))
        #expect(manager.automationRecoveryDecision?.decision == .resume)
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
    }

    @Test
    func heartbeatAutoProgressDefersHiddenBlockedRunUntilRetryAfterElapsesWithoutVisibleHeartbeatLeak() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Heartbeat Recovery Leak Guard"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: baseNow - 10,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: "自动化执行中",
            nextStepSummary: "等待 heartbeat 恢复",
            blockerSummary: nil,
            lastSummaryAt: baseNow - 60,
            lastEventAt: baseNow - 60
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: baseNow,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdictionNow = baseNow - 9
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: baseNow - 8))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 30,
            auditRef: "audit-xt-auto-heartbeat-hidden-blocked-no-leak",
            now: Date(timeIntervalSince1970: baseNow - 7)
        )

        manager.emitHeartbeatCycleForTesting(force: true, reason: "timer")

        #expect(manager.automationRecoveryDecision?.decision == .hold)
        #expect(manager.automationRecoveryDecision?.holdReason == "retry_after_not_elapsed")
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.heartbeatHistory.isEmpty)
    }

    @Test
    func externalTriggerIngressStartsRunAndFailClosesReplayAndCooldown() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "我的世界还原项目"
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_900,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let first = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-001",
                dedupeKey: "sha256:webhook-evt-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_900),
                ingressChannel: "test_webhook_bridge"
            )
        )

        #expect(first.decision == SupervisorManager.SupervisorAutomationExternalTriggerDecision.run)
        #expect(first.reasonCode == "trigger_route_allowed")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        let firstRunId = try #require(first.runId)
        let routeRowsAfterFirst = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRowsAfterFirst.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "run"
                && ($0["run_id"] as? String) == firstRunId
        })

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: firstRunId,
            auditRef: "audit-xt-auto-external-webhook-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_901)
        )

        let cooldown = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-002",
                dedupeKey: "sha256:webhook-evt-002",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_910),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(cooldown.decision == .drop)
        #expect(cooldown.reasonCode == "trigger_cooldown_active")

        let replay = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: project.projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/webhook-003",
                dedupeKey: "sha256:webhook-evt-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_940),
                ingressChannel: "test_webhook_bridge"
            )
        )
        #expect(replay.decision == .drop)
        #expect(replay.reasonCode == "external_trigger_replay_detected")

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "drop"
                && ($0["reason_code"] as? String) == "trigger_cooldown_active"
        })
        #expect(routeRows.contains {
            ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "drop"
                && ($0["reason_code"] as? String) == "external_trigger_replay_detected"
        })
    }

    @Test
    func externalTriggerIngressRunsWhenProjectOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden External Trigger"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_920,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: "等待外部触发",
            nextStepSummary: "接 webhook/github_pr",
            blockerSummary: nil,
            lastSummaryAt: 1_773_200_920,
            lastEventAt: 1_773_200_920
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_920,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_200_921)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: 1_773_200_921)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let result = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: "webhook/github_pr",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/hidden-webhook-001",
                dedupeKey: "sha256:hidden-webhook-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_922),
                ingressChannel: "test_webhook_bridge"
            )
        )

        #expect(result.decision == .run)
        #expect(result.reasonCode == "trigger_route_allowed")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.messages.isEmpty)
    }

    @Test
    func externalTriggerFailureSystemMessageUsesFriendlyProjectDisplayName() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "外出采购项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_950,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_950,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.clearMessages()

        let result = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: "webhook/not_allowed",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/not-allowed",
                dedupeKey: "sha256:not-allowed-001",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_951),
                ingressChannel: "test_webhook_bridge"
            ),
            emitSystemMessage: true
        )

        #expect(result.decision == .failClosed)
        #expect(result.reasonCode == "trigger_ingress_not_allowed")
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("automation 外部触发未执行：\(friendlyName) -> webhook/not_allowed (trigger_ingress_not_allowed)") &&
                !$0.content.contains(root.lastPathComponent)
        }))
    }

    @Test
    func externalTriggerFailureDoesNotLeakWhenProjectOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden External Trigger Failure"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_952,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: "等待隐藏失败触发",
            nextStepSummary: "故意触发 fail-closed",
            blockerSummary: nil,
            lastSummaryAt: 1_773_200_952,
            lastEventAt: 1_773_200_952
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_200_952,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_200_953)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: 1_773_200_953)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let result = manager.ingestAutomationExternalTrigger(
            SupervisorManager.SupervisorAutomationExternalTriggerIngress(
                projectId: projectId,
                triggerId: "webhook/not_allowed",
                triggerType: .webhook,
                source: .github,
                payloadRef: "local://trigger-payload/hidden-not-allowed",
                dedupeKey: "sha256:hidden-not-allowed",
                receivedAt: Date(timeIntervalSince1970: 1_773_200_954),
                ingressChannel: "test_webhook_bridge"
            ),
            emitSystemMessage: true
        )

        #expect(result.decision == .failClosed)
        #expect(result.reasonCode == "trigger_ingress_not_allowed")
        #expect(manager.messages.isEmpty)
    }

    @Test
    func scheduleServiceStartsRunOncePerWindowAndReopensOnNextWindow() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeScheduledLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_201_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let firstWindowAt = Date(timeIntervalSince1970: 1_773_201_000)
        let firstResults = manager.serviceAutomationScheduleTriggers(now: firstWindowAt)
        #expect(firstResults.count == 1)
        #expect(firstResults.first?.decision == SupervisorManager.SupervisorAutomationExternalTriggerDecision.run)
        #expect(firstResults.first?.triggerId == "schedule/nightly")
        let firstRunId = try #require(firstResults.first?.runId)

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: firstRunId,
            auditRef: "audit-xt-auto-schedule-delivered-1",
            now: Date(timeIntervalSince1970: 1_773_201_001)
        )

        let sameWindowResults = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_000 + 60 * 60)
        )
        #expect(sameWindowResults.isEmpty)

        let nextWindowResults = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_000 + 24 * 60 * 60 + 5)
        )
        #expect(nextWindowResults.count == 1)
        #expect(nextWindowResults.first?.decision == SupervisorManager.SupervisorAutomationExternalTriggerDecision.run)
        let nextRunId = try #require(nextWindowResults.first?.runId)
        #expect(nextRunId != firstRunId)
    }

    @Test
    func scheduleServiceStartsNewRunOnNextWindowAfterManualCancel() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeScheduledLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_201_100,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let firstWindowAt = Date(timeIntervalSince1970: 1_773_201_100)
        let firstResults = manager.serviceAutomationScheduleTriggers(now: firstWindowAt)
        #expect(firstResults.count == 1)
        #expect(firstResults.first?.decision == .run)
        let firstRunId = try #require(firstResults.first?.runId)

        let cancelled = try manager.cancelAutomationRun(
            for: ctx,
            runID: firstRunId,
            auditRef: "audit-xt-auto-schedule-cancelled",
            now: Date(timeIntervalSince1970: 1_773_201_101)
        )
        #expect(cancelled.decision == .suppressed)
        #expect(cancelled.holdReason == "manual_cancelled")

        let nextWindowResults = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_100 + 24 * 60 * 60 + 5)
        )
        #expect(nextWindowResults.count == 1)
        #expect(nextWindowResults.first?.decision == .run)
        let nextRunId = try #require(nextWindowResults.first?.runId)
        #expect(nextRunId != firstRunId)
    }

    @Test
    func scheduleServiceDoesNotTreatOlderBlockedRunAsCurrentBlockingRunWhenNewerVisibleRunIsDelivered() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeScheduledLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_201_150,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let blockedRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_140))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            runID: blockedRun.launchRef,
            auditRef: "audit-xt-auto-schedule-older-blocked",
            now: Date(timeIntervalSince1970: 1_773_201_141)
        )

        let deliveredRun = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_201_142))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: deliveredRun.launchRef,
            auditRef: "audit-xt-auto-schedule-newer-delivered",
            now: Date(timeIntervalSince1970: 1_773_201_143)
        )

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.lastAutomationLaunchRef = deliveredRun.launchRef
        try AXProjectStore.saveConfig(config, for: ctx)

        let results = manager.serviceAutomationScheduleTriggers(
            now: Date(timeIntervalSince1970: 1_773_201_150)
        )

        #expect(results.count == 1)
        #expect(results.first?.decision == .run)
        let nextRunId = try #require(results.first?.runId)
        #expect(nextRunId != blockedRun.launchRef)
        #expect(nextRunId != deliveredRun.launchRef)
    }

    @Test
    func scheduleServiceStartsRunWhenProjectOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeScheduledLiveIngressRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Schedule Trigger"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_201_010,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "paused",
            currentStateSummary: "等待定时调度",
            nextStepSummary: "schedule/nightly",
            blockerSummary: nil,
            lastSummaryAt: 1_773_201_010,
            lastEventAt: 1_773_201_010
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_201_010,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_201_011)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: 1_773_201_011)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let results = manager.serviceAutomationScheduleTriggers(now: Date(timeIntervalSince1970: 1_773_201_000))
        #expect(results.count == 1)
        #expect(results.first?.decision == .run)
        #expect(results.first?.triggerId == "schedule/nightly")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.messages.isEmpty)
    }

    @Test
    @MainActor
    func hubConnectorIngressSnapshotFailClosesUnsupportedSourceAndRoutesDeclaredWebhook() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_202_000,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )
        manager.clearMessages()

        let snapshot = HubIPCClient.ConnectorIngressSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_202_060_000,
            items: [
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-unsupported-001",
                    requestId: "req-hub-unsupported-001",
                    projectId: project.projectId,
                    connector: "discord",
                    targetId: "room-1",
                    ingressType: "connector_event",
                    channelScope: "dm",
                    sourceId: "user-1",
                    messageId: "msg-unsupported-001",
                    dedupeKey: "sha256:hub-unsupported-001",
                    receivedAtMs: 1_773_202_010_000,
                    eventSequence: 17,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                ),
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-webhook-001",
                    requestId: "req-hub-webhook-001",
                    projectId: project.projectId,
                    connector: "github",
                    targetId: "repo-1",
                    ingressType: "webhook",
                    channelScope: "repo",
                    sourceId: "pr-42",
                    messageId: "msg-webhook-001",
                    dedupeKey: "sha256:hub-webhook-001",
                    receivedAtMs: 1_773_202_020_000,
                    eventSequence: 18,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                )
            ]
        )

        let firstPass = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_060)
        )
        #expect(firstPass.count == 2)
        #expect(firstPass.first?.decision == .failClosed)
        #expect(firstPass.first?.reasonCode == "hub_ingress_source_unsupported")
        #expect(firstPass.last?.decision == SupervisorManager.SupervisorAutomationExternalTriggerDecision.run)
        #expect(firstPass.last?.triggerId == "webhook/github_pr")
        let runId = try #require(firstPass.last?.runId)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("Discord") &&
                $0.content.contains("失败闭锁")
        }))
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("GitHub") &&
                $0.content.contains("已转入 XT automation")
        }))
        #expect(spoken.contains(where: {
            $0.contains("Discord") &&
                $0.contains("失败闭锁")
        }))
        #expect(spoken.contains(where: {
            $0.contains("GitHub") &&
                $0.contains("远程入口")
        }))

        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: runId,
            auditRef: "audit-xt-auto-hub-connector-delivered",
            now: Date(timeIntervalSince1970: 1_773_202_061)
        )

        let secondPass = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_090)
        )
        #expect(secondPass.isEmpty)

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["decision"] as? String) == "fail_closed"
                && ($0["reason_code"] as? String) == "hub_ingress_source_unsupported"
        })
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["trigger_id"] as? String) == "webhook/github_pr"
                && ($0["decision"] as? String) == "run"
                && ($0["run_id"] as? String) == runId
        })
    }

    @Test
    @MainActor
    func hubConnectorIngressSnapshotRoutesHiddenProjectWithoutVisibleAnnouncements() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "Hidden Connector Ingress"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_202_200,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "active",
            currentStateSummary: "等待 Hub connector ingress",
            nextStepSummary: "webhook/github_pr",
            blockerSummary: nil,
            lastSummaryAt: 1_773_202_200,
            lastEventAt: 1_773_202_200
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_202_200,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_202_201)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: 1_773_202_201)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
        manager.clearMessages()

        let snapshot = HubIPCClient.ConnectorIngressSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_202_260_000,
            items: [
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-hidden-webhook-001",
                    requestId: "req-hub-hidden-webhook-001",
                    projectId: projectId,
                    connector: "github",
                    targetId: "repo-hidden-1",
                    ingressType: "webhook",
                    channelScope: "repo",
                    sourceId: "pr-hidden-42",
                    messageId: "msg-hidden-webhook-001",
                    dedupeKey: "sha256:hub-hidden-webhook-001",
                    receivedAtMs: 1_773_202_220_000,
                    eventSequence: 28,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                )
            ]
        )

        let results = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_260)
        )
        #expect(results.count == 1)
        #expect(results.first?.decision == .run)
        #expect(results.first?.triggerId == "webhook/github_pr")
        #expect(manager.automationCurrentCheckpoint?.state == .queued)
        #expect(manager.messages.isEmpty)
        #expect(spoken.isEmpty)
    }

    @Test
    @MainActor
    func hubConnectorIngressSnapshotHoldsBusyProjectAndAnnouncesBrief() throws {
        var spoken: [String] = []
        let synthesizer = SupervisorSpeechSynthesizer(
            deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
            speakSink: { spoken.append($0) }
        )
        let manager = SupervisorManager.makeForTesting(
            supervisorSpeechSynthesizer: synthesizer
        )
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeLiveIngressRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 1_773_202_100,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )
        manager.clearMessages()

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_202_100)),
            emitSystemMessage: false
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        let snapshot = HubIPCClient.ConnectorIngressSnapshot(
            source: "hub_runtime_grpc",
            updatedAtMs: 1_773_202_110_000,
            items: [
                HubIPCClient.ConnectorIngressReceipt(
                    receiptId: "hub-slack-hold-001",
                    requestId: "req-hub-slack-hold-001",
                    projectId: project.projectId,
                    connector: "slack",
                    targetId: "dm-9",
                    ingressType: "connector_event",
                    channelScope: "dm",
                    sourceId: "user-9",
                    messageId: "msg-slack-hold-001",
                    dedupeKey: "sha256:hub-slack-hold-001",
                    receivedAtMs: 1_773_202_105_000,
                    eventSequence: 21,
                    deliveryState: "accepted",
                    runtimeState: "queued"
                )
            ]
        )

        let results = manager.serviceHubConnectorIngressReceiptsForTesting(
            snapshot,
            now: Date(timeIntervalSince1970: 1_773_202_110)
        )
        #expect(results.count == 1)
        #expect(results.first?.decision == .hold)
        #expect(results.first?.reasonCode == "automation_active_run_present")
        #expect(manager.messages.contains(where: {
            $0.role == .system &&
                $0.content.contains("Slack") &&
                $0.content.contains("暂缓")
        }))
        #expect(spoken.contains(where: {
            $0.contains("Slack") &&
                $0.contains("暂缓")
        }))

        let routeRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_external_trigger_route"
        }
        #expect(routeRows.contains {
            ($0["ingress_channel"] as? String) == "hub_connector_receipt_snapshot"
                && ($0["decision"] as? String) == "hold"
                && ($0["reason_code"] as? String) == "automation_active_run_present"
        })
    }

    @Test
    func operatorChannelXTCommandPrepareDeployPlanUsesPrepareOnlyPathAndPersistsResult() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetAutomationRuntimeState()

            let originalMode = HubAIClient.transportMode()
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_operator_channel_test_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)

            let root = try makeRegistryVisibleProjectRoot()
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                manager.resetAutomationRuntimeState()
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.removeItem(at: hubBase)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_202_300,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: project.projectId,
                projects: [project]
            )
            manager.setAppModel(appModel)
            manager.clearMessages()

            let snapshot = HubIPCClient.OperatorChannelXTCommandSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_202_301_000,
                items: [
                    HubIPCClient.OperatorChannelXTCommandItem(
                        commandId: "cmd-op-1",
                        requestId: "req-op-1",
                        actionName: "deploy.plan",
                        bindingId: "binding-op-1",
                        routeId: "route-op-1",
                        scopeType: "project",
                        scopeId: project.projectId,
                        projectId: project.projectId,
                        provider: "slack",
                        accountId: "ops-slack",
                        conversationId: "C123",
                        threadKey: "1710000000.0001",
                        actorRef: "xhub.im_identity_binding.v1:slack/U123",
                        resolvedDeviceId: "device_xt_001",
                        preferredDeviceId: "device_xt_001",
                        note: "",
                        createdAtMs: 1_773_202_300_500,
                        auditRef: "audit-op-1"
                    )
                ]
            )

            let results = manager.serviceOperatorChannelXTCommandsForTesting(
                snapshot,
                now: Date(timeIntervalSince1970: 1_773_202_302)
            )
            #expect(results.count == 1)
            let first = try #require(results.first)
            #expect(first.commandId == "cmd-op-1")
            #expect(first.status == "prepared")
            #expect(first.actionName == "deploy.plan")
            #expect(first.projectId == project.projectId)
            let runId = try #require(first.runId.isEmpty ? nil : first.runId)
            #expect(manager.automationPreparedRun?.launchRef == runId)
            #expect(manager.automationCurrentCheckpoint?.state == .queued)

            let stored = await HubIPCClient.requestOperatorChannelXTCommandResults(projectId: project.projectId, limit: 10)
            #expect(stored?.items.first?.commandId == "cmd-op-1")
            #expect(stored?.items.first?.status == "prepared")

            let commandRows = try rawLogEntries(for: ctx).filter {
                ($0["type"] as? String) == "operator_channel_xt_command"
            }
            #expect(commandRows.contains {
                ($0["phase"] as? String) == "prepared"
                    && ($0["command_id"] as? String) == "cmd-op-1"
                    && ($0["run_id"] as? String) == runId
            })
            #expect(manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("Slack") &&
                    $0.content.contains("已准备执行")
            }))
            #expect(spoken.contains(where: {
                $0.contains("Slack") &&
                    $0.contains("XT 指令")
            }))
        }
    }

    @Test
    func operatorChannelXTCommandPrepareDeployPlanRunsForHiddenProjectWithoutVisibleAnnouncements() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetAutomationRuntimeState()

            let originalMode = HubAIClient.transportMode()
            let hubBase = FileManager.default.temporaryDirectory
                .appendingPathComponent("xt_operator_channel_hidden_test_\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: hubBase, withIntermediateDirectories: true)
            HubAIClient.setTransportMode(.fileIPC)
            HubPaths.setPinnedBaseDirOverride(hubBase)

            let root = try makeRegistryVisibleProjectRoot()
            defer {
                HubAIClient.setTransportMode(originalMode)
                HubPaths.clearPinnedBaseDirOverride()
                manager.resetAutomationRuntimeState()
                try? FileManager.default.removeItem(at: root)
                try? FileManager.default.removeItem(at: hubBase)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let projectId = AXProjectRegistryStore.projectId(forRoot: root)
            let friendlyName = "Hidden Operator Command"
            let project = AXProjectEntry(
                projectId: projectId,
                rootPath: root.path,
                displayName: friendlyName,
                lastOpenedAt: 1_773_202_500,
                manualOrderIndex: nil,
                pinned: false,
                statusDigest: "active",
                currentStateSummary: "等待 operator command",
                nextStepSummary: "deploy.plan",
                blockerSummary: nil,
                lastSummaryAt: 1_773_202_500,
                lastEventAt: 1_773_202_500
            )
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_202_500,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: projectId,
                projects: [project]
            )
            manager.setAppModel(appModel)

            let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: 1_773_202_501)
                .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: 1_773_202_501)
            _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)
            manager.clearMessages()

            let snapshot = HubIPCClient.OperatorChannelXTCommandSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_202_501_000,
                items: [
                    HubIPCClient.OperatorChannelXTCommandItem(
                        commandId: "cmd-op-hidden-1",
                        requestId: "req-op-hidden-1",
                        actionName: "deploy.plan",
                        bindingId: "binding-op-hidden-1",
                        routeId: "route-op-hidden-1",
                        scopeType: "project",
                        scopeId: projectId,
                        projectId: projectId,
                        provider: "slack",
                        accountId: "ops-slack",
                        conversationId: "C999",
                        threadKey: "1710000000.9999",
                        actorRef: "xhub.im_identity_binding.v1:slack/U999",
                        resolvedDeviceId: "device_xt_001",
                        preferredDeviceId: "device_xt_001",
                        note: "",
                        createdAtMs: 1_773_202_500_500,
                        auditRef: "audit-op-hidden-1"
                    )
                ]
            )

            let results = manager.serviceOperatorChannelXTCommandsForTesting(
                snapshot,
                now: Date(timeIntervalSince1970: 1_773_202_502)
            )
            #expect(results.count == 1)
            let first = try #require(results.first)
            #expect(first.status == "prepared")
            #expect(first.projectId == projectId)
            #expect(manager.automationPreparedRun?.launchRef == first.runId)
            #expect(manager.messages.isEmpty)
            #expect(spoken.isEmpty)
        }
    }

    @Test
    func operatorChannelXTCommandFailsClosedWhenProjectBindingDoesNotMatchRoutedDevice() async throws {
        try await Self.gate.run {
            var spoken: [String] = []
            let synthesizer = SupervisorSpeechSynthesizer(
                deduper: SupervisorVoiceBriefDeduper(cooldown: 0),
                speakSink: { spoken.append($0) }
            )
            let manager = SupervisorManager.makeForTesting(
                supervisorSpeechSynthesizer: synthesizer
            )
            manager.resetAutomationRuntimeState()

            let root = try makeRegistryVisibleProjectRoot()
            defer {
                manager.resetAutomationRuntimeState()
                try? FileManager.default.removeItem(at: root)
            }

            let ctx = AXProjectContext(root: root)
            _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
            try armTrustedAutomation(for: ctx)
            let project = makeProjectEntry(root: root)
            let appModel = AppModel()
            appModel.registry = AXProjectRegistry(
                version: AXProjectRegistry.currentVersion,
                updatedAt: 1_773_202_400,
                sortPolicy: "manual_then_last_opened",
                globalHomeVisible: false,
                lastSelectedProjectId: project.projectId,
                projects: [project]
            )
            appModel.selectedProjectId = project.projectId
            manager.setAppModel(appModel)
            manager.clearMessages()

            let snapshot = HubIPCClient.OperatorChannelXTCommandSnapshot(
                source: "hub_runtime_grpc",
                updatedAtMs: 1_773_202_401_000,
                items: [
                    HubIPCClient.OperatorChannelXTCommandItem(
                        commandId: "cmd-op-mismatch",
                        requestId: "req-op-mismatch",
                        actionName: "deploy.plan",
                        bindingId: "binding-op-1",
                        routeId: "route-op-1",
                        scopeType: "project",
                        scopeId: project.projectId,
                        projectId: project.projectId,
                        provider: "slack",
                        accountId: "ops-slack",
                        conversationId: "C123",
                        threadKey: "1710000000.0002",
                        actorRef: "xhub.im_identity_binding.v1:slack/U123",
                        resolvedDeviceId: "device_xt_999",
                        preferredDeviceId: "device_xt_999",
                        note: "",
                        createdAtMs: 1_773_202_400_500,
                        auditRef: "audit-op-mismatch"
                    )
                ]
            )

            let first = manager.executeOperatorChannelXTCommandForTesting(
                snapshot.items[0],
                project: project,
                now: Date(timeIntervalSince1970: 1_773_202_402)
            )
            #expect(first.status == "failed")
            #expect(first.denyCode == "trusted_automation_project_not_bound")
            #expect(first.runId.isEmpty)
            #expect(manager.automationPreparedRun == nil)

            let commandRows = try rawLogEntries(for: ctx).filter {
                ($0["type"] as? String) == "operator_channel_xt_command"
            }
            #expect(commandRows.contains {
                ($0["phase"] as? String) == "failed"
                    && ($0["command_id"] as? String) == "cmd-op-mismatch"
                    && ($0["deny_code"] as? String) == "trusted_automation_project_not_bound"
            })
            try await waitUntil("operator xt fail-closed announcement visible") {
                manager.messages.contains(where: {
                    $0.role == .system &&
                        $0.content.contains("失败闭锁") &&
                        $0.content.contains("trusted_automation_project_not_bound")
                }) &&
                spoken.contains(where: {
                    $0.contains("Slack") &&
                        $0.contains("失败闭锁")
                })
            }
            #expect(manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("失败闭锁") &&
                    $0.content.contains("trusted_automation_project_not_bound")
            }))
            #expect(spoken.contains(where: {
                $0.contains("Slack") &&
                    $0.contains("失败闭锁")
            }))
        }
    }

    @Test
    func naturalLanguageAutomationStatusAndCancelMapToRuntimeCommands() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_000))
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)
        #expect(manager.automationCurrentCheckpoint?.state == .queued)

        let statusText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("亮亮的自动流程现在怎么样")
        )
        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(project.displayName)"))
        #expect(statusText.contains("last_launch: \(prepared.launchRef)"))

        let cancelText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先暂停亮亮的自动流程")
        )
        #expect(cancelText.contains("🛑 automation 已取消"))
        #expect(cancelText.contains("run_id: \(prepared.launchRef)"))
    }

    @Test
    func naturalLanguageAutomationCancelPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-cancel-grant-1",
                    dedupeKey: "automation-cancel-grant-1",
                    grantRequestId: "automation-cancel-grant-1",
                    requestId: "req-automation-cancel-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_050))
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)

        let cancelText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("先暂停亮亮的自动流程")
        )

        #expect(cancelText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(cancelText.contains("Hub 待处理授权"))
        #expect(cancelText.contains("查看：查看授权板"))
        #expect(cancelText.contains("🛑 automation 已取消"))
        #expect(cancelText.contains("run_id: \(prepared.launchRef)"))
    }

    @Test
    func naturalLanguageAutomationExplicitHiddenProjectStillResolvesOutsideJurisdictionView() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 1_773_384_520).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(projectId: project.projectId, displayName: project.displayName, role: .triageOnly, now: now)
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_060))
        )
        #expect(manager.automationCurrentCheckpoint?.runID == prepared.launchRef)

        let statusText = try #require(
            manager.directSupervisorActionIfApplicableForTesting("亮亮的自动流程现在怎么样")
        )
        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(project.displayName)"))
        #expect(statusText.contains("last_launch: \(prepared.launchRef)"))
        #expect(!statusText.contains("project_not_found"))
    }

    @Test
    func automationStatusPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-status-grant-1",
                    dedupeKey: "automation-status-grant-1",
                    grantRequestId: "automation-status-grant-1",
                    requestId: "req-automation-status-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )

        #expect(statusText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(statusText.contains("Hub 待处理授权"))
        #expect(statusText.contains("查看：查看授权板"))
        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(project.displayName)"))
    }

    @Test
    func automationStatusDoesNotLeakGovernanceBriefFromOtherProject() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-governance-only",
            rootPath: rootA.appendingPathComponent("beta-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-status-other-project-grant-1",
                    dedupeKey: "automation-status-other-project-grant-1",
                    grantRequestId: "automation-status-other-project-grant-1",
                    requestId: "req-automation-status-other-project-grant-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(projectA.projectId)")
        )

        #expect(statusText.contains("🤖 Automation Runtime 状态"))
        #expect(statusText.contains("项目: \(projectA.displayName)"))
        #expect(statusText.contains("🧭 Supervisor Brief") == false)
        #expect(statusText.contains("查看：查看授权板") == false)
    }

    @Test
    func automationRecoverPrependsProjectScopedGovernanceBriefForPendingSkillApproval() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-recover-approval-1",
                    requestId: "automation-recover-approval-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看失败后的页面状态",
                    reason: "需要人工确认恢复前的页面操作",
                    createdAt: baseNow - 30,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-recover-governance-brief",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(recoveryText.contains("待审批技能"))
        #expect(recoveryText.contains("查看：查看技能审批"))
        #expect(recoveryText.contains("♻️ automation 恢复判定"))
        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
    }

    @Test
    func automationRecoverPrependsProjectScopedGovernanceBriefForPendingSkillGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                makeGovernedAutomationPendingSkillApproval(
                    requestId: "automation-recover-grant-1",
                    project: project,
                    createdAt: baseNow - 30,
                    executionReadiness: XTSkillExecutionReadinessState.grantRequired.rawValue,
                    approvalFloor: XTSkillApprovalFloor.hubGrant.rawValue,
                    requiredGrantCapabilities: ["browser.interact"],
                    unblockActions: ["request_hub_grant"]
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctx,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-recover-governance-grant-brief",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)")
        )

        #expect(recoveryText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(recoveryText.contains("技能授权待处理"))
        #expect(recoveryText.contains("查看：查看技能授权"))
        #expect(recoveryText.contains("♻️ automation 恢复判定"))
        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
    }

    @Test
    func automationRecoverDoesNotLeakGovernanceBriefFromOtherProject() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        let baseNow = Date().timeIntervalSince1970

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-recover-governance-only",
            rootPath: rootA.appendingPathComponent("beta-recover-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-recover-other-project-approval-1",
                    requestId: "automation-recover-other-project-approval-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看失败后的页面状态",
                    reason: "需要人工确认恢复前的页面操作",
                    createdAt: baseNow - 30,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let prepared = try manager.prepareAutomationRun(
            for: ctxA,
            request: makeRequest(now: Date(timeIntervalSince1970: baseNow - 10))
        )
        _ = try manager.advanceAutomationRun(
            for: ctxA,
            to: .blocked,
            retryAfterSeconds: 120,
            auditRef: "audit-xt-auto-recover-governance-no-leak",
            now: Date(timeIntervalSince1970: baseNow - 9)
        )

        let recoveryText = try #require(
            manager.performAutomationRuntimeCommand("/automation recover \(projectA.projectId)")
        )

        #expect(recoveryText.contains("♻️ automation 恢复判定"))
        #expect(recoveryText.contains("run_id: \(prepared.launchRef)"))
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("🧭 Supervisor Brief") == false)
        #expect(recoveryText.contains("查看：查看技能审批") == false)
    }

    @Test
    func automationStartPrependsProjectScopedGovernanceBriefForPendingGrant() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            AXTrustedAutomationPermissionOwnerReadiness(
                schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                ownerID: "owner-xt",
                ownerType: "xterminal_app",
                bundleID: "com.xterminal.app",
                installState: "ready",
                mode: "managed_or_prompted",
                accessibility: .granted,
                automation: .granted,
                screenRecording: .missing,
                fullDiskAccess: .missing,
                inputMonitoring: .missing,
                canPromptUser: true,
                managedByMDM: false,
                overallState: "ready",
                openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                auditRef: "audit-xt-auto-start-governance-brief"
            )
        }

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        try armTrustedAutomation(for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-start-grant-1",
                    dedupeKey: "automation-start-grant-1",
                    grantRequestId: "automation-start-grant-1",
                    requestId: "req-automation-start-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let startText = try #require(
            manager.performAutomationRuntimeCommand("/automation start \(project.projectId)")
        )

        #expect(startText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(startText.contains("Hub 待处理授权"))
        #expect(startText.contains("查看：查看授权板"))
        #expect(startText.contains("✅ automation 已启动准备"))
        #expect(startText.contains("项目: \(project.displayName)"))
    }

    @Test
    func automationStartDoesNotLeakGovernanceBriefFromOtherProject() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()
        AXTrustedAutomationPermissionOwnerReadiness.installCurrentProviderForTesting {
            AXTrustedAutomationPermissionOwnerReadiness(
                schemaVersion: AXTrustedAutomationPermissionOwnerReadiness.currentSchemaVersion,
                ownerID: "owner-xt",
                ownerType: "xterminal_app",
                bundleID: "com.xterminal.app",
                installState: "ready",
                mode: "managed_or_prompted",
                accessibility: .granted,
                automation: .granted,
                screenRecording: .missing,
                fullDiskAccess: .missing,
                inputMonitoring: .missing,
                canPromptUser: true,
                managedByMDM: false,
                overallState: "ready",
                openSettingsActions: AXTrustedAutomationPermissionKey.allCases.map { $0.openSettingsAction },
                auditRef: "audit-xt-auto-start-governance-no-leak"
            )
        }

        let rootA = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            AXTrustedAutomationPermissionOwnerReadiness.resetCurrentProviderForTesting()
            try? FileManager.default.removeItem(at: rootA)
        }

        let ctxA = AXProjectContext(root: rootA)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctxA)
        try armTrustedAutomation(for: ctxA)

        var projectA = makeProjectEntry(root: rootA)
        projectA.displayName = "Alpha"
        let projectB = AXProjectEntry(
            projectId: "project-beta-governance-only",
            rootPath: rootA.appendingPathComponent("beta-governance-only").path,
            displayName: "Beta",
            lastOpenedAt: Date().timeIntervalSince1970,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: projectA.projectId,
            projects: [projectA, projectB]
        )
        appModel.selectedProjectId = projectA.projectId
        manager.setAppModel(appModel)
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-start-other-project-grant-1",
                    dedupeKey: "automation-start-other-project-grant-1",
                    grantRequestId: "automation-start-other-project-grant-1",
                    requestId: "req-automation-start-other-project-grant-1",
                    projectId: projectB.projectId,
                    projectName: projectB.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        let startText = try #require(
            manager.performAutomationRuntimeCommand("/automation start \(projectA.projectId)")
        )

        #expect(startText.contains("✅ automation 已启动准备"))
        #expect(startText.contains("项目: \(projectA.displayName)"))
        #expect(startText.contains("🧭 Supervisor Brief") == false)
        #expect(startText.contains("查看：查看授权板") == false)
    }

    @Test
    func automationSelfIterateStatusPrependsProjectScopedGovernanceBriefForPendingSkillApproval() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        manager.setAppModel(appModel)
        manager.setPendingSupervisorSkillApprovalsForTesting(
            [
                SupervisorManager.SupervisorPendingSkillApproval(
                    id: "automation-self-iterate-approval-1",
                    requestId: "automation-self-iterate-approval-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    jobId: "job-1",
                    planId: "plan-1",
                    stepId: "step-1",
                    skillId: "agent-browser",
                    toolName: "browser.open",
                    tool: nil,
                    toolSummary: "打开浏览器查看当前自动化页面状态",
                    reason: "需要人工确认后再继续",
                    createdAt: 1_000,
                    actionURL: nil,
                    routingReasonCode: nil,
                    routingExplanation: nil
                )
            ]
        )

        let statusText = try #require(
            manager.performAutomationRuntimeCommand("/automation self-iterate status \(project.projectId)")
        )

        #expect(statusText.contains("🧭 Supervisor Brief · 亮亮"))
        #expect(statusText.contains("待审批技能"))
        #expect(statusText.contains("查看：查看技能审批"))
        #expect(statusText.contains("🧠 automation self-iterate 状态"))
        #expect(statusText.contains("self_iterate_mode: disabled"))
    }

    @Test
    func automationSelfIterateCommandsUpdateProjectConfigAndSelectedSnapshot() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)

        let appModel = makeTestingAppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        await appModel.waitForPendingSelectionWorkForTesting()
        appModel.projectContext = ctx
        appModel.projectConfig = try AXProjectStore.loadOrCreateConfig(for: ctx)
        manager.setAppModel(appModel)

        let enableText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate on \(project.projectId)"))
        #expect(enableText.contains("self_iterate_mode: enabled"))
        #expect(appModel.projectConfig?.automationSelfIterateEnabled == true)

        let maxText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate max 3 \(project.projectId)"))
        #expect(maxText.contains("self_iterate_max_auto_retry_depth: 3"))
        #expect(appModel.projectConfig?.automationMaxAutoRetryDepth == 3)

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate status \(project.projectId)"))
        #expect(statusText.contains("behavior: bounded_auto_retry_only"))

        let reloaded = try AXProjectStore.loadOrCreateConfig(for: ctx)
        #expect(reloaded.automationSelfIterateEnabled == true)
        #expect(reloaded.automationMaxAutoRetryDepth == 3)

        let disableText = try #require(manager.performAutomationRuntimeCommand("/automation self-iterate off \(project.projectId)"))
        #expect(disableText.contains("self_iterate_mode: disabled"))
        #expect(appModel.projectConfig?.automationSelfIterateEnabled == false)
    }

    @Test
    func automationStartRunExecutesRecipeActionGraphInBackground() async throws {
        try await Self.runtimeGate.runOnMainActor {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_100)),
            emitSystemMessage: false
        )
        #expect(prepared.currentCheckpoint.state == .queued)

        try await waitUntil("automation action graph delivered") {
            manager.automationCurrentCheckpoint?.state == .delivered
        }

        if manager.automationLatestExecutionReport == nil {
            let checkpointState = manager.automationCurrentCheckpoint?.state.rawValue ?? "nil"
            let checkpointTransition = manager.automationCurrentCheckpoint?.lastTransition ?? "nil"
            let rawLogTail: [String] = (try? Array(rawLogEntries(for: ctx).suffix(6)).map { entry in
                let type = (entry["type"] as? String) ?? "?"
                let phase = (entry["phase"] as? String) ?? ""
                let state = (entry["state"] as? String) ?? ""
                let detail = (entry["detail"] as? String) ?? ""
                return [type, phase, state, detail]
                    .filter { !$0.isEmpty }
                    .joined(separator: "|")
            }) ?? []
            Issue.record(
                "automation execution missing report status=\(manager.automationStatusLine) checkpoint_state=\(checkpointState) checkpoint_transition=\(checkpointTransition) raw_log_tail=\(rawLogTail.joined(separator: " || "))"
            )
        }

        #expect(manager.automationLatestExecutionReport?.executedActionCount == 1)
        #expect(manager.automationLatestExecutionReport?.finalState == .delivered)
        let handoffPath = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)
        #expect(handoffPath.contains("build/reports/xt_automation_run_handoff_"))
        }
    }

    @Test
    func automationExecutionSystemSummaryPrependsProjectScopedGovernanceBriefForPendingGrant() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        try armRepoAutomationGovernance(for: ctx)
        var project = makeProjectEntry(root: root)
        project.displayName = "亮亮"

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: project.projectId,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        manager.setAppModel(appModel)
        manager.clearMessages()
        manager.setPendingHubGrantsForTesting(
            [
                SupervisorManager.SupervisorPendingGrant(
                    id: "automation-execution-grant-1",
                    dedupeKey: "automation-execution-grant-1",
                    grantRequestId: "automation-execution-grant-1",
                    requestId: "req-automation-execution-grant-1",
                    projectId: project.projectId,
                    projectName: project.displayName,
                    capability: "device_authority",
                    modelId: "",
                    reason: "需要批准设备级权限后继续自动化",
                    requestedTtlSec: 3600,
                    requestedTokenCap: 12_000,
                    createdAt: 1_000,
                    actionURL: nil,
                    priorityRank: 1,
                    priorityReason: "release_path",
                    nextAction: "打开授权并批准设备级权限"
                )
            ]
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_203_101)),
            emitSystemMessage: true
        )

        try await waitUntil(
            "automation action graph delivered for execution summary",
            timeoutMs: 10_000
        ) {
            manager.automationLatestExecutionReport?.finalState == .delivered
        }

        #expect(
            manager.messages.contains(where: {
                $0.role == .system &&
                    $0.content.contains("🧭 Supervisor Brief · 亮亮") &&
                    $0.content.contains("Hub 待处理授权") &&
                    $0.content.contains("查看：查看授权板") &&
                    $0.content.contains("⚙️ automation 自动执行完成")
            })
        )
    }

    @Test
    func automationStartSafePointHoldPausesBeforeExecutorAndRunsSupervisorFollowUp() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        try await waitUntil("app model selected project for safe point hold") {
            appModel.projectContext?.root == root
        }
        manager.setAppModel(appModel)
        _ = manager.applySupervisorJurisdictionRegistry(
            .ownerAll(for: [project]),
            persist: false,
            normalizeWithKnownProjects: true
        )

        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, rootURL in
                await counter.increment(call.tool)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=\(rootURL.path)")
            }
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("trigger=automation_safe_point"))
            #expect(userMessage.contains("requested_state=running"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-start-1"))
            #expect(userMessage.contains("guidance_summary=执行 action graph 前先停下，让 supervisor 重审方案。"))
            #expect(!userMessage.contains("guidance_text="))
            return """
            1. 先确认为什么要在当前 safe point 暂停。
            2. 对照 guidance 判断是否需要重排 action graph。
            3. 给 coder 一个可执行的下一步。
            """
        }

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-start-1",
                reviewId: "review-auto-safe-point-start-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "执行 action graph 前先停下，让 supervisor 重审方案。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_700_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-start-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_701)),
            emitSystemMessage: false
        )

        try await waitUntil("automation safe point hold before execution") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await counter.count(for: .project_snapshot) == 0)
        #expect(await followUpFlag.value())
        #expect(manager.automationLatestExecutionReport == nil)

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-start-1"
        })
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_execution" &&
            ($0["phase"] as? String) == "started" &&
            ($0["run_id"] as? String) == prepared.launchRef
        } == false)
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先确认为什么要在当前 safe point 暂停")
        })
    }

    @Test
    func automationStartSafePointHoldRunsSupervisorFollowUpOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "我的世界还原项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_700,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_700).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, rootURL in
                await counter.increment(call.tool)
                return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=\(rootURL.path)")
            }
        )
        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("trigger=automation_safe_point"))
            #expect(userMessage.contains("project_ref=\(friendlyName)"))
            #expect(userMessage.contains("requested_state=running"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-hidden-start-1"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return """
            1. 先解释为什么 hidden 项目要在当前 safe point 暂停。
            2. 对照 guidance 判断 action graph 是否还要重排。
            3. 给 coder 一个可执行的下一步。
            """
        }

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-hidden-start-1",
                reviewId: "review-auto-safe-point-hidden-start-1",
                projectId: projectId,
                targetRole: .coder,
                deliveryMode: .replanRequest,
                interventionMode: .replanNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "hidden 项目在执行 action graph 前也要先停下，让 supervisor 重审方案。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_700_000,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-hidden-start-1"
            ),
            for: ctx
        )

        let prepared = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_701)),
            emitSystemMessage: false
        )

        try await waitUntil("hidden automation safe point hold before execution") {
            manager.automationCurrentCheckpoint?.runID == prepared.launchRef &&
            manager.automationCurrentCheckpoint?.state == .blocked
        }
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await counter.count(for: .project_snapshot) == 0)
        #expect(await followUpFlag.value())
        #expect(manager.automationLatestExecutionReport == nil)

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.running.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-hidden-start-1"
        })
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_execution" &&
            ($0["phase"] as? String) == "started" &&
            ($0["run_id"] as? String) == prepared.launchRef
        } == false)
        try await waitUntil("hidden start safe point follow-up assistant message visible", timeoutMs: 30_000) {
            manager.messages.contains {
                $0.role == .assistant && $0.content.contains("先解释为什么 hidden 项目要在当前 safe point 暂停")
            }
        }
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先解释为什么 hidden 项目要在当前 safe point 暂停")
        })
    }

    @Test
    func automationSafePointHoldAfterExecutionRunsSupervisorFollowUp() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        appModel.selectedProjectId = project.projectId
        try await waitUntil("app model selected project for post execution hold") {
            appModel.projectContext?.root == root
        }
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("requested_state=delivered"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-finish-1"))
            return """
            1. 先审查这次 automation 产物是否已经满足 done definition。
            2. 如果 guidance 要求延后交付，就重新决定下一步是复核、replan 还是放行。
            3. 输出给 coder 的具体执行建议。
            """
        }

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_800))
        )
        let running = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-running-before-post-safe-point",
            now: Date(timeIntervalSince1970: 1_773_200_801),
            emitSystemMessage: false
        )
        #expect(running.state == .running)

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-finish-1",
                reviewId: "review-auto-safe-point-finish-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "动作跑完了，但先别交付，给 supervisor 一次 review 窗口。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_800_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-finish-1"
            ),
            for: ctx
        )

        let finalCheckpoint = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-post-safe-point-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_802),
            emitSystemMessage: false
        )
        #expect(finalCheckpoint.state == .blocked)
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await followUpFlag.value())

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.delivered.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-finish-1"
        })
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先审查这次 automation 产物是否已经满足 done definition")
        })
    }

    @Test
    func automationSafePointHoldAfterExecutionRunsSupervisorFollowUpOutsideJurisdictionView() async throws {
        let manager = SupervisorManager.makeForTesting(enableSupervisorEventLoopAutoFollowUp: true)
        manager.resetAutomationRuntimeState()
        actor FollowUpFlag {
            private var hit = false
            func mark() { hit = true }
            func value() -> Bool { hit }
        }
        let followUpFlag = FollowUpFlag()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        _ = try AXProjectStore.upsertAutomationRecipe(makeAutoExecutableRecipe(), activate: true, for: ctx)
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let friendlyName = "我的世界还原项目"
        let project = AXProjectEntry(
            projectId: projectId,
            rootPath: root.path,
            displayName: friendlyName,
            lastOpenedAt: 1_773_200_900,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        manager.setSupervisorEventLoopResponseOverrideForTesting { userMessage, triggerSource in
            await followUpFlag.mark()
            #expect(triggerSource == "automation_safe_point")
            #expect(userMessage.contains("project_ref=\(friendlyName)"))
            #expect(userMessage.contains("requested_state=delivered"))
            #expect(userMessage.contains("injection_id=guidance-auto-safe-point-hidden-1"))
            #expect(!userMessage.contains(root.lastPathComponent))
            return """
            1. 先检查 hidden automation 产物是否满足交付要求。
            2. 如果 safe point guidance 仍要求停住，就决定是继续复核还是重新规划。
            3. 输出给 coder 的下一步。
            """
        }

        let prepared = try manager.prepareAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_900))
        )
        let running = try manager.advanceAutomationRun(
            for: ctx,
            to: .running,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-running-before-hidden-post-safe-point",
            now: Date(timeIntervalSince1970: 1_773_200_901),
            emitSystemMessage: false
        )
        #expect(running.state == .running)

        try SupervisorGuidanceInjectionStore.upsert(
            SupervisorGuidanceInjectionBuilder.build(
                injectionId: "guidance-auto-safe-point-hidden-1",
                reviewId: "review-auto-safe-point-hidden-1",
                projectId: project.projectId,
                targetRole: .coder,
                deliveryMode: .priorityInsert,
                interventionMode: .suggestNextSafePoint,
                safePointPolicy: .checkpointBoundary,
                guidanceText: "hidden 项目也要在交付前给 supervisor 一次 review 窗口。",
                ackStatus: .pending,
                ackRequired: true,
                ackNote: "",
                injectedAtMs: 1_773_200_900_500,
                ackUpdatedAtMs: 0,
                auditRef: "audit-guidance-auto-safe-point-hidden-1"
            ),
            for: ctx
        )

        let jurisdictionNow = Date(timeIntervalSince1970: 1_773_200_901).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: jurisdictionNow)
            .upserting(projectId: projectId, displayName: friendlyName, role: .triageOnly, now: jurisdictionNow)
        _ = manager.applySupervisorJurisdictionRegistry(jurisdiction, persist: false, normalizeWithKnownProjects: false)

        let finalCheckpoint = try manager.advanceAutomationRun(
            for: ctx,
            to: .delivered,
            runID: prepared.launchRef,
            auditRef: "audit-xt-auto-hidden-post-safe-point-delivered",
            now: Date(timeIntervalSince1970: 1_773_200_902),
            emitSystemMessage: false
        )
        #expect(finalCheckpoint.state == .blocked)
        await manager.waitForSupervisorEventLoopForTesting()

        #expect(await followUpFlag.value())

        let rows = try rawLogEntries(for: ctx)
        #expect(rows.contains {
            ($0["type"] as? String) == "automation_safe_point_hold" &&
            ($0["run_id"] as? String) == prepared.launchRef &&
            ($0["requested_state"] as? String) == XTAutomationRunState.delivered.rawValue &&
            ($0["injection_id"] as? String) == "guidance-auto-safe-point-hidden-1"
        })
        try await waitUntil("hidden post safe point follow-up assistant message visible", timeoutMs: 30_000) {
            manager.messages.contains {
                $0.role == .assistant && $0.content.contains("先检查 hidden automation 产物是否满足交付要求")
            }
        }
        #expect(manager.messages.contains {
            $0.role == .assistant && $0.content.contains("先检查 hidden automation 产物是否满足交付要求")
        })
    }

    @Test
    func automationStartCommandPublishesVerifyAndDiffStatusForMutationRun() async throws {
        try await Self.runtimeGate.runOnMainActor {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "exit: 0\nSmokeTests passed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))

        try await waitUntil("automation mutation run delivered") {
            manager.automationCurrentCheckpoint?.state == .delivered
        }

        let report = try #require(manager.automationLatestExecutionReport)
        #expect(report.finalState == .delivered)
        #expect(report.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(report.verificationReport?.passedCommandCount == 1)
        #expect(report.workspaceDiffReport?.fileCount == 1)
        let handoffPath = try #require(report.handoffArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(handoffPath).path))

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("delivery_closure_run_id: \(report.runID)"))
        #expect(statusText.contains("delivery_closure_delivery_ref: build/reports/xt_auto_manual_delivery.v1.json"))
        #expect(statusText.contains("delivery_closure_source: execution_report"))
        #expect(statusText.contains("last_execution_handoff: \(handoffPath)"))
        #expect(statusText.contains("last_execution_delivery_ref: build/reports/xt_auto_manual_delivery.v1.json"))
        #expect(statusText.contains("last_execution_verify: 1/1"))
        #expect(statusText.contains("last_execution_diff: 1 files"))
        #expect(statusText.contains("last_execution_diff_detail: diff_captured:1_files"))
        }
    }

    @Test
    func automationRecoverSchedulesRetryRunFromVerificationHandoff() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    await counter.increment(.project_snapshot)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))

        try await waitUntil("initial verify-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_verify_failed"
        }

        let initialReport = try #require(manager.automationLatestExecutionReport)
        let sourceRunID = initialReport.runID
        let sourceHandoff = try #require(initialReport.handoffArtifactPath)
        let sourceLineage = try #require(initialReport.lineage)
        let sourceDeliveryRef = try #require(
            manager.automationPreparedRun?.verticalSlice.eventRunner.runTimeline.deliveryRef
        )
        #expect(sourceLineage.rootRunID == sourceRunID)
        #expect(sourceLineage.parentRunID.isEmpty)
        #expect(sourceLineage.retryDepth == 0)

        let preRecoveryStatusText = try #require(
            manager.performAutomationRuntimeCommand("/automation status \(project.projectId)")
        )
        #expect(preRecoveryStatusText.contains("delivery_closure_run_id: \(sourceRunID)"))
        #expect(preRecoveryStatusText.contains("delivery_closure_delivery_ref: \(sourceDeliveryRef)"))
        #expect(preRecoveryStatusText.contains("delivery_closure_source: execution_report"))
        #expect(preRecoveryStatusText.contains("delivery_closure_lineage: \(sourceLineage.lineageID)"))
        #expect(preRecoveryStatusText.contains("delivery_closure_root_run: \(sourceRunID)"))
        #expect(preRecoveryStatusText.contains("delivery_closure_retry_depth: 0"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_automatic_decision: hold"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_delivery_ref: \(sourceDeliveryRef)"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_resume_mode: retry_package"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_retry_strategy: verify_failed_retry"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_retry_reason: automation_verify_failed"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_retry_planning_mode: verify_only_retry"))
        #expect(preRecoveryStatusText.contains("recovery_candidate_retry_source_handoff: \(sourceHandoff)"))

        let recoveryText = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))
        let scheduledRetryPackage = try #require(manager.automationLatestRetryPackage)
        let scheduledRetryLineage = try #require(scheduledRetryPackage.lineage)
        let scheduledRetryRunID = try #require(
            scheduledRetryPackage.retryRunID.isEmpty ? nil : scheduledRetryPackage.retryRunID
        )
        #expect(recoveryText.contains("decision: resume"))
        #expect(recoveryText.contains("delivery_closure_run_id: \(scheduledRetryRunID)"))
        #expect(recoveryText.contains("delivery_closure_delivery_ref: \(sourceDeliveryRef)"))
        #expect(recoveryText.contains("delivery_closure_source: retry_package"))
        #expect(recoveryText.contains("delivery_closure_lineage: \(scheduledRetryLineage.lineageID)"))
        #expect(recoveryText.contains("delivery_closure_root_run: \(sourceRunID)"))
        #expect(recoveryText.contains("delivery_closure_parent_run: \(sourceRunID)"))
        #expect(recoveryText.contains("delivery_closure_retry_depth: 1"))
        #expect(recoveryText.contains("candidate_delivery_ref: \(sourceDeliveryRef)"))
        #expect(recoveryText.contains("candidate_resume_mode: retry_package"))
        #expect(recoveryText.contains("candidate_retry_strategy: verify_failed_retry"))
        #expect(recoveryText.contains("candidate_retry_reason: automation_verify_failed"))
        #expect(recoveryText.contains("candidate_retry_planning_mode: verify_only_retry"))
        #expect(recoveryText.contains("candidate_retry_source_handoff: \(sourceHandoff)"))
        #expect(recoveryText.contains("retry_strategy: verify_failed_retry"))
        #expect(recoveryText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(recoveryText.contains("last_retry_source_handoff: \(sourceHandoff)"))
        #expect(recoveryText.contains("retry_delivery_ref: \(sourceDeliveryRef)"))

        try await waitUntil("retry run prepared") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty && retryRunID != sourceRunID
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        let retryRunID = try #require(manager.automationPreparedRun?.launchRef)
        let retryLineage = try #require(retryPackage.lineage)
        let retryDeliveryRef = try #require(
            manager.automationPreparedRun?.verticalSlice.eventRunner.runTimeline.deliveryRef
        )
        let launchRows = try rawLogEntries(for: ctx).filter {
            ($0["type"] as? String) == "automation_run_launch"
                && ($0["run_id"] as? String) == retryRunID
        }
        #expect(retryPackage.sourceRunID == sourceRunID)
        #expect(retryPackage.deliveryRef == sourceDeliveryRef)
        #expect(retryPackage.sourceHandoffArtifactPath == sourceHandoff)
        #expect(retryLineage.lineageID == sourceLineage.lineageID)
        #expect(retryLineage.rootRunID == sourceRunID)
        #expect(retryLineage.parentRunID == sourceRunID)
        #expect(retryLineage.retryDepth == 1)
        #expect(retryDeliveryRef == sourceDeliveryRef)
        #expect(launchRows.contains { ($0["delivery_ref"] as? String) == sourceDeliveryRef })
        #expect(retryPackage.retryStrategy == "verify_failed_retry")
        #expect(retryPackage.planningMode == "verify_only_retry")
        #expect(retryPackage.runtimePatchOverlay != nil)
        #expect(retryPackage.revisedActionGraph?.count == 2)
        #expect(retryPackage.revisedVerifyCommands == ["swift test --filter SmokeTests"])
        #expect(retryPackage.revisedVerificationContract?.verifyMethod == "project_verify_commands")
        #expect(retryPackage.revisedVerificationContract?.verifyCommands == ["swift test --filter SmokeTests"])
        #expect(retryPackage.planningArtifactPath?.isEmpty == false)
        #expect(retryPackage.recipeProposalArtifactPath?.isEmpty == false)
        #expect(retryPackage.retryRunID == retryRunID)
        #expect(retryPackage.additionalEvidenceRefs.contains(sourceHandoff))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(retryPackage.retryArtifactPath).path))
        let planningArtifactPath = try #require(retryPackage.planningArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(planningArtifactPath).path))
        let recipeProposalArtifactPath = try #require(retryPackage.recipeProposalArtifactPath)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent(recipeProposalArtifactPath).path))

        try await waitUntil("retry verify-failed run blocked") {
            manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("delivery_closure_run_id: \(retryRunID)"))
        #expect(statusText.contains("delivery_closure_delivery_ref: \(sourceDeliveryRef)"))
        #expect(statusText.contains("delivery_closure_source: execution_report"))
        #expect(statusText.contains("delivery_closure_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("delivery_closure_root_run: \(sourceRunID)"))
        #expect(statusText.contains("delivery_closure_parent_run: \(sourceRunID)"))
        #expect(statusText.contains("delivery_closure_retry_depth: 1"))
        #expect(statusText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_strategy: verify_failed_retry"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("retry_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("retry_depth: 1"))
        #expect(statusText.contains("retry_revised_verify_commands: swift test --filter SmokeTests"))
        #expect(statusText.contains("retry_revised_verification_method: project_verify_commands"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verification_contract,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact: \(recipeProposalArtifactPath)"))
        #expect(statusText.contains("retry_planning_artifact: \(planningArtifactPath)"))
        #expect(statusText.contains("last_retry_source_handoff: \(sourceHandoff)"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))
        #expect(statusText.contains("retry_delivery_ref: \(sourceDeliveryRef)"))
        #expect(statusText.contains("last_execution_delivery_ref: \(sourceDeliveryRef)"))
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .project_snapshot) >= 1)
        }

    @Test
    func automationRecoverBuildsPatchCheckRetryPackage() async throws {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        try armRepoAutomationGovernance(for: ctx)
        _ = try AXProjectStore.upsertAutomationRecipe(makeGitApplyRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .git_apply_check:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\npatch does not apply")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_700))
        )

        try await waitUntil("initial patch-check-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_patch_check_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let sourceHandoff = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)

        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 0,
            auditRef: "audit-xt-auto-manager-patch-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)

        try await waitUntil("patch retry run prepared") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty && retryRunID != sourceRunID
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        #expect(retryPackage.sourceRunID == sourceRunID)
        #expect(retryPackage.sourceHandoffArtifactPath == sourceHandoff)
        #expect(retryPackage.retryStrategy == "patch_check_retry")
        #expect(retryPackage.retryReason == "automation_patch_check_failed")
        #expect(retryPackage.additionalEvidenceRefs.contains("retry://hold_reason/automation_patch_check_failed"))
        #expect(retryPackage.additionalEvidenceRefs.contains(sourceHandoff))
    }

    @Test
    func automationSelfIterateAutoRetriesBlockedRunWithinBudget() async throws {
        try await Self.runtimeGate.runOnMainActor {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        config.automationSelfIterateEnabled = true
        config.automationMaxAutoRetryDepth = 1
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    await counter.increment(.project_snapshot)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        let startText = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))
        #expect(startText.contains("run_id:"))

        try await waitUntil("automatic self-iterate retry launch") {
            let retryRunID = manager.automationLatestRetryPackage?.retryRunID ?? ""
            return !retryRunID.isEmpty
                && manager.automationRetryTriggerForTesting() == "automatic"
        }

        let sourceRunID = try #require(manager.automationLatestRetryPackage?.sourceRunID)
        let retryRunID = try #require(manager.automationLatestRetryPackage?.retryRunID)
        let retryLineage = try #require(manager.automationLatestRetryPackage?.lineage)
        #expect(sourceRunID != retryRunID)
        #expect(manager.automationLatestRetryPackage?.retryStrategy == "verify_failed_retry")
        #expect(manager.automationLatestRetryPackage?.planningMode == "verify_only_retry")
        #expect(retryLineage.rootRunID == sourceRunID)
        #expect(retryLineage.parentRunID == sourceRunID)
        #expect(retryLineage.retryDepth == 1)
        #expect(manager.automationLatestRetryPackage?.planningArtifactPath?.isEmpty == false)
        #expect(manager.automationLatestRetryPackage?.recipeProposalArtifactPath?.isEmpty == false)
        #expect(manager.automationLatestRetryPackage?.runtimePatchOverlay != nil)
        #expect(manager.automationLatestRetryPackage?.revisedVerificationContract?.verifyMethod == "project_verify_commands")
        #expect(manager.automationLatestRetryPackage?.additionalEvidenceRefs.contains("retry://trigger/automatic") == true)
        #expect(manager.automationLatestRetryPackage?.additionalEvidenceRefs.contains("retry://depth/1") == true)

        try await waitUntil("automatic self-iterate retry finishes blocked") {
            manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.runID == retryRunID
        }

        try await waitUntil("automatic self-iterate budget exhausts after retry") {
            manager.automationStatusLine.contains("auto_retry_budget_exhausted")
        }

        let statusText = try #require(manager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("self_iterate_mode: enabled"))
        #expect(statusText.contains("self_iterate_max_auto_retry_depth: 1"))
        #expect(statusText.contains("retry_trigger: automatic"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("retry_revised_verification_method: project_verify_commands"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verification_contract,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact:"))
        #expect(statusText.contains("retry_planning_artifact:"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .project_snapshot) >= 1)
        }
    }

    @Test
    func automationStatusHydratesExecutionAndRetryFromDiskAfterRestart() async throws {
        try await Self.runtimeGate.runOnMainActor {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeRegistryVisibleProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }
        try markAsSwiftPackage(root)

        let ctx = AXProjectContext(root: root)
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config.verifyCommands = ["swift test --filter SmokeTests"]
        config.verifyAfterChanges = true
        try AXProjectStore.saveConfig(config, for: ctx)
        try armRepoAutomationGovernance(for: ctx)

        _ = try AXProjectStore.upsertAutomationRecipe(makeMutationRecipe(), activate: true, for: ctx)
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .project_snapshot:
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "root=/tmp/project")
                case .git_diff:
                    return ToolResult(
                        id: call.id,
                        tool: call.tool,
                        ok: true,
                        output: """
                        diff --git a/README.md b/README.md
                        @@ -0,0 +1 @@
                        +hello
                        """
                    )
                case .run_command:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nSmokeTests failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        let project = makeProjectEntry(root: root)
        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: Date().timeIntervalSince1970,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: nil,
            projects: [project]
        )
        manager.setAppModel(appModel)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation start \(project.projectId)"))

        try await waitUntil("initial verify-failed run blocked for hydration") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_verify_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let sourceHandoff = try #require(manager.automationLatestExecutionReport?.handoffArtifactPath)

        _ = try #require(manager.performAutomationRuntimeCommand("/automation recover \(project.projectId)"))

        try await waitUntil("retry run blocked for hydration") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty
                && retryRunID != sourceRunID
                && manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let retryRunID = try #require(manager.automationPreparedRun?.launchRef)
        let retryReport = try #require(manager.automationLatestExecutionReport)
        let retryHandoff = try #require(retryReport.handoffArtifactPath)
        let retryDeliveryRef = try #require(retryReport.deliveryRef)
        let retryLineage = try #require(retryReport.lineage)

        let restartedManager = SupervisorManager.makeForTesting()
        restartedManager.resetAutomationRuntimeState()
        restartedManager.setAppModel(appModel)
        restartedManager.syncAutomationRuntimeSnapshot(forSelectedProject: project)

        try await waitUntil("restarted manager hydrates selected project runtime without status command") {
            restartedManager.automationCurrentCheckpoint?.runID == retryRunID
                && restartedManager.automationLatestExecutionReport?.runID == retryRunID
                && restartedManager.automationLatestRetryPackage?.retryRunID == retryRunID
        }

        #expect(restartedManager.automationStatusLine.contains(retryRunID))
        #expect(restartedManager.automationStatusLine.contains("受阻"))

        let statusText = try #require(restartedManager.performAutomationRuntimeCommand("/automation status \(project.projectId)"))
        #expect(statusText.contains("continuity_context_source: checkpoint+execution_report+retry_package"))
        #expect(statusText.contains("continuity_effective_run_id: \(retryRunID)"))
        #expect(statusText.contains("delivery_closure_run_id: \(retryRunID)"))
        #expect(statusText.contains("delivery_closure_delivery_ref: \(retryDeliveryRef)"))
        #expect(statusText.contains("delivery_closure_source: execution_report"))
        #expect(statusText.contains("delivery_closure_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("delivery_closure_root_run: \(sourceRunID)"))
        #expect(statusText.contains("delivery_closure_parent_run: \(sourceRunID)"))
        #expect(statusText.contains("delivery_closure_retry_depth: 1"))
        #expect(statusText.contains("last_recovery_run_id: \(sourceRunID)"))
        #expect(statusText.contains("last_recovery_decision: resume"))
        #expect(statusText.contains("last_recovery_mode: operator_override"))
        #expect(statusText.contains("last_recovery_checkpoint_ref:"))
        #expect(statusText.contains("last_recovery_resume_token:"))
        #expect(statusText.contains("last_recovery_audit_ref:"))
        #expect(statusText.contains("last_recovery_resume_mode: retry_package"))
        #expect(statusText.contains("last_recovery_retry_run_id: \(retryRunID)"))
        #expect(statusText.contains("last_recovery_retry_strategy: verify_failed_retry"))
        #expect(statusText.contains("last_recovery_retry_reason: automation_verify_failed"))
        #expect(statusText.contains("last_recovery_delivery_ref: \(retryDeliveryRef)"))
        #expect(statusText.contains("last_recovery_delivery_closure_source: retry_package"))
        #expect(statusText.contains("last_recovery_delivery_closure_run_id: \(retryRunID)"))
        #expect(statusText.contains("last_recovery_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("last_recovery_root_run: \(sourceRunID)"))
        #expect(statusText.contains("last_recovery_parent_run: \(sourceRunID)"))
        #expect(statusText.contains("last_recovery_retry_depth: 1"))
        #expect(statusText.contains("last_execution_state: blocked"))
        #expect(statusText.contains("last_execution_handoff: \(retryHandoff)"))
        #expect(statusText.contains("last_execution_delivery_ref: \(retryDeliveryRef)"))
        #expect(statusText.contains("last_execution_verify_hold_reason: automation_verify_failed"))
        #expect(statusText.contains("retry_attempt_from_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_strategy: verify_failed_retry"))
        #expect(statusText.contains("retry_planning_mode: verify_only_retry"))
        #expect(statusText.contains("retry_delivery_ref: \(retryDeliveryRef)"))
        #expect(statusText.contains("last_execution_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("last_execution_parent_run: \(sourceRunID)"))
        #expect(statusText.contains("retry_lineage: \(retryLineage.lineageID)"))
        #expect(statusText.contains("retry_revised_verification_method: project_verify_commands"))
        #expect(statusText.contains("retry_runtime_patch_overlay_keys: action_graph,verification_contract,verify_commands"))
        #expect(statusText.contains("retry_recipe_proposal_artifact:"))
        #expect(statusText.contains("retry_planning_artifact:"))
        #expect(statusText.contains("last_retry_source_handoff: \(sourceHandoff)"))
        #expect(statusText.contains("retry_run_id: \(retryRunID)"))

        #expect(restartedManager.automationCurrentCheckpoint?.runID == retryRunID)
        #expect(restartedManager.automationCurrentCheckpoint?.state == .blocked)
        #expect(restartedManager.automationLatestExecutionReport?.runID == retryRunID)
        #expect(restartedManager.automationLatestExecutionReport?.deliveryRef == retryDeliveryRef)
        #expect(restartedManager.automationLatestExecutionReport?.handoffArtifactPath == retryHandoff)
        #expect(restartedManager.automationLatestExecutionReport?.lineage?.parentRunID == sourceRunID)
        #expect(restartedManager.automationLatestExecutionReport?.lineage?.retryDepth == 1)
        #expect(restartedManager.automationLatestRetryPackage?.retryRunID == retryRunID)
        #expect(restartedManager.automationLatestRetryPackage?.sourceRunID == sourceRunID)
        #expect(restartedManager.automationLatestRetryPackage?.deliveryRef == retryDeliveryRef)
        #expect(restartedManager.automationLatestRetryPackage?.lineage?.lineageID == retryLineage.lineageID)
        #expect(restartedManager.automationLatestRetryPackage?.lineage?.retryDepth == 1)
        #expect(restartedManager.automationLatestRetryPackage?.planningMode == "verify_only_retry")
        #expect(restartedManager.automationLatestRetryPackage?.planningArtifactPath?.isEmpty == false)
        #expect(restartedManager.automationLatestRetryPackage?.recipeProposalArtifactPath?.isEmpty == false)
        #expect(restartedManager.automationLatestRetryPackage?.runtimePatchOverlay != nil)
        #expect(restartedManager.automationLatestRetryPackage?.revisedVerificationContract?.verifyMethod == "project_verify_commands")
        }
    }

    @Test
    func retryPackageHydratesRecipeProposalArtifactWithoutPlanningArtifact() throws {
        let root = try makeProjectRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        let project = makeProjectEntry(root: root)
        let sourceRunID = "run-source-001"
        let retryRunID = "run-retry-001"
        let lineage = XTAutomationRunLineage(
            lineageID: "lineage-test-001",
            rootRunID: sourceRunID,
            parentRunID: sourceRunID,
            retryDepth: 1
        )
        let proposalArtifact = XTAutomationRecipeProposalArtifact(
            schemaVersion: XTAutomationRecipeProposalArtifact.currentSchemaVersion,
            generatedAt: 1_773_200_850,
            projectID: project.projectId,
            lineage: lineage,
            sourceRunID: sourceRunID,
            sourceHandoffArtifactPath: "build/reports/xt_automation_run_handoff_source.v1.json",
            sourcePlanningArtifactPath: nil,
            baseRecipeRef: "xt-auto-resume-failed-action@v1",
            retryStrategy: "action_failure_retry",
            retryReason: "automation_action_failed",
            proposalMode: "resume_from_failed_action",
            proposalSummary: "resume from the first failed action only",
            runtimePatchOverlay: XTAutomationRuntimePatchOverlay(
                mergePatch: [
                    "action_graph": .array([
                        .object([
                            "action_id": .string("resume_failed_action"),
                            "title": .string("Resume failed action"),
                            "tool": .string(ToolName.run_command.rawValue),
                            "args": .object([
                                "command": .string("false")
                            ]),
                            "continue_on_failure": .bool(false),
                            "success_body_contains": .string(""),
                            "requires_verification": .bool(false)
                        ])
                    ]),
                    "verify_commands": .array([
                        .string("swift test --filter RetryOnly")
                    ]),
                    "verification_contract": .object([
                        "expected_state": .string("retry verification passes"),
                        "verify_method": .string("project_verify_commands_override"),
                        "retry_policy": .string("retry_failed_verify_commands_within_budget"),
                        "hold_policy": .string("block_run_and_emit_structured_blocker"),
                        "evidence_required": .bool(true),
                        "trigger_action_ids": .array([.string("resume_failed_action")]),
                        "verify_commands": .array([.string("swift test --filter RetryOnly")])
                    ])
                ]
            ),
            proposedActionGraph: [],
            proposedVerifyCommands: [],
            proposedVerificationContract: XTAutomationVerificationContract(
                expectedState: "retry verification passes",
                verifyMethod: "project_verify_commands_override",
                retryPolicy: "retry_failed_verify_commands_within_budget",
                holdPolicy: "block_run_and_emit_structured_blocker",
                evidenceRequired: true,
                triggerActionIDs: ["resume_failed_action"],
                verifyCommands: ["swift test --filter RetryOnly"]
            ),
            suggestedNextActions: ["rerun failed command"],
            additionalEvidenceRefs: ["retry://proposal_mode/resume_from_failed_action"]
        )
        let proposalPath = try #require(
            xtAutomationPersistRetryRecipeProposalArtifact(
                proposalArtifact,
                ctx: ctx
            )
        )

        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_851,
                "source_run_id": sourceRunID,
                "retry_run_id": retryRunID,
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "lineage_id": lineage.lineageID,
                "root_run_id": lineage.rootRunID,
                "parent_run_id": lineage.parentRunID,
                "retry_depth": lineage.retryDepth,
                "retry_strategy": "action_failure_retry",
                "retry_reason": "automation_action_failed",
                "source_handoff_artifact_path": proposalArtifact.sourceHandoffArtifactPath,
                "recipe_proposal_artifact_path": proposalPath,
                "retry_trigger": "manual"
            ],
            for: ctx
        )

        let loaded = try #require(
            xtAutomationLoadRetryPackage(
                forRetryRunID: retryRunID,
                projectID: project.projectId,
                ctx: ctx
            )
        )
        #expect(loaded.recipeProposalArtifactPath == proposalPath)
        #expect(loaded.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(loaded.planningArtifactPath == nil)
        #expect(loaded.planningMode == "resume_from_failed_action")
        #expect(loaded.planningSummary == "resume from the first failed action only")
        #expect(loaded.runtimePatchOverlay != nil)
        #expect(loaded.revisedActionGraph?.count == 1)
        #expect(loaded.revisedActionGraph?.first?.tool == .run_command)
        #expect(loaded.revisedVerifyCommands == ["swift test --filter RetryOnly"])
        #expect(loaded.revisedVerificationContract?.verifyMethod == "project_verify_commands_override")
        #expect(loaded.revisedVerificationContract?.verifyCommands == ["swift test --filter RetryOnly"])
        #expect(loaded.lineage?.lineageID == lineage.lineageID)
        #expect(loaded.lineage?.parentRunID == sourceRunID)
        #expect(loaded.lineage?.retryDepth == 1)
    }

    @Test
    func automationRecoverResumesFromFailedActionInsteadOfReplayingSuccessfulPrefix() async throws {
        try await Self.runtimeGate.runOnMainActor {
        let manager = SupervisorManager.makeForTesting()
        manager.resetAutomationRuntimeState()

        let root = try makeProjectRoot()
        defer {
            manager.resetAutomationRuntimeState()
            try? FileManager.default.removeItem(at: root)
        }

        let ctx = AXProjectContext(root: root)
        try armRepoAutomationGovernance(for: ctx)
        _ = try AXProjectStore.upsertAutomationRecipe(makeResumeFromFailedActionRecipe(), activate: true, for: ctx)

        let counter = ToolCallCounter()
        manager.installAutomationRunExecutorForTesting(
            XTAutomationRunExecutor { call, _ in
                switch call.tool {
                case .write_file:
                    await counter.increment(.write_file)
                    return ToolResult(id: call.id, tool: call.tool, ok: true, output: "ok")
                case .run_command:
                    await counter.increment(.run_command)
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "exit: 1\nstep failed")
                default:
                    return ToolResult(id: call.id, tool: call.tool, ok: false, output: "unexpected_tool")
                }
            }
        )

        _ = try manager.startAutomationRun(
            for: ctx,
            request: makeManualRequest(now: Date(timeIntervalSince1970: 1_773_200_800))
        )

        try await waitUntil("initial action-failed run blocked") {
            manager.automationCurrentCheckpoint?.state == .blocked
                && manager.automationLatestExecutionReport?.holdReason == "automation_action_failed"
        }

        let sourceRunID = try #require(manager.automationLatestExecutionReport?.runID)
        let recovery = try manager.recoverLatestAutomationRun(
            for: ctx,
            checkpointAgeSeconds: 0,
            auditRef: "audit-xt-auto-manager-action-recover"
        )
        let recovered = try #require(recovery)
        #expect(recovered.decision == .resume)

        try await waitUntil("resume-from-failed-action retry blocked") {
            let retryRunID = manager.automationPreparedRun?.launchRef ?? ""
            return !retryRunID.isEmpty
                && retryRunID != sourceRunID
                && manager.automationCurrentCheckpoint?.runID == retryRunID
                && manager.automationCurrentCheckpoint?.state == .blocked
        }

        let retryPackage = try #require(manager.automationLatestRetryPackage)
        #expect(retryPackage.retryStrategy == "action_failure_retry")
        #expect(retryPackage.planningMode == "resume_from_failed_action")
        #expect(retryPackage.runtimePatchOverlay != nil)
        #expect(retryPackage.revisedActionGraph?.count == 1)
        #expect(retryPackage.revisedActionGraph?.first?.tool == .run_command)
        #expect(retryPackage.planningArtifactPath?.isEmpty == false)
        #expect(retryPackage.recipeProposalArtifactPath?.isEmpty == false)
        #expect(await counter.count(for: .write_file) == 1)
        #expect(await counter.count(for: .run_command) == 2)
        }
    }

    private func armTrustedAutomation(for ctx: AXProjectContext) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingTrustedAutomationBinding(
            mode: .trustedAutomation,
            deviceId: "device_xt_001",
            deviceToolGroups: ["device.ui.step"],
            workspaceBindingHash: xtTrustedAutomationWorkspaceHash(forProjectRoot: ctx.root)
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func armRepoAutomationGovernance(for ctx: AXProjectContext) throws {
        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        config = config.settingProjectGovernance(
            executionTier: .a2RepoAuto,
            supervisorInterventionTier: .s2PeriodicReview
        )
        try AXProjectStore.saveConfig(config, for: ctx)
    }

    private func makeProjectRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xterminal-supervisor-manager-automation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeRegistryVisibleProjectRoot() throws -> URL {
        // Keep a non-ephemeral prefix so registry-backed selection paths can still see the test project.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-operator-channel-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeProjectEntry(root: URL, displayName: String? = nil) -> AXProjectEntry {
        AXProjectEntry(
            projectId: AXProjectRegistryStore.projectId(forRoot: root),
            rootPath: root.path,
            displayName: displayName ?? root.lastPathComponent,
            lastOpenedAt: 1_773_200_200,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: nil,
            currentStateSummary: nil,
            nextStepSummary: nil,
            blockerSummary: nil,
            lastSummaryAt: nil,
            lastEventAt: nil
        )
    }

    private func makeHeartbeatRecoveryLaneSnapshot(
        projectId: String,
        status: LaneHealthStatus,
        blockedReason: LaneBlockedReason?,
        nextActionRecommendation: String,
        laneID: String? = nil
    ) -> SupervisorLaneHealthSnapshot {
        let projectUUID = UUID(uuidString: oneShotDeterministicUUIDString(seed: projectId))
        var state = LaneRuntimeState(
            laneID: laneID ?? "lane-\(blockedReason?.rawValue ?? status.rawValue)",
            taskId: UUID(),
            projectId: projectUUID,
            agentProfile: "coder",
            status: status,
            blockedReason: blockedReason,
            nextActionRecommendation: nextActionRecommendation
        )
        state.heartbeatSeq = 4
        state.lastHeartbeatAtMs = 1_773_384_000_000
        state.oldestWaitMs = 1_773_383_940_000

        return SupervisorLaneHealthSnapshot(
            generatedAtMs: 1_773_384_000_000,
            summary: laneHealthSummary(status: status),
            lanes: [SupervisorLaneHealthLaneState(state: state)]
        )
    }

    private func laneHealthSummary(
        status: LaneHealthStatus
    ) -> LaneHealthSummary {
        LaneHealthSummary(
            total: 1,
            running: status == .running ? 1 : 0,
            blocked: status == .blocked ? 1 : 0,
            stalled: status == .stalled ? 1 : 0,
            failed: status == .failed ? 1 : 0,
            waiting: status == .waiting ? 1 : 0,
            recovering: status == .recovering ? 1 : 0,
            completed: status == .completed ? 1 : 0
        )
    }

    private func makeTestingAppModel() -> AppModel {
        AppModel.makeForTesting()
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
            requiredDeviceToolGroups: ["device.ui.step"],
            requiresTrustedAutomation: true,
            trustedDeviceID: "device://trusted/project-a",
            workspaceBindingHash: "sha256:workspace-binding-project-a",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_000_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-001",
            lastLaunchRef: ""
        )
    }

    private func makeAutoExecutableRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-project-snapshot",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "capture project snapshot automatically",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Project snapshot",
                    tool: .project_snapshot,
                    args: [:],
                    successBodyContains: "root="
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_500_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-002",
            lastLaunchRef: ""
        )
    }

    private func makeMutationRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-mutation-verify",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "write change and verify automatically",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Write README",
                    tool: .write_file,
                    args: [
                        "path": .string("README.md"),
                        "content": .string("hello")
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_600_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-003",
            lastLaunchRef: ""
        )
    }

    private func makeLiveIngressRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-live-ingress",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "ingest webhook and connector events into automation runtime",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:webhook/github_pr",
                "xt.automation_trigger_envelope.v1:connector_event/slack_dm"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_900_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-live-ingress",
            lastLaunchRef: ""
        )
    }

    private func makeScheduledLiveIngressRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-scheduled-live-ingress",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "drive scheduled automation directly from supervisor poll runtime",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:schedule/nightly"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_201_000_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-scheduled-live-ingress",
            lastLaunchRef: ""
        )
    }

    private func makeGitApplyRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-git-apply-recover",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "apply patch with precheck",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Apply README patch",
                    tool: .git_apply,
                    args: [
                        "patch": .string("--- a/README.md\n+++ b/README.md\n@@\n-old\n+new\n")
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_700_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-004",
            lastLaunchRef: ""
        )
    }

    private func makeResumeFromFailedActionRecipe() -> AXAutomationRecipeRuntimeBinding {
        AXAutomationRecipeRuntimeBinding(
            recipeID: "xt-auto-resume-failed-action",
            recipeVersion: 1,
            lifecycleState: .ready,
            goal: "resume from failed action instead of replaying successful prefix",
            triggerRefs: [
                "xt.automation_trigger_envelope.v1:manual/retry"
            ],
            deliveryTargets: ["channel://telegram/project-a"],
            acceptancePackRef: "build/reports/xt_w3_22_acceptance_pack.v1.json",
            executionProfile: .balanced,
            touchMode: .guidedTouch,
            innovationLevel: .l1,
            laneStrategy: .singleLane,
            requiredToolGroups: ["group:full"],
            actionGraph: [
                XTAutomationRecipeAction(
                    title: "Write README",
                    tool: .write_file,
                    args: [
                        "path": .string("README.md"),
                        "content": .string("hello")
                    ]
                ),
                XTAutomationRecipeAction(
                    title: "Run failing step",
                    tool: .run_command,
                    args: [
                        "command": .string("false"),
                        "timeout_sec": .number(10)
                    ]
                )
            ],
            requiresTrustedAutomation: false,
            trustedDeviceID: "",
            workspaceBindingHash: "",
            grantPolicyRef: "policy://automation-trigger/project-a",
            rolloutStatus: .active,
            lastEditedAtMs: 1_773_200_800_000,
            lastEditAuditRef: "audit-xt-auto-manager-bind-005",
            lastLaunchRef: ""
        )
    }

    private func rawLogEntries(for ctx: AXProjectContext) throws -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path) else { return [] }
        let data = try Data(contentsOf: ctx.rawLogURL)
        guard let text = String(data: data, encoding: .utf8) else {
            struct RawLogDecodeError: Error {}
            throw RawLogDecodeError()
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
    }

    private func makeRequest(now: Date) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "schedule/nightly",
                    triggerType: .schedule,
                    source: .timer,
                    payloadRef: "local://trigger-payload/20260310-101",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "sha256:schedule-nightly-manager"
                )
            ],
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func makeManualRequest(
        now: Date,
        lineage: XTAutomationRunLineage? = nil
    ) -> XTAutomationRunRequest {
        XTAutomationRunRequest(
            triggerSeeds: [
                XTAutomationTriggerSeed(
                    triggerID: "manual/retry",
                    triggerType: .manual,
                    source: .hub,
                    payloadRef: "local://trigger-payload/manual-retry",
                    requiresGrant: true,
                    policyRef: "policy://automation-trigger/project-a",
                    dedupeKey: "manual|project-a|\(Int(now.timeIntervalSince1970))"
                )
            ],
            lineage: lineage,
            blockedTaskID: "XT-W3-25-C",
            upstreamDependencyIDs: ["Hub-Wx"],
            now: now
        )
    }

    private func waitUntil(
        _ label: String,
        timeoutMs: UInt64 = 20_000,
        intervalMs: UInt64 = 50,
        condition: @escaping @MainActor @Sendable () -> Bool
    ) async throws {
        let attempts = max(1, Int(timeoutMs / intervalMs))
        for _ in 0..<attempts {
            if await MainActor.run(body: condition) {
                return
            }
            try await Task.sleep(nanoseconds: intervalMs * 1_000_000)
        }
        Issue.record("Timed out waiting for \(label)")
    }

    private func markAsSwiftPackage(_ root: URL) throws {
        let packageURL = root.appendingPathComponent("Package.swift")
        let package = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "Fixture",
            targets: [
                .target(name: "Fixture")
            ]
        )
        """
        try package.write(to: packageURL, atomically: true, encoding: .utf8)
    }

    private func makeGovernedAutomationPendingSkillApproval(
        requestId: String,
        project: AXProjectEntry,
        createdAt: TimeInterval,
        executionReadiness: String,
        approvalFloor: String,
        requiredGrantCapabilities: [String],
        unblockActions: [String]
    ) -> SupervisorManager.SupervisorPendingSkillApproval {
        SupervisorManager.SupervisorPendingSkillApproval(
            id: requestId,
            requestId: requestId,
            projectId: project.projectId,
            projectName: project.displayName,
            jobId: "job-1",
            planId: "plan-1",
            stepId: "step-1",
            skillId: "agent-browser",
            requestedSkillId: "browser.open",
            toolName: ToolName.deviceBrowserControl.rawValue,
            tool: .deviceBrowserControl,
            toolSummary: "打开浏览器查看失败后的页面状态",
            reason: "需要人工确认恢复前的页面操作",
            createdAt: createdAt,
            actionURL: "x-terminal://approval/\(requestId)",
            routingReasonCode: "preferred_builtin_selected",
            routingExplanation: "requested entrypoint browser.open converged to preferred builtin guarded-automation · resolved action open",
            readiness: XTSkillExecutionReadiness(
                schemaVersion: XTSkillExecutionReadiness.currentSchemaVersion,
                projectId: project.projectId,
                skillId: "agent-browser",
                packageSHA256: "pkg-\(requestId)",
                publisherID: "xhub.official",
                policyScope: "hub_governed",
                intentFamilies: ["browser.observe", "browser.interact"],
                capabilityFamilies: ["browser.observe", "browser.interact"],
                capabilityProfiles: ["observe_only", "browser_operator"],
                discoverabilityState: "discoverable",
                installabilityState: "installable",
                pinState: "pinned",
                resolutionState: "resolved",
                executionReadiness: executionReadiness,
                runnableNow: false,
                denyCode: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                    ? "grant_required"
                    : "local_approval_required",
                reasonCode: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                    ? "grant floor privileged requires hub grant"
                    : "approval floor local_approval requires local confirmation",
                grantFloor: XTSkillGrantFloor.privileged.rawValue,
                approvalFloor: approvalFloor,
                requiredGrantCapabilities: requiredGrantCapabilities,
                requiredRuntimeSurfaces: ["managed_browser_runtime"],
                stateLabel: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                    ? "awaiting_hub_grant"
                    : "awaiting_local_approval",
                installHint: "",
                unblockActions: unblockActions,
                auditRef: "audit-\(requestId)",
                doctorAuditRef: "",
                vetterAuditRef: "",
                resolvedSnapshotId: "snapshot-\(requestId)",
                grantSnapshotRef: executionReadiness == XTSkillExecutionReadinessState.grantRequired.rawValue
                    ? "grant-\(requestId)"
                    : ""
            )
        )
    }
}
