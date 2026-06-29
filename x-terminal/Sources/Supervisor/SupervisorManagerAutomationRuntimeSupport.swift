import Foundation

extension SupervisorManager {
    @discardableResult
    func performAutomationRuntimeCommand(
        _ userMessage: String,
        emitSystemMessage: Bool = false
    ) -> String? {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard looksLikeAutomationRuntimeCommand(trimmed) else { return nil }

        let response: String
        guard let command = parseAutomationRuntimeCommand(trimmed) else {
            response = automationRuntimeCommandHelpText()
            if emitSystemMessage {
                addSystemMessage(response)
            }
            return response
        }

        do {
            switch command.action {
            case .help:
                response = automationRuntimeCommandHelpText()

            case .status:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                response = try renderAutomationRuntimeStatus(for: project, ctx: ctx)

            case .start:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let request = try makeManualAutomationRunRequest(for: project, ctx: ctx)
                let prepared = try startAutomationRun(for: ctx, request: request, emitSystemMessage: false)
                response = renderAutomationStartSummary(project: project, prepared: prepared)

            case .recover:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let recoveryNow = Date().timeIntervalSince1970
                let recoveryCandidate = try automationRunCoordinator.latestRecoveryCandidate(
                    for: ctx,
                    now: recoveryNow
                )
                let decision = try recoverLatestAutomationRun(
                    for: project,
                    ctx: ctx,
                    now: recoveryNow,
                    recoveryMode: .operatorOverride,
                    auditRef: automationRuntimeAuditRef(action: "recover", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationRecoverySummary(
                    project: project,
                    ctx: ctx,
                    decision: decision,
                    retryPackage: automationLatestRetryPackage,
                    recoveryCandidate: recoveryCandidate
                )

            case .cancel:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                guard let runID = effectiveAutomationRunRef(
                    for: ctx,
                    allowedStates: automationMutableRunStates
                ) else {
                    throw XTAutomationRunCoordinatorError.runNotFound("active")
                }
                let decision = try cancelAutomationRun(
                    for: ctx,
                    runID: runID,
                    auditRef: automationRuntimeAuditRef(action: "cancel", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationCancelSummary(project: project, decision: decision)

            case .advance(let nextState):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                guard let runID = effectiveAutomationRunRef(
                    for: ctx,
                    allowedStates: automationMutableRunStates
                ) else {
                    throw XTAutomationRunCoordinatorError.runNotFound("active")
                }
                let checkpoint = try advanceAutomationRun(
                    for: ctx,
                    to: nextState,
                    runID: runID,
                    auditRef: automationRuntimeAuditRef(action: "advance_\(nextState.rawValue)", project: project),
                    emitSystemMessage: false
                )
                response = renderAutomationAdvanceSummary(project: project, checkpoint: checkpoint)

            case .selfIterateStatus:
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try AXProjectStore.loadOrCreateConfig(for: ctx)
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: "🧠 automation self-iterate 状态"
                )

            case .selfIterateSet(let enabled):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try updateAutomationSelfIterateConfig(
                    for: project,
                    ctx: ctx,
                    enabled: enabled
                )
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: enabled
                        ? "🧠 automation self-iterate 已开启"
                        : "🧠 automation self-iterate 已关闭"
                )

            case .selfIterateMax(let depth):
                let (project, ctx) = try resolveAutomationCommandProject(command.projectRef)
                let config = try updateAutomationSelfIterateConfig(
                    for: project,
                    ctx: ctx,
                    maxAutoRetryDepth: depth
                )
                response = renderAutomationSelfIterateSummary(
                    project: project,
                    config: config,
                    headline: "🧠 automation self-iterate 深度已更新"
                )
            }
        } catch {
            response = renderAutomationRuntimeError(error)
        }

        if emitSystemMessage {
            addSystemMessage(response)
        }
        return response
    }

    var automationMutableRunStates: Set<XTAutomationRunState> {
        [.queued, .running, .blocked, .takeover, .downgraded]
    }

    var automationBlockingRunStates: Set<XTAutomationRunState> {
        [.queued, .running, .blocked, .takeover]
    }

    func automationRuntimeAuditRef(action: String, project: AXProjectEntry) -> String {
        let actionToken = normalizedLookupKey(action)
        let projectToken = normalizedLookupKey(project.projectId)
        return "audit-xt-auto-\(actionToken)-\(projectToken)-\(Int(Date().timeIntervalSince1970))"
    }

    func automationRetryDepthValue(from retryPackage: XTAutomationRetryPackage) -> Int {
        if let retryDepth = retryPackage.lineage?.retryDepth,
           retryDepth > 0 {
            return retryDepth
        }
        for ref in retryPackage.additionalEvidenceRefs where ref.hasPrefix("retry://depth/") {
            if let token = ref.split(separator: "/").last,
               let depth = Int(token) {
                return max(1, depth)
            }
        }
        return 1
    }

    func xtAutomationBlockerLogValue(
        _ blocker: XTAutomationBlockerDescriptor
    ) -> [String: Any] {
        [
            "code": blocker.code,
            "summary": blocker.summary,
            "stage": blocker.stage.rawValue,
            "detail": blocker.detail,
            "next_safe_action": blocker.nextSafeAction,
            "retry_eligible": blocker.retryEligible,
            "current_step_id": blocker.currentStepID ?? NSNull(),
            "current_step_title": blocker.currentStepTitle ?? NSNull(),
            "current_step_state": blocker.currentStepState?.rawValue ?? NSNull(),
            "current_step_summary": blocker.currentStepSummary ?? NSNull(),
        ]
    }

    func xtAutomationRetryReasonLogValue(
        _ reason: XTAutomationRetryReasonDescriptor
    ) -> [String: Any] {
        [
            "code": reason.code,
            "category": reason.category.rawValue,
            "summary": reason.summary,
            "strategy": reason.strategy,
            "blocker_code": reason.blockerCode,
            "planning_mode": reason.planningMode ?? NSNull(),
            "current_step_id": reason.currentStepID ?? NSNull(),
            "current_step_title": reason.currentStepTitle ?? NSNull(),
            "current_step_state": reason.currentStepState?.rawValue ?? NSNull(),
            "current_step_summary": reason.currentStepSummary ?? NSNull(),
        ]
    }

    func automationRetryLineage(for retryPackage: XTAutomationRetryPackage) -> XTAutomationRunLineage {
        let fallbackRunID = retryPackage.retryRunID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? retryPackage.sourceRunID
            : retryPackage.retryRunID
        let lineage = xtAutomationResolvedLineage(retryPackage.lineage, fallbackRunID: fallbackRunID)
        let sourceRunID = retryPackage.sourceRunID.trimmingCharacters(in: .whitespacesAndNewlines)
        if sourceRunID.isEmpty {
            return lineage
        }
        if lineage.parentRunID == sourceRunID {
            return lineage
        }
        return lineage.retryChild(
            parentRunID: sourceRunID,
            retryDepth: automationRetryDepthValue(from: retryPackage)
        )
    }

    func xtAutomationMergeEvidenceRefs(_ lhs: [String], _ rhs: [String]) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []

        for value in lhs + rhs {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            merged.append(trimmed)
        }

        return merged
    }

    func automationDeliveryClosureProjection(
        for project: AXProjectEntry,
        ctx: AXProjectContext,
        preferredRunID: String?,
        now: Date
    ) -> XTAutomationDeliveryClosureProjection? {
        xtAutomationProjectDeliveryClosureProjection(
            for: ctx,
            projectID: project.projectId,
            preferredRunID: preferredRunID,
            now: now
        )
    }

    func appendAutomationDeliveryClosureLines(
        _ projection: XTAutomationDeliveryClosureProjection?,
        to lines: inout [String]
    ) {
        guard let projection else { return }
        lines.append("delivery_closure_run_id: \(projection.runID)")
        if let deliveryRef = projection.deliveryRef,
           !deliveryRef.isEmpty {
            lines.append("delivery_closure_delivery_ref: \(deliveryRef)")
        }
        lines.append("delivery_closure_source: \(projection.source.rawValue)")
        lines.append("delivery_closure_lineage: \(projection.lineage.lineageID)")
        lines.append("delivery_closure_root_run: \(projection.lineage.rootRunID)")
        if !projection.lineage.parentRunID.isEmpty {
            lines.append("delivery_closure_parent_run: \(projection.lineage.parentRunID)")
        }
        lines.append("delivery_closure_retry_depth: \(projection.lineage.retryDepth)")
    }

    func appendPersistedAutomationRecoveryLines(
        _ summary: XTAutomationPersistedRecoveryActionSummary?,
        to lines: inout [String]
    ) {
        guard let summary else { return }
        lines.append("last_recovery_run_id: \(summary.decision.runID)")
        lines.append("last_recovery_state: \(summary.decision.recoveredState.rawValue)")
        lines.append("last_recovery_decision: \(summary.decision.decision.rawValue)")
        lines.append("last_recovery_mode: \(summary.recoveryMode.rawValue)")
        lines.append("last_recovery_checkpoint_ref: \(summary.decision.checkpointRef)")
        lines.append("last_recovery_resume_token: \(summary.decision.resumeToken)")
        lines.append("last_recovery_audit_ref: \(summary.decision.auditRef)")
        if !summary.decision.holdReason.isEmpty {
            lines.append("last_recovery_hold_reason: \(summary.decision.holdReason)")
        }
        if let resumeMode = summary.resumeMode {
            lines.append("last_recovery_resume_mode: \(resumeMode.rawValue)")
        }
        if let retryRunID = summary.retryRunID,
           !retryRunID.isEmpty {
            lines.append("last_recovery_retry_run_id: \(retryRunID)")
        }
        if let retryStrategy = summary.retryStrategy,
           !retryStrategy.isEmpty {
            lines.append("last_recovery_retry_strategy: \(retryStrategy)")
        }
        if let retryReason = summary.retryReason,
           !retryReason.isEmpty {
            lines.append("last_recovery_retry_reason: \(retryReason)")
        }
        if let deliveryClosure = summary.deliveryClosure {
            if let deliveryRef = deliveryClosure.deliveryRef,
               !deliveryRef.isEmpty {
                lines.append("last_recovery_delivery_ref: \(deliveryRef)")
            }
            lines.append("last_recovery_delivery_closure_source: \(deliveryClosure.source.rawValue)")
            lines.append("last_recovery_delivery_closure_run_id: \(deliveryClosure.runID)")
            lines.append("last_recovery_lineage: \(deliveryClosure.lineage.lineageID)")
            lines.append("last_recovery_root_run: \(deliveryClosure.lineage.rootRunID)")
            if !deliveryClosure.lineage.parentRunID.isEmpty {
                lines.append("last_recovery_parent_run: \(deliveryClosure.lineage.parentRunID)")
            }
            lines.append("last_recovery_retry_depth: \(deliveryClosure.lineage.retryDepth)")
        }
    }
}
