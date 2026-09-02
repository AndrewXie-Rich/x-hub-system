import Foundation

extension SupervisorManager {
    private func shouldAttemptHeartbeatAutoProgress(reason: String) -> Bool {
        reason == "timer"
    }

    func heartbeatAutoProgressActions(
        reason: String,
        now: Date,
        projects: [AXProjectEntry],
        queueSignals: [ProjectQueueSignal],
        permissionSignals: [ProjectPermissionSignal]
    ) -> [HeartbeatAutoProgressAction] {
        guard shouldAttemptHeartbeatAutoProgress(reason: reason) else { return [] }

        let nowSec = now.timeIntervalSince1970
        let queuedProjectIds = Set(queueSignals.map { $0.project.projectId })
        let permissionProjectIds = Set(permissionSignals.map(\.projectId))
        var actions: [HeartbeatAutoProgressAction] = []

        for project in projects {
            if actions.count >= 2 { break }
            if queuedProjectIds.contains(project.projectId) { continue }
            if permissionProjectIds.contains(project.projectId) { continue }
            if let lastActionAt = heartbeatAutoProgressLedger[project.projectId],
               nowSec - lastActionAt < heartbeatAutoProgressCooldownSec {
                continue
            }
            guard let ctx = projectContext(from: project) else { continue }
            guard let config = try? AXProjectStore.loadOrCreateConfig(for: ctx),
                  let recipe = config.activeAutomationRecipe,
                  recipe.lifecycleState == .ready else {
                continue
            }

            let recoverAuditRef = automationRuntimeAuditRef(action: "heartbeat_recover", project: project)
            if let decision = try? recoverLatestAutomationRun(
                for: project,
                ctx: ctx,
                now: nowSec,
                recoveryMode: .automatic,
                auditRef: recoverAuditRef,
                emitSystemMessage: false
            ), decision.decision == .resume {
                heartbeatAutoProgressLedger[project.projectId] = nowSec
                actions.append(
                    HeartbeatAutoProgressAction(
                        kind: .recover,
                        projectId: project.projectId,
                        projectName: project.displayName,
                        detail: "已恢复可继续的 automation run",
                        runId: decision.runID
                    )
                )
                continue
            }

            if automationProjectHasBlockingRun(ctx) {
                continue
            }
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !blocker.isEmpty { continue }
            if !recipe.actionGraph.isEmpty {
                let runtime = runtimeStatus(for: project, now: nowSec)
                if runtime.state == .paused,
                   (try? latestAutomationLaunchRef(for: ctx)) == nil,
                   let request = try? makeManualAutomationRunRequest(for: project, ctx: ctx),
                   let prepared = try? startAutomationRun(for: ctx, request: request, emitSystemMessage: false) {
                    heartbeatAutoProgressLedger[project.projectId] = nowSec
                    actions.append(
                        HeartbeatAutoProgressAction(
                            kind: .start,
                            projectId: project.projectId,
                            projectName: project.displayName,
                            detail: "已发起 automation kickstart",
                            runId: prepared.launchRef
                        )
                    )
                }
            }
        }

        return actions
    }

    func evaluateBlockerSignal(
        now: TimeInterval,
        blockerCount: Int,
        blockerFingerprint: String
    ) -> BlockerSignal {
        guard blockerCount > 0 else {
            blockerStreakCount = 0
            lastBlockerFingerprint = ""
            return BlockerSignal(streak: 0, escalated: false, cooldownRemainingSec: 0)
        }

        if blockerFingerprint == lastBlockerFingerprint {
            blockerStreakCount += 1
        } else {
            blockerStreakCount = 1
            lastBlockerFingerprint = blockerFingerprint
        }

        guard blockerStreakCount >= blockerEscalationThreshold else {
            return BlockerSignal(streak: blockerStreakCount, escalated: false, cooldownRemainingSec: 0)
        }

        let elapsed = now - lastBlockerEscalationAt
        if elapsed >= blockerEscalationCooldownSec {
            lastBlockerEscalationAt = now
            return BlockerSignal(streak: blockerStreakCount, escalated: true, cooldownRemainingSec: 0)
        }

        let remaining = Int(max(0, ceil(blockerEscalationCooldownSec - elapsed)))
        return BlockerSignal(streak: blockerStreakCount, escalated: false, cooldownRemainingSec: remaining)
    }

    func queuedProjectSignals(
        for projects: [AXProjectEntry],
        now: TimeInterval
    ) -> [ProjectQueueSignal] {
        projects.compactMap { project in
            guard let signal = schedulerSignal(for: project.projectId, now: now) else { return nil }
            guard signal.queued > 0 else { return nil }
            return ProjectQueueSignal(
                project: project,
                inFlight: signal.inFlight,
                queued: signal.queued,
                oldestQueuedMs: signal.oldestQueuedMs
            )
        }.sorted { lhs, rhs in
            if lhs.oldestQueuedMs != rhs.oldestQueuedMs { return lhs.oldestQueuedMs > rhs.oldestQueuedMs }
            if lhs.queued != rhs.queued { return lhs.queued > rhs.queued }
            return lhs.project.displayName.localizedCaseInsensitiveCompare(rhs.project.displayName) == .orderedAscending
        }
    }

    func collectPermissionSignals(
        for projects: [AXProjectEntry]
    ) -> [ProjectPermissionSignal] {
        var out: [ProjectPermissionSignal] = []
        for project in projects {
            guard let ctx = projectContext(from: project) else { continue }

            if let pending = AXPendingActionsStore.pendingToolApproval(for: ctx) {
                let preview = (pending.preview ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let reason = (pending.reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = !preview.isEmpty ? preview : (!reason.isEmpty ? reason : "待确认工具操作")
                let requestId = pending.toolCalls?.first?.id.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append(
                    ProjectPermissionSignal(
                        projectId: project.projectId,
                        projectName: project.displayName,
                        kind: .toolApproval,
                        summary: "等待你审批工具：\(capped(detail, maxChars: 66))",
                        createdAt: pending.createdAt,
                        grantRequestId: nil,
                        capability: nil,
                        actionURL: toolApprovalActionURL(
                            projectId: project.projectId,
                            requestId: requestId
                        )
                    )
                )
            }
        }

        out.append(contentsOf: supervisorPendingSkillApprovalSignals(for: projects))
        out.append(contentsOf: hubPendingGrantSignals(for: projects))

        return out.sorted { lhs, rhs in
            let lt = lhs.createdAt ?? 0
            let rt = rhs.createdAt ?? 0
            if lt != rt { return lt < rt }
            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    func collectGovernanceRepairSignals(
        for projects: [AXProjectEntry],
        limit: Int = 8
    ) -> [ProjectGovernanceRepairSignal] {
        guard limit > 0 else { return [] }

        let activities = normalizedRecentSupervisorSkillActivities(
            projects: projects,
            limit: max(limit * 3, 12)
        )
        var seenProjects = Set<String>()
        var out: [ProjectGovernanceRepairSignal] = []

        for activity in activities {
            let projectId = activity.projectId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !projectId.isEmpty, !seenProjects.contains(projectId) else { continue }
            guard let hint = governanceRepairHint(for: activity.record) else { continue }
            let blockedSummary = SupervisorSkillActivityPresentation.blockedSummaryText(for: activity)
            let policyReason = firstNonEmpty(activity.policyReason)
            let governanceReason = SupervisorSkillActivityPresentation.governanceReasonText(for: activity)
            let governanceTruth = SupervisorSkillActivityPresentation.governanceTruthLine(for: activity)

            seenProjects.insert(projectId)
            out.append(
                ProjectGovernanceRepairSignal(
                    projectId: projectId,
                    projectName: activity.projectName,
                    summary: governanceRepairSummary(
                        item: activity,
                        hint: hint
                    ),
                    destination: hint.destination,
                    blockedSummary: blockedSummary,
                    policyReason: policyReason,
                    governanceReason: governanceReason,
                    governanceTruth: governanceTruth,
                    updatedAt: activity.updatedAt,
                    actionURL: projectGovernanceActionURL(
                        projectId: projectId,
                        destination: hint.destination
                    )
                )
            )

            if out.count >= limit {
                break
            }
        }

        return out.sorted { lhs, rhs in
            let lt = lhs.updatedAt ?? 0
            let rt = rhs.updatedAt ?? 0
            if lt != rt { return lt > rt }
            if lhs.projectName != rhs.projectName {
                return lhs.projectName.localizedCaseInsensitiveCompare(rhs.projectName) == .orderedAscending
            }
            return lhs.summary.localizedCaseInsensitiveCompare(rhs.summary) == .orderedAscending
        }
    }

    private func governanceRepairSummary(
        item: SupervisorRecentSkillActivity,
        hint: XTGuardrailRepairHint
    ) -> String {
        let destinationLabel: String
        switch hint.destination {
        case .overview:
            destinationLabel = "Project Governance 需要调整"
        case .uiReview:
            destinationLabel = "UI Review 需要调整"
        case .executionTier:
            destinationLabel = "A-Tier 需要调整"
        case .supervisorTier:
            destinationLabel = "S-Tier 需要调整"
        case .heartbeatReview:
            destinationLabel = "Heartbeat / Review 需要调整"
        }

        let detail = XTGuardrailMessagePresentation.blockedBody(
            tool: item.tool,
            toolLabel: item.toolSummary,
            denyCode: item.denyCode,
            policySource: item.policySource,
            policyReason: item.policyReason,
            requiredCapability: item.requiredCapability,
            fallbackSummary: item.resultSummary,
            fallbackDetail: item.record.resultSummary
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let helpText = hint.helpText.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts = [destinationLabel]
        if !detail.isEmpty {
            parts.append(detail)
        }
        if !helpText.isEmpty, !detail.contains(helpText) {
            parts.append(helpText)
        }
        return parts.joined(separator: "；")
    }
}
