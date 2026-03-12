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
            verifyCommandsOverride: request.verifyCommandsOverride
        )
    }

    @discardableResult
    func advanceRun(
        _ runID: String,
        to nextState: XTAutomationRunState,
        retryAfterSeconds: Int = 0,
        for ctx: AXProjectContext,
        auditRef: String,
        now: Date = Date()
    ) throws -> XTAutomationRunCheckpoint {
        let store = try resolvedStore(for: runID, ctx: ctx)
        let checkpoint = store.transition(
            to: nextState,
            retryAfterSeconds: retryAfterSeconds,
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
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision? {
        let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
        let runID = config.lastAutomationLaunchRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !runID.isEmpty else { return nil }
        return try recoverRun(runID, for: ctx, checkpointAgeSeconds: checkpointAgeSeconds, auditRef: auditRef)
    }

    func recoverRun(
        _ runID: String,
        for ctx: AXProjectContext,
        checkpointAgeSeconds: Int,
        auditRef: String
    ) throws -> XTAutomationRestartRecoveryDecision {
        let reconstruction = try loadCheckpointReconstruction(for: runID, ctx: ctx)
        checkpointStores[runID] = reconstruction.store
        return XTAutomationRunCheckpointStore.recoveryDecision(
            for: reconstruction.latestCheckpoint,
            wasCancelled: reconstruction.wasCancelled,
            checkpointAgeSeconds: checkpointAgeSeconds,
            auditRef: auditRef
        )
    }

    func latestCheckpoint(for runID: String, in ctx: AXProjectContext) throws -> XTAutomationRunCheckpoint {
        let reconstruction = try loadCheckpointReconstruction(for: runID, ctx: ctx)
        checkpointStores[runID] = reconstruction.store
        return reconstruction.latestCheckpoint
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
        let log = xtAutomationReadRawLogEntries(for: ctx)
        let checkpointRows = log.filter {
            ($0["type"] as? String) == "automation_checkpoint"
                && ($0["run_id"] as? String) == runID
        }
        guard let firstRow = checkpointRows.first,
              let firstCheckpoint = xtAutomationCheckpoint(from: firstRow) else {
            throw XTAutomationRunCoordinatorError.runNotFound(runID)
        }

        let store = XTAutomationRunCheckpointStore()
        _ = store.bootstrap(
            runID: firstCheckpoint.runID,
            recipeID: firstCheckpoint.recipeID,
            initialState: firstCheckpoint.state,
            retryAfterSeconds: firstCheckpoint.retryAfterSeconds,
            auditRef: firstCheckpoint.auditRef
        )
        var latestCheckpoint = firstCheckpoint
        for row in checkpointRows.dropFirst() {
            guard let checkpoint = xtAutomationCheckpoint(from: row) else { continue }
            latestCheckpoint = store.transition(
                to: checkpoint.state,
                retryAfterSeconds: checkpoint.retryAfterSeconds,
                auditRef: checkpoint.auditRef
            )
        }

        let cancelRows = log.filter {
            ($0["type"] as? String) == "automation_run_cancel"
                && ($0["run_id"] as? String) == runID
        }
        if let latestCancel = cancelRows.last,
           let cancelAuditRef = latestCancel["audit_ref"] as? String {
            store.markCancelled(auditRef: cancelAuditRef)
        }

        return (store, latestCheckpoint, !cancelRows.isEmpty)
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
                "audit_ref": checkpoint.auditRef
            ],
            for: ctx
        )
    }
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

private func xtAutomationReadRawLogEntries(for ctx: AXProjectContext) -> [[String: Any]] {
    guard FileManager.default.fileExists(atPath: ctx.rawLogURL.path),
          let data = try? Data(contentsOf: ctx.rawLogURL),
          let text = String(data: data, encoding: .utf8) else {
        return []
    }

    return text
        .split(separator: "\n", omittingEmptySubsequences: true)
        .compactMap { line in
            let rawLine = String(line)
            guard let lineData = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                return nil
            }
            return object
        }
}

private func xtAutomationCheckpoint(from row: [String: Any]) -> XTAutomationRunCheckpoint? {
    guard let runID = row["run_id"] as? String,
          let recipeID = row["recipe_id"] as? String,
          let stateRaw = row["state"] as? String,
          let state = XTAutomationRunState(rawValue: stateRaw),
          let lastTransition = row["last_transition"] as? String,
          let resumeToken = row["resume_token"] as? String,
          let checkpointRef = row["checkpoint_ref"] as? String,
          let auditRef = row["audit_ref"] as? String else {
        return nil
    }

    return XTAutomationRunCheckpoint(
        schemaVersion: XTAutomationRunCheckpoint.currentSchemaVersion,
        runID: runID,
        recipeID: recipeID,
        state: state,
        attempt: xtAutomationInt(row["attempt"], fallback: 1),
        lastTransition: lastTransition,
        retryAfterSeconds: xtAutomationInt(row["retry_after_seconds"], fallback: 0),
        resumeToken: resumeToken,
        checkpointRef: checkpointRef,
        stableIdentity: xtAutomationBool(row["stable_identity"]),
        auditRef: auditRef
    )
}

private func xtAutomationInt(_ value: Any?, fallback: Int) -> Int {
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    if let stringValue = value as? String, let intValue = Int(stringValue) {
        return intValue
    }
    return fallback
}

private func xtAutomationBool(_ value: Any?) -> Bool {
    if let boolValue = value as? Bool {
        return boolValue
    }
    if let intValue = value as? Int {
        return intValue != 0
    }
    if let stringValue = value as? String {
        return ["1", "true", "yes"].contains(stringValue.lowercased())
    }
    return false
}
