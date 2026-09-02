import Foundation

extension SupervisorManager {
    func buildSupervisorDeltaFeed(
        userMessage: String,
        projectDigests: [SupervisorMemoryProjectDigest],
        focusedSelection: SupervisorFocusedProjectSelection?,
        focusedExecutionBrief: SupervisorFocusedProjectExecutionBrief?,
        workflowObservation: String?
    ) -> String {
        let projection = supervisorDeltaFeedProjection(
            projectDigests: projectDigests,
            focusedSelection: focusedSelection,
            focusedExecutionBrief: focusedExecutionBrief,
            workflowObservation: workflowObservation
        )
        let deltaItemsText = projection.deltaItems.isEmpty
            ? "- [no_material_change] keep_current_strategy"
            : projection.deltaItems.joined(separator: "\n")
        let recentProjectActionsText = projection.recentProjectActions.isEmpty
            ? "(none)"
            : projection.recentProjectActions.joined(separator: "\n")
        let recentActionsText = projection.recentActionLedger.isEmpty
            ? "(none)"
            : projection.recentActionLedger.joined(separator: "\n")
        let recentEventsText = projection.recentEventLines.isEmpty
            ? "(none)"
            : projection.recentEventLines.joined(separator: "\n")
        return """
cursor_from: \(projection.cursorFrom)
cursor_to: \(projection.cursorTo)
focus_project: \(focusedSelection?.project.displayName ?? "(none)")
focus_project_id: \(projection.focusProjectId)
project_state_hash_before: \(projection.projectStateHashBefore)
project_state_hash_after: \(projection.projectStateHashAfter)
portfolio_state_hash_before: \(projection.portfolioStateHashBefore)
portfolio_state_hash_after: \(projection.portfolioStateHashAfter)
material_change_flags: \(projection.materialChangeFlags.isEmpty ? "none" : projection.materialChangeFlags.joined(separator: ", "))
user_intent_hint: \(capped(userMessage, maxChars: 160))
delta_items:
\(deltaItemsText)
focused_project_delta:
\(focusedExecutionBrief?.observation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? focusedExecutionBrief!.observation : "(none)")
workflow_delta:
\(workflowObservation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? workflowObservation! : "(none)")
recent_project_actions:
\(recentProjectActionsText)
recent_events:
\(recentEventsText)
recent_actions:
\(recentActionsText)
"""
    }

    func supervisorDeltaFeedProjection(
        projectDigests: [SupervisorMemoryProjectDigest],
        focusedSelection: SupervisorFocusedProjectSelection?,
        focusedExecutionBrief: SupervisorFocusedProjectExecutionBrief?,
        workflowObservation: String?
    ) -> SupervisorDeltaFeedProjection {
        let nowMs = max(0, Int64((Date().timeIntervalSince1970 * 1000.0).rounded()))
        var flags: [String] = []
        var deltaItems: [String] = []
        let portfolioStateHashAfter = supervisorPortfolioStateHash(projectDigests)

        guard let focusedSelection else {
            let recentProjectActions = frontstageRecentProjectActionEvents
                .prefix(3)
                .map { event in
                    "- [\(supervisorDeltaItemType(for: event.eventType))] \(capped(event.projectName, maxChars: 48)): \(capped(event.actionSummary, maxChars: 140))"
                }
            let recentActionLedger = actionLedgerEntriesForPrompt(focusedSelection: nil)
                .suffix(3)
                .map(supervisorDeltaActionLedgerLine(_:))
            let recentEventLines = Array(recentEvents.suffix(4))
            if !recentProjectActions.isEmpty { flags.append("portfolio_action_feed") }
            if !recentActionLedger.isEmpty { flags.append("action_ledger") }
            if projectDigests.contains(where: { !isDigestPlaceholder($0.blocker, treatNoValueAsPlaceholder: true) }) {
                flags.append("portfolio_blockers_present")
            }
            if recentProjectActions.isEmpty && recentActionLedger.isEmpty {
                flags.append("no_material_change")
                deltaItems.append("- [no_material_change] no focused project selected; keep portfolio strategy and inspect only if a project surfaces material drift")
            } else {
                deltaItems.append(contentsOf: recentProjectActions)
                deltaItems.append(contentsOf: recentActionLedger)
            }
            return SupervisorDeltaFeedProjection(
                cursorFrom: "portfolio_bootstrap",
                cursorTo: "memory_build:\(nowMs)",
                focusProjectId: "(none)",
                projectStateHashBefore: "(none)",
                projectStateHashAfter: "(none)",
                portfolioStateHashBefore: "(none)",
                portfolioStateHashAfter: portfolioStateHashAfter,
                materialChangeFlags: orderedUniqueSupervisorFlags(flags),
                deltaItems: deltaItems,
                recentProjectActions: recentProjectActions,
                recentActionLedger: recentActionLedger,
                recentEventLines: recentEventLines
            )
        }

        let project = focusedSelection.project
        let ctx = supervisorMemoryContext(for: project)
        let digest = projectDigests.first(where: { $0.projectId == project.projectId }) ?? supervisorMemoryDigest(project)
        let governance = loadSupervisorProjectDigestGovernanceContext(projectId: project.projectId, ctx: ctx)
        let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
        let effectiveRuntimeSurface = config.effectiveRuntimeSurfacePolicy()
        let workflowState = supervisorWorkflowState(
            project: project,
            ctx: ctx,
            preferredJobId: currentTask?.projectId == project.projectId ? currentTask?.id : nil,
            preferredPlanId: nil,
            preferredRequestId: nil
        )
        let activeJobGoal = workflowState?.job.goal.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let doneDefinition = firstMeaningfulDigestValue([
            governance.specCapsule?.mvpDefinition,
            activeJobGoal
        ])
        let currentConstraints = focusedSupervisorReviewConstraintItems(
            specCapsule: governance.specCapsule,
            config: config,
            effectiveRuntimeSurface: effectiveRuntimeSurface
        )
        let latestReview = SupervisorReviewNoteStore.latest(for: ctx)
        let latestGuidance = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pendingAckGuidance = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)
        let cursorFromMs = max(
            latestReview?.createdAtMs ?? 0,
            0
        )
        let cursorFrom = latestReview?.memoryCursor ?? latestReview.map {
            supervisorReviewCursor(reviewId: $0.reviewId, createdAtMs: $0.createdAtMs)
        } ?? "none"
        let projectStateHashBefore = latestReview?.projectStateHash ?? latestReview.map(focusedSupervisorReviewedStateHash(note:)) ?? "(none)"
        let projectStateHashAfter = focusedSupervisorCurrentStateHash(
            digest: digest,
            doneDefinition: doneDefinition,
            executionBrief: focusedExecutionBrief,
            workflowObservation: workflowObservation,
            workflowState: workflowState,
            latestGuidance: latestGuidance,
            pendingAckGuidance: pendingAckGuidance
        )
        let portfolioStateHashBefore = latestReview?.portfolioStateHash ?? "(none)"

        flags.append("focused_project")
        if latestReview == nil {
            flags.append("first_review_baseline")
            deltaItems.append("- [progress_delta] no prior focused-project review cursor; treating the current project state as the new baseline")
        }
        if projectStateHashBefore != "(none)", projectStateHashBefore != projectStateHashAfter {
            flags.append("project_state_changed")
        }
        if portfolioStateHashBefore != "(none)", portfolioStateHashBefore != portfolioStateHashAfter {
            flags.append("portfolio_state_changed")
        }

        if let latestReview {
            appendSupervisorDeltaFieldChange(
                kind: "progress_delta",
                field: "current_state",
                before: latestReview.currentState,
                after: digest.currentState,
                flags: &flags,
                items: &deltaItems
            )
            appendSupervisorDeltaFieldChange(
                kind: "progress_delta",
                field: "next_step",
                before: latestReview.nextStep,
                after: digest.nextStep,
                flags: &flags,
                items: &deltaItems
            )
            appendSupervisorDeltaFieldChange(
                kind: "blocker_delta",
                field: "blocker",
                before: latestReview.blocker,
                after: digest.blocker,
                flags: &flags,
                items: &deltaItems
            )
            appendSupervisorDeltaFieldChange(
                kind: "decision_delta",
                field: "goal",
                before: latestReview.anchorGoal,
                after: digest.goal,
                flags: &flags,
                items: &deltaItems
            )
            appendSupervisorDeltaFieldChange(
                kind: "decision_delta",
                field: "done_definition",
                before: latestReview.anchorDoneDefinition,
                after: doneDefinition,
                flags: &flags,
                items: &deltaItems
            )

            let normalizedCurrentConstraints = normalizedSupervisorConstraintScalars(currentConstraints)
            let normalizedPreviousConstraints = normalizedSupervisorConstraintScalars(latestReview.anchorConstraints)
            if normalizedCurrentConstraints != normalizedPreviousConstraints {
                flags.append("constraint_delta")
                deltaItems.append(
                    "- [decision_delta] constraints/guardrails changed since last review: before=\(supervisorDeltaConstraintInline(normalizedPreviousConstraints)) after=\(supervisorDeltaConstraintInline(normalizedCurrentConstraints))"
                )
            }
        }

        if let latestGuidance,
           latestGuidance.injectedAtMs > cursorFromMs {
            flags.append("guidance_delta")
            deltaItems.append(
                "- [guidance_delta] guidance updated: ack_status=\(latestGuidance.ackStatus.rawValue) delivery=\(latestGuidance.deliveryMode.rawValue) intervention=\(latestGuidance.interventionMode.rawValue)"
            )
        } else if let pendingAckGuidance,
                  pendingAckGuidance.ackRequired,
                  pendingAckGuidance.ackStatus == .pending {
            flags.append("guidance_delta")
            deltaItems.append(
                "- [guidance_delta] pending supervisor guidance ack remains open: delivery=\(pendingAckGuidance.deliveryMode.rawValue) intervention=\(pendingAckGuidance.interventionMode.rawValue)"
            )
        }

        let projectActionEvents = supervisorDeltaFeedProjectActionEvents(
            focusedSelection: focusedSelection
        )
            .filter { event in
                event.projectId == project.projectId &&
                max(0, Int64((event.occurredAt * 1000.0).rounded())) > cursorFromMs
            }
            .prefix(3)
        let recentProjectActions = projectActionEvents.map { event in
            "- [\(supervisorDeltaItemType(for: event.eventType))] \(capped(event.actionTitle, maxChars: 96)) -> \(capped(event.nextAction, maxChars: 96))"
        }
        if !recentProjectActions.isEmpty {
            flags.append("project_action_feed")
            deltaItems.append(contentsOf: recentProjectActions)
        }

        let recentActionLedger = actionLedger
            .filter { item in
                (item.projectId == project.projectId || item.projectName == project.displayName) &&
                max(0, Int64((item.createdAt * 1000.0).rounded())) > cursorFromMs
            }
            .suffix(3)
            .map(supervisorDeltaActionLedgerLine(_:))
        if !recentActionLedger.isEmpty {
            flags.append("action_ledger")
            deltaItems.append(contentsOf: recentActionLedger)
        }

        let recentEventLines = supervisorRecentEventLines(
            focusedSelection: focusedSelection,
            cursorFromMs: cursorFromMs
        )
        if !recentEventLines.isEmpty {
            flags.append("recent_events")
        }
        if projectDigests.contains(where: { !isDigestPlaceholder($0.blocker, treatNoValueAsPlaceholder: true) }) {
            flags.append("portfolio_blockers_present")
        }
        if projectStateHashBefore == projectStateHashAfter && latestReview != nil && deltaItems.isEmpty {
            flags.append("no_material_change")
            deltaItems.append("- [no_material_change] focused project state hash is unchanged since the latest review; keep current strategy unless new evidence appears")
        }

        return SupervisorDeltaFeedProjection(
            cursorFrom: cursorFrom,
            cursorTo: "memory_build:\(nowMs)",
            focusProjectId: project.projectId,
            projectStateHashBefore: projectStateHashBefore,
            projectStateHashAfter: projectStateHashAfter,
            portfolioStateHashBefore: portfolioStateHashBefore,
            portfolioStateHashAfter: portfolioStateHashAfter,
            materialChangeFlags: orderedUniqueSupervisorFlags(flags),
            deltaItems: deltaItems,
            recentProjectActions: recentProjectActions,
            recentActionLedger: recentActionLedger,
            recentEventLines: recentEventLines
        )
    }

    func appendSupervisorDeltaFieldChange(
        kind: String,
        field: String,
        before: String,
        after: String,
        flags: inout [String],
        items: inout [String]
    ) {
        let beforeValue = supervisorNormalizedDeltaScalar(before)
        let afterValue = supervisorNormalizedDeltaScalar(after)
        guard beforeValue != afterValue else { return }
        flags.append(kind)
        items.append(
            "- [\(kind)] \(field): before=\(capped(beforeValue, maxChars: 96)) after=\(capped(afterValue, maxChars: 96))"
        )
    }

    func supervisorPortfolioStateHash(
        _ projectDigests: [SupervisorMemoryProjectDigest]
    ) -> String {
        let stable = projectDigests
            .sorted { lhs, rhs in
                if lhs.projectId != rhs.projectId {
                    return lhs.projectId < rhs.projectId
                }
                return lhs.updatedAt < rhs.updatedAt
            }
            .map { digest in
                [
                    "project_id=\(digest.projectId)",
                    "runtime_state=\(digest.runtimeState)",
                    "goal=\(digest.goal)",
                    "current_state=\(digest.currentState)",
                    "next_step=\(digest.nextStep)",
                    "blocker=\(digest.blocker)"
                ].joined(separator: "\n")
            }
            .joined(separator: "\n---\n")
        return supervisorDeterministicDigest(stable: stable.isEmpty ? "portfolio:none" : stable)
    }

    func focusedSupervisorReviewedStateHash(
        note: SupervisorReviewNoteRecord
    ) -> String {
        let stable = """
project_id=\(note.projectId)
goal=\(note.anchorGoal)
done_definition=\(note.anchorDoneDefinition)
constraints=\(normalizedSupervisorConstraintScalars(note.anchorConstraints).joined(separator: " | "))
current_state=\(note.currentState)
next_step=\(note.nextStep)
blocker=\(note.blocker)
"""
        return supervisorDeterministicDigest(stable: stable)
    }

    func focusedSupervisorCurrentStateHash(
        digest: SupervisorMemoryProjectDigest,
        doneDefinition: String,
        executionBrief: SupervisorFocusedProjectExecutionBrief?,
        workflowObservation: String?,
        workflowState: (job: SupervisorJobRecord, plan: SupervisorPlanRecord?, skillCall: SupervisorSkillCallRecord?)?,
        latestGuidance: SupervisorGuidanceInjectionRecord?,
        pendingAckGuidance: SupervisorGuidanceInjectionRecord?
    ) -> String {
        let activeJob = workflowState?.job
        let activePlan = workflowState?.plan
        let activeSkillCall = workflowState?.skillCall
        let stable = """
project_id=\(digest.projectId)
runtime_state=\(digest.runtimeState)
goal=\(digest.goal)
done_definition=\(doneDefinition)
current_state=\(digest.currentState)
next_step=\(digest.nextStep)
blocker=\(digest.blocker)
anchor=\(executionBrief?.anchorPackBody ?? "(none)")
longterm_outline=\(executionBrief?.longtermOutlineBody ?? "(none)")
workflow_observation=\(workflowObservation ?? "(none)")
active_job_id=\(activeJob?.jobId ?? "(none)")
active_job_status=\(activeJob?.status.rawValue ?? "(none)")
active_plan_id=\(activePlan?.planId ?? "(none)")
active_plan_status=\(activePlan?.status.rawValue ?? "(none)")
active_skill_request_id=\(activeSkillCall?.requestId ?? "(none)")
active_skill_status=\(activeSkillCall?.status.rawValue ?? "(none)")
latest_guidance=\(latestGuidance?.reviewId ?? "(none)")/\(latestGuidance?.ackStatus.rawValue ?? "(none)")
pending_ack_guidance=\(pendingAckGuidance?.reviewId ?? "(none)")/\(pendingAckGuidance?.ackStatus.rawValue ?? "(none)")
"""
        return supervisorDeterministicDigest(stable: stable)
    }

    func supervisorRecentEventLines(
        focusedSelection: SupervisorFocusedProjectSelection?,
        cursorFromMs: Int64
    ) -> [String] {
        let targetName = focusedSelection?.project.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetID = focusedSelection?.project.projectId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let records = supervisorRecentEventRecordsForPrompt(
            focusedSelection: focusedSelection
        )
        let filtered = records.reversed().filter { record in
            guard let focusedSelection else { return true }
            let line = record.text
            return supervisorRecentEventRecord(record, matches: focusedSelection.project)
                || (!targetName.isEmpty && line.localizedCaseInsensitiveContains(targetName))
                || (!targetID.isEmpty && line.localizedCaseInsensitiveContains(targetID))
                || line.localizedCaseInsensitiveContains("guidance ack")
        }
        let limited = Array(filtered.prefix(cursorFromMs > 0 ? 4 : 3).reversed())
        return limited.map(\.text)
    }

    func supervisorObservationRecentEventLines(
        focusedSelection: SupervisorFocusedProjectSelection?
    ) -> [String] {
        supervisorRecentEventRecordsForPrompt(
            focusedSelection: focusedSelection
        )
        .suffix(8)
        .map(\.text)
    }

    func supervisorDeltaActionLedgerLine(
        _ item: SupervisorActionLedgerEntry
    ) -> String {
        let project = (item.projectName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let projectToken = project.isEmpty ? (item.projectId ?? "(none)") : project
        let kind = supervisorDeltaItemType(for: item)
        return "- [\(kind)] \(item.action) target=\(capped(projectToken, maxChars: 64)) status=\(item.status) reason=\(item.reasonCode)"
    }

    func supervisorDeltaItemType(
        for eventType: SupervisorProjectActionEventType
    ) -> String {
        switch eventType {
        case .created, .progressed, .completed:
            return "progress_delta"
        case .blocked:
            return "blocker_delta"
        case .awaitingAuthorization:
            return "grant_delta"
        case .archived:
            return "verification_delta"
        }
    }

    func supervisorDeltaItemType(
        for item: SupervisorActionLedgerEntry
    ) -> String {
        let action = item.action.lowercased()
        let status = item.status.lowercased()
        let reason = item.reasonCode.lowercased()
        if action.contains("grant") || reason.contains("authorization") || reason.contains("approve") {
            return "grant_delta"
        }
        if status.contains("verified") || action.contains("verify") {
            return "verification_delta"
        }
        if status.contains("blocked") || reason.contains("blocked") {
            return "blocker_delta"
        }
        return "progress_delta"
    }

    func supervisorDeltaConstraintInline(
        _ items: [String]
    ) -> String {
        guard !items.isEmpty else { return "(none)" }
        return capped(normalizedSupervisorConstraintScalars(items).prefix(4).joined(separator: " | "), maxChars: 160)
    }

    func supervisorNormalizedDeltaScalar(
        _ value: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "(none)"
        }
        if isDigestPlaceholder(trimmed, treatContinueCurrentTaskAsPlaceholder: true, treatNoValueAsPlaceholder: true) {
            return "(none)"
        }
        return trimmed
    }

    func orderedUniqueSupervisorFlags(
        _ flags: [String]
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for flag in flags {
            let trimmed = flag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            ordered.append(trimmed)
        }
        return ordered
    }

    func normalizedSupervisorConstraintScalars(
        _ values: [String]
    ) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            let normalized = normalizedSupervisorConstraintScalar(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            ordered.append(normalized)
        }
        return ordered
    }

    func normalizedSupervisorConstraintScalar(
        _ value: String
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("autonomy=") {
            return "surface=\(trimmed.dropFirst("autonomy=".count))"
        }
        if trimmed.hasPrefix("autonomy_guard:") {
            return "runtime_surface_guard:\(trimmed.dropFirst("autonomy_guard:".count))"
        }
        if trimmed.hasPrefix("autonomy:") {
            return "runtime_surface:\(trimmed.dropFirst("autonomy:".count))"
        }
        return trimmed
    }
}
