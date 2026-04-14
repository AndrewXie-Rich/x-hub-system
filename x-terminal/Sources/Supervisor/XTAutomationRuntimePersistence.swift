import Foundation

struct XTAutomationPersistedCheckpointSummary {
    let checkpoint: XTAutomationRunCheckpoint
    let createdAt: TimeInterval
    let rowIndex: Int
    let wasCancelled: Bool
}

struct XTAutomationPersistedRunLaunchSummary {
    let runID: String
    let createdAt: TimeInterval
    let rowIndex: Int
    let lineage: XTAutomationRunLineage
    let deliveryRef: String
}

enum XTAutomationDeliveryClosureProjectionSource: String, Equatable {
    case executionReport = "execution_report"
    case retryPackage = "retry_package"
    case launch = "launch"
}

struct XTAutomationDeliveryClosureProjection: Equatable {
    let runID: String
    let deliveryRef: String?
    let lineage: XTAutomationRunLineage
    let source: XTAutomationDeliveryClosureProjectionSource
}

struct XTAutomationPersistedRecoveryActionSummary: Equatable {
    let createdAt: TimeInterval
    let decision: XTAutomationRestartRecoveryDecision
    let recoveryMode: XTAutomationRestartRecoveryMode
    let resumeMode: XTAutomationRecoveryResumeMode?
    let retryRunID: String?
    let retryStrategy: String?
    let retryReason: String?
    let deliveryClosure: XTAutomationDeliveryClosureProjection?
}

enum XTAutomationRecoveryCandidateSelection: String, Equatable {
    case latestRecoverableUnsuperseded = "latest_recoverable_unsuperseded"
    case latestVisibleCheckpoint = "latest_visible_checkpoint"
}

enum XTAutomationRecoveryCandidateReason: String, Equatable {
    case latestVisibleRecoverable = "latest_visible_recoverable"
    case latestVisibleRetryWait = "latest_visible_retry_wait"
    case latestVisibleRetryBudgetExhausted = "latest_visible_retry_budget_exhausted"
    case latestVisibleStaleRecoverable = "latest_visible_stale_recoverable"
    case latestVisibleStableIdentityFailed = "latest_visible_stable_identity_failed"
    case latestVisibleActiveRun = "latest_visible_active_run"
    case latestVisibleCancelled = "latest_visible_cancelled"
    case latestVisibleSuperseded = "latest_visible_superseded"
    case latestVisibleNotRecoverable = "latest_visible_not_recoverable"
    case noRecoverableUnsupersededRun = "no_recoverable_unsuperseded_run"
}

struct XTAutomationPersistedRecoveryCandidateSummary {
    let checkpointSummary: XTAutomationPersistedCheckpointSummary
    let selection: XTAutomationRecoveryCandidateSelection
    let latestVisibleRunID: String
    let latestVisibleState: XTAutomationRunState
    let reason: XTAutomationRecoveryCandidateReason
    let supersededRunID: String?
    let supersededByRunID: String?
}

struct XTAutomationPersistedCheckpointReconstruction {
    let store: XTAutomationRunCheckpointStore
    let latestCheckpoint: XTAutomationRunCheckpoint
    let wasCancelled: Bool
}

struct XTAutomationProjectRecoveryState {
    let selection: XTAutomationRecoveryCandidateSelection
    let reason: XTAutomationRecoveryCandidateReason
    let automaticDecision: XTAutomationRestartRecoveryAction
    let automaticHoldReason: String
    let retryAfterRemainingSeconds: Int?
}

struct XTAutomationProjectContinuitySnapshot {
    let checkpointSummary: XTAutomationPersistedCheckpointSummary?
    let executionReport: XTAutomationRunExecutionReport?
    let retryPackage: XTAutomationRetryPackage?
    let recoveryState: XTAutomationProjectRecoveryState?
    let deliveryClosure: XTAutomationDeliveryClosureProjection?
    let persistedRecoveryAction: XTAutomationPersistedRecoveryActionSummary?
    let contextSource: String

    var runID: String? {
        xtAutomationFirstNonEmpty([
            checkpointSummary?.checkpoint.runID,
            executionReport?.runID,
            retryPackage?.retryRunID,
            retryPackage?.sourceRunID,
        ])
    }

    var runState: XTAutomationRunState? {
        checkpointSummary?.checkpoint.state
            ?? executionReport?.finalState
            ?? retryPackage?.sourceFinalState
    }

    private var preparedRetryRunID: String? {
        let retryRunID = retryPackage?.retryRunID.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !retryRunID.isEmpty else { return nil }
        let activeRunID = xtAutomationFirstNonEmpty([
            checkpointSummary?.checkpoint.runID,
            executionReport?.runID,
        ])
        guard retryRunID != activeRunID else { return nil }
        return retryRunID
    }

    var effectiveRunID: String? {
        xtAutomationFirstNonEmpty([
            preparedRetryRunID,
            deliveryClosure?.runID,
            persistedRecoveryAction?.deliveryClosure?.runID,
            retryPackage?.retryRunID,
            runID,
        ])
    }

    var effectiveLineage: XTAutomationRunLineage? {
        if preparedRetryRunID != nil {
            return retryPackage?.lineage
        }
        return deliveryClosure?.lineage
            ?? persistedRecoveryAction?.deliveryClosure?.lineage
            ?? retryPackage?.lineage
            ?? executionReport?.lineage
    }

    var effectiveDeliveryRef: String? {
        xtAutomationFirstNonEmpty([
            preparedRetryRunID == nil ? nil : retryPackage?.deliveryRef,
            deliveryClosure?.deliveryRef,
            persistedRecoveryAction?.deliveryClosure?.deliveryRef,
            retryPackage?.deliveryRef,
            executionReport?.deliveryRef,
        ])
    }

    var effectiveDeliveryClosureSource: XTAutomationDeliveryClosureProjectionSource? {
        if preparedRetryRunID != nil {
            return .retryPackage
        }
        return deliveryClosure?.source ?? persistedRecoveryAction?.deliveryClosure?.source
    }

    var attempt: Int? {
        checkpointSummary?.checkpoint.attempt
    }

    var retryAfterSeconds: Int? {
        guard let value = checkpointSummary?.checkpoint.retryAfterSeconds,
              value > 0 else {
            return nil
        }
        return value
    }

    var currentStepID: String? {
        xtAutomationFirstNonEmpty([
            checkpointSummary?.checkpoint.currentStepID,
            executionReport?.currentStepID,
            retryPackage?.retryReasonDescriptor?.currentStepID,
            retryPackage?.sourceBlocker?.currentStepID,
        ])
    }

    var currentStepTitle: String? {
        xtAutomationFirstNonEmpty([
            checkpointSummary?.checkpoint.currentStepTitle,
            executionReport?.currentStepTitle,
            retryPackage?.retryReasonDescriptor?.currentStepTitle,
            retryPackage?.sourceBlocker?.currentStepTitle,
        ])
    }

    var currentStepState: XTAutomationRunStepState? {
        checkpointSummary?.checkpoint.currentStepState
            ?? executionReport?.currentStepState
            ?? retryPackage?.retryReasonDescriptor?.currentStepState
            ?? retryPackage?.sourceBlocker?.currentStepState
    }

    var currentStepSummary: String? {
        xtAutomationFirstNonEmpty([
            checkpointSummary?.checkpoint.currentStepSummary,
            executionReport?.currentStepSummary,
            retryPackage?.retryReasonDescriptor?.currentStepSummary,
            retryPackage?.sourceBlocker?.currentStepSummary,
        ])
    }

    var verificationReport: XTAutomationVerificationReport? {
        executionReport?.verificationReport
    }

    var blocker: XTAutomationBlockerDescriptor? {
        executionReport?.structuredBlocker
            ?? retryPackage?.sourceBlocker
    }

    var retryReasonDescriptor: XTAutomationRetryReasonDescriptor? {
        retryPackage?.retryReasonDescriptor
    }

    var hasCurrentStep: Bool {
        currentStepState != nil || xtAutomationFirstNonEmpty([
            currentStepID,
            currentStepTitle,
            currentStepSummary,
        ]) != nil
    }

    var hasVerificationState: Bool {
        verificationReport != nil
    }

    var verificationNeedsAttention: Bool {
        guard let verificationReport else { return false }
        return !verificationReport.ok
    }

    var hasBlocker: Bool {
        blocker != nil
    }

    var hasRetryReason: Bool {
        retryReasonDescriptor != nil
    }
}

func xtAutomationLatestProjectContinuitySnapshot(
    for ctx: AXProjectContext,
    projectID: String? = nil,
    now: Date = Date()
) -> XTAutomationProjectContinuitySnapshot? {
    let rows = xtAutomationReadRawLogRows(for: ctx)
    let checkpointSummary = xtAutomationLatestPersistedCheckpointSummary(
        from: rows,
        excludeCancelled: true
    )
    let resolvedProjectID = xtAutomationFirstNonEmpty([
        projectID,
        AXProjectRegistryStore.projectId(forRoot: ctx.root),
    ])

    let retryPackage = resolvedProjectID.flatMap { normalizedProjectID in
        xtAutomationLatestScheduledRetryPackage(
            projectID: normalizedProjectID,
            ctx: ctx,
            rows: rows,
            preferredSourceRunID: checkpointSummary?.checkpoint.runID,
            preferredRetryRunID: checkpointSummary?.checkpoint.runID
        )
    }

    let preferredExecutionRunID = xtAutomationFirstNonEmpty([
        checkpointSummary?.checkpoint.runID,
        retryPackage?.sourceRunID,
        retryPackage?.retryRunID,
    ])
    let checkpointRunID = checkpointSummary?.checkpoint.runID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let retrySourceRunID = retryPackage?.sourceRunID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let executionReport = preferredExecutionRunID.flatMap {
        xtAutomationLoadExecutionReport(for: $0, ctx: ctx)
    } ?? {
        guard !retrySourceRunID.isEmpty else { return nil }
        guard checkpointRunID.isEmpty || checkpointRunID == retrySourceRunID else {
            return nil
        }
        return xtAutomationLoadExecutionReport(for: retrySourceRunID, ctx: ctx)
    }()

    var sources: [String] = []
    if checkpointSummary != nil {
        sources.append("checkpoint")
    }
    if executionReport != nil {
        sources.append("execution_report")
    }
    if retryPackage != nil {
        sources.append("retry_package")
    }
    guard !sources.isEmpty else { return nil }

    let recoveryState = xtAutomationProjectRecoveryState(
        from: rows,
        preferredRunID: checkpointSummary?.checkpoint.runID,
        now: now.timeIntervalSince1970
    )

    let baseSnapshot = XTAutomationProjectContinuitySnapshot(
        checkpointSummary: checkpointSummary,
        executionReport: executionReport,
        retryPackage: retryPackage,
        recoveryState: recoveryState,
        deliveryClosure: nil,
        persistedRecoveryAction: nil,
        contextSource: sources.joined(separator: "+")
    )
    let activeRunID = xtAutomationFirstNonEmpty([
        checkpointSummary?.checkpoint.runID,
        executionReport?.runID,
    ])
    let retryRunID = retryPackage?.retryRunID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let retryPackageClosure = retryPackage.flatMap {
        xtAutomationRetryPackageDeliveryClosureProjection(
            $0,
            rows: rows,
            preferredRunID: nil
        )
    }
    let executionClosure = executionReport.map {
        xtAutomationExecutionDeliveryClosureProjection(
            $0,
            rows: rows
        )
    }
    let deliveryClosure: XTAutomationDeliveryClosureProjection? = {
        if !retryRunID.isEmpty, retryRunID == activeRunID {
            if executionReport?.runID == retryRunID {
                return executionClosure
            }
            if retryPackageClosure != nil {
                return retryPackageClosure
            }
        }
        if retryPackageClosure != nil {
            return retryPackageClosure
        }
        if executionClosure != nil {
            return executionClosure
        }
        return xtAutomationRuntimeOrderedUniqueStrings([
            checkpointSummary?.checkpoint.runID,
            executionReport?.runID,
            retryPackage?.sourceRunID,
            baseSnapshot.runID,
        ].compactMap { $0 }).compactMap {
            xtAutomationResolvedDeliveryClosureProjection(
                for: $0,
                snapshot: baseSnapshot,
                rows: rows
            )
        }.first
    }()
    let persistedRecoveryAction = xtAutomationLatestPersistedRecoveryActionSummary(
        from: rows,
        preferredRunID: xtAutomationFirstNonEmpty([
            deliveryClosure?.runID,
            checkpointSummary?.checkpoint.runID,
            retryPackage?.retryRunID,
            executionReport?.runID,
            retryPackage?.sourceRunID,
        ])
    )
    let resolvedPersistedRecoveryAction = xtAutomationContinuityRelevantPersistedRecoveryAction(
        persistedRecoveryAction,
        checkpointSummary: checkpointSummary,
        executionReport: executionReport,
        retryPackage: retryPackage,
        deliveryClosure: deliveryClosure
    )

    return XTAutomationProjectContinuitySnapshot(
        checkpointSummary: checkpointSummary,
        executionReport: executionReport,
        retryPackage: retryPackage,
        recoveryState: recoveryState,
        deliveryClosure: deliveryClosure,
        persistedRecoveryAction: resolvedPersistedRecoveryAction,
        contextSource: sources.joined(separator: "+")
    )
}

private func xtAutomationContinuityRelevantPersistedRecoveryAction(
    _ summary: XTAutomationPersistedRecoveryActionSummary?,
    checkpointSummary: XTAutomationPersistedCheckpointSummary?,
    executionReport: XTAutomationRunExecutionReport?,
    retryPackage: XTAutomationRetryPackage?,
    deliveryClosure: XTAutomationDeliveryClosureProjection?
) -> XTAutomationPersistedRecoveryActionSummary? {
    guard let summary else { return nil }

    let sourceRunID = summary.decision.runID.trimmingCharacters(in: .whitespacesAndNewlines)
    let continuationRunID = xtAutomationFirstNonEmpty([
        summary.deliveryClosure?.runID,
        summary.retryRunID,
    ])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let checkpointRunID = checkpointSummary?.checkpoint.runID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let executionRunID = executionReport?.runID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let retryRunID = retryPackage?.retryRunID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let deliveryRunID = deliveryClosure?.runID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let retrySourceRunID = retryPackage?.sourceRunID
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let continuationEvidenceRunIDs = xtAutomationRuntimeOrderedUniqueStrings([
        checkpointRunID,
        executionRunID,
        retryRunID,
        deliveryRunID,
    ].filter {
        !$0.isEmpty && $0 != sourceRunID
    })
    if !continuationEvidenceRunIDs.isEmpty {
        guard !continuationRunID.isEmpty,
              continuationEvidenceRunIDs.contains(continuationRunID) else {
            return nil
        }
        return summary
    }

    let sourceRunStillVisible =
        checkpointRunID == sourceRunID ||
        executionRunID == sourceRunID ||
        deliveryRunID == sourceRunID ||
        retrySourceRunID == sourceRunID
    guard sourceRunStillVisible else { return nil }

    if checkpointRunID == sourceRunID,
       let checkpointSummary,
       checkpointSummary.createdAt > summary.createdAt {
        return nil
    }

    return summary
}

func xtAutomationProjectDeliveryClosureProjection(
    for ctx: AXProjectContext,
    projectID: String? = nil,
    preferredRunID: String? = nil,
    now: Date = Date()
) -> XTAutomationDeliveryClosureProjection? {
    let rows = xtAutomationReadRawLogRows(for: ctx)
    let snapshot = xtAutomationLatestProjectContinuitySnapshot(
        for: ctx,
        projectID: projectID,
        now: now
    )
    let candidateRunIDs = xtAutomationRuntimeOrderedUniqueStrings([
        preferredRunID,
        snapshot?.checkpointSummary?.checkpoint.runID,
        snapshot?.retryPackage?.retryRunID,
        snapshot?.executionReport?.runID,
        snapshot?.retryPackage?.sourceRunID,
        snapshot?.runID,
    ].compactMap { $0 })

    if let projection = snapshot?.deliveryClosure,
       (candidateRunIDs.isEmpty || candidateRunIDs.contains(projection.runID)) {
        return projection
    }
    if let projection = snapshot?.persistedRecoveryAction?.deliveryClosure,
       (candidateRunIDs.isEmpty || candidateRunIDs.contains(projection.runID)) {
        return projection
    }

    for runID in candidateRunIDs {
        if let projection = xtAutomationResolvedDeliveryClosureProjection(
            for: runID,
            snapshot: snapshot,
            rows: rows
        ) {
            return projection
        }
    }

    if let executionReport = snapshot?.executionReport {
        return xtAutomationExecutionDeliveryClosureProjection(
            executionReport,
            rows: rows
        )
    }
    if let retryPackage = snapshot?.retryPackage {
        return xtAutomationRetryPackageDeliveryClosureProjection(
            retryPackage,
            rows: rows,
            preferredRunID: nil
        )
    }
    return nil
}

func xtAutomationLatestPersistedRecoveryActionSummary(
    for ctx: AXProjectContext,
    preferredRunID: String? = nil
) -> XTAutomationPersistedRecoveryActionSummary? {
    xtAutomationLatestPersistedRecoveryActionSummary(
        from: xtAutomationReadRawLogRows(for: ctx),
        preferredRunID: preferredRunID
    )
}

func xtAutomationLatestPersistedRecoveryActionSummary(
    from rows: [[String: Any]],
    preferredRunID: String? = nil
) -> XTAutomationPersistedRecoveryActionSummary? {
    let normalizedPreferredRunID = preferredRunID?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasPreferredRunContext = !normalizedPreferredRunID.isEmpty

    func matchesPreferred(_ row: [String: Any]) -> Bool {
        guard hasPreferredRunContext else { return true }
        return xtAutomationRuntimeOrderedUniqueStrings([
            xtAutomationRuntimeString(row["run_id"]),
            xtAutomationRuntimeString(row["retry_run_id"]),
            xtAutomationRuntimeString(row["delivery_closure_run_id"]),
        ].compactMap { $0 }).contains(normalizedPreferredRunID)
    }

    for row in rows.reversed() {
        guard (row["type"] as? String) == "automation_run_recovery",
              matchesPreferred(row),
              let summary = xtAutomationPersistedRecoveryActionSummary(from: row) else {
            continue
        }
        return summary
    }

    guard !hasPreferredRunContext else { return nil }
    for row in rows.reversed() {
        guard (row["type"] as? String) == "automation_run_recovery",
              let summary = xtAutomationPersistedRecoveryActionSummary(from: row) else {
            continue
        }
        return summary
    }
    return nil
}

private func xtAutomationPersistedRecoveryActionSummary(
    from row: [String: Any]
) -> XTAutomationPersistedRecoveryActionSummary? {
    guard let runID = xtAutomationRuntimeString(row["run_id"]),
          let recipeID = xtAutomationRuntimeString(row["recipe_id"]),
          let recoveredState = xtAutomationRuntimeState(row["recovered_state"]),
          let decisionActionRaw = xtAutomationRuntimeString(row["decision"]),
          let decisionAction = XTAutomationRestartRecoveryAction(rawValue: decisionActionRaw),
          let checkpointRef = xtAutomationRuntimeString(row["checkpoint_ref"]),
          let resumeToken = xtAutomationRuntimeString(row["resume_token"]),
          let auditRef = xtAutomationRuntimeString(row["audit_ref"]) else {
        return nil
    }

    let decision = XTAutomationRestartRecoveryDecision(
        schemaVersion: xtAutomationRuntimeString(row["schema_version"])
            ?? XTAutomationRestartRecoveryDecision.currentSchemaVersion,
        runID: runID,
        recipeID: recipeID,
        recoveredState: recoveredState,
        decision: decisionAction,
        holdReason: xtAutomationRuntimeString(row["hold_reason"]) ?? "",
        stableIdentityPass: xtAutomationRuntimeBool(row["stable_identity_pass"]),
        checkpointRef: checkpointRef,
        resumeToken: resumeToken,
        auditRef: auditRef
    )
    let retryRunID = xtAutomationRuntimeString(row["retry_run_id"])
    let deliveryClosureRunID = xtAutomationRuntimeString(row["delivery_closure_run_id"])
        ?? retryRunID
        ?? runID
    let deliveryClosure = xtAutomationRuntimeString(row["delivery_closure_source"])
        .flatMap(XTAutomationDeliveryClosureProjectionSource.init(rawValue:))
        .map { source in
            XTAutomationDeliveryClosureProjection(
                runID: deliveryClosureRunID,
                deliveryRef: xtAutomationRuntimeString(row["delivery_ref"]),
                lineage: xtAutomationRuntimeLineage(
                    from: row,
                    artifactLineage: nil,
                    fallbackRunID: deliveryClosureRunID
                ),
                source: source
            )
        }

    return XTAutomationPersistedRecoveryActionSummary(
        createdAt: xtAutomationRuntimeDouble(row["created_at"]),
        decision: decision,
        recoveryMode: xtAutomationRuntimeString(row["recovery_mode"])
            .flatMap(XTAutomationRestartRecoveryMode.init(rawValue:))
            ?? .automatic,
        resumeMode: xtAutomationRuntimeString(row["resume_mode"])
            .flatMap(XTAutomationRecoveryResumeMode.init(rawValue:)),
        retryRunID: retryRunID,
        retryStrategy: xtAutomationRuntimeString(row["retry_strategy"]),
        retryReason: xtAutomationRuntimeString(row["retry_reason"]),
        deliveryClosure: deliveryClosure
    )
}

private func xtAutomationResolvedDeliveryClosureProjection(
    for runID: String,
    snapshot: XTAutomationProjectContinuitySnapshot?,
    rows: [[String: Any]]
) -> XTAutomationDeliveryClosureProjection? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    if let executionReport = snapshot?.executionReport,
       executionReport.runID == normalizedRunID {
        return xtAutomationExecutionDeliveryClosureProjection(
            executionReport,
            rows: rows
        )
    }
    if let retryPackage = snapshot?.retryPackage,
       let projection = xtAutomationRetryPackageDeliveryClosureProjection(
            retryPackage,
            rows: rows,
            preferredRunID: normalizedRunID
       ) {
        return projection
    }
    if let launchSummary = xtAutomationPersistedRunLaunchSummary(
        for: normalizedRunID,
        from: rows
    ) {
        return XTAutomationDeliveryClosureProjection(
            runID: launchSummary.runID,
            deliveryRef: xtAutomationFirstNonEmpty([
                launchSummary.deliveryRef
            ]),
            lineage: launchSummary.lineage,
            source: .launch
        )
    }
    return nil
}

private func xtAutomationExecutionDeliveryClosureProjection(
    _ report: XTAutomationRunExecutionReport,
    rows: [[String: Any]]
) -> XTAutomationDeliveryClosureProjection {
    let launchSummary = xtAutomationPersistedRunLaunchSummary(
        for: report.runID,
        from: rows
    )
    return XTAutomationDeliveryClosureProjection(
        runID: report.runID,
        deliveryRef: xtAutomationFirstNonEmpty([
            report.deliveryRef,
            launchSummary?.deliveryRef
        ]),
        lineage: xtAutomationResolvedLineage(
            report.lineage ?? launchSummary?.lineage,
            fallbackRunID: report.runID
        ),
        source: .executionReport
    )
}

private func xtAutomationRetryPackageDeliveryClosureProjection(
    _ retryPackage: XTAutomationRetryPackage,
    rows: [[String: Any]],
    preferredRunID: String?
) -> XTAutomationDeliveryClosureProjection? {
    let retryRunID = retryPackage.retryRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let sourceRunID = retryPackage.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedPreferredRunID = preferredRunID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

    let runID: String
    if !normalizedPreferredRunID.isEmpty {
        if !retryRunID.isEmpty, retryRunID == normalizedPreferredRunID {
            runID = retryRunID
        } else if retryRunID.isEmpty, !sourceRunID.isEmpty, sourceRunID == normalizedPreferredRunID {
            runID = sourceRunID
        } else {
            return nil
        }
    } else {
        runID = !retryRunID.isEmpty ? retryRunID : sourceRunID
    }

    guard !runID.isEmpty else { return nil }

    let launchSummary = xtAutomationPersistedRunLaunchSummary(
        for: runID,
        from: rows
    )
    let fallbackSourceLaunchSummary = sourceRunID.isEmpty
        ? nil
        : xtAutomationPersistedRunLaunchSummary(for: sourceRunID, from: rows)

    return XTAutomationDeliveryClosureProjection(
        runID: runID,
        deliveryRef: xtAutomationFirstNonEmpty([
            retryPackage.deliveryRef,
            launchSummary?.deliveryRef,
            fallbackSourceLaunchSummary?.deliveryRef
        ]),
        lineage: xtAutomationResolvedLineage(
            retryPackage.lineage
                ?? launchSummary?.lineage
                ?? fallbackSourceLaunchSummary?.lineage,
            fallbackRunID: runID
        ),
        source: .retryPackage
    )
}

private func xtAutomationProjectRecoveryState(
    from rows: [[String: Any]],
    preferredRunID: String?,
    now: TimeInterval
) -> XTAutomationProjectRecoveryState? {
    guard let candidate = xtAutomationLatestRecoveryCandidateSummary(
        from: rows,
        preferredRunID: preferredRunID,
        now: now
    ) else {
        return nil
    }

    let selectedCheckpoint = candidate.checkpointSummary.checkpoint
    let checkpointAgeSeconds = max(0, Int(now - candidate.checkpointSummary.createdAt))
    let automaticRecovery = XTAutomationRunCheckpointStore.recoveryDecision(
        for: selectedCheckpoint,
        wasCancelled: candidate.checkpointSummary.wasCancelled,
        checkpointAgeSeconds: checkpointAgeSeconds,
        recoveryMode: .automatic,
        auditRef: "audit-xt-project-continuity-recovery-state"
    )
    let retryAfterRemainingSeconds: Int? = {
        guard automaticRecovery.holdReason == "retry_after_not_elapsed" else {
            return nil
        }
        return max(0, selectedCheckpoint.retryAfterSeconds - checkpointAgeSeconds)
    }()

    return XTAutomationProjectRecoveryState(
        selection: candidate.selection,
        reason: candidate.reason,
        automaticDecision: automaticRecovery.decision,
        automaticHoldReason: automaticRecovery.holdReason,
        retryAfterRemainingSeconds: retryAfterRemainingSeconds
    )
}

func xtAutomationReadRawLogRows(for ctx: AXProjectContext) -> [[String: Any]] {
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

func xtAutomationCheckpoint(from row: [String: Any]) -> XTAutomationRunCheckpoint? {
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
        attempt: xtAutomationRuntimeInt(row["attempt"], fallback: 1),
        lastTransition: lastTransition,
        retryAfterSeconds: xtAutomationRuntimeInt(row["retry_after_seconds"], fallback: 0),
        resumeToken: resumeToken,
        checkpointRef: checkpointRef,
        stableIdentity: xtAutomationRuntimeBool(row["stable_identity"]),
        currentStepID: xtAutomationRuntimeString(row["current_step_id"]),
        currentStepTitle: xtAutomationRuntimeString(row["current_step_title"]),
        currentStepState: xtAutomationRuntimeString(row["current_step_state"]).flatMap(XTAutomationRunStepState.init(rawValue:)),
        currentStepSummary: xtAutomationRuntimeString(row["current_step_summary"]),
        auditRef: auditRef
    )
}

func xtAutomationPersistedCheckpointSummary(
    for runID: String,
    from rows: [[String: Any]]
) -> XTAutomationPersistedCheckpointSummary? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    var latestSummary: XTAutomationPersistedCheckpointSummary?
    var wasCancelled = false

    for (index, row) in rows.enumerated() {
        if (row["type"] as? String) == "automation_checkpoint",
           let checkpoint = xtAutomationCheckpoint(from: row),
           checkpoint.runID == normalizedRunID {
            latestSummary = XTAutomationPersistedCheckpointSummary(
                checkpoint: checkpoint,
                createdAt: xtAutomationRuntimeDouble(row["created_at"]),
                rowIndex: index,
                wasCancelled: wasCancelled
            )
            continue
        }

        if (row["type"] as? String) == "automation_run_cancel",
           let cancelledRunID = xtAutomationRuntimeString(row["run_id"]),
           cancelledRunID == normalizedRunID {
            wasCancelled = true
            if let currentSummary = latestSummary {
                latestSummary = XTAutomationPersistedCheckpointSummary(
                    checkpoint: currentSummary.checkpoint,
                    createdAt: currentSummary.createdAt,
                    rowIndex: currentSummary.rowIndex,
                    wasCancelled: true
                )
            }
        }
    }

    return latestSummary
}

func xtAutomationLatestPersistedCheckpointSummary(
    from rows: [[String: Any]],
    preferredRunID: String? = nil,
    allowedStates: Set<XTAutomationRunState>? = nil,
    excludeCancelled: Bool = false
) -> XTAutomationPersistedCheckpointSummary? {
    let latestByRunID = xtAutomationLatestPersistedCheckpointSummariesByRunID(from: rows)
    guard !latestByRunID.isEmpty else { return nil }
    let latestVisibleSummary = latestByRunID.values.max(by: { $0.rowIndex < $1.rowIndex })

    let candidateSummaries = latestByRunID.values.filter { summary in
        if excludeCancelled, summary.wasCancelled {
            return false
        }
        if let allowedStates, !allowedStates.contains(summary.checkpoint.state) {
            return false
        }
        return true
    }

    guard let latestSummary = candidateSummaries.max(by: { $0.rowIndex < $1.rowIndex }) else {
        return nil
    }
    if let allowedStates,
       let latestVisibleSummary,
       latestVisibleSummary.rowIndex > latestSummary.rowIndex {
        let visibleExcludedByCancellation = excludeCancelled && latestVisibleSummary.wasCancelled
        if !visibleExcludedByCancellation,
           !allowedStates.contains(latestVisibleSummary.checkpoint.state) {
            return nil
        }
    }

    let normalizedPreferredRunID = preferredRunID?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !normalizedPreferredRunID.isEmpty,
       normalizedPreferredRunID == latestSummary.checkpoint.runID {
        return latestSummary
    }

    return latestSummary
}

func xtAutomationRunLaunchSummary(
    for runID: String,
    from rows: [[String: Any]]
) -> XTAutomationPersistedRunLaunchSummary? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    return xtAutomationLatestRunLaunchSummariesByRunID(from: rows)[normalizedRunID]
}

func xtAutomationLatestRecoverableCheckpointSummary(
    from rows: [[String: Any]]
) -> XTAutomationPersistedCheckpointSummary? {
    let latestByRunID = xtAutomationLatestPersistedCheckpointSummariesByRunID(from: rows)
    guard !latestByRunID.isEmpty else { return nil }

    return xtAutomationLatestRecoverableCheckpointSummary(
        from: latestByRunID,
        supersededByRunID: xtAutomationSupersededRunIDsBySuccessorRunID(
            from: xtAutomationLatestRunLaunchSummariesByRunID(from: rows)
        )
    )
}

func xtAutomationLatestRecoveryCandidateSummary(
    from rows: [[String: Any]],
    preferredRunID: String? = nil,
    now: TimeInterval? = nil
) -> XTAutomationPersistedRecoveryCandidateSummary? {
    let latestByRunID = xtAutomationLatestPersistedCheckpointSummariesByRunID(from: rows)
    guard let latestVisible = xtAutomationLatestPersistedCheckpointSummary(
        from: rows,
        preferredRunID: preferredRunID
    ) else {
        return nil
    }

    let supersededByRunID = xtAutomationSupersededRunIDsBySuccessorRunID(
        from: xtAutomationLatestRunLaunchSummariesByRunID(from: rows)
    )
    let latestVisibleAutomaticRecovery = XTAutomationRunCheckpointStore.recoveryDecision(
        for: latestVisible.checkpoint,
        wasCancelled: latestVisible.wasCancelled,
        checkpointAgeSeconds: xtAutomationRecoveryCandidateCheckpointAgeSeconds(
            latestVisible,
            now: now
        ),
        recoveryMode: .automatic,
        auditRef: "audit-xt-auto-recovery-candidate-selection"
    )
    if latestVisibleAutomaticRecovery.holdReason == "stable_identity_failed" {
        return XTAutomationPersistedRecoveryCandidateSummary(
            checkpointSummary: latestVisible,
            selection: .latestVisibleCheckpoint,
            latestVisibleRunID: latestVisible.checkpoint.runID,
            latestVisibleState: latestVisible.checkpoint.state,
            reason: .latestVisibleStableIdentityFailed,
            supersededRunID: nil,
            supersededByRunID: nil
        )
    }
    let directlySupersededRecoverable = xtAutomationLatestRecoverableCheckpointSummary(
        from: latestByRunID,
        supersededByRunID: supersededByRunID,
        supersededBySuccessorRunID: latestVisible.checkpoint.runID
    )
    if let recoverable = xtAutomationLatestRecoverableCheckpointSummary(
        from: latestByRunID,
        supersededByRunID: supersededByRunID
    ) {
        if recoverable.checkpoint.runID != latestVisible.checkpoint.runID,
           xtAutomationVisibleRunKeepsRecoveryFocus(latestVisible.checkpoint.state) {
            return XTAutomationPersistedRecoveryCandidateSummary(
                checkpointSummary: latestVisible,
                selection: .latestVisibleCheckpoint,
                latestVisibleRunID: latestVisible.checkpoint.runID,
                latestVisibleState: latestVisible.checkpoint.state,
                reason: .latestVisibleActiveRun,
                supersededRunID: directlySupersededRecoverable?.checkpoint.runID,
                supersededByRunID: directlySupersededRecoverable.flatMap {
                    supersededByRunID[$0.checkpoint.runID]
                }
            )
        }
        return XTAutomationPersistedRecoveryCandidateSummary(
            checkpointSummary: recoverable,
            selection: .latestRecoverableUnsuperseded,
            latestVisibleRunID: latestVisible.checkpoint.runID,
            latestVisibleState: latestVisible.checkpoint.state,
            reason: xtAutomationRecoveryCandidateReason(
                selected: recoverable,
                latestVisible: latestVisible,
                supersededByRunID: supersededByRunID,
                now: now
            ),
            supersededRunID: nil,
            supersededByRunID: nil
        )
    }

    return XTAutomationPersistedRecoveryCandidateSummary(
        checkpointSummary: latestVisible,
        selection: .latestVisibleCheckpoint,
        latestVisibleRunID: latestVisible.checkpoint.runID,
        latestVisibleState: latestVisible.checkpoint.state,
        reason: .noRecoverableUnsupersededRun,
        supersededRunID: directlySupersededRecoverable?.checkpoint.runID,
        supersededByRunID: directlySupersededRecoverable.flatMap {
            supersededByRunID[$0.checkpoint.runID]
        }
    )
}

private func xtAutomationLatestScheduledRetryPackage(
    projectID: String,
    ctx: AXProjectContext,
    rows: [[String: Any]],
    preferredSourceRunID: String?,
    preferredRetryRunID: String?
) -> XTAutomationRetryPackage? {
    let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedProjectID.isEmpty else { return nil }

    let normalizedPreferredSourceRunID = preferredSourceRunID?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let normalizedPreferredRetryRunID = preferredRetryRunID?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let hasPreferredRunContext = !normalizedPreferredSourceRunID.isEmpty || !normalizedPreferredRetryRunID.isEmpty

    func package(for row: [String: Any]) -> XTAutomationRetryPackage? {
        guard let retryRunID = xtAutomationRuntimeString(row["retry_run_id"]) else {
            return nil
        }
        return xtAutomationLoadRetryPackage(
            forRetryRunID: retryRunID,
            projectID: normalizedProjectID,
            ctx: ctx
        )
    }

    for row in rows.reversed() {
        guard (row["type"] as? String) == "automation_retry",
              (row["status"] as? String) == "scheduled" else {
            continue
        }
        let rowSourceRunID = xtAutomationRuntimeString(row["source_run_id"]) ?? ""
        let rowRetryRunID = xtAutomationRuntimeString(row["retry_run_id"]) ?? ""
        let matchesPreferred = (!normalizedPreferredSourceRunID.isEmpty && rowSourceRunID == normalizedPreferredSourceRunID)
            || (!normalizedPreferredRetryRunID.isEmpty && rowRetryRunID == normalizedPreferredRetryRunID)
        guard matchesPreferred else { continue }
        if let package = package(for: row) {
            return package
        }
    }

    guard !hasPreferredRunContext else { return nil }

    for row in rows.reversed() {
        guard (row["type"] as? String) == "automation_retry",
              (row["status"] as? String) == "scheduled" else {
            continue
        }
        if let package = package(for: row) {
            return package
        }
    }

    return nil
}

func xtAutomationRunStartedAtMs(
    for runID: String,
    from rows: [[String: Any]]
) -> Int64 {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return 0 }

    let launchCreatedAt = rows.first(where: {
        ($0["type"] as? String) == "automation_run_launch"
            && xtAutomationRuntimeString($0["run_id"]) == normalizedRunID
    }).map { xtAutomationRuntimeDouble($0["created_at"]) } ?? 0
    if launchCreatedAt > 0 {
        return Int64((launchCreatedAt * 1000.0).rounded())
    }

    let firstCheckpointCreatedAt = rows.first(where: {
        ($0["type"] as? String) == "automation_checkpoint"
            && xtAutomationRuntimeString($0["run_id"]) == normalizedRunID
    }).map { xtAutomationRuntimeDouble($0["created_at"]) } ?? 0
    if firstCheckpointCreatedAt > 0 {
        return Int64((firstCheckpointCreatedAt * 1000.0).rounded())
    }

    return 0
}

func xtAutomationHasSafePointHold(
    runID: String,
    injectionId: String,
    from rows: [[String: Any]]
) -> Bool {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedInjectionId = injectionId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty, !normalizedInjectionId.isEmpty else { return false }

    return rows.contains {
        ($0["type"] as? String) == "automation_safe_point_hold"
            && xtAutomationRuntimeString($0["run_id"]) == normalizedRunID
            && xtAutomationRuntimeString($0["injection_id"]) == normalizedInjectionId
    }
}

func xtAutomationCheckpointReconstruction(
    for runID: String,
    from rows: [[String: Any]]
) -> XTAutomationPersistedCheckpointReconstruction? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    let checkpointRows = rows.filter {
        ($0["type"] as? String) == "automation_checkpoint"
            && xtAutomationRuntimeString($0["run_id"]) == normalizedRunID
    }
    let checkpoints = checkpointRows.compactMap(xtAutomationCheckpoint(from:))
    guard let latestCheckpoint = checkpoints.last else {
        return nil
    }

    let store = XTAutomationRunCheckpointStore()
    let cancelRows = rows.filter {
        ($0["type"] as? String) == "automation_run_cancel"
            && xtAutomationRuntimeString($0["run_id"]) == normalizedRunID
    }
    let cancelAuditRef = cancelRows.last.flatMap {
        xtAutomationRuntimeString($0["audit_ref"])
    } ?? ""

    _ = store.restore(
        checkpoints: checkpoints,
        wasCancelled: !cancelRows.isEmpty,
        cancelAuditRef: cancelAuditRef
    )

    return XTAutomationPersistedCheckpointReconstruction(
        store: store,
        latestCheckpoint: latestCheckpoint,
        wasCancelled: !cancelRows.isEmpty
    )
}

func xtAutomationCheckpointAgeSeconds(
    for runID: String? = nil,
    from rows: [[String: Any]],
    now: TimeInterval
) -> Int {
    let createdAt: TimeInterval
    if let runID {
        createdAt = xtAutomationPersistedCheckpointSummary(
            for: runID,
            from: rows
        )?.createdAt ?? now
    } else {
        createdAt = xtAutomationLatestPersistedCheckpointSummary(
            from: rows
        )?.createdAt ?? now
    }
    return max(0, Int(now - createdAt))
}

private func xtAutomationLatestPersistedCheckpointSummariesByRunID(
    from rows: [[String: Any]]
) -> [String: XTAutomationPersistedCheckpointSummary] {
    var latestByRunID: [String: XTAutomationPersistedCheckpointSummary] = [:]
    var cancelledRunIDs = Set<String>()

    for (index, row) in rows.enumerated() {
        if (row["type"] as? String) == "automation_checkpoint",
           let checkpoint = xtAutomationCheckpoint(from: row) {
            let wasCancelled = cancelledRunIDs.contains(checkpoint.runID)
            latestByRunID[checkpoint.runID] = XTAutomationPersistedCheckpointSummary(
                checkpoint: checkpoint,
                createdAt: xtAutomationRuntimeDouble(row["created_at"]),
                rowIndex: index,
                wasCancelled: wasCancelled
            )
            continue
        }

        if (row["type"] as? String) == "automation_run_cancel",
           let runID = xtAutomationRuntimeString(row["run_id"]) {
            cancelledRunIDs.insert(runID)
            if let latestSummary = latestByRunID[runID] {
                latestByRunID[runID] = XTAutomationPersistedCheckpointSummary(
                    checkpoint: latestSummary.checkpoint,
                    createdAt: latestSummary.createdAt,
                    rowIndex: latestSummary.rowIndex,
                    wasCancelled: true
                )
            }
        }
    }

    return latestByRunID
}

private func xtAutomationLatestRecoverableCheckpointSummary(
    from latestByRunID: [String: XTAutomationPersistedCheckpointSummary],
    supersededByRunID: [String: String]
) -> XTAutomationPersistedCheckpointSummary? {
    latestByRunID.values
        .filter { summary in
            XTAutomationRunCheckpointStore.recoverableStates.contains(summary.checkpoint.state)
                && summary.checkpoint.stableIdentity
                && !summary.wasCancelled
                && supersededByRunID[summary.checkpoint.runID] == nil
        }
        .max(by: { $0.rowIndex < $1.rowIndex })
}

private func xtAutomationLatestRecoverableCheckpointSummary(
    from latestByRunID: [String: XTAutomationPersistedCheckpointSummary],
    supersededByRunID: [String: String],
    supersededBySuccessorRunID: String
) -> XTAutomationPersistedCheckpointSummary? {
    latestByRunID.values
        .filter { summary in
            XTAutomationRunCheckpointStore.recoverableStates.contains(summary.checkpoint.state)
                && summary.checkpoint.stableIdentity
                && !summary.wasCancelled
                && supersededByRunID[summary.checkpoint.runID] == supersededBySuccessorRunID
        }
        .max(by: { $0.rowIndex < $1.rowIndex })
}

private func xtAutomationRecoveryCandidateCheckpointAgeSeconds(
    _ summary: XTAutomationPersistedCheckpointSummary,
    now: TimeInterval?
) -> Int {
    let referenceNow = now ?? summary.createdAt
    return max(0, Int(referenceNow - summary.createdAt))
}

private func xtAutomationLatestRunLaunchSummariesByRunID(
    from rows: [[String: Any]]
) -> [String: XTAutomationPersistedRunLaunchSummary] {
    var latestByRunID: [String: XTAutomationPersistedRunLaunchSummary] = [:]

    for (index, row) in rows.enumerated() {
        guard (row["type"] as? String) == "automation_run_launch",
              let runID = xtAutomationRuntimeString(row["run_id"]),
              !runID.isEmpty else {
            continue
        }

        latestByRunID[runID] = XTAutomationPersistedRunLaunchSummary(
            runID: runID,
            createdAt: xtAutomationRuntimeDouble(row["created_at"]),
            rowIndex: index,
            lineage: xtAutomationRuntimeLineage(
                from: row,
                artifactLineage: nil,
                fallbackRunID: runID
            ),
            deliveryRef: xtAutomationRuntimeString(row["delivery_ref"]) ?? ""
        )
    }

    return latestByRunID
}

func xtAutomationPersistedRunLaunchSummary(
    for runID: String,
    from rows: [[String: Any]]
) -> XTAutomationPersistedRunLaunchSummary? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }
    return xtAutomationLatestRunLaunchSummariesByRunID(from: rows)[normalizedRunID]
}

func xtAutomationPersistedRunLaunchSummary(
    for runID: String,
    ctx: AXProjectContext
) -> XTAutomationPersistedRunLaunchSummary? {
    xtAutomationPersistedRunLaunchSummary(
        for: runID,
        from: xtAutomationReadRawLogRows(for: ctx)
    )
}

func xtAutomationPersistedRunDeliveryRef(
    for runID: String,
    from rows: [[String: Any]]
) -> String? {
    let deliveryRef = xtAutomationPersistedRunLaunchSummary(for: runID, from: rows)?
        .deliveryRef
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return deliveryRef.isEmpty ? nil : deliveryRef
}

func xtAutomationPersistedRunDeliveryRef(
    for runID: String,
    ctx: AXProjectContext
) -> String? {
    xtAutomationPersistedRunDeliveryRef(
        for: runID,
        from: xtAutomationReadRawLogRows(for: ctx)
    )
}

private func xtAutomationSupersededRunIDsBySuccessorRunID(
    from launchSummariesByRunID: [String: XTAutomationPersistedRunLaunchSummary]
) -> [String: String] {
    let latestRunIDByLineageID = Dictionary(
        launchSummariesByRunID.values.map { ($0.lineage.lineageID, $0) },
        uniquingKeysWith: { current, candidate in
            candidate.rowIndex >= current.rowIndex ? candidate : current
        }
    )

    return launchSummariesByRunID.values.reduce(into: [String: String]()) { result, summary in
        guard let latestForLineage = latestRunIDByLineageID[summary.lineage.lineageID],
              latestForLineage.runID != summary.runID,
              latestForLineage.rowIndex > summary.rowIndex else {
            return
        }
        result[summary.runID] = latestForLineage.runID
    }
}

private func xtAutomationRecoveryCandidateReason(
    selected: XTAutomationPersistedCheckpointSummary,
    latestVisible: XTAutomationPersistedCheckpointSummary,
    supersededByRunID: [String: String],
    now: TimeInterval?
) -> XTAutomationRecoveryCandidateReason {
    if selected.checkpoint.runID == latestVisible.checkpoint.runID {
        guard let now else {
            return .latestVisibleRecoverable
        }
        let automaticRecovery = XTAutomationRunCheckpointStore.recoveryDecision(
            for: selected.checkpoint,
            wasCancelled: selected.wasCancelled,
            checkpointAgeSeconds: max(0, Int(now - selected.createdAt)),
            recoveryMode: .automatic,
            auditRef: "audit-xt-auto-recovery-candidate-reason"
        )
        switch automaticRecovery.holdReason {
        case "retry_after_not_elapsed":
            return .latestVisibleRetryWait
        case "retry_budget_exhausted":
            return .latestVisibleRetryBudgetExhausted
        case "stale_run_scavenged":
            return .latestVisibleStaleRecoverable
        case "stable_identity_failed":
            return .latestVisibleStableIdentityFailed
        default:
            return .latestVisibleRecoverable
        }
    }
    if latestVisible.wasCancelled {
        return .latestVisibleCancelled
    }
    if supersededByRunID[latestVisible.checkpoint.runID] != nil {
        return .latestVisibleSuperseded
    }
    return .latestVisibleNotRecoverable
}

private func xtAutomationVisibleRunKeepsRecoveryFocus(_ state: XTAutomationRunState) -> Bool {
    switch state {
    case .queued, .running:
        return true
    case .blocked, .takeover, .delivered, .failed, .downgraded:
        return false
    }
}

func xtAutomationLoadExecutionReport(
    for runID: String,
    ctx: AXProjectContext
) -> XTAutomationRunExecutionReport? {
    let normalizedRunID = runID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty else { return nil }

    let rows = xtAutomationReadRawLogRows(for: ctx)
    let executionRow = rows.last(where: {
        ($0["type"] as? String) == "automation_execution"
            && ($0["phase"] as? String) == "completed"
            && ($0["run_id"] as? String) == normalizedRunID
    })

    let reportedHandoffPath = xtAutomationRuntimeString(executionRow?["handoff_artifact_path"])
    let handoff = xtAutomationLoadHandoffArtifact(
        for: normalizedRunID,
        ctx: ctx,
        reportedRelativePath: reportedHandoffPath
    )

    let handoffArtifact = handoff?.artifact
    let relativeHandoffPath = handoff?.relativePath
    let finalState = xtAutomationRuntimeState(executionRow?["final_state"])
        ?? handoffArtifact?.finalState
    guard let finalState else { return nil }
    let lineage = xtAutomationRuntimeLineage(
        from: executionRow,
        artifactLineage: handoffArtifact?.lineage,
        fallbackRunID: normalizedRunID
    )

    let recipeRef = xtAutomationRuntimeString(executionRow?["recipe_ref"])
        ?? handoffArtifact?.recipeRef ?? ""
    let deliveryRef = xtAutomationRuntimeString(executionRow?["delivery_ref"])
        ?? handoffArtifact?.deliveryRef
        ?? xtAutomationPersistedRunDeliveryRef(for: normalizedRunID, from: rows)
    let totalActionCount = xtAutomationRuntimeInt(executionRow?["total_action_count"], fallback: handoffArtifact?.actionResults.count ?? 0)
    let executedActionCount = xtAutomationRuntimeInt(executionRow?["executed_action_count"], fallback: handoffArtifact?.actionResults.count ?? 0)
    let succeededActionCount = xtAutomationRuntimeInt(
        executionRow?["succeeded_action_count"],
        fallback: handoffArtifact?.actionResults.filter(\.ok).count ?? 0
    )
    let holdReason = xtAutomationRuntimeString(executionRow?["hold_reason"])
        ?? handoffArtifact?.holdReason ?? ""
    let detail = xtAutomationRuntimeString(executionRow?["detail"])
        ?? handoffArtifact?.detail ?? ""
    let verificationReport = xtAutomationMergedVerificationReport(
        rowReport: xtAutomationRuntimeVerificationReport(from: executionRow?["verification"]),
        artifactReport: handoffArtifact?.verificationReport
    )
    let workspaceDiffReport = xtAutomationRuntimeWorkspaceDiffReport(from: executionRow?["workspace_diff"])
        ?? handoffArtifact?.workspaceDiffReport
    let auditRef = xtAutomationRuntimeString(executionRow?["audit_ref"]) ?? ""
    let currentStepID = xtAutomationRuntimeString(executionRow?["current_step_id"])
        ?? handoffArtifact?.currentStepID
    let currentStepTitle = xtAutomationRuntimeString(executionRow?["current_step_title"])
        ?? handoffArtifact?.currentStepTitle
    let currentStepState = xtAutomationRuntimeString(executionRow?["current_step_state"])
        .flatMap(XTAutomationRunStepState.init(rawValue:))
        ?? handoffArtifact?.currentStepState
    let currentStepSummary = xtAutomationRuntimeString(executionRow?["current_step_summary"])
        ?? handoffArtifact?.currentStepSummary
    let structuredBlocker = xtAutomationRuntimeBlockerDescriptor(from: executionRow?["blocker"])
        ?? handoffArtifact?.structuredBlocker
        ?? xtAutomationStructuredBlocker(
            finalState: finalState,
            holdReason: holdReason,
            detail: detail,
            verificationReport: verificationReport,
            currentStepID: currentStepID,
            currentStepTitle: currentStepTitle,
            currentStepState: currentStepState,
            currentStepSummary: currentStepSummary
        )

    return XTAutomationRunExecutionReport(
        runID: normalizedRunID,
        lineage: lineage,
        recipeRef: recipeRef,
        deliveryRef: deliveryRef,
        totalActionCount: totalActionCount,
        executedActionCount: executedActionCount,
        succeededActionCount: succeededActionCount,
        finalState: finalState,
        holdReason: holdReason,
        detail: detail,
        actionResults: handoffArtifact?.actionResults ?? [],
        verificationReport: verificationReport,
        workspaceDiffReport: workspaceDiffReport,
        handoffArtifactPath: relativeHandoffPath ?? reportedHandoffPath,
        auditRef: auditRef,
        structuredBlocker: structuredBlocker,
        currentStepID: currentStepID,
        currentStepTitle: currentStepTitle,
        currentStepState: currentStepState,
        currentStepSummary: currentStepSummary
    )
}

func xtAutomationLoadRetryPackage(
    forRetryRunID retryRunID: String,
    projectID: String,
    ctx: AXProjectContext
) -> XTAutomationRetryPackage? {
    let normalizedRunID = retryRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedProjectID = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedRunID.isEmpty, !normalizedProjectID.isEmpty else { return nil }

    let allRows = xtAutomationReadRawLogRows(for: ctx)
    let rows = allRows.reversed()
    for row in rows {
        guard (row["type"] as? String) == "automation_retry",
              (row["status"] as? String) == "scheduled",
              xtAutomationRuntimeString(row["retry_run_id"]) == normalizedRunID else {
            continue
        }

        let artifactPath = xtAutomationRuntimeString(row["retry_artifact_path"])
            ?? xtAutomationRetryPackageRelativePath(for: normalizedRunID)
        let url = ctx.root.appendingPathComponent(artifactPath)
        if FileManager.default.fileExists(atPath: url.path),
           let package = xtAutomationDecodeJSON(from: url, as: XTAutomationRetryPackage.self),
           package.projectID == normalizedProjectID {
            let normalized = xtAutomationNormalizedRetryPackage(package, fallbackRetryRunID: normalizedRunID)
            return xtAutomationHydratedRetryPackage(
                normalized,
                ctx: ctx,
                row: row,
                fallbackRetryRunID: normalizedRunID,
                allRows: allRows
            )
        }

        let sourceRunID = xtAutomationRuntimeString(row["source_run_id"]) ?? ""
        let planningArtifactPath = xtAutomationRuntimeString(row["planning_artifact_path"])
        let planningArtifact = xtAutomationLoadRetryPlanningArtifact(
            sourceRunID: sourceRunID,
            ctx: ctx,
            reportedRelativePath: planningArtifactPath
        )
        let recipeProposalArtifactPath = xtAutomationRuntimeString(row["recipe_proposal_artifact_path"])
        let recipeProposalArtifact = xtAutomationLoadRetryRecipeProposalArtifact(
            sourceRunID: sourceRunID,
            ctx: ctx,
            reportedRelativePath: recipeProposalArtifactPath
        )
        let retryDepth = xtAutomationRuntimeIntOptional(row["retry_depth"])
        let lineage = xtAutomationRuntimeLineage(
            from: row,
            artifactLineage: recipeProposalArtifact?.artifact.lineage ?? planningArtifact?.artifact.lineage,
            fallbackRunID: normalizedRunID
        )
        let runtimePatchOverlay = xtAutomationRuntimeResolvedPatchOverlay(
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact,
            fallbackActionGraph: nil,
            fallbackVerifyCommands: nil,
            fallbackVerificationContract: XTAutomationVerificationContractSupport.contract(
                from: row["revised_verification_contract"] ?? row["verification_contract"]
            )
        )
        let fallbackRowVerificationContract = XTAutomationVerificationContractSupport.contract(
            from: row["revised_verification_contract"] ?? row["verification_contract"]
        )
        let sourceBlocker = planningArtifact?.artifact.sourceBlocker
            ?? recipeProposalArtifact?.artifact.sourceBlocker
            ?? xtAutomationRuntimeBlockerDescriptor(from: row["source_blocker"])
            ?? xtAutomationStructuredBlocker(
                finalState: .blocked,
                holdReason: xtAutomationRuntimeString(row["source_hold_reason"]) ?? "",
                detail: xtAutomationRuntimeString(row["detail"]) ?? "",
                verificationReport: nil,
                currentStepID: xtAutomationRuntimeString(row["current_step_id"]),
                currentStepTitle: xtAutomationRuntimeString(row["current_step_title"]),
                currentStepState: xtAutomationRuntimeString(row["current_step_state"]).flatMap(XTAutomationRunStepState.init(rawValue:)),
                currentStepSummary: xtAutomationRuntimeString(row["current_step_summary"])
            )
        let retryReasonDescriptor = planningArtifact?.artifact.retryReasonDescriptor
            ?? recipeProposalArtifact?.artifact.retryReasonDescriptor
            ?? xtAutomationRuntimeRetryReasonDescriptor(from: row["retry_reason_descriptor"])
            ?? xtAutomationStructuredRetryReason(
                strategy: xtAutomationRuntimeString(row["retry_strategy"]) ?? "",
                reason: xtAutomationRuntimeString(row["retry_reason"]) ?? "",
                blocker: sourceBlocker,
                planningMode: planningArtifact?.artifact.planningMode
                    ?? recipeProposalArtifact?.artifact.proposalMode
            )
        let deliveryRef = xtAutomationRuntimeString(row["delivery_ref"])
            ?? xtAutomationPersistedRunDeliveryRef(for: normalizedRunID, from: allRows)
            ?? xtAutomationPersistedRunDeliveryRef(for: sourceRunID, from: allRows)

        return XTAutomationRetryPackage(
            schemaVersion: XTAutomationRetryPackage.currentSchemaVersion,
            generatedAt: xtAutomationRuntimeDouble(row["created_at"]),
            projectID: normalizedProjectID,
            lineage: lineage.retryChild(
                parentRunID: sourceRunID,
                retryDepth: retryDepth
            ),
            deliveryRef: deliveryRef,
            sourceRunID: sourceRunID,
            sourceFinalState: .blocked,
            sourceHoldReason: "",
            sourceHandoffArtifactPath: xtAutomationRuntimeString(row["source_handoff_artifact_path"]) ?? "",
            sourceBlocker: sourceBlocker,
            retryStrategy: xtAutomationRuntimeString(row["retry_strategy"]) ?? "",
            retryReason: xtAutomationRuntimeString(row["retry_reason"]) ?? "",
            retryReasonDescriptor: retryReasonDescriptor,
            suggestedNextActions: [],
            additionalEvidenceRefs: xtAutomationRuntimeOrderedUniqueStrings(
                xtAutomationRuntimeStringArray(row["additional_evidence_refs"]) + [
                    (xtAutomationRuntimeString(row["retry_trigger"]).map { "retry://trigger/\($0)" }) ?? "",
                    (retryDepth.map { "retry://depth/\($0)" }) ?? ""
                ]
            ),
            planningMode: planningArtifact?.artifact.planningMode
                ?? recipeProposalArtifact?.artifact.proposalMode,
            planningSummary: planningArtifact?.artifact.planningSummary
                ?? recipeProposalArtifact?.artifact.proposalSummary,
            runtimePatchOverlay: runtimePatchOverlay,
            revisedActionGraph: xtAutomationRuntimeProposedActionGraph(
                runtimePatchOverlay: runtimePatchOverlay,
                recipeProposalArtifact: recipeProposalArtifact?.artifact,
                planningArtifact: planningArtifact?.artifact
            ),
            revisedVerifyCommands: xtAutomationRuntimeProposedVerifyCommands(
                runtimePatchOverlay: runtimePatchOverlay,
                recipeProposalArtifact: recipeProposalArtifact?.artifact,
                planningArtifact: planningArtifact?.artifact
            ) ?? fallbackRowVerificationContract?.verifyCommands,
            revisedVerificationContract: xtAutomationRuntimeProposedVerificationContract(
                runtimePatchOverlay: runtimePatchOverlay,
                recipeProposalArtifact: recipeProposalArtifact?.artifact,
                planningArtifact: planningArtifact?.artifact
            ) ?? fallbackRowVerificationContract,
            planningArtifactPath: planningArtifact?.relativePath ?? planningArtifactPath,
            recipeProposalArtifactPath: recipeProposalArtifact?.relativePath ?? recipeProposalArtifactPath,
            retryRunID: normalizedRunID,
            retryArtifactPath: artifactPath
        )
    }

    return nil
}

private func xtAutomationNormalizedRetryPackage(
    _ package: XTAutomationRetryPackage,
    fallbackRetryRunID: String
) -> XTAutomationRetryPackage {
    var normalized = package
    let lineage = xtAutomationResolvedLineage(
        package.lineage,
        fallbackRunID: fallbackRetryRunID
    )
    let sourceRunID = package.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    if sourceRunID.isEmpty {
        normalized.lineage = lineage
    } else if lineage.parentRunID == sourceRunID {
        normalized.lineage = lineage
    } else if lineage.retryDepth > 0 {
        normalized.lineage = XTAutomationRunLineage(
            lineageID: lineage.lineageID,
            rootRunID: lineage.rootRunID,
            parentRunID: sourceRunID,
            retryDepth: lineage.retryDepth
        )
    } else {
        normalized.lineage = lineage.retryChild(
            parentRunID: sourceRunID,
            retryDepth: automationRuntimeRetryDepthFallback(from: package)
        )
    }
    return normalized
}

private func xtAutomationHydratedRetryPackage(
    _ package: XTAutomationRetryPackage,
    ctx: AXProjectContext,
    row: [String: Any]?,
    fallbackRetryRunID: String,
    allRows: [[String: Any]]
) -> XTAutomationRetryPackage {
    var hydrated = xtAutomationNormalizedRetryPackage(package, fallbackRetryRunID: fallbackRetryRunID)
    let sourceRunID = hydrated.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedDeliveryRef = hydrated.deliveryRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        ? hydrated.deliveryRef
        : (
            xtAutomationRuntimeString(row?["delivery_ref"])
                ?? xtAutomationPersistedRunDeliveryRef(for: fallbackRetryRunID, from: allRows)
                ?? (sourceRunID.isEmpty ? nil : xtAutomationPersistedRunDeliveryRef(for: sourceRunID, from: allRows))
        )
    hydrated.deliveryRef = resolvedDeliveryRef
    guard !sourceRunID.isEmpty else { return hydrated }

    let planningArtifact = xtAutomationLoadRetryPlanningArtifact(
        sourceRunID: sourceRunID,
        ctx: ctx,
        reportedRelativePath: xtAutomationRuntimeString(row?["planning_artifact_path"]) ?? hydrated.planningArtifactPath
    )
    let recipeProposalArtifact = xtAutomationLoadRetryRecipeProposalArtifact(
        sourceRunID: sourceRunID,
        ctx: ctx,
        reportedRelativePath: xtAutomationRuntimeString(row?["recipe_proposal_artifact_path"]) ?? hydrated.recipeProposalArtifactPath
    )
    let runtimePatchOverlay = hydrated.runtimePatchOverlay
        ?? xtAutomationRuntimeResolvedPatchOverlay(
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact,
            fallbackActionGraph: hydrated.revisedActionGraph,
            fallbackVerifyCommands: hydrated.revisedVerifyCommands,
            fallbackVerificationContract: hydrated.revisedVerificationContract
        )

    if let planningArtifact {
        hydrated.planningArtifactPath = planningArtifact.relativePath
        if hydrated.sourceBlocker == nil {
            hydrated.sourceBlocker = planningArtifact.artifact.sourceBlocker
        }
        if hydrated.retryReasonDescriptor == nil {
            hydrated.retryReasonDescriptor = planningArtifact.artifact.retryReasonDescriptor
        }
        if hydrated.planningMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningMode = planningArtifact.artifact.planningMode
        }
        if hydrated.planningSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningSummary = planningArtifact.artifact.planningSummary
        }
    }
    if let recipeProposalArtifact {
        hydrated.recipeProposalArtifactPath = recipeProposalArtifact.relativePath
        if hydrated.sourceBlocker == nil {
            hydrated.sourceBlocker = recipeProposalArtifact.artifact.sourceBlocker
        }
        if hydrated.retryReasonDescriptor == nil {
            hydrated.retryReasonDescriptor = recipeProposalArtifact.artifact.retryReasonDescriptor
        }
        if hydrated.planningMode?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningMode = recipeProposalArtifact.artifact.proposalMode
        }
        if hydrated.planningSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            hydrated.planningSummary = recipeProposalArtifact.artifact.proposalSummary
        }
    }
    if hydrated.runtimePatchOverlay == nil {
        hydrated.runtimePatchOverlay = runtimePatchOverlay
    }
    if hydrated.sourceBlocker == nil {
        hydrated.sourceBlocker = xtAutomationRuntimeBlockerDescriptor(from: row?["source_blocker"])
    }
    if hydrated.retryReasonDescriptor == nil {
        hydrated.retryReasonDescriptor = xtAutomationRuntimeRetryReasonDescriptor(from: row?["retry_reason_descriptor"])
            ?? xtAutomationStructuredRetryReason(
                strategy: hydrated.retryStrategy,
                reason: hydrated.retryReason,
                blocker: hydrated.sourceBlocker,
                planningMode: hydrated.planningMode
            )
    }

    if hydrated.revisedActionGraph?.isEmpty != false {
        hydrated.revisedActionGraph = xtAutomationRuntimeProposedActionGraph(
            runtimePatchOverlay: runtimePatchOverlay,
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact
        )
    }
    if hydrated.revisedVerifyCommands?.isEmpty != false {
        hydrated.revisedVerifyCommands = xtAutomationRuntimeProposedVerifyCommands(
            runtimePatchOverlay: runtimePatchOverlay,
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact
        )
    }
    if hydrated.revisedVerificationContract == nil {
        hydrated.revisedVerificationContract = xtAutomationRuntimeProposedVerificationContract(
            runtimePatchOverlay: runtimePatchOverlay,
            recipeProposalArtifact: recipeProposalArtifact?.artifact,
            planningArtifact: planningArtifact?.artifact
        )
            ?? XTAutomationVerificationContractSupport.contract(
                from: row?["revised_verification_contract"] ?? row?["verification_contract"]
            )
    }
    if hydrated.revisedVerifyCommands?.isEmpty != false,
       let fallbackCommands = hydrated.revisedVerificationContract?.verifyCommands,
       !fallbackCommands.isEmpty {
        hydrated.revisedVerifyCommands = fallbackCommands
    }

    return hydrated
}

private func xtAutomationRuntimeProposedActionGraph(
    runtimePatchOverlay: XTAutomationRuntimePatchOverlay?,
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?
) -> [XTAutomationRecipeAction]? {
    if let runtimePatchOverlay,
       let value = runtimePatchOverlay.normalized().mergePatch["action_graph"],
       let decoded = xtAutomationDecodedJSONValue(value, as: [XTAutomationRecipeAction].self),
       !decoded.isEmpty {
        return decoded
    }
    if let proposed = recipeProposalArtifact?.proposedActionGraph,
       !proposed.isEmpty {
        return proposed
    }
    if let proposed = planningArtifact?.proposedActionGraph,
       !proposed.isEmpty {
        return proposed
    }
    return nil
}

private func xtAutomationRuntimeProposedVerifyCommands(
    runtimePatchOverlay: XTAutomationRuntimePatchOverlay?,
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?
) -> [String]? {
    if let runtimePatchOverlay,
       let value = runtimePatchOverlay.normalized().mergePatch["verify_commands"],
       let commands = xtAutomationRuntimeStringArray(from: value),
       !commands.isEmpty {
        return commands
    }
    if let commands = recipeProposalArtifact?.proposedVerifyCommands,
       !commands.isEmpty {
        return commands
    }
    if let commands = planningArtifact?.proposedVerifyCommands,
       !commands.isEmpty {
        return commands
    }
    if let contract = recipeProposalArtifact?.proposedVerificationContract,
       !contract.verifyCommands.isEmpty {
        return contract.verifyCommands
    }
    if let contract = planningArtifact?.proposedVerificationContract,
       !contract.verifyCommands.isEmpty {
        return contract.verifyCommands
    }
    return nil
}

private func xtAutomationRuntimeProposedVerificationContract(
    runtimePatchOverlay: XTAutomationRuntimePatchOverlay?,
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?
) -> XTAutomationVerificationContract? {
    if let runtimePatchOverlay,
       let value = runtimePatchOverlay.normalized().mergePatch["verification_contract"],
       let contract = xtAutomationDecodedJSONValue(value, as: XTAutomationVerificationContract.self) {
        return contract
    }
    if let contract = recipeProposalArtifact?.proposedVerificationContract {
        return contract
    }
    if let contract = planningArtifact?.proposedVerificationContract {
        return contract
    }
    return nil
}

private func xtAutomationRuntimeResolvedPatchOverlay(
    recipeProposalArtifact: XTAutomationRecipeProposalArtifact?,
    planningArtifact: XTAutomationRetryPlanningArtifact?,
    fallbackActionGraph: [XTAutomationRecipeAction]?,
    fallbackVerifyCommands: [String]?,
    fallbackVerificationContract: XTAutomationVerificationContract?
) -> XTAutomationRuntimePatchOverlay? {
    if let overlay = recipeProposalArtifact?.runtimePatchOverlay {
        return overlay.normalized()
    }
    if let overlay = planningArtifact?.runtimePatchOverlay {
        return overlay.normalized()
    }
    return xtAutomationRuntimePatchOverlay(
        revisedActionGraph: recipeProposalArtifact?.proposedActionGraph
            ?? planningArtifact?.proposedActionGraph
            ?? fallbackActionGraph,
        revisedVerifyCommands: recipeProposalArtifact?.proposedVerifyCommands
            ?? planningArtifact?.proposedVerifyCommands
            ?? fallbackVerifyCommands,
        revisedVerificationContract: recipeProposalArtifact?.proposedVerificationContract
            ?? planningArtifact?.proposedVerificationContract
            ?? fallbackVerificationContract
    )
}

private func xtAutomationRuntimeLineage(
    from row: [String: Any]?,
    artifactLineage: XTAutomationRunLineage?,
    fallbackRunID: String
) -> XTAutomationRunLineage {
    if let artifactLineage {
        let merged = XTAutomationRunLineage(
            lineageID: xtAutomationRuntimeString(row?["lineage_id"]) ?? artifactLineage.lineageID,
            rootRunID: xtAutomationRuntimeString(row?["root_run_id"]) ?? artifactLineage.rootRunID,
            parentRunID: xtAutomationRuntimeString(row?["parent_run_id"]) ?? artifactLineage.parentRunID,
            retryDepth: xtAutomationRuntimeIntOptional(row?["retry_depth"]) ?? artifactLineage.retryDepth
        )
        return xtAutomationResolvedLineage(merged, fallbackRunID: fallbackRunID)
    }

    let lineage = XTAutomationRunLineage(
        lineageID: xtAutomationRuntimeString(row?["lineage_id"]) ?? "",
        rootRunID: xtAutomationRuntimeString(row?["root_run_id"]) ?? "",
        parentRunID: xtAutomationRuntimeString(row?["parent_run_id"]) ?? "",
        retryDepth: xtAutomationRuntimeIntOptional(row?["retry_depth"]) ?? 0
    )
    return xtAutomationResolvedLineage(lineage, fallbackRunID: fallbackRunID)
}

private func automationRuntimeRetryDepthFallback(from package: XTAutomationRetryPackage) -> Int {
    if let retryDepth = package.lineage?.retryDepth,
       retryDepth > 0 {
        return retryDepth
    }
    for ref in package.additionalEvidenceRefs where ref.hasPrefix("retry://depth/") {
        if let token = ref.split(separator: "/").last,
           let depth = Int(token) {
            return max(1, depth)
        }
    }
    return 1
}

private func xtAutomationRuntimeVerificationReport(from value: Any?) -> XTAutomationVerificationReport? {
    guard let object = value as? [String: Any] else { return nil }
    let commandRows = object["command_results"] as? [Any] ?? []
    let commandResults = commandRows.compactMap { item -> XTAutomationVerificationCommandOutcome? in
        guard let row = item as? [String: Any] else { return nil }
        return XTAutomationVerificationCommandOutcome(
            commandID: xtAutomationRuntimeString(row["command_id"]) ?? "",
            command: xtAutomationRuntimeString(row["command"]) ?? "",
            ok: xtAutomationRuntimeBool(row["ok"]),
            detail: xtAutomationRuntimeString(row["detail"]) ?? ""
        )
    }
    let contract = xtAutomationRuntimeVerificationContract(
        from: object["verification_contract"]
    )

    return XTAutomationVerificationReport(
        required: xtAutomationRuntimeBool(object["required"]),
        executed: xtAutomationRuntimeBool(object["executed"]),
        commandCount: xtAutomationRuntimeInt(object["command_count"], fallback: commandResults.count),
        passedCommandCount: xtAutomationRuntimeInt(
            object["passed_command_count"],
            fallback: commandResults.filter(\.ok).count
        ),
        holdReason: xtAutomationRuntimeString(object["hold_reason"]) ?? "",
        detail: xtAutomationRuntimeString(object["detail"]) ?? "",
        commandResults: commandResults,
        contract: contract
    )
}

private func xtAutomationMergedVerificationReport(
    rowReport: XTAutomationVerificationReport?,
    artifactReport: XTAutomationVerificationReport?
) -> XTAutomationVerificationReport? {
    guard var merged = rowReport ?? artifactReport else { return nil }
    if merged.contract == nil {
        merged.contract = artifactReport?.contract
    }
    if merged.commandResults.isEmpty,
       let artifactResults = artifactReport?.commandResults,
       !artifactResults.isEmpty {
        merged.commandResults = artifactResults
    }
    if merged.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let artifactDetail = artifactReport?.detail.trimmingCharacters(in: .whitespacesAndNewlines),
       !artifactDetail.isEmpty {
        merged.detail = artifactDetail
    }
    if merged.holdReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
       let artifactHoldReason = artifactReport?.holdReason.trimmingCharacters(in: .whitespacesAndNewlines),
       !artifactHoldReason.isEmpty {
        merged.holdReason = artifactHoldReason
    }
    if merged.commandCount == 0,
       let artifactCount = artifactReport?.commandCount,
       artifactCount > 0 {
        merged.commandCount = artifactCount
    }
    if merged.passedCommandCount == 0,
       let artifactPassedCount = artifactReport?.passedCommandCount,
       artifactPassedCount > 0 {
        merged.passedCommandCount = artifactPassedCount
    }
    return merged
}

private func xtAutomationRuntimeVerificationContract(from value: Any?) -> XTAutomationVerificationContract? {
    XTAutomationVerificationContractSupport.contract(from: value)
}

private func xtAutomationRuntimeWorkspaceDiffReport(from value: Any?) -> XTAutomationWorkspaceDiffReport? {
    guard let object = value as? [String: Any] else { return nil }
    return XTAutomationWorkspaceDiffReport(
        attempted: xtAutomationRuntimeBool(object["attempted"]),
        captured: xtAutomationRuntimeBool(object["captured"]),
        fileCount: xtAutomationRuntimeInt(object["file_count"], fallback: 0),
        diffChars: xtAutomationRuntimeInt(object["diff_chars"], fallback: 0),
        detail: xtAutomationRuntimeString(object["detail"]) ?? "",
        excerpt: xtAutomationRuntimeString(object["excerpt"]) ?? ""
    )
}

private func xtAutomationRuntimeBlockerDescriptor(from value: Any?) -> XTAutomationBlockerDescriptor? {
    guard let object = value as? [String: Any],
          let code = xtAutomationRuntimeString(object["code"]),
          let summary = xtAutomationRuntimeString(object["summary"]),
          let stageRaw = xtAutomationRuntimeString(object["stage"]),
          let stage = XTAutomationBlockerStage(rawValue: stageRaw),
          let detail = xtAutomationRuntimeString(object["detail"]),
          let nextSafeAction = xtAutomationRuntimeString(object["next_safe_action"]) else {
        return nil
    }

    return XTAutomationBlockerDescriptor(
        code: code,
        summary: summary,
        stage: stage,
        detail: detail,
        nextSafeAction: nextSafeAction,
        retryEligible: xtAutomationRuntimeBool(object["retry_eligible"]),
        currentStepID: xtAutomationRuntimeString(object["current_step_id"]),
        currentStepTitle: xtAutomationRuntimeString(object["current_step_title"]),
        currentStepState: xtAutomationRuntimeString(object["current_step_state"]).flatMap(XTAutomationRunStepState.init(rawValue:)),
        currentStepSummary: xtAutomationRuntimeString(object["current_step_summary"])
    )
}

private func xtAutomationRuntimeRetryReasonDescriptor(from value: Any?) -> XTAutomationRetryReasonDescriptor? {
    guard let object = value as? [String: Any],
          let code = xtAutomationRuntimeString(object["code"]),
          let categoryRaw = xtAutomationRuntimeString(object["category"]),
          let category = XTAutomationRetryReasonCategory(rawValue: categoryRaw),
          let summary = xtAutomationRuntimeString(object["summary"]),
          let strategy = xtAutomationRuntimeString(object["strategy"]),
          let blockerCode = xtAutomationRuntimeString(object["blocker_code"]) else {
        return nil
    }

    return XTAutomationRetryReasonDescriptor(
        code: code,
        category: category,
        summary: summary,
        strategy: strategy,
        blockerCode: blockerCode,
        planningMode: xtAutomationRuntimeString(object["planning_mode"]),
        currentStepID: xtAutomationRuntimeString(object["current_step_id"]),
        currentStepTitle: xtAutomationRuntimeString(object["current_step_title"]),
        currentStepState: xtAutomationRuntimeString(object["current_step_state"]).flatMap(XTAutomationRunStepState.init(rawValue:)),
        currentStepSummary: xtAutomationRuntimeString(object["current_step_summary"])
    )
}

private func xtAutomationRuntimeState(_ value: Any?) -> XTAutomationRunState? {
    guard let rawValue = xtAutomationRuntimeString(value) else { return nil }
    return XTAutomationRunState(rawValue: rawValue)
}

private func xtAutomationRuntimeString(_ value: Any?) -> String? {
    if value is NSNull { return nil }
    if let stringValue = value as? String {
        let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    return nil
}

private func xtAutomationRuntimeStringArray(_ value: Any?) -> [String] {
    guard let array = value as? [Any] else { return [] }
    return array.compactMap { xtAutomationRuntimeString($0) }
}

private func xtAutomationRuntimeOrderedUniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    var ordered: [String] = []
    for value in values {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
        ordered.append(trimmed)
    }
    return ordered
}

private func xtAutomationRuntimeInt(_ value: Any?, fallback: Int) -> Int {
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    if let stringValue = value as? String,
       let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return intValue
    }
    return fallback
}

private func xtAutomationRuntimeIntOptional(_ value: Any?) -> Int? {
    if value is NSNull { return nil }
    if let intValue = value as? Int {
        return intValue
    }
    if let doubleValue = value as? Double {
        return Int(doubleValue)
    }
    if let stringValue = value as? String,
       let intValue = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return intValue
    }
    return nil
}

private func xtAutomationRuntimeDouble(_ value: Any?) -> TimeInterval {
    if let doubleValue = value as? Double {
        return doubleValue
    }
    if let intValue = value as? Int {
        return TimeInterval(intValue)
    }
    if let stringValue = value as? String,
       let doubleValue = Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return doubleValue
    }
    return Date().timeIntervalSince1970
}

private func xtAutomationRuntimeBool(_ value: Any?) -> Bool {
    if let boolValue = value as? Bool {
        return boolValue
    }
    if let intValue = value as? Int {
        return intValue != 0
    }
    if let stringValue = value as? String {
        return ["1", "true", "yes"].contains(stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    return false
}
