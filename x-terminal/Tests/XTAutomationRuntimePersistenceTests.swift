import Foundation
import Testing
@testable import XTerminal

struct XTAutomationRuntimePersistenceTests {
    @Test
    func persistedCheckpointSummaryMarksRunCancelledWhenCancelArrivesAfterCheckpoint() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-cancelled-late",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_000
            ),
            cancelRow(
                runID: "run-cancelled-late",
                createdAt: 1_773_200_001
            )
        ]

        let summary = try #require(
            xtAutomationPersistedCheckpointSummary(
                for: "run-cancelled-late",
                from: rows
            )
        )

        #expect(summary.checkpoint.runID == "run-cancelled-late")
        #expect(summary.checkpoint.state == .blocked)
        #expect(summary.rowIndex == 0)
        #expect(summary.wasCancelled)
    }

    @Test
    func latestPersistedCheckpointSummaryIgnoresOlderPreferredRunWhenNewerRunExists() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-older-preferred",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_010
            ),
            checkpointRow(
                runID: "run-newer-latest",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_011
            )
        ]

        let summary = try #require(
            xtAutomationLatestPersistedCheckpointSummary(
                from: rows,
                preferredRunID: "run-older-preferred"
            )
        )

        #expect(summary.checkpoint.runID == "run-newer-latest")
        #expect(summary.checkpoint.state == .blocked)
        #expect(!summary.wasCancelled)
    }

    @Test
    func latestPersistedCheckpointSummaryKeepsCancelledRunVisibleButExcludesItFromMutableSelection() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-older-blocked",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_020
            ),
            checkpointRow(
                runID: "run-latest-cancelled",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_021
            ),
            cancelRow(
                runID: "run-latest-cancelled",
                createdAt: 1_773_200_022
            )
        ]

        let latestVisible = try #require(
            xtAutomationLatestPersistedCheckpointSummary(
                from: rows,
                preferredRunID: "run-latest-cancelled",
                allowedStates: [.blocked]
            )
        )
        let latestMutable = try #require(
            xtAutomationLatestPersistedCheckpointSummary(
                from: rows,
                preferredRunID: "run-latest-cancelled",
                allowedStates: [.blocked],
                excludeCancelled: true
            )
        )

        #expect(latestVisible.checkpoint.runID == "run-latest-cancelled")
        #expect(latestVisible.wasCancelled)
        #expect(latestMutable.checkpoint.runID == "run-older-blocked")
        #expect(!latestMutable.wasCancelled)
    }

    @Test
    func latestPersistedCheckpointSummaryDoesNotReuseOlderMutableRunWhenNewerVisibleRunIsNotMutable() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-older-blocked",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_023
            ),
            checkpointRow(
                runID: "run-newer-delivered",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_024
            )
        ]

        let latestMutable = xtAutomationLatestPersistedCheckpointSummary(
            from: rows,
            preferredRunID: "run-older-blocked",
            allowedStates: [.blocked, .takeover, .downgraded]
        )

        #expect(latestMutable == nil)
    }

    @Test
    func checkpointHelperParsesFlexibleScalarRepresentations() throws {
        let checkpoint = try #require(
            xtAutomationCheckpoint(
                from: checkpointRow(
                    runID: "run-scalar-parser",
                    recipeID: "recipe-runtime",
                    state: .running,
                    createdAt: 1_773_200_030,
                    attempt: "2",
                    retryAfterSeconds: "45",
                    stableIdentity: "true"
                )
            )
        )

        #expect(checkpoint.runID == "run-scalar-parser")
        #expect(checkpoint.state == .running)
        #expect(checkpoint.attempt == 2)
        #expect(checkpoint.retryAfterSeconds == 45)
        #expect(checkpoint.stableIdentity)
    }

    @Test
    func checkpointHelperParsesOptionalStepContextWhenPresent() throws {
        var row = checkpointRow(
            runID: "run-step-parser",
            recipeID: "recipe-runtime",
            state: .blocked,
            createdAt: 1_773_200_031
        )
        row["current_step_id"] = "step-verify"
        row["current_step_title"] = "Verify smoke tests"
        row["current_step_state"] = XTAutomationRunStepState.retryWait.rawValue
        row["current_step_summary"] = "Waiting before retrying the reduced verify set."

        let checkpoint = try #require(xtAutomationCheckpoint(from: row))

        #expect(checkpoint.currentStepID == "step-verify")
        #expect(checkpoint.currentStepTitle == "Verify smoke tests")
        #expect(checkpoint.currentStepState == .retryWait)
        #expect(checkpoint.currentStepSummary == "Waiting before retrying the reduced verify set.")
    }

    @Test
    func latestProjectContinuitySnapshotCombinesCheckpointExecutionAndRetryPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-step-memory-1",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_032,
                attempt: 2,
                retryAfterSeconds: 45,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retrying the reduced verify set."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_033,
                "run_id": "run-step-memory-1",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "Smoke tests are still red.",
                "executed_action_count": 2,
                "succeeded_action_count": 1,
                "total_action_count": 2,
                "current_step_id": "step-verify",
                "current_step_title": "Verify focused smoke tests",
                "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                "current_step_summary": "Waiting before retrying the reduced verify set.",
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 3,
                    "passed_command_count": 1,
                    "hold_reason": "automation_verify_failed",
                    "detail": "Smoke tests are still red."
                ],
                "blocker": [
                    "code": "automation_verify_failed",
                    "summary": "Smoke tests are still red.",
                    "stage": XTAutomationBlockerStage.verification.rawValue,
                    "detail": "Focused smoke tests failed during retry.",
                    "next_safe_action": "shrink verify scope and retry",
                    "retry_eligible": true,
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ],
                "audit_ref": "audit-step-memory-execution"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_034,
                "source_run_id": "run-step-memory-1",
                "retry_run_id": "run-step-memory-2",
                "retry_strategy": "shrink_verify_scope",
                "retry_reason": "retry_verify_scope",
                "retry_reason_descriptor": [
                    "code": "retry_verify_scope",
                    "category": XTAutomationRetryReasonCategory.verification.rawValue,
                    "summary": "Retry with a reduced verify set",
                    "strategy": "shrink_verify_scope",
                    "blocker_code": "automation_verify_failed",
                    "current_step_id": "step-verify",
                    "current_step_title": "Verify focused smoke tests",
                    "current_step_state": XTAutomationRunStepState.retryWait.rawValue,
                    "current_step_summary": "Waiting before retrying the reduced verify set."
                ]
            ],
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_120)
            )
        )

        #expect(snapshot.contextSource == "checkpoint+execution_report+retry_package")
        #expect(snapshot.runID == "run-step-memory-1")
        #expect(snapshot.runState == .blocked)
        #expect(snapshot.attempt == 2)
        #expect(snapshot.retryAfterSeconds == 45)
        #expect(snapshot.currentStepID == "step-verify")
        #expect(snapshot.currentStepTitle == "Verify focused smoke tests")
        #expect(snapshot.currentStepState == .retryWait)
        #expect(snapshot.verificationReport?.commandCount == 3)
        #expect(snapshot.verificationReport?.passedCommandCount == 1)
        #expect(snapshot.blocker?.stage == .verification)
        #expect(snapshot.blocker?.summary == "Smoke tests are still red.")
        #expect(snapshot.retryReasonDescriptor?.summary == "Retry with a reduced verify set")
        #expect(snapshot.retryReasonDescriptor?.strategy == "shrink_verify_scope")
        #expect(snapshot.recoveryState?.selection == .latestRecoverableUnsuperseded)
        #expect(snapshot.recoveryState?.reason == .latestVisibleRecoverable)
        #expect(snapshot.recoveryState?.automaticDecision == .resume)
        #expect(snapshot.recoveryState?.automaticHoldReason == "")
        #expect(snapshot.recoveryState?.retryAfterRemainingSeconds == nil)
        #expect(snapshot.hasCurrentStep)
        #expect(snapshot.hasVerificationState)
        #expect(snapshot.verificationNeedsAttention)
        #expect(snapshot.hasBlocker)
        #expect(snapshot.hasRetryReason)
    }

    @Test
    func latestProjectContinuitySnapshotCarriesRetryWindowRecoveryState() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-retry-window",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_200,
                attempt: 2,
                retryAfterSeconds: 45,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retrying the reduced verify set."
            ),
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_220)
            )
        )

        #expect(snapshot.recoveryState?.selection == .latestRecoverableUnsuperseded)
        #expect(snapshot.recoveryState?.reason == .latestVisibleRetryWait)
        #expect(snapshot.recoveryState?.automaticDecision == .hold)
        #expect(snapshot.recoveryState?.automaticHoldReason == "retry_after_not_elapsed")
        #expect(snapshot.recoveryState?.retryAfterRemainingSeconds == 25)
    }

    @Test
    func latestProjectContinuitySnapshotCarriesDeliveryClosureAndPersistedRecoveryAction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_240,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_241,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting for retry child handoff."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_242,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_243,
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
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "audit_ref": "audit-recovery-row"
            ],
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_260)
            )
        )

        #expect(snapshot.runID == "run-source")
        #expect(snapshot.effectiveRunID == "run-retry-child")
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .retryPackage)
        #expect(snapshot.deliveryClosure?.runID == "run-retry-child")
        #expect(snapshot.deliveryClosure?.source == .retryPackage)
        #expect(snapshot.deliveryClosure?.lineage.lineageID == retryLineage.lineageID)
        #expect(snapshot.persistedRecoveryAction?.decision.runID == "run-source")
        #expect(
            snapshot.persistedRecoveryAction?.decision.schemaVersion
                == XTAutomationRestartRecoveryDecision.currentSchemaVersion
        )
        #expect(snapshot.persistedRecoveryAction?.decision.decision == .resume)
        #expect(snapshot.persistedRecoveryAction?.recoveryMode == .operatorOverride)
        #expect(snapshot.persistedRecoveryAction?.resumeMode == .retryPackage)
        #expect(snapshot.persistedRecoveryAction?.retryRunID == "run-retry-child")
        #expect(snapshot.persistedRecoveryAction?.deliveryClosure?.runID == "run-retry-child")
    }

    @Test
    func latestProjectContinuitySnapshotPrefersNewestPersistedRecoveryActionForSameSourceRun() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-latest-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let firstRetryLineage = sourceLineage.retryChild(parentRunID: "run-source", retryDepth: 1)
        let secondRetryLineage = sourceLineage.retryChild(parentRunID: "run-source", retryDepth: 2)

        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_245,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "source run is still waiting for the newest retry child"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_246,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "recovered_state": XTAutomationRunState.blocked.rawValue,
                "decision": XTAutomationRestartRecoveryAction.resume.rawValue,
                "hold_reason": NSNull(),
                "stable_identity_pass": true,
                "checkpoint_ref": "checkpoint-run-source-first",
                "resume_token": "resume-run-source-first",
                "recovery_mode": XTAutomationRestartRecoveryMode.operatorOverride.rawValue,
                "resume_mode": XTAutomationRecoveryResumeMode.retryPackage.rawValue,
                "retry_run_id": "run-retry-child-1",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_retry_1_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child-1",
                "lineage_id": firstRetryLineage.lineageID,
                "root_run_id": firstRetryLineage.rootRunID,
                "parent_run_id": firstRetryLineage.parentRunID,
                "retry_depth": firstRetryLineage.retryDepth,
                "audit_ref": "audit-recovery-row-first"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_247,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "recovered_state": XTAutomationRunState.blocked.rawValue,
                "decision": XTAutomationRestartRecoveryAction.resume.rawValue,
                "hold_reason": NSNull(),
                "stable_identity_pass": true,
                "checkpoint_ref": "checkpoint-run-source-second",
                "resume_token": "resume-run-source-second",
                "recovery_mode": XTAutomationRestartRecoveryMode.operatorOverride.rawValue,
                "resume_mode": XTAutomationRecoveryResumeMode.retryPackage.rawValue,
                "retry_run_id": "run-retry-child-2",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_retry_2_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child-2",
                "lineage_id": secondRetryLineage.lineageID,
                "root_run_id": secondRetryLineage.rootRunID,
                "parent_run_id": secondRetryLineage.parentRunID,
                "retry_depth": secondRetryLineage.retryDepth,
                "audit_ref": "audit-recovery-row-second"
            ],
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_260)
            )
        )

        #expect(snapshot.contextSource == "checkpoint")
        #expect(snapshot.runID == "run-source")
        #expect(snapshot.persistedRecoveryAction?.decision.runID == "run-source")
        #expect(snapshot.persistedRecoveryAction?.retryRunID == "run-retry-child-2")
        #expect(snapshot.persistedRecoveryAction?.deliveryClosure?.runID == "run-retry-child-2")
        #expect(snapshot.effectiveRunID == "run-retry-child-2")
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_retry_2_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .retryPackage)
        #expect(snapshot.effectiveLineage?.lineageID == secondRetryLineage.lineageID)
        #expect(snapshot.effectiveLineage?.parentRunID == "run-source")
        #expect(snapshot.effectiveLineage?.retryDepth == 2)
    }

    @Test
    func projectDeliveryClosureProjectionPrefersRetryPackageForPreparedRetryChild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-delivery-closure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_300,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_301
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_302,
                "run_id": "run-source",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "audit_ref": "audit-source-blocked"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-retry-child",
                createdAt: 1_773_200_303,
                lineage: retryLineage
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-retry-child",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_304
            ),
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
                "retry_reason": "automation_verify_failed"
            ],
            for: ctx
        )

        let projection = try #require(
            xtAutomationProjectDeliveryClosureProjection(
                for: ctx,
                projectID: projectId,
                preferredRunID: "run-retry-child",
                now: Date(timeIntervalSince1970: 1_773_200_320)
            )
        )

        #expect(projection.runID == "run-retry-child")
        #expect(projection.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(projection.source == .retryPackage)
        #expect(projection.lineage.lineageID == retryLineage.lineageID)
        #expect(projection.lineage.rootRunID == "run-source")
        #expect(projection.lineage.parentRunID == "run-source")
        #expect(projection.lineage.retryDepth == 1)
    }

    @Test
    func latestProjectContinuitySnapshotPrefersPreparedRetryChildBeforeRetryRunStarts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-prepared-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_306,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_307,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retry child launch."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_308,
                "run_id": "run-source",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "audit_ref": "audit-source-blocked-prepared-retry"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_309,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json"
            ],
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_320)
            )
        )

        #expect(snapshot.runID == "run-source")
        #expect(snapshot.effectiveRunID == "run-retry-child")
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .retryPackage)
        #expect(snapshot.deliveryClosure?.runID == "run-retry-child")
        #expect(snapshot.deliveryClosure?.source == .retryPackage)
        #expect(snapshot.deliveryClosure?.lineage.lineageID == retryLineage.lineageID)
        #expect(snapshot.deliveryClosure?.lineage.rootRunID == "run-source")
        #expect(snapshot.deliveryClosure?.lineage.parentRunID == "run-source")
        #expect(snapshot.deliveryClosure?.lineage.retryDepth == 1)
    }

    @Test
    func latestProjectContinuitySnapshotDoesNotReuseSourceExecutionWhenRetryChildAlreadyHasCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-active-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_321,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_322,
                attempt: 2,
                retryAfterSeconds: 45,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retry child launch."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_323,
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
                "audit_ref": "audit-source-blocked-active-retry"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_324,
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
            launchRow(
                runID: "run-retry-child",
                createdAt: 1_773_200_325,
                lineage: retryLineage
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-retry-child",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_326,
                currentStepID: "step-retry-prepare",
                currentStepTitle: "Prepare retry child launch",
                currentStepState: .pending,
                currentStepSummary: "Retry child queued and waiting to start."
            ),
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_340)
            )
        )

        #expect(snapshot.contextSource == "checkpoint+retry_package")
        #expect(snapshot.runID == "run-retry-child")
        #expect(snapshot.runState == .queued)
        #expect(snapshot.executionReport == nil)
        #expect(snapshot.verificationReport == nil)
        #expect(snapshot.effectiveRunID == "run-retry-child")
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .retryPackage)
        #expect(snapshot.deliveryClosure?.runID == "run-retry-child")
        #expect(snapshot.deliveryClosure?.source == .retryPackage)
        #expect(snapshot.deliveryClosure?.lineage.lineageID == retryLineage.lineageID)
        #expect(snapshot.deliveryClosure?.lineage.rootRunID == "run-source")
        #expect(snapshot.deliveryClosure?.lineage.parentRunID == "run-source")
        #expect(snapshot.deliveryClosure?.lineage.retryDepth == 1)
    }

    @Test
    func latestProjectContinuitySnapshotIgnoresUnrelatedRetryPackageWhenNewerRunIsActive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-unrelated-retry-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let unrelatedLineage = XTAutomationRunLineage.root(runID: "run-newer")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_341,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_source_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_342,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retry child launch."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_343,
                "run_id": "run-source",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "source verification failed",
                "audit_ref": "audit-source-blocked-unrelated-retry"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_344,
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
            launchRow(
                runID: "run-newer",
                createdAt: 1_773_200_345,
                lineage: unrelatedLineage,
                deliveryRef: "build/reports/xt_auto_newer_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-newer",
                recipeID: "recipe-runtime-2",
                state: .queued,
                createdAt: 1_773_200_346,
                currentStepID: "step-collect-context",
                currentStepTitle: "Collect context",
                currentStepState: .pending,
                currentStepSummary: "waiting_to_start_first_action"
            ),
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_360)
            )
        )

        #expect(snapshot.contextSource == "checkpoint")
        #expect(snapshot.runID == "run-newer")
        #expect(snapshot.effectiveRunID == "run-newer")
        #expect(snapshot.retryPackage == nil)
        #expect(snapshot.executionReport == nil)
        #expect(snapshot.runState == .queued)
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_newer_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .launch)
        #expect(snapshot.deliveryClosure?.runID == "run-newer")
        #expect(snapshot.deliveryClosure?.source == .launch)
        #expect(snapshot.deliveryClosure?.lineage.lineageID == unrelatedLineage.lineageID)
    }

    @Test
    func latestProjectContinuitySnapshotIgnoresUnrelatedPersistedRecoveryActionWhenNewerRunIsActive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-unrelated-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let retryLineage = sourceLineage.retryChild(parentRunID: "run-source")
        let unrelatedLineage = XTAutomationRunLineage.root(runID: "run-newer")

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_348,
                lineage: sourceLineage,
                deliveryRef: "build/reports/xt_auto_source_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_349,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting for retry child handoff."
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_350,
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
            launchRow(
                runID: "run-newer",
                createdAt: 1_773_200_351,
                lineage: unrelatedLineage,
                deliveryRef: "build/reports/xt_auto_newer_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-newer",
                recipeID: "recipe-runtime-newer",
                state: .queued,
                createdAt: 1_773_200_352,
                currentStepID: "step-collect-context",
                currentStepTitle: "Collect context",
                currentStepState: .pending,
                currentStepSummary: "waiting_to_start_first_action"
            ),
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_360)
            )
        )

        #expect(snapshot.contextSource == "checkpoint")
        #expect(snapshot.runID == "run-newer")
        #expect(snapshot.effectiveRunID == "run-newer")
        #expect(snapshot.persistedRecoveryAction == nil)
        #expect(snapshot.effectiveDeliveryRef == "build/reports/xt_auto_newer_delivery.v1.json")
        #expect(snapshot.effectiveDeliveryClosureSource == .launch)
        #expect(snapshot.deliveryClosure?.runID == "run-newer")
        #expect(snapshot.deliveryClosure?.source == .launch)
        #expect(snapshot.deliveryClosure?.lineage.lineageID == unrelatedLineage.lineageID)
        #expect(
            xtAutomationLatestPersistedRecoveryActionSummary(
                from: xtAutomationReadRawLogRows(for: ctx),
                preferredRunID: "run-newer"
            ) == nil
        )
    }

    @Test
    func latestProjectContinuitySnapshotIgnoresStalePersistedRecoveryActionWhenSameSourceRunHasNewerCheckpoint() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-project-continuity-stale-recovery-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let retryLineage = XTAutomationRunLineage.root(runID: "run-source").retryChild(
            parentRunID: "run-source",
            retryDepth: 1
        )

        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_370,
                attempt: 2,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "older blocked checkpoint before recovery"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_371,
                "run_id": "run-source",
                "recipe_id": "recipe-runtime",
                "recovered_state": XTAutomationRunState.blocked.rawValue,
                "decision": XTAutomationRestartRecoveryAction.resume.rawValue,
                "hold_reason": NSNull(),
                "stable_identity_pass": true,
                "checkpoint_ref": "checkpoint-run-source-old-recovery",
                "resume_token": "resume-run-source-old-recovery",
                "recovery_mode": XTAutomationRestartRecoveryMode.operatorOverride.rawValue,
                "resume_mode": XTAutomationRecoveryResumeMode.retryPackage.rawValue,
                "retry_run_id": "run-retry-child-old",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "delivery_ref": "build/reports/xt_auto_retry_old_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child-old",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "audit_ref": "audit-recovery-row-old"
            ],
            for: ctx
        )
        AXProjectStore.appendRawLog(
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_372,
                attempt: 3,
                currentStepID: "step-verify",
                currentStepTitle: "Verify focused smoke tests",
                currentStepState: .blocked,
                currentStepSummary: "newer checkpoint proves the older recovery action is stale"
            ),
            for: ctx
        )

        let snapshot = try #require(
            xtAutomationLatestProjectContinuitySnapshot(
                for: ctx,
                projectID: projectId,
                now: Date(timeIntervalSince1970: 1_773_200_380)
            )
        )

        #expect(snapshot.contextSource == "checkpoint")
        #expect(snapshot.runID == "run-source")
        #expect(snapshot.persistedRecoveryAction == nil)
        #expect(snapshot.effectiveRunID == "run-source")
        #expect(snapshot.effectiveLineage == nil)
        #expect(snapshot.effectiveDeliveryRef == nil)
        #expect(snapshot.effectiveDeliveryClosureSource == nil)
    }

    @Test
    func latestPersistedRecoveryActionSummaryMatchesRetryRunIDAndCarriesDeliveryClosure() throws {
        let retryLineage = XTAutomationRunLineage.root(runID: "run-source").retryChild(
            parentRunID: "run-source",
            retryDepth: 1
        )
        let rows: [[String: Any]] = [
            [
                "type": "automation_run_recovery",
                "created_at": 1_773_200_330,
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
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "delivery_closure_source": XTAutomationDeliveryClosureProjectionSource.retryPackage.rawValue,
                "delivery_closure_run_id": "run-retry-child",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "audit_ref": "audit-recovery-row"
            ]
        ]

        let summary = try #require(
            xtAutomationLatestPersistedRecoveryActionSummary(
                from: rows,
                preferredRunID: "run-retry-child"
            )
        )

        #expect(summary.decision.runID == "run-source")
        #expect(summary.decision.decision == .resume)
        #expect(summary.recoveryMode == .operatorOverride)
        #expect(summary.resumeMode == .retryPackage)
        #expect(summary.retryRunID == "run-retry-child")
        #expect(summary.retryStrategy == "verify_failed_retry")
        #expect(summary.retryReason == "automation_verify_failed")
        #expect(summary.decision.schemaVersion == XTAutomationRestartRecoveryDecision.currentSchemaVersion)
        #expect(summary.deliveryClosure?.runID == "run-retry-child")
        #expect(summary.deliveryClosure?.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(summary.deliveryClosure?.source == .retryPackage)
        #expect(summary.deliveryClosure?.lineage.lineageID == retryLineage.lineageID)
        #expect(summary.deliveryClosure?.lineage.parentRunID == "run-source")
        #expect(summary.deliveryClosure?.lineage.retryDepth == 1)
    }

    @Test
    func runStartedAtMsUsesLaunchEventWhenPresent() {
        let rows: [[String: Any]] = [
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_040,
                "run_id": "run-started-with-launch"
            ],
            checkpointRow(
                runID: "run-started-with-launch",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_041
            )
        ]

        let startedAtMs = xtAutomationRunStartedAtMs(
            for: "run-started-with-launch",
            from: rows
        )

        #expect(startedAtMs == 1_773_200_040_000)
    }

    @Test
    func runStartedAtMsFallsBackToFirstCheckpointWhenLaunchEventMissing() {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-started-from-checkpoint",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_050
            ),
            checkpointRow(
                runID: "run-started-from-checkpoint",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_051
            )
        ]

        let startedAtMs = xtAutomationRunStartedAtMs(
            for: "run-started-from-checkpoint",
            from: rows
        )

        #expect(startedAtMs == 1_773_200_050_000)
    }

    @Test
    func persistedRunDeliveryRefLoadsFromLaunchRow() {
        let rows: [[String: Any]] = [
            [
                "type": "automation_run_launch",
                "created_at": 1_773_200_040,
                "run_id": "run-with-delivery-ref",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json"
            ]
        ]

        let deliveryRef = xtAutomationPersistedRunDeliveryRef(
            for: "run-with-delivery-ref",
            from: rows
        )

        #expect(deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
    }

    @Test
    func loadExecutionReportFallsBackToLaunchDeliveryRefWhenExecutionRowOmitsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-runtime-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-execution-delivery-ref-fallback",
                createdAt: 1_773_200_045,
                lineage: .root(runID: "run-execution-delivery-ref-fallback"),
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_046,
                "run_id": "run-execution-delivery-ref-fallback",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "SmokeTests failed",
                "executed_action_count": 1,
                "succeeded_action_count": 1,
                "total_action_count": 1,
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 1,
                    "passed_command_count": 0,
                    "hold_reason": "automation_verify_failed",
                    "detail": "SmokeTests failed",
                    "verification_contract": [
                        "expected_state": "post_change_verification_passes",
                        "verify_method": "project_verify_commands",
                        "retry_policy": "manual_retry_or_replan",
                        "hold_policy": "block_run_and_emit_structured_blocker",
                        "evidence_required": true,
                        "trigger_action_ids": ["apply_patch"],
                        "verify_commands": ["swift test --filter SmokeTests"]
                    ]
                ],
                "audit_ref": "audit-execution-delivery-ref-fallback"
            ],
            for: ctx
        )

        let report = try #require(
            xtAutomationLoadExecutionReport(
                for: "run-execution-delivery-ref-fallback",
                ctx: ctx
            )
        )

        #expect(report.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(report.verificationReport?.contract?.verifyMethod == "project_verify_commands")
        #expect(report.verificationReport?.contract?.retryPolicy == "manual_retry_or_replan")
        #expect(report.verificationReport?.contract?.verifyCommands == ["swift test --filter SmokeTests"])
    }

    @Test
    func loadExecutionReportPreservesVerificationContractFromHandoffArtifactWhenRowOnlyHasSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-runtime-handoff-verify-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        let handoffPath = "build/reports/xt_auto_handoff_verify_contract.json"
        let handoffURL = root.appendingPathComponent(handoffPath)
        try FileManager.default.createDirectory(
            at: handoffURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let verificationContract = XTAutomationVerificationContract(
            expectedState: "post_change_verification_passes",
            verifyMethod: "project_verify_commands",
            retryPolicy: "manual_retry_or_replan",
            holdPolicy: "block_run_and_emit_structured_blocker",
            evidenceRequired: true,
            triggerActionIDs: ["apply_patch"],
            verifyCommands: ["swift test --filter SmokeTests"]
        )
        let handoffArtifact = XTAutomationRunHandoffArtifact(
            schemaVersion: XTAutomationRunHandoffArtifact.currentSchemaVersion,
            generatedAt: 1_773_200_048,
            runID: "run-execution-handoff-contract",
            lineage: nil,
            recipeRef: "recipe-runtime",
            deliveryRef: nil,
            finalState: .blocked,
            holdReason: "automation_verify_failed",
            detail: "SmokeTests failed",
            actionResults: [],
            verificationReport: XTAutomationVerificationReport(
                required: true,
                executed: true,
                commandCount: 1,
                passedCommandCount: 0,
                holdReason: "automation_verify_failed",
                detail: "SmokeTests failed",
                commandResults: [],
                contract: verificationContract
            ),
            workspaceDiffReport: nil,
            suggestedNextActions: [],
            structuredBlocker: nil,
            currentStepID: "step-verify",
            currentStepTitle: "Verify focused smoke tests",
            currentStepState: .retryWait,
            currentStepSummary: "Waiting before retrying the reduced verify set."
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(handoffArtifact).write(to: handoffURL, options: .atomic)

        AXProjectStore.appendRawLog(
            [
                "type": "automation_execution",
                "phase": "completed",
                "created_at": 1_773_200_049,
                "run_id": "run-execution-handoff-contract",
                "recipe_ref": "recipe-runtime",
                "final_state": XTAutomationRunState.blocked.rawValue,
                "hold_reason": "automation_verify_failed",
                "detail": "SmokeTests failed",
                "executed_action_count": 1,
                "succeeded_action_count": 1,
                "total_action_count": 1,
                "handoff_artifact_path": handoffPath,
                "verification": [
                    "required": true,
                    "executed": true,
                    "command_count": 1,
                    "passed_command_count": 0,
                    "hold_reason": "automation_verify_failed",
                    "detail": "SmokeTests failed"
                ],
                "audit_ref": "audit-execution-handoff-contract"
            ],
            for: ctx
        )

        let report = try #require(
            xtAutomationLoadExecutionReport(
                for: "run-execution-handoff-contract",
                ctx: ctx
            )
        )

        #expect(report.verificationReport?.required == true)
        #expect(report.verificationReport?.executed == true)
        #expect(report.verificationReport?.commandCount == 1)
        #expect(report.verificationReport?.passedCommandCount == 0)
        #expect(report.verificationReport?.contract?.verifyMethod == "project_verify_commands")
        #expect(report.verificationReport?.contract?.retryPolicy == "manual_retry_or_replan")
        #expect(report.verificationReport?.contract?.verifyCommands == ["swift test --filter SmokeTests"])
    }

    @Test
    func loadRetryPackageFallsBackToRowLevelRevisedVerificationContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-runtime-retry-row-contract-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let project = AXProjectEntry(
            projectId: "project-runtime",
            rootPath: root.path,
            displayName: "project-runtime",
            lastOpenedAt: 1_773_200_047,
            pinned: false
        )

        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_047,
                "source_run_id": "run-source-verify",
                "retry_run_id": "run-retry-verify",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "source_handoff_artifact_path": "build/reports/handoff.json",
                "retry_trigger": "manual",
                "revised_verification_contract": [
                    "expected_state": "post_change_verification_passes",
                    "verify_method": "project_verify_commands_override",
                    "retry_policy": "retry_failed_verify_commands_within_budget",
                    "hold_policy": "block_run_and_emit_structured_blocker",
                    "evidence_required": true,
                    "trigger_action_ids": ["verify_smoke"],
                    "verify_commands": ["swift test --filter SmokeTests --skip PassedCase"]
                ]
            ],
            for: ctx
        )

        let package = try #require(
            xtAutomationLoadRetryPackage(
                forRetryRunID: "run-retry-verify",
                projectID: project.projectId,
                ctx: ctx
            )
        )

        #expect(package.revisedVerificationContract?.verifyMethod == "project_verify_commands_override")
        #expect(package.revisedVerificationContract?.retryPolicy == "retry_failed_verify_commands_within_budget")
        #expect(package.revisedVerificationContract?.verifyCommands == ["swift test --filter SmokeTests --skip PassedCase"])
        #expect(package.revisedVerifyCommands == ["swift test --filter SmokeTests --skip PassedCase"])
    }

    @Test
    func safePointHoldHelperMatchesRunAndInjectionIdentity() {
        let rows: [[String: Any]] = [
            [
                "type": "automation_safe_point_hold",
                "created_at": 1_773_200_055,
                "run_id": "run-safe-point-target",
                "injection_id": "guidance-safe-point-target"
            ],
            [
                "type": "automation_safe_point_hold",
                "created_at": 1_773_200_056,
                "run_id": "run-safe-point-other",
                "injection_id": "guidance-safe-point-other"
            ]
        ]

        #expect(
            xtAutomationHasSafePointHold(
                runID: "run-safe-point-target",
                injectionId: "guidance-safe-point-target",
                from: rows
            )
        )
        #expect(
            !xtAutomationHasSafePointHold(
                runID: "run-safe-point-target",
                injectionId: "guidance-safe-point-other",
                from: rows
            )
        )
        #expect(
            !xtAutomationHasSafePointHold(
                runID: "run-safe-point-target",
                injectionId: "",
                from: rows
            )
        )
    }

    @Test
    func latestRecoverableCheckpointSummaryPrefersOlderUnsupersededBlockedRunOverNewerUnrelatedDeliveredRun() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-older-blocked",
                createdAt: 1_773_200_056,
                lineage: .root(runID: "run-older-blocked")
            ),
            checkpointRow(
                runID: "run-older-blocked",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_057
            ),
            launchRow(
                runID: "run-newer-delivered",
                createdAt: 1_773_200_058,
                lineage: .root(runID: "run-newer-delivered")
            ),
            checkpointRow(
                runID: "run-newer-delivered",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_059
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoverableCheckpointSummary(from: rows)
        )

        #expect(summary.checkpoint.runID == "run-older-blocked")
        #expect(summary.checkpoint.state == .blocked)
    }

    @Test
    func latestRecoveryCandidateSummaryExplainsVisibleLatestDeliveredRunAsNonRecoverable() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-older-blocked",
                createdAt: 1_773_200_056,
                lineage: .root(runID: "run-older-blocked")
            ),
            checkpointRow(
                runID: "run-older-blocked",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_057
            ),
            launchRow(
                runID: "run-newer-delivered",
                createdAt: 1_773_200_058,
                lineage: .root(runID: "run-newer-delivered")
            ),
            checkpointRow(
                runID: "run-newer-delivered",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_059
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(from: rows)
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-older-blocked")
        #expect(summary.selection == .latestRecoverableUnsuperseded)
        #expect(summary.latestVisibleRunID == "run-newer-delivered")
        #expect(summary.latestVisibleState == .delivered)
        #expect(summary.reason == .latestVisibleNotRecoverable)
        #expect(summary.supersededRunID == nil)
        #expect(summary.supersededByRunID == nil)
    }

    @Test
    func latestRecoveryCandidateSummaryPrefersLatestVisibleQueuedRunOverOlderUnrelatedRecoverableRun() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-older-blocked",
                createdAt: 1_773_200_056,
                lineage: .root(runID: "run-older-blocked")
            ),
            checkpointRow(
                runID: "run-older-blocked",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_057
            ),
            launchRow(
                runID: "run-newer-queued",
                createdAt: 1_773_200_058,
                lineage: .root(runID: "run-newer-queued")
            ),
            checkpointRow(
                runID: "run-newer-queued",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_059
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(from: rows)
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-newer-queued")
        #expect(summary.checkpointSummary.checkpoint.state == .queued)
        #expect(summary.selection == .latestVisibleCheckpoint)
        #expect(summary.latestVisibleRunID == "run-newer-queued")
        #expect(summary.latestVisibleState == .queued)
        #expect(summary.reason == .latestVisibleActiveRun)
        #expect(summary.supersededRunID == nil)
        #expect(summary.supersededByRunID == nil)
    }

    @Test
    func latestRecoveryCandidateSummaryProjectsLatestVisibleRetryWaitReasonWhenBackoffNotElapsed() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-retry-wait",
                createdAt: 1_773_200_080,
                lineage: .root(runID: "run-retry-wait")
            ),
            checkpointRow(
                runID: "run-retry-wait",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_081,
                retryAfterSeconds: 120
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(
                from: rows,
                now: 1_773_200_141
            )
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-retry-wait")
        #expect(summary.selection == .latestRecoverableUnsuperseded)
        #expect(summary.reason == .latestVisibleRetryWait)
    }

    @Test
    func latestRecoveryCandidateSummaryProjectsLatestVisibleRetryBudgetExhaustedReason() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-retry-budget",
                createdAt: 1_773_200_082,
                lineage: .root(runID: "run-retry-budget")
            ),
            checkpointRow(
                runID: "run-retry-budget",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_083,
                attempt: 4
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(
                from: rows,
                now: 1_773_200_084
            )
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-retry-budget")
        #expect(summary.selection == .latestRecoverableUnsuperseded)
        #expect(summary.reason == .latestVisibleRetryBudgetExhausted)
    }

    @Test
    func latestRecoveryCandidateSummaryProjectsStableIdentityFailureReason() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-identity-drift",
                createdAt: 1_773_200_085,
                lineage: .root(runID: "run-identity-drift")
            ),
            checkpointRow(
                runID: "run-identity-drift",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_086,
                attempt: 2,
                stableIdentity: false
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(
                from: rows,
                now: 1_773_200_090
            )
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-identity-drift")
        #expect(summary.selection == .latestVisibleCheckpoint)
        #expect(summary.reason == .latestVisibleStableIdentityFailed)
    }

    @Test
    func latestRecoveryCandidateSummaryKeepsLatestVisibleStableIdentityFailureOverOlderRecoverableRun() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-older-stable",
                createdAt: 1_773_200_080,
                lineage: .root(runID: "run-older-stable")
            ),
            checkpointRow(
                runID: "run-older-stable",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_081,
                stableIdentity: true
            ),
            launchRow(
                runID: "run-latest-identity-drift",
                createdAt: 1_773_200_082,
                lineage: .root(runID: "run-latest-identity-drift")
            ),
            checkpointRow(
                runID: "run-latest-identity-drift",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_083,
                stableIdentity: false
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(
                from: rows,
                now: 1_773_200_090
            )
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-latest-identity-drift")
        #expect(summary.selection == .latestVisibleCheckpoint)
        #expect(summary.reason == .latestVisibleStableIdentityFailed)
        #expect(summary.latestVisibleRunID == "run-latest-identity-drift")
    }

    @Test
    func latestRecoverableCheckpointSummarySkipsStableIdentityFailedRun() throws {
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-stable",
                createdAt: 1_773_200_084,
                lineage: .root(runID: "run-stable")
            ),
            checkpointRow(
                runID: "run-stable",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_085,
                stableIdentity: true
            ),
            launchRow(
                runID: "run-unstable",
                createdAt: 1_773_200_086,
                lineage: .root(runID: "run-unstable")
            ),
            checkpointRow(
                runID: "run-unstable",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_087,
                stableIdentity: false
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoverableCheckpointSummary(from: rows)
        )

        #expect(summary.checkpoint.runID == "run-stable")
        #expect(summary.checkpoint.stableIdentity)
    }

    @Test
    func latestRecoverableCheckpointSummarySkipsSupersededRunWhenNewerSameLineageRetryExists() throws {
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_060,
                lineage: sourceLineage
            ),
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_061
            ),
            launchRow(
                runID: "run-retry-child",
                createdAt: 1_773_200_062,
                lineage: sourceLineage.retryChild(parentRunID: "run-source")
            ),
            checkpointRow(
                runID: "run-retry-child",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_063
            )
        ]

        #expect(
            xtAutomationLatestRecoverableCheckpointSummary(from: rows) == nil
        )
    }

    @Test
    func latestRecoveryCandidateSummaryReportsSupersededRecoverableRunWhenFallbackSelectsLatestVisibleCheckpoint() throws {
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_060,
                lineage: sourceLineage
            ),
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_061
            ),
            launchRow(
                runID: "run-retry-child",
                createdAt: 1_773_200_062,
                lineage: sourceLineage.retryChild(parentRunID: "run-source")
            ),
            checkpointRow(
                runID: "run-retry-child",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_063
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(from: rows)
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-retry-child")
        #expect(summary.selection == .latestVisibleCheckpoint)
        #expect(summary.latestVisibleRunID == "run-retry-child")
        #expect(summary.latestVisibleState == .delivered)
        #expect(summary.reason == .noRecoverableUnsupersededRun)
        #expect(summary.supersededRunID == "run-source")
        #expect(summary.supersededByRunID == "run-retry-child")
    }

    @Test
    func latestRecoveryCandidateSummaryDoesNotReportUnrelatedSupersededRunWhenFallbackSelectsDifferentLatestVisibleCheckpoint() throws {
        let sourceLineage = XTAutomationRunLineage.root(runID: "run-source")
        let rows: [[String: Any]] = [
            launchRow(
                runID: "run-source",
                createdAt: 1_773_200_070,
                lineage: sourceLineage
            ),
            checkpointRow(
                runID: "run-source",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_071
            ),
            launchRow(
                runID: "run-retry-child",
                createdAt: 1_773_200_072,
                lineage: sourceLineage.retryChild(parentRunID: "run-source")
            ),
            checkpointRow(
                runID: "run-retry-child",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_073
            ),
            launchRow(
                runID: "run-unrelated-delivered",
                createdAt: 1_773_200_074,
                lineage: .root(runID: "run-unrelated-delivered")
            ),
            checkpointRow(
                runID: "run-unrelated-delivered",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_075
            )
        ]

        let summary = try #require(
            xtAutomationLatestRecoveryCandidateSummary(from: rows)
        )

        #expect(summary.checkpointSummary.checkpoint.runID == "run-unrelated-delivered")
        #expect(summary.selection == .latestVisibleCheckpoint)
        #expect(summary.latestVisibleRunID == "run-unrelated-delivered")
        #expect(summary.latestVisibleState == .delivered)
        #expect(summary.reason == .noRecoverableUnsupersededRun)
        #expect(summary.supersededRunID == nil)
        #expect(summary.supersededByRunID == nil)
    }

    @Test
    func checkpointReconstructionReplaysTransitionsAndCancellation() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-reconstruct",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_060,
                currentStepID: "step-bootstrap",
                currentStepTitle: "Collect context",
                currentStepState: .pending,
                currentStepSummary: "waiting_to_start_first_action"
            ),
            checkpointRow(
                runID: "run-reconstruct",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_061,
                retryAfterSeconds: 90,
                currentStepID: "step-verify",
                currentStepTitle: "Verify smoke tests",
                currentStepState: .retryWait,
                currentStepSummary: "Waiting before retrying the reduced verify set."
            ),
            cancelRow(
                runID: "run-reconstruct",
                createdAt: 1_773_200_062
            )
        ]

        let reconstruction = try #require(
            xtAutomationCheckpointReconstruction(
                for: "run-reconstruct",
                from: rows
            )
        )

        #expect(reconstruction.latestCheckpoint.runID == "run-reconstruct")
        #expect(reconstruction.latestCheckpoint.state == .blocked)
        #expect(reconstruction.latestCheckpoint.retryAfterSeconds == 90)
        #expect(reconstruction.latestCheckpoint.currentStepID == "step-verify")
        #expect(reconstruction.latestCheckpoint.currentStepTitle == "Verify smoke tests")
        #expect(reconstruction.latestCheckpoint.currentStepState == .retryWait)
        #expect(reconstruction.latestCheckpoint.currentStepSummary == "Waiting before retrying the reduced verify set.")
        #expect(reconstruction.store.current == reconstruction.latestCheckpoint)
        #expect(reconstruction.store.history.count == 2)
        #expect(reconstruction.store.cancelled)
        #expect(reconstruction.wasCancelled)
    }

    @Test
    func checkpointReconstructionPreservesPersistedStableIdentityFailure() throws {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-identity-drift",
                recipeID: "recipe-runtime",
                state: .queued,
                createdAt: 1_773_200_063,
                stableIdentity: true,
                currentStepID: "step-bootstrap",
                currentStepTitle: "Collect context",
                currentStepState: .pending,
                currentStepSummary: "waiting_to_start_first_action"
            ),
            checkpointRow(
                runID: "run-identity-drift",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_064,
                retryAfterSeconds: 0,
                stableIdentity: false,
                currentStepID: "step-verify",
                currentStepTitle: "Verify smoke tests",
                currentStepState: .blocked,
                currentStepSummary: "Identity drift detected during persisted recovery reconstruction."
            )
        ]

        let reconstruction = try #require(
            xtAutomationCheckpointReconstruction(
                for: "run-identity-drift",
                from: rows
            )
        )

        #expect(reconstruction.latestCheckpoint.runID == "run-identity-drift")
        #expect(reconstruction.latestCheckpoint.state == .blocked)
        #expect(reconstruction.latestCheckpoint.stableIdentity == false)
        #expect(reconstruction.store.current?.stableIdentity == false)
        #expect(reconstruction.store.history.map(\.state) == [.queued, .blocked])
        #expect(reconstruction.store.history.map(\.stableIdentity) == [true, false])
    }

    @Test
    func loadRetryPackageHydratesStructuredBlockerAndReasonFromRawLogFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-runtime-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)

        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_095,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry",
                "delivery_ref": "build/reports/xt_auto_manual_delivery.v1.json",
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed",
                "retry_reason_descriptor": [
                    "code": "automation_verify_failed",
                    "category": "verification",
                    "summary": "retry failing verification only",
                    "strategy": "verify_failed_retry",
                    "blocker_code": "automation_verify_failed",
                    "planning_mode": "verify_only_retry",
                    "current_step_id": "verify_smoke",
                    "current_step_title": "Verify smoke",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting for retry window"
                ],
                "source_blocker": [
                    "code": "automation_verify_failed",
                    "summary": "verification failed",
                    "stage": "verification",
                    "detail": "1 of 2 checks passed",
                    "next_safe_action": "rerun_focused_verification",
                    "retry_eligible": true,
                    "current_step_id": "verify_smoke",
                    "current_step_title": "Verify smoke",
                    "current_step_state": "retry_wait",
                    "current_step_summary": "Waiting for retry window"
                ]
            ],
            for: ctx
        )

        let package = try #require(
            xtAutomationLoadRetryPackage(
                forRetryRunID: "run-retry",
                projectID: projectId,
                ctx: ctx
            )
        )

        #expect(package.sourceRunID == "run-source")
        #expect(package.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(package.sourceBlocker?.code == "automation_verify_failed")
        #expect(package.sourceBlocker?.stage == .verification)
        #expect(package.sourceBlocker?.currentStepTitle == "Verify smoke")
        #expect(package.retryReasonDescriptor?.category == .verification)
        #expect(package.retryReasonDescriptor?.summary == "retry failing verification only")
        #expect(package.retryReasonDescriptor?.currentStepState == .retryWait)
    }

    @Test
    func loadRetryPackageFallsBackToRetryRunLaunchDeliveryRefWhenRawRowOmitsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xt-automation-runtime-persistence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()
        let projectId = AXProjectRegistryStore.projectId(forRoot: root)
        let retryLineage = XTAutomationRunLineage.root(runID: "run-source").retryChild(
            parentRunID: "run-source",
            retryDepth: 1
        )

        AXProjectStore.appendRawLog(
            launchRow(
                runID: "run-retry-with-launch-delivery",
                createdAt: 1_773_200_096,
                lineage: retryLineage,
                deliveryRef: "build/reports/xt_auto_manual_delivery.v1.json"
            ),
            for: ctx
        )
        AXProjectStore.appendRawLog(
            [
                "type": "automation_retry",
                "status": "scheduled",
                "created_at": 1_773_200_097,
                "source_run_id": "run-source",
                "retry_run_id": "run-retry-with-launch-delivery",
                "lineage_id": retryLineage.lineageID,
                "root_run_id": retryLineage.rootRunID,
                "parent_run_id": retryLineage.parentRunID,
                "retry_depth": retryLineage.retryDepth,
                "retry_strategy": "verify_failed_retry",
                "retry_reason": "automation_verify_failed"
            ],
            for: ctx
        )

        let package = try #require(
            xtAutomationLoadRetryPackage(
                forRetryRunID: "run-retry-with-launch-delivery",
                projectID: projectId,
                ctx: ctx
            )
        )

        #expect(package.deliveryRef == "build/reports/xt_auto_manual_delivery.v1.json")
        #expect(package.lineage?.parentRunID == "run-source")
        #expect(package.lineage?.retryDepth == 1)
    }

    @Test
    func checkpointAgeSecondsCanBeComputedForSpecificRun() {
        let rows: [[String: Any]] = [
            checkpointRow(
                runID: "run-older",
                recipeID: "recipe-runtime",
                state: .blocked,
                createdAt: 1_773_200_070
            ),
            checkpointRow(
                runID: "run-newer",
                recipeID: "recipe-runtime",
                state: .delivered,
                createdAt: 1_773_200_090
            )
        ]

        let specificRunAge = xtAutomationCheckpointAgeSeconds(
            for: "run-older",
            from: rows,
            now: 1_773_200_100
        )
        let latestRunAge = xtAutomationCheckpointAgeSeconds(
            from: rows,
            now: 1_773_200_100
        )

        #expect(specificRunAge == 30)
        #expect(latestRunAge == 10)
    }
}

private func checkpointRow(
    runID: String,
    recipeID: String,
    state: XTAutomationRunState,
    createdAt: TimeInterval,
    attempt: Any = 1,
    retryAfterSeconds: Any = 0,
    stableIdentity: Any = true,
    currentStepID: String? = nil,
    currentStepTitle: String? = nil,
    currentStepState: XTAutomationRunStepState? = nil,
    currentStepSummary: String? = nil
) -> [String: Any] {
    [
        "type": "automation_checkpoint",
        "created_at": createdAt,
        "run_id": runID,
        "recipe_id": recipeID,
        "state": state.rawValue,
        "attempt": attempt,
        "last_transition": "transition-\(state.rawValue)",
        "retry_after_seconds": retryAfterSeconds,
        "resume_token": "resume-\(runID)",
        "checkpoint_ref": "checkpoint-\(runID)",
        "stable_identity": stableIdentity,
        "current_step_id": currentStepID ?? NSNull(),
        "current_step_title": currentStepTitle ?? NSNull(),
        "current_step_state": currentStepState?.rawValue ?? NSNull(),
        "current_step_summary": currentStepSummary ?? NSNull(),
        "audit_ref": "audit-\(runID)"
    ]
}

private func launchRow(
    runID: String,
    createdAt: TimeInterval,
    lineage: XTAutomationRunLineage,
    deliveryRef: String? = nil
) -> [String: Any] {
    [
        "type": "automation_run_launch",
        "created_at": createdAt,
        "run_id": runID,
        "lineage_id": lineage.lineageID,
        "root_run_id": lineage.rootRunID,
        "parent_run_id": lineage.parentRunID.isEmpty ? NSNull() : lineage.parentRunID,
        "retry_depth": lineage.retryDepth,
        "delivery_ref": deliveryRef ?? NSNull()
    ]
}

private func cancelRow(
    runID: String,
    createdAt: TimeInterval
) -> [String: Any] {
    [
        "type": "automation_run_cancel",
        "created_at": createdAt,
        "run_id": runID,
        "audit_ref": "audit-cancel-\(runID)"
    ]
}
