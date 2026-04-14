import Foundation

enum XTAutomationRunCoordinatorError: Error, Equatable {
    case activeRecipeMissing
    case triggerSeedsMissing
    case triggerIngressNotAllowed(String)
    case triggerIngressReplayDetected(String)
    case triggerIngressPolicyMissing(String)
    case runNotFound(String)
}

struct XTAutomationRunRequest {
    let triggerSeeds: [XTAutomationTriggerSeed]
    let lineage: XTAutomationRunLineage?
    let hubTransportMode: HubTransportMode
    let hasRemoteProfile: Bool
    let budgetOK: Bool
    let trustedAutomationReady: Bool
    let permissionOwnerReady: Bool
    let currentOwner: String
    let activePoolCount: Int
    let activeLaneCount: Int
    let blockedTaskID: String
    let upstreamDependencyIDs: [String]
    let operatorConsoleEvidenceRef: String
    let latestDeltaRef: String
    let deliveryRef: String
    let firstRunChecklistRef: String
    let additionalEvidenceRefs: [String]
    let intakeWorkflow: ProjectIntakeWorkflowResult?
    let acceptanceWorkflow: AcceptanceWorkflowResult?
    let recipeOverride: AXAutomationRecipeRuntimeBinding?
    let verifyCommandsOverride: [String]?
    let verificationContractOverride: XTAutomationVerificationContract?
    let now: Date

    init(
        triggerSeeds: [XTAutomationTriggerSeed],
        lineage: XTAutomationRunLineage? = nil,
        hubTransportMode: HubTransportMode = .auto,
        hasRemoteProfile: Bool = true,
        budgetOK: Bool = true,
        trustedAutomationReady: Bool = true,
        permissionOwnerReady: Bool = true,
        currentOwner: String = "XT-L2",
        activePoolCount: Int = 1,
        activeLaneCount: Int = 1,
        blockedTaskID: String = "XT-AUTO-BLOCKER",
        upstreamDependencyIDs: [String] = [],
        operatorConsoleEvidenceRef: String = "build/reports/xt_w3_24_d_operator_console_evidence.v1.json",
        latestDeltaRef: String = "build/reports/xt_w3_25_run_delta_3line.v1.json",
        deliveryRef: String = "build/reports/xt_w3_25_delivery_card.v1.json",
        firstRunChecklistRef: String = "docs/open-source/OSS_MINIMAL_RUNNABLE_PACKAGE_CHECKLIST_v1.md",
        additionalEvidenceRefs: [String] = [],
        intakeWorkflow: ProjectIntakeWorkflowResult? = nil,
        acceptanceWorkflow: AcceptanceWorkflowResult? = nil,
        recipeOverride: AXAutomationRecipeRuntimeBinding? = nil,
        verifyCommandsOverride: [String]? = nil,
        verificationContractOverride: XTAutomationVerificationContract? = nil,
        now: Date = Date()
    ) {
        self.triggerSeeds = triggerSeeds
        self.lineage = lineage
        self.hubTransportMode = hubTransportMode
        self.hasRemoteProfile = hasRemoteProfile
        self.budgetOK = budgetOK
        self.trustedAutomationReady = trustedAutomationReady
        self.permissionOwnerReady = permissionOwnerReady
        self.currentOwner = currentOwner
        self.activePoolCount = activePoolCount
        self.activeLaneCount = activeLaneCount
        self.blockedTaskID = blockedTaskID
        self.upstreamDependencyIDs = upstreamDependencyIDs
        self.operatorConsoleEvidenceRef = operatorConsoleEvidenceRef
        self.latestDeltaRef = latestDeltaRef
        self.deliveryRef = deliveryRef
        self.firstRunChecklistRef = firstRunChecklistRef
        self.additionalEvidenceRefs = additionalEvidenceRefs
        self.intakeWorkflow = intakeWorkflow
        self.acceptanceWorkflow = acceptanceWorkflow
        self.recipeOverride = recipeOverride
        self.verifyCommandsOverride = verifyCommandsOverride
        self.verificationContractOverride = verificationContractOverride
        self.now = now
    }
}

struct XTAutomationPreparedRun: Equatable {
    let recipeRef: String
    let launchRef: String
    let lineage: XTAutomationRunLineage
    let verticalSlice: XTAutomationVerticalSliceResult
    let currentCheckpoint: XTAutomationRunCheckpoint
    let executionRecipe: AXAutomationRecipeRuntimeBinding
    let verifyCommandsOverride: [String]?
    let verificationContractOverride: XTAutomationVerificationContract?
}

struct XTAutomationRecoveryCandidate: Equatable {
    let runID: String
    let state: XTAutomationRunState
    let selection: XTAutomationRecoveryCandidateSelection
    let latestVisibleRunID: String
    let latestVisibleState: XTAutomationRunState
    let reason: XTAutomationRecoveryCandidateReason
    let supersededRunID: String?
    let supersededByRunID: String?
    let deliveryRef: String?
    let checkpointAgeSeconds: Int
    let retryAfterSeconds: Int
    let retryAfterRemainingSeconds: Int?
    let automaticDecision: XTAutomationRestartRecoveryAction
    let automaticHoldReason: String
    let automaticResumeMode: XTAutomationRecoveryResumeMode?
    let automaticRetryStrategy: String?
    let automaticRetryReason: String?
    let automaticRetryPlanningMode: String?
    let automaticRetrySourceHandoffArtifactPath: String?
}

final class XTAutomationRunCoordinator {
    private let verticalSliceEngine = XTAutomationProductGapClosureEngine()
    private var checkpointStores: [String: XTAutomationRunCheckpointStore] = [:]

    @discardableResult
    func prepareActiveRun(
        for ctx: AXProjectContext,
        request: XTAutomationRunRequest
    ) throws -> XTAutomationPreparedRun {
        guard !request.triggerSeeds.isEmpty else {
            throw XTAutomationRunCoordinatorError.triggerSeedsMissing
        }

        var config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let activeRecipe = config.activeAutomationRecipe, activeRecipe.lifecycleState == .ready else {
            throw XTAutomationRunCoordinatorError.activeRecipeMissing
        }
        let recipe = (request.recipeOverride ?? activeRecipe).normalized()
        try xtAutomationValidateTriggerIngressSeeds(
            request.triggerSeeds,
            allowedTriggerRefs: recipe.triggerRefs
        )

        let runID = xtAutomationCoordinatorRunID(
            projectRoot: ctx.root.path,
            recipeRef: recipe.ref,
            triggerSeeds: request.triggerSeeds,
            now: request.now
        )
        let lineage = xtAutomationResolvedLineage(request.lineage, fallbackRunID: runID)
        let projectUUID = UUID(
            uuidString: oneShotDeterministicUUIDString(
                seed: "xt_auto_project|\(ctx.root.path)|\(recipe.ref)"
            )
        ) ?? UUID(uuidString: "00000000-0000-5000-8000-000000000000")!

        let input = XTAutomationVerticalSliceInput(
            projectID: projectUUID,
            recipeID: recipe.recipeID,
            goal: recipe.goal,
            deliveryTargets: recipe.deliveryTargets,
            acceptancePackRef: recipe.acceptancePackRef,
            executionProfile: recipe.executionProfile,
            touchMode: recipe.touchMode,
            innovationLevel: recipe.innovationLevel,
            laneStrategy: recipe.laneStrategy,
            runID: runID,
            currentOwner: request.currentOwner,
            activePoolCount: request.activePoolCount,
            activeLaneCount: request.activeLaneCount,
            blockedTaskID: request.blockedTaskID,
            upstreamDependencyIDs: request.upstreamDependencyIDs,
            operatorConsoleEvidenceRef: request.operatorConsoleEvidenceRef,
            latestDeltaRef: request.latestDeltaRef,
            deliveryRef: request.deliveryRef,
            firstRunChecklistRef: request.firstRunChecklistRef,
            triggerSeeds: request.triggerSeeds,
            hubTransportMode: request.hubTransportMode,
            hasRemoteProfile: request.hasRemoteProfile,
            budgetOK: request.budgetOK,
            requiresTrustedAutomation: recipe.requiresTrustedAutomation,
            trustedAutomationReady: request.trustedAutomationReady,
            permissionOwnerReady: request.permissionOwnerReady,
            workspaceBindingHash: recipe.workspaceBindingHash,
            grantPolicyRef: recipe.grantPolicyRef,
            trustedDeviceID: recipe.trustedDeviceID,
            requiredDeviceToolGroups: recipe.requiredDeviceToolGroups,
            intakeWorkflow: request.intakeWorkflow,
            acceptanceWorkflow: request.acceptanceWorkflow,
            additionalEvidenceRefs: request.additionalEvidenceRefs,
            now: request.now
        )

        let verticalSlice = verticalSliceEngine.buildVerticalSlice(input)
        let store = XTAutomationRunCheckpointStore()
        let initialCheckpoint = store.bootstrap(
            runID: runID,
            recipeID: recipe.recipeID,
            initialState: xtAutomationCoordinatorInitialState(for: verticalSlice.eventRunner.launchDecision),
            retryAfterSeconds: verticalSlice.eventRunner.retryAfterSeconds,
            currentStepID: recipe.actionGraph.first?.actionID,
            currentStepTitle: xtAutomationCoordinatorInitialStepTitle(recipe.actionGraph.first),
            currentStepState: recipe.actionGraph.isEmpty ? nil : .pending,
            currentStepSummary: recipe.actionGraph.isEmpty ? nil : "waiting_to_start_first_action",
            auditRef: verticalSlice.overall.auditRef
        )

        checkpointStores[runID] = store
        _ = config.recordAutomationLaunch(recipeRef: recipe.ref, launchRef: runID)
        try AXProjectStore.saveConfig(config, for: ctx)

        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_launch",
                "created_at": request.now.timeIntervalSince1970,
                "run_id": runID,
                "lineage_id": lineage.lineageID,
                "root_run_id": lineage.rootRunID,
                "parent_run_id": lineage.parentRunID.isEmpty ? NSNull() : lineage.parentRunID,
                "retry_depth": lineage.retryDepth,
                "recipe_id": recipe.recipeID,
                "recipe_ref": recipe.ref,
                "delivery_ref": request.deliveryRef,
                "external_trigger_ingress_schema_version": XTAutomationExternalTriggerIngressEnvelope.currentSchemaVersion,
                "trigger_count": request.triggerSeeds.count,
                "non_manual_trigger_count": request.triggerSeeds.filter { $0.triggerType != .manual }.count,
                "launch_decision": verticalSlice.eventRunner.launchDecision.decision.rawValue,
                "hold_reason": verticalSlice.eventRunner.launchDecision.holdReason,
                "audit_ref": verticalSlice.overall.auditRef
            ],
            for: ctx
        )
        persistCheckpoint(initialCheckpoint, createdAt: request.now, for: ctx)

        return XTAutomationPreparedRun(
            recipeRef: recipe.ref,
            launchRef: runID,
            lineage: lineage,
            verticalSlice: verticalSlice,
            currentCheckpoint: initialCheckpoint,
            executionRecipe: recipe,
            verifyCommandsOverride: request.verifyCommandsOverride,
            verificationContractOverride: request.verificationContractOverride
        )
    }

    @discardableResult
    func advanceRun(
        _ runID: String,
        to nextState: XTAutomationRunState,
        retryAfterSeconds: Int = 0,
        currentStepID: String? = nil,
        currentStepTitle: String? = nil,
        currentStepState: XTAutomationRunStepState? = nil,
        currentStepSummary: String? = nil,
        for ctx: AXProjectContext,
        auditRef: String,
        now: Date = Date()
    ) throws -> XTAutomationRunCheckpoint {
        let store = try resolvedStore(for: runID, ctx: ctx)
        let rows = xtAutomationReadRawLogRows(for: ctx)
        if nextState != .blocked,
           let guidance = pendingAutomationSafePointGuidance(
            for: ctx,
            runID: runID,
            store: store,
            rows: rows
           ),
           !xtAutomationHasSafePointHold(
            runID: runID,
            injectionId: guidance.injectionId,
            from: rows
           ) {
            let checkpoint = store.transition(
                to: .blocked,
                retryAfterSeconds: max(retryAfterSeconds, 0),
                currentStepID: currentStepID,
                currentStepTitle: currentStepTitle,
                currentStepState: currentStepState,
                currentStepSummary: currentStepSummary,
                auditRef: auditRef
            )
            AXProjectStore.appendRawLog(
                [
                    "type": "automation_safe_point_hold",
                    "created_at": now.timeIntervalSince1970,
                    "run_id": runID,
                    "requested_state": nextState.rawValue,
                    "result_state": XTAutomationRunState.blocked.rawValue,
                    "review_id": guidance.reviewId,
                    "injection_id": guidance.injectionId,
                    "safe_point_policy": guidance.safePointPolicy.rawValue,
                    "intervention_mode": guidance.interventionMode.rawValue,
                    "delivery_mode": guidance.deliveryMode.rawValue,
                    "audit_ref": auditRef
                ],
                for: ctx
            )
            persistCheckpoint(checkpoint, createdAt: now, for: ctx)
            return checkpoint
        }
        let checkpoint = store.transition(
            to: nextState,
            retryAfterSeconds: retryAfterSeconds,
            currentStepID: currentStepID,
            currentStepTitle: currentStepTitle,
            currentStepState: currentStepState,
            currentStepSummary: currentStepSummary,
            auditRef: auditRef
        )
        persistCheckpoint(checkpoint, createdAt: now, for: ctx)
        return checkpoint
    }

    func cancelRun(
        _ runID: String,
        for ctx: AXProjectContext,
        auditRef: String,
        now: Date = Date()
    ) throws {
        let store = try resolvedStore(for: runID, ctx: ctx)
        store.markCancelled(auditRef: auditRef)
        AXProjectStore.appendRawLog(
            [
                "type": "automation_run_cancel",
                "created_at": now.timeIntervalSince1970,
                "run_id": runID,
                "audit_ref": auditRef
            ],
            for: ctx
        )
    }

    func recoverLatestRun(
        for ctx: AXProjectContext,
        checkpointAgeSeconds: Int,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision? {
        let rows = xtAutomationReadRawLogRows(for: ctx)
        guard let candidate = try latestRecoveryCandidate(
            for: ctx,
            rows: rows,
            now: Date().timeIntervalSince1970
        ) else {
            return nil
        }
        return try recoverRun(
            candidate.runID,
            for: ctx,
            rows: rows,
            checkpointAgeSeconds: checkpointAgeSeconds,
            recoveryMode: recoveryMode,
            auditRef: auditRef
        )
    }

    func recoverLatestRun(
        for ctx: AXProjectContext,
        now: TimeInterval,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision? {
        let rows = xtAutomationReadRawLogRows(for: ctx)
        guard let candidate = try latestRecoveryCandidate(for: ctx, rows: rows, now: now) else {
            return nil
        }
        return try recoverRun(
            candidate.runID,
            for: ctx,
            rows: rows,
            checkpointAgeSeconds: xtAutomationCheckpointAgeSeconds(
                for: candidate.runID,
                from: rows,
                now: now
            ),
            recoveryMode: recoveryMode,
            auditRef: auditRef
        )
    }

    func latestRecoveryCandidate(
        for ctx: AXProjectContext,
        now: TimeInterval = Date().timeIntervalSince1970
    ) throws -> XTAutomationRecoveryCandidate? {
        try latestRecoveryCandidate(
            for: ctx,
            rows: xtAutomationReadRawLogRows(for: ctx),
            now: now
        )
    }

    func latestPersistedRunID(
        for ctx: AXProjectContext,
        preferredRunID: String? = nil,
        allowedStates: Set<XTAutomationRunState>? = nil,
        excludeCancelled: Bool = false
    ) -> String? {
        xtAutomationLatestPersistedCheckpointSummary(
            from: xtAutomationReadRawLogRows(for: ctx),
            preferredRunID: preferredRunID,
            allowedStates: allowedStates,
            excludeCancelled: excludeCancelled
        )?.checkpoint.runID
    }

    func recoverRun(
        _ runID: String,
        for ctx: AXProjectContext,
        checkpointAgeSeconds: Int,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision {
        try recoverRun(
            runID,
            for: ctx,
            rows: xtAutomationReadRawLogRows(for: ctx),
            checkpointAgeSeconds: checkpointAgeSeconds,
            recoveryMode: recoveryMode,
            auditRef: auditRef
        )
    }

    func recoverRun(
        _ runID: String,
        for ctx: AXProjectContext,
        now: TimeInterval,
        recoveryMode: XTAutomationRestartRecoveryMode = .automatic,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision {
        let rows = xtAutomationReadRawLogRows(for: ctx)
        return try recoverRun(
            runID,
            for: ctx,
            rows: rows,
            checkpointAgeSeconds: xtAutomationCheckpointAgeSeconds(
                for: runID,
                from: rows,
                now: now
            ),
            recoveryMode: recoveryMode,
            auditRef: auditRef
        )
    }

    func latestCheckpoint(for runID: String, in ctx: AXProjectContext) throws -> XTAutomationRunCheckpoint {
        let reconstruction = try loadCheckpointReconstruction(for: runID, ctx: ctx)
        checkpointStores[runID] = reconstruction.store
        return reconstruction.latestCheckpoint
    }

    func safePointGuidanceForBlockedTransition(
        _ runID: String,
        requestedState: XTAutomationRunState,
        in ctx: AXProjectContext
    ) throws -> SupervisorGuidanceInjectionRecord? {
        guard requestedState != .blocked else { return nil }
        let store = try resolvedStore(for: runID, ctx: ctx)
        guard store.current?.state == .blocked else { return nil }
        return pendingAutomationSafePointGuidance(
            for: ctx,
            runID: runID,
            store: store
        )
    }

    private func resolvedStore(for runID: String, ctx: AXProjectContext) throws -> XTAutomationRunCheckpointStore {
        if let store = checkpointStores[runID] {
            return store
        }
        let reconstruction = try loadCheckpointReconstruction(for: runID, ctx: ctx)
        checkpointStores[runID] = reconstruction.store
        return reconstruction.store
    }

    private func loadCheckpointReconstruction(
        for runID: String,
        ctx: AXProjectContext
    ) throws -> (
        store: XTAutomationRunCheckpointStore,
        latestCheckpoint: XTAutomationRunCheckpoint,
        wasCancelled: Bool
    ) {
        try loadCheckpointReconstruction(
            for: runID,
            rows: xtAutomationReadRawLogRows(for: ctx)
        )
    }

    private func loadCheckpointReconstruction(
        for runID: String,
        rows: [[String: Any]]
    ) throws -> (
        store: XTAutomationRunCheckpointStore,
        latestCheckpoint: XTAutomationRunCheckpoint,
        wasCancelled: Bool
    ) {
        guard let reconstruction = xtAutomationCheckpointReconstruction(
            for: runID,
            from: rows
        ) else {
            throw XTAutomationRunCoordinatorError.runNotFound(runID)
        }
        return (
            reconstruction.store,
            reconstruction.latestCheckpoint,
            reconstruction.wasCancelled
        )
    }

    private func recoverRun(
        _ runID: String,
        for ctx: AXProjectContext,
        rows: [[String: Any]],
        checkpointAgeSeconds: Int,
        recoveryMode: XTAutomationRestartRecoveryMode,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision {
        let reconstruction = try loadCheckpointReconstruction(for: runID, rows: rows)
        checkpointStores[runID] = reconstruction.store
        return XTAutomationRunCheckpointStore.recoveryDecision(
            for: reconstruction.latestCheckpoint,
            wasCancelled: reconstruction.wasCancelled,
            checkpointAgeSeconds: checkpointAgeSeconds,
            recoveryMode: recoveryMode,
            auditRef: auditRef
        )
    }

    private func latestRecoveryCandidate(
        for ctx: AXProjectContext,
        rows: [[String: Any]],
        now: TimeInterval
    ) throws -> XTAutomationRecoveryCandidate? {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        guard let candidate = xtAutomationLatestRecoveryCandidateSummary(
            from: rows,
            preferredRunID: config.lastAutomationLaunchRef,
            now: now
        ) else {
            return nil
        }
        let checkpointAgeSeconds = max(0, Int(now - candidate.checkpointSummary.createdAt))
        let automaticRecovery = XTAutomationRunCheckpointStore.recoveryDecision(
            for: candidate.checkpointSummary.checkpoint,
            wasCancelled: candidate.checkpointSummary.wasCancelled,
            checkpointAgeSeconds: checkpointAgeSeconds,
            recoveryMode: .automatic,
            auditRef: "audit-xt-auto-recovery-candidate-projection"
        )
        let retryAfterRemainingSeconds: Int? = {
            guard automaticRecovery.holdReason == "retry_after_not_elapsed" else {
                return nil
            }
            return max(0, candidate.checkpointSummary.checkpoint.retryAfterSeconds - checkpointAgeSeconds)
        }()
        let retryPlanPreview: XTAutomationRetryPlanPreview? = {
            guard automaticRecovery.decision == .resume
                    || automaticRecovery.holdReason == "retry_after_not_elapsed" else {
                return nil
            }
            return xtAutomationRetryPlanPreview(
                for: candidate.checkpointSummary.checkpoint.runID,
                ctx: ctx
            )
        }()
        let automaticResumeMode: XTAutomationRecoveryResumeMode? = {
            guard automaticRecovery.decision == .resume
                    || automaticRecovery.holdReason == "retry_after_not_elapsed" else {
                return nil
            }
            return retryPlanPreview == nil ? .inPlace : .retryPackage
        }()
        return XTAutomationRecoveryCandidate(
            runID: candidate.checkpointSummary.checkpoint.runID,
            state: candidate.checkpointSummary.checkpoint.state,
            selection: candidate.selection,
            latestVisibleRunID: candidate.latestVisibleRunID,
            latestVisibleState: candidate.latestVisibleState,
            reason: candidate.reason,
            supersededRunID: candidate.supersededRunID,
            supersededByRunID: candidate.supersededByRunID,
            deliveryRef: xtAutomationPersistedRunDeliveryRef(
                for: candidate.checkpointSummary.checkpoint.runID,
                from: rows
            ),
            checkpointAgeSeconds: checkpointAgeSeconds,
            retryAfterSeconds: candidate.checkpointSummary.checkpoint.retryAfterSeconds,
            retryAfterRemainingSeconds: retryAfterRemainingSeconds,
            automaticDecision: automaticRecovery.decision,
            automaticHoldReason: automaticRecovery.holdReason,
            automaticResumeMode: automaticResumeMode,
            automaticRetryStrategy: retryPlanPreview?.retryStrategy,
            automaticRetryReason: retryPlanPreview?.retryReason,
            automaticRetryPlanningMode: retryPlanPreview?.planningMode,
            automaticRetrySourceHandoffArtifactPath: retryPlanPreview?.sourceHandoffArtifactPath
        )
    }

    private func persistCheckpoint(
        _ checkpoint: XTAutomationRunCheckpoint,
        createdAt: Date,
        for ctx: AXProjectContext
    ) {
        AXProjectStore.appendRawLog(
            [
                "type": "automation_checkpoint",
                "created_at": createdAt.timeIntervalSince1970,
                "run_id": checkpoint.runID,
                "recipe_id": checkpoint.recipeID,
                "state": checkpoint.state.rawValue,
                "attempt": checkpoint.attempt,
                "last_transition": checkpoint.lastTransition,
                "retry_after_seconds": checkpoint.retryAfterSeconds,
                "resume_token": checkpoint.resumeToken,
                "checkpoint_ref": checkpoint.checkpointRef,
                "stable_identity": checkpoint.stableIdentity,
                "current_step_id": checkpoint.currentStepID ?? NSNull(),
                "current_step_title": checkpoint.currentStepTitle ?? NSNull(),
                "current_step_state": checkpoint.currentStepState?.rawValue ?? NSNull(),
                "current_step_summary": checkpoint.currentStepSummary ?? NSNull(),
                "audit_ref": checkpoint.auditRef
            ],
            for: ctx
        )
    }

    private func pendingAutomationSafePointGuidance(
        for ctx: AXProjectContext,
        runID: String,
        store: XTAutomationRunCheckpointStore
    ) -> SupervisorGuidanceInjectionRecord? {
        pendingAutomationSafePointGuidance(
            for: ctx,
            runID: runID,
            store: store,
            rows: xtAutomationReadRawLogRows(for: ctx)
        )
    }

    private func pendingAutomationSafePointGuidance(
        for ctx: AXProjectContext,
        runID: String,
        store: XTAutomationRunCheckpointStore,
        rows: [[String: Any]]
    ) -> SupervisorGuidanceInjectionRecord? {
        let runStartedAtMs = xtAutomationRunStartedAtMs(
            for: runID,
            from: rows
        )
        return SupervisorSafePointCoordinator.deliverablePendingAutomationGuidance(
            for: ctx,
            runStartedAtMs: runStartedAtMs,
            checkpointCount: store.history.count
        )
    }
}

private func xtAutomationCoordinatorInitialStepTitle(_ action: XTAutomationRecipeAction?) -> String? {
    let title = action?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !title.isEmpty {
        return title
    }
    let actionID = action?.actionID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return actionID.isEmpty ? nil : actionID
}

private func xtAutomationCoordinatorInitialState(
    for launchDecision: XTAutomationRunLaunchDecision
) -> XTAutomationRunState {
    switch launchDecision.decision {
    case .run:
        return .queued
    case .hold:
        return .blocked
    case .downgrade:
        return .downgraded
    case .deny:
        return .failed
    }
}

private func xtAutomationCoordinatorRunID(
    projectRoot: String,
    recipeRef: String,
    triggerSeeds: [XTAutomationTriggerSeed],
    now: Date
) -> String {
    let dedupeToken = triggerSeeds
        .map(\.dedupeKey)
        .joined(separator: "|")
    let dateToken = xtAutomationCoordinatorDateToken(now)
    let uuidToken = oneShotDeterministicUUIDString(
        seed: "xt_auto_run|\(projectRoot)|\(recipeRef)|\(dedupeToken)|\(dateToken)"
    )
    return "run-\(dateToken)-\(uuidToken.prefix(8))"
}

private func xtAutomationCoordinatorDateToken(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
        .replacingOccurrences(of: ":", with: "")
        .replacingOccurrences(of: "-", with: "")
}

private func xtAutomationValidateTriggerIngressSeeds(
    _ triggerSeeds: [XTAutomationTriggerSeed],
    allowedTriggerRefs: [String]
) throws {
    let allowedTriggerIDs = Set(
        allowedTriggerRefs.compactMap { ref -> String? in
            let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard let separator = trimmed.lastIndex(of: ":") else { return trimmed }
            let suffix = trimmed[trimmed.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return suffix.isEmpty ? nil : suffix
        }
    )

    var nonManualDedupeKeys = Set<String>()
    for seed in triggerSeeds {
        let triggerID = seed.triggerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let policyRef = seed.policyRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let dedupeKey = seed.dedupeKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if seed.triggerType != .manual && !allowedTriggerIDs.contains(triggerID) {
            throw XTAutomationRunCoordinatorError.triggerIngressNotAllowed(triggerID)
        }
        if seed.triggerType != .manual && seed.requiresGrant && policyRef.isEmpty {
            throw XTAutomationRunCoordinatorError.triggerIngressPolicyMissing(triggerID)
        }
        if seed.triggerType != .manual {
            if dedupeKey.isEmpty {
                throw XTAutomationRunCoordinatorError.triggerIngressReplayDetected(triggerID)
            }
            if !nonManualDedupeKeys.insert(dedupeKey).inserted {
                throw XTAutomationRunCoordinatorError.triggerIngressReplayDetected(dedupeKey)
            }
        }
    }
}
