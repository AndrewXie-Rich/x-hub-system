import Foundation

extension SupervisorManager {
    func scheduleGovernedReviewFromHeartbeat(
        projects: [AXProjectEntry],
        blockerProjects: [(projectId: String, blocker: String)],
        now: Date
    ) -> HeartbeatGovernedReviewSignal? {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let nowSec = now.timeIntervalSince1970
        let blockerIDs = Set(blockerProjects.map(\.projectId))
        let portfolioCardsByProjectId = Dictionary(
            uniqueKeysWithValues: supervisorPortfolioSnapshot.projects.map { ($0.projectId, $0) }
        )
        let candidates = projects.compactMap { project -> HeartbeatGovernedReviewSelectionCandidate? in
            let ctx = supervisorMemoryContext(for: project)
            let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
            let priorSchedule = SupervisorReviewScheduleStore.load(for: ctx)
            let assessment = HeartbeatQualityPolicy.assess(
                project: project,
                previousState: priorSchedule,
                blockerDetected: blockerIDs.contains(project.projectId),
                nowMs: nowMs
            )
            let observedProgressAtMs = max(
                projectObservedProgressAtMs(project) ?? 0,
                assessment.meaningfulProgressAtMs ?? 0
            )
            let resolvedObservedProgressAtMs = observedProgressAtMs > 0 ? observedProgressAtMs : nil
            let governance = resolvedSupervisorProjectGovernanceState(
                projectId: project.projectId,
                ctx: ctx
            ) ?? xtResolveProjectGovernance(
                projectRoot: ctx.root,
                config: config,
                effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
            )
            let schedule = (try? SupervisorReviewScheduleStore.touchHeartbeat(
                for: ctx,
                config: config,
                observedProgressAtMs: resolvedObservedProgressAtMs,
                assessment: assessment,
                nowMs: nowMs
            ))
                ?? SupervisorReviewScheduleStore.load(for: ctx)
            syncSupervisorProjectHeartbeatMemoryProjection(
                ctx: ctx,
                project: project,
                config: config,
                schedule: schedule,
                nowMs: nowMs
            )
            guard governance.effectiveBundle.supervisorInterventionTier != .s0SilentAudit else {
                return nil
            }
            guard let candidate = SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: blockerIDs.contains(project.projectId),
                nowMs: nowMs
            ) else {
                return nil
            }
            return HeartbeatGovernedReviewSelectionCandidate(
                project: project,
                governance: governance,
                candidate: candidate,
                portfolioCard: heartbeatPortfolioCard(
                    for: project,
                    cachedCards: portfolioCardsByProjectId,
                    now: nowSec
                )
            )
        }

        guard let selected = candidates.max(by: governedReviewCandidateSort(lhs:rhs:)) else { return nil }
        let workflowContext = supervisorEventLoopWorkflowContext(
            project: selected.project,
            preferredJobId: nil,
            preferredPlanId: nil,
            preferredRequestId: nil,
            excludingStepId: nil
        )
        var lines = [
            "自动按 project governance 执行周期 review。",
            "trigger=\(SupervisorCommandTriggerSource.heartbeat.rawValue)",
            "project_ref=\(selected.project.displayName)",
            "project_id=\(selected.project.projectId)",
            "review_trigger=\(selected.candidate.trigger.rawValue)",
            "review_level_hint=\(selected.candidate.reviewLevel.rawValue)",
            "review_run_kind=\(selected.candidate.runKind.rawValue)",
            "policy_reason=\(selected.candidate.policyReason)"
        ]
        let selectedContext = supervisorMemoryContext(for: selected.project)
        let selectedHeartbeatProjection = XTHeartbeatMemoryAssemblySupport.loadProjection(for: selectedContext)
        let projectMemoryStatusLine = heartbeatGovernedReviewProjectMemoryStatusLine(
            from: selectedHeartbeatProjection
        )
        let projectMemoryMetadataText = heartbeatGovernedReviewProjectMemoryMetadataText(
            from: selectedHeartbeatProjection
        )
        if let projectMemoryTokenLine = heartbeatGovernedReviewProjectMemoryTokenLine(
            from: selectedHeartbeatProjection
        ) {
            lines.append(projectMemoryTokenLine)
        }
        lines.append(contentsOf: heartbeatPortfolioTokenLines(card: selected.portfolioCard))
        lines.append(contentsOf: supervisorGovernedReviewGovernanceTokenLines(
            governance: selected.governance,
            candidate: selected.candidate
        ))
        if !workflowContext.isEmpty {
            lines.append(workflowContext.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let dedupeKey = "governed_review:\(selected.project.projectId):\(selected.candidate.trigger.rawValue):\(selected.candidate.runKind.rawValue)"
        let queued = queueSupervisorEventLoopTurn(
            userMessage: lines.joined(separator: "\n"),
            triggerSource: .heartbeat,
            dedupeKey: dedupeKey
        )
        guard queued else { return nil }
        recordRuntimeActivity(
            supervisorGovernedReviewRuntimeActivityLine(
                project: selected.project,
                governance: selected.governance,
                candidate: selected.candidate,
                portfolioCard: selected.portfolioCard
            ),
            project: selected.project
        )
        let causeLabel = heartbeatGovernedReviewCauseLabel(candidate: selected.candidate)
        return HeartbeatGovernedReviewSignal(
            projectId: selected.project.projectId,
            projectName: selected.project.displayName,
            trigger: selected.candidate.trigger,
            runKind: selected.candidate.runKind,
            reviewLevel: selected.candidate.reviewLevel,
            causeLabel: causeLabel,
            summaryLine: heartbeatGovernedReviewSummaryLine(
                project: selected.project,
                candidate: selected.candidate
            ),
            detailLine: heartbeatGovernedReviewDetailLine(
                candidate: selected.candidate,
                portfolioCard: selected.portfolioCard
            ),
            projectMemoryStatusLine: projectMemoryStatusLine,
            projectMemoryMetadataText: projectMemoryMetadataText,
            actionURL: resumeProjectActionURL(projectId: selected.project.projectId)
        )
    }

    private func supervisorGovernedReviewGovernanceTokenLines(
        governance: AXProjectResolvedGovernanceState,
        candidate: SupervisorHeartbeatReviewCandidate
    ) -> [String] {
        let schedule = governance.effectiveBundle.schedule
        var lines = [
            "execution_tier=\(governance.configuredBundle.executionTier.rawValue)",
            "effective_execution_tier=\(governance.effectiveBundle.executionTier.rawValue)",
            "supervisor_intervention_tier=\(governance.configuredBundle.supervisorInterventionTier.rawValue)",
            "effective_supervisor_intervention_tier=\(governance.effectiveBundle.supervisorInterventionTier.rawValue)",
            "review_policy_mode=\(governance.effectiveBundle.reviewPolicyMode.rawValue)",
            "progress_heartbeat_sec=\(schedule.progressHeartbeatSeconds)",
            "review_pulse_sec=\(schedule.reviewPulseSeconds)",
            "brainstorm_review_sec=\(schedule.brainstormReviewSeconds)",
            "governance_compat_source=\(governance.compatSource.rawValue)"
        ]
        let governanceReason = capped(
            supervisorGovernedReviewGovernanceReason(candidate: candidate),
            maxChars: 220
        )
        if !governanceReason.isEmpty {
            lines.append("governance_reason=\(governanceReason)")
        }
        if let governanceTruth = XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: governance.configuredBundle.executionTier.rawValue,
            effectiveExecutionTier: governance.effectiveBundle.executionTier.rawValue,
            configuredSupervisorTier: governance.configuredBundle.supervisorInterventionTier.rawValue,
            effectiveSupervisorTier: governance.effectiveBundle.supervisorInterventionTier.rawValue,
            reviewPolicyMode: governance.effectiveBundle.reviewPolicyMode.rawValue,
            progressHeartbeatSeconds: schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: schedule.reviewPulseSeconds,
            brainstormReviewSeconds: schedule.brainstormReviewSeconds,
            compatSource: governance.compatSource.rawValue
        ) {
            lines.append("governance_truth=\(governanceTruth)")
        }
        return lines
    }

    func supervisorGovernedReviewGovernanceReason(
        candidate: SupervisorHeartbeatReviewCandidate
    ) -> String {
        switch candidate.trigger {
        case .periodicPulse:
            return "当前项目治理要求按固定脉冲周期补做 review，heartbeat 已自动排队。"
        case .noProgressWindow:
            return "当前项目治理要求在长时间无进展时进入 brainstorm review，heartbeat 已自动排队。"
        case .blockerDetected:
            return "当前项目治理允许 blocker 事件驱动 review，heartbeat 检测到阻塞后已自动排队。"
        case .periodicHeartbeat:
            return "当前项目治理要求按 heartbeat 周期补做 review，系统已自动排队。"
        case .failureStreak:
            return "当前项目治理要求在连续失败时补做 review，heartbeat 已自动排队。"
        case .planDrift:
            return "当前项目治理要求在计划漂移时补做 review，heartbeat 已自动排队。"
        case .preHighRiskAction:
            return "当前项目治理要求在高风险动作前补做 review，heartbeat 已自动排队。"
        case .preDoneSummary:
            return "当前项目治理要求在完成前补做 review，heartbeat 已自动排队。"
        case .manualRequest:
            return "当前项目治理按手动请求补做 review，系统已自动排队。"
        case .userOverride:
            return "当前项目治理按显式 override 补做 review，系统已自动排队。"
        }
    }

    private func supervisorGovernedReviewRuntimeActivityLine(
        project: AXProjectEntry,
        governance: AXProjectResolvedGovernanceState,
        candidate: SupervisorHeartbeatReviewCandidate,
        portfolioCard: SupervisorPortfolioProjectCard
    ) -> String {
        (
            [
                "heartbeat_governed_review status=queued",
                "trigger=\(SupervisorCommandTriggerSource.heartbeat.rawValue)",
                "project_ref=\(project.displayName)",
                "project_id=\(project.projectId)",
                "review_trigger=\(candidate.trigger.rawValue)",
                "review_level_hint=\(candidate.reviewLevel.rawValue)",
                "review_run_kind=\(candidate.runKind.rawValue)",
                "policy_reason=\(candidate.policyReason)"
            ]
            + heartbeatPortfolioTokenLines(card: portfolioCard)
            + supervisorGovernedReviewGovernanceTokenLines(
                governance: governance,
                candidate: candidate
            )
        )
        .joined(separator: " · ")
    }

    private func governedReviewCandidateSort(
        lhs: HeartbeatGovernedReviewSelectionCandidate,
        rhs: HeartbeatGovernedReviewSelectionCandidate
    ) -> Bool {
        if lhs.candidate.priority != rhs.candidate.priority {
            return lhs.candidate.priority < rhs.candidate.priority
        }
        let lhsBandRank = heartbeatPortfolioBandRank(lhs.portfolioCard.prioritySnapshot?.priorityBand)
        let rhsBandRank = heartbeatPortfolioBandRank(rhs.portfolioCard.prioritySnapshot?.priorityBand)
        if lhsBandRank != rhsBandRank {
            return lhsBandRank > rhsBandRank
        }
        let lhsPortfolioScore = lhs.portfolioCard.prioritySnapshot?.priorityScore ?? Int.min
        let rhsPortfolioScore = rhs.portfolioCard.prioritySnapshot?.priorityScore ?? Int.min
        if lhsPortfolioScore != rhsPortfolioScore {
            return lhsPortfolioScore < rhsPortfolioScore
        }
        if lhs.candidate.reviewLevel != rhs.candidate.reviewLevel {
            return lhs.candidate.reviewLevel < rhs.candidate.reviewLevel
        }
        return lhs.project.projectId < rhs.project.projectId
    }

    private func projectObservedProgressAtMs(_ project: AXProjectEntry) -> Int64? {
        let summaryMs = Int64(((project.lastSummaryAt ?? 0) * 1000.0).rounded())
        let eventMs = Int64(((project.lastEventAt ?? 0) * 1000.0).rounded())
        let observed = max(summaryMs, eventMs)
        return observed > 0 ? observed : nil
    }
}
