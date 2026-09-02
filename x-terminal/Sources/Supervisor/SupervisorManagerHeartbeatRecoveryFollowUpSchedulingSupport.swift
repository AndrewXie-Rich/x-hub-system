import Foundation

extension SupervisorManager {
    @discardableResult
    func scheduleRecoveryFollowUpFromHeartbeat(
        projects: [AXProjectEntry],
        queueSignals: [ProjectQueueSignal],
        permissionSignals: [ProjectPermissionSignal],
        now: Date
    ) -> HeartbeatRecoveryFollowUpSignal? {
        let nowMs = Int64((now.timeIntervalSince1970 * 1000.0).rounded())
        let nowSec = now.timeIntervalSince1970
        let permissionProjectIds = Set(permissionSignals.map(\.projectId))
        let queueProjectIds = Set(queueSignals.map { $0.project.projectId })
        let portfolioCardsByProjectId = Dictionary(
            uniqueKeysWithValues: supervisorPortfolioSnapshot.projects.map { ($0.projectId, $0) }
        )

        let candidates = projects.compactMap {
            project -> HeartbeatRecoveryFollowUpSelectionCandidate? in
            let ctx = supervisorMemoryContext(for: project)
            let config = (try? AXProjectStore.loadOrCreateConfig(for: ctx)) ?? .default(forProjectRoot: ctx.root)
            let governance = resolvedSupervisorProjectGovernanceState(
                projectId: project.projectId,
                ctx: ctx
            ) ?? xtResolveProjectGovernance(
                projectRoot: ctx.root,
                config: config,
                effectiveRuntimeSurface: config.effectiveRuntimeSurfacePolicy()
            )
            guard governance.effectiveBundle.supervisorInterventionTier != .s0SilentAudit else {
                return nil
            }

            let schedule = SupervisorReviewScheduleStore.load(for: ctx)
            let cadence = SupervisorReviewPolicyEngine.cadenceExplainability(
                governance: governance,
                schedule: schedule,
                nowMs: nowMs
            )
            let openAnomalies = SupervisorReviewPolicyEngine.runtimeOpenAnomalies(
                governance: governance,
                schedule: schedule,
                nowMs: nowMs,
                cadence: cadence
            )
            let blockerDetected = !(project.blockerSummary?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty ?? true)
            let reviewCandidate = SupervisorReviewPolicyEngine.heartbeatCandidate(
                governance: governance,
                schedule: schedule,
                blockerDetected: blockerDetected,
                nowMs: nowMs
            )
            let laneSnapshot = heartbeatRecoveryLaneSnapshot(
                for: project,
                projects: projects,
                permissionProjectIds: permissionProjectIds,
                queueProjectIds: queueProjectIds
            )
            guard let decision = SupervisorReviewPolicyEngine.recoveryDecision(
                schedule: schedule,
                laneSnapshot: laneSnapshot,
                reviewCandidate: reviewCandidate,
                openAnomalies: openAnomalies
            ) else {
                return nil
            }
            guard heartbeatRecoveryFollowUpEligible(decision.action) else { return nil }
            guard heartbeatRecoveryDecisionIsProjectRelevant(
                decision: decision,
                projectId: project.projectId,
                totalProjectCount: projects.count,
                permissionProjectIds: permissionProjectIds,
                queueProjectIds: queueProjectIds,
                laneSnapshot: laneSnapshot
            ) else {
                return nil
            }
            return HeartbeatRecoveryFollowUpSelectionCandidate(
                project: project,
                governance: governance,
                decision: decision,
                laneSnapshot: laneSnapshot,
                portfolioCard: heartbeatPortfolioCard(
                    for: project,
                    cachedCards: portfolioCardsByProjectId,
                    now: nowSec
                )
            )
        }

        guard let selected = candidates.max(by: heartbeatRecoveryFollowUpCandidateSort(lhs:rhs:)) else {
            return nil
        }

        let workflowContext = supervisorEventLoopWorkflowContext(
            project: selected.project,
            preferredJobId: nil,
            preferredPlanId: nil,
            preferredRequestId: nil,
            excludingStepId: nil
        )
        let permissionSignal = permissionSignals.first(where: { $0.projectId == selected.project.projectId })
        let queueSignal = queueSignals.first(where: { $0.project.projectId == selected.project.projectId })
        var lines = [
            "自动按 heartbeat recovery beat 跟进当前项目。",
            "trigger=\(SupervisorCommandTriggerSource.heartbeat.rawValue)",
            "project_ref=\(selected.project.displayName)",
            "project_id=\(selected.project.projectId)",
            "summary=\(heartbeatRecoveryFollowUpSummaryLine(project: selected.project, decision: selected.decision))",
            "reason_code=\(selected.decision.reasonCode)",
            "policy_reason=\(heartbeatRecoveryFollowUpPolicyReason(decision: selected.decision))",
            "recovery_action=\(selected.decision.action.rawValue)",
            "recovery_urgency=\(selected.decision.urgency.rawValue)",
            "requires_user_action=\(selected.decision.requiresUserAction)",
            "event_followup_rhythm=\(SupervisorReviewPolicyEngine.eventFollowUpCadenceSummary(governance: selected.governance))",
            "blocked_summary=\(capped(heartbeatRecoveryFollowUpDetailLine(decision: selected.decision), maxChars: 240))"
        ]
        lines.append(contentsOf: heartbeatPortfolioTokenLines(card: selected.portfolioCard))
        lines.append(contentsOf: heartbeatRecoveryFollowUpGovernanceTokenLines(
            governance: selected.governance,
            decision: selected.decision
        ))
        if let grantRequestId = permissionSignal?.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grantRequestId.isEmpty {
            lines.append("grant_request_id=\(grantRequestId)")
        }
        if let capability = permissionSignal?.capability?.trimmingCharacters(in: .whitespacesAndNewlines),
           !capability.isEmpty {
            lines.append("grant_capability=\(capability)")
        }
        if let queueSignal {
            lines.append("queue_depth=\(queueSignal.queued)")
            lines.append("queue_oldest_wait_ms=\(max(0, queueSignal.oldestQueuedMs))")
        }
        if !workflowContext.isEmpty {
            lines.append(workflowContext.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let signal = HeartbeatRecoveryFollowUpSignal(
            projectId: selected.project.projectId,
            projectName: selected.project.displayName,
            action: selected.decision.action,
            urgency: selected.decision.urgency,
            reasonCode: selected.decision.reasonCode,
            requiresUserAction: selected.decision.requiresUserAction,
            summaryLine: heartbeatRecoveryFollowUpSummaryLine(
                project: selected.project,
                decision: selected.decision
            ),
            detailLine: heartbeatRecoveryFollowUpDetailLine(
                decision: selected.decision
            ),
            priorityReasonLine: heartbeatPortfolioPriorityReasonLine(
                card: selected.portfolioCard,
                lead: "为什么先跟进"
            ),
            actionURL: heartbeatRecoveryFollowUpActionURL(
                projectId: selected.project.projectId,
                action: selected.decision.action,
                grantRequestId: permissionSignal?.grantRequestId,
                grantCapability: permissionSignal?.capability
            )
        )

        let dedupeKey = "heartbeat_recovery_follow_up:\(selected.project.projectId):\(selected.decision.action.rawValue):\(selected.decision.reasonCode)"
        let queued = queueSupervisorEventLoopTurn(
            userMessage: lines.joined(separator: "\n"),
            triggerSource: .heartbeat,
            dedupeKey: dedupeKey
        )
        if queued {
            recordRuntimeActivity(
                heartbeatRecoveryFollowUpRuntimeActivityLine(
                    project: selected.project,
                    governance: selected.governance,
                    decision: selected.decision,
                    portfolioCard: selected.portfolioCard,
                    permissionSignal: permissionSignal,
                    queueSignal: queueSignal
                ),
                project: selected.project
            )
        }

        return signal
    }

    private func heartbeatRecoveryFollowUpEligible(
        _ action: HeartbeatRecoveryAction
    ) -> Bool {
        switch action {
        case .requestGrantFollowUp, .replayFollowUp:
            return true
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return false
        }
    }

    private func heartbeatRecoveryDecisionIsProjectRelevant(
        decision: HeartbeatRecoveryDecision,
        projectId: String,
        totalProjectCount: Int,
        permissionProjectIds: Set<String>,
        queueProjectIds: Set<String>,
        laneSnapshot: SupervisorLaneHealthSnapshot?
    ) -> Bool {
        if laneSnapshot != nil || totalProjectCount <= 1 {
            return true
        }

        switch decision.action {
        case .requestGrantFollowUp:
            return permissionProjectIds.contains(projectId)
        case .replayFollowUp:
            return queueProjectIds.contains(projectId) || decision.anomalyTypes.contains(.queueStall)
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return false
        }
    }

    private func heartbeatRecoveryLaneSnapshot(
        for project: AXProjectEntry,
        projects: [AXProjectEntry],
        permissionProjectIds: Set<String>,
        queueProjectIds: Set<String>
    ) -> SupervisorLaneHealthSnapshot? {
        guard let snapshot = supervisorLaneHealthSnapshot,
              !snapshot.lanes.isEmpty else {
            return nil
        }

        let projectUUIDs = heartbeatRecoveryProjectUUIDs(projectId: project.projectId)
        var lanes = snapshot.lanes.filter { lane in
            guard let laneProjectID = lane.projectID else { return false }
            return projectUUIDs.contains(laneProjectID)
        }
        if lanes.isEmpty,
           projects.count == 1
                || permissionProjectIds.contains(project.projectId)
                || queueProjectIds.contains(project.projectId) {
            lanes = snapshot.lanes.filter { $0.projectID == nil }
        }
        guard !lanes.isEmpty else { return nil }

        return SupervisorLaneHealthSnapshot(
            generatedAtMs: snapshot.generatedAtMs,
            summary: heartbeatRecoveryLaneSummary(lanes: lanes),
            lanes: lanes
        )
    }

    private func heartbeatRecoveryProjectUUIDs(
        projectId: String
    ) -> Set<UUID> {
        let normalizedProjectId = projectId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProjectId.isEmpty else { return [] }

        var uuids: Set<UUID> = []
        if let direct = UUID(uuidString: normalizedProjectId) {
            uuids.insert(direct)
        }
        if let derived = UUID(uuidString: oneShotDeterministicUUIDString(seed: normalizedProjectId)) {
            uuids.insert(derived)
        }
        return uuids
    }

    private func heartbeatRecoveryLaneSummary(
        lanes: [SupervisorLaneHealthLaneState]
    ) -> LaneHealthSummary {
        guard !lanes.isEmpty else { return .empty }

        var running = 0
        var blocked = 0
        var stalled = 0
        var failed = 0
        var waiting = 0
        var recovering = 0
        var completed = 0

        for lane in lanes {
            switch lane.status {
            case .running:
                running += 1
            case .blocked:
                blocked += 1
            case .stalled:
                stalled += 1
            case .failed:
                failed += 1
            case .waiting:
                waiting += 1
            case .recovering:
                recovering += 1
            case .completed:
                completed += 1
            }
        }

        return LaneHealthSummary(
            total: lanes.count,
            running: running,
            blocked: blocked,
            stalled: stalled,
            failed: failed,
            waiting: waiting,
            recovering: recovering,
            completed: completed
        )
    }

    private func heartbeatRecoveryFollowUpCandidateSort(
        lhs: HeartbeatRecoveryFollowUpSelectionCandidate,
        rhs: HeartbeatRecoveryFollowUpSelectionCandidate
    ) -> Bool {
        let lhsScore = heartbeatRecoveryFollowUpPriorityScore(
            decision: lhs.decision,
            laneSnapshot: lhs.laneSnapshot
        )
        let rhsScore = heartbeatRecoveryFollowUpPriorityScore(
            decision: rhs.decision,
            laneSnapshot: rhs.laneSnapshot
        )
        if lhsScore != rhsScore {
            return lhsScore < rhsScore
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
        return lhs.project.projectId < rhs.project.projectId
    }

    private func heartbeatRecoveryFollowUpPriorityScore(
        decision: HeartbeatRecoveryDecision,
        laneSnapshot: SupervisorLaneHealthSnapshot?
    ) -> Int {
        var score = heartbeatRecoveryUrgencyPriority(decision.urgency) * 100
        if decision.requiresUserAction {
            score += 40
        }
        score += heartbeatRecoveryActionPriority(decision.action)
        score += max(0, laneSnapshot?.summary.failed ?? 0) * 4
        score += max(0, laneSnapshot?.summary.blocked ?? 0)
        return score
    }

    private func heartbeatRecoveryUrgencyPriority(
        _ urgency: HeartbeatRecoveryUrgency
    ) -> Int {
        switch urgency {
        case .observe:
            return 0
        case .active:
            return 1
        case .urgent:
            return 2
        }
    }

    private func heartbeatRecoveryActionPriority(
        _ action: HeartbeatRecoveryAction
    ) -> Int {
        switch action {
        case .requestGrantFollowUp:
            return 20
        case .replayFollowUp:
            return 10
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return 0
        }
    }

    private func heartbeatRecoveryFollowUpSummaryLine(
        project: AXProjectEntry,
        decision: HeartbeatRecoveryDecision
    ) -> String {
        switch decision.action {
        case .requestGrantFollowUp:
            return "\(project.displayName) 需要 grant / 授权跟进"
        case .replayFollowUp:
            return "\(project.displayName) 需要重放 follow-up / 续跑链"
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return capped(decision.summary, maxChars: 120)
        }
    }

    private func heartbeatRecoveryFollowUpDetailLine(
        decision: HeartbeatRecoveryDecision
    ) -> String {
        capped(
            firstNonEmpty(
                decision.userFacingSystemNextStepText(),
                decision.summary
            ) ?? "系统会继续观察当前 heartbeat recovery 状态。",
            maxChars: 220
        )
    }

    private func heartbeatRecoveryFollowUpPolicyReason(
        decision: HeartbeatRecoveryDecision
    ) -> String {
        switch decision.action {
        case .requestGrantFollowUp:
            if decision.blockedLaneReasons.contains(.authzDenied)
                || decision.blockedLaneReasons.contains(.authChallengeLoop) {
                return "当前 heartbeat 检测到授权路径卡住，系统已自动排队 grant / 授权跟进。"
            }
            return "当前 heartbeat 检测到 grant 相关阻塞，系统已自动排队 grant 跟进。"
        case .replayFollowUp:
            if decision.blockedLaneReasons.contains(.restartDrain) {
                return "当前 heartbeat 检测到 drain 收口后仍需续跑，系统已自动排队 replay follow-up。"
            }
            return "当前 heartbeat 检测到 queue stall / starvation，系统已自动排队 replay follow-up。"
        case .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return capped(decision.summary, maxChars: 120)
        }
    }

    private func heartbeatRecoveryFollowUpActionURL(
        projectId: String,
        action: HeartbeatRecoveryAction,
        grantRequestId: String?,
        grantCapability: String?
    ) -> String? {
        switch action {
        case .requestGrantFollowUp:
            return supervisorActionURL(
                projectId: projectId,
                focusTarget: .grant,
                grantRequestId: grantRequestId,
                capability: grantCapability
            )
        case .replayFollowUp, .resumeRun, .repairRoute, .rehydrateContext, .queueStrategicReview, .holdForUser:
            return resumeProjectActionURL(projectId: projectId)
        }
    }

    private func heartbeatRecoveryFollowUpGovernanceTokenLines(
        governance: AXProjectResolvedGovernanceState,
        decision: HeartbeatRecoveryDecision
    ) -> [String] {
        let schedule = governance.effectiveBundle.schedule
        let adaptation = governance.supervisorAdaptation
        var lines = [
            "execution_tier=\(governance.configuredBundle.executionTier.rawValue)",
            "effective_execution_tier=\(governance.effectiveBundle.executionTier.rawValue)",
            "supervisor_intervention_tier=\(governance.configuredBundle.supervisorInterventionTier.rawValue)",
            "effective_supervisor_intervention_tier=\(governance.effectiveBundle.supervisorInterventionTier.rawValue)",
            "effective_supervisor_tier=\(adaptation.effectiveSupervisorTier.rawValue)",
            "effective_work_order_depth=\(adaptation.effectiveWorkOrderDepth.rawValue)",
            "project_ai_strength_band=\(adaptation.projectAIStrengthProfile?.strengthBand.rawValue ?? AXProjectAIStrengthBand.unknown.rawValue)",
            "review_policy_mode=\(governance.effectiveBundle.reviewPolicyMode.rawValue)",
            "progress_heartbeat_sec=\(schedule.progressHeartbeatSeconds)",
            "review_pulse_sec=\(schedule.reviewPulseSeconds)",
            "brainstorm_review_sec=\(schedule.brainstormReviewSeconds)",
            "governance_compat_source=\(governance.compatSource.rawValue)",
            "governance_reason=\(capped(heartbeatRecoveryFollowUpPolicyReason(decision: decision), maxChars: 220))"
        ]
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

    private func heartbeatRecoveryFollowUpRuntimeActivityLine(
        project: AXProjectEntry,
        governance: AXProjectResolvedGovernanceState,
        decision: HeartbeatRecoveryDecision,
        portfolioCard: SupervisorPortfolioProjectCard,
        permissionSignal: ProjectPermissionSignal?,
        queueSignal: ProjectQueueSignal?
    ) -> String {
        var tokens = [
            "heartbeat_recovery_follow_up status=queued",
            "trigger=\(SupervisorCommandTriggerSource.heartbeat.rawValue)",
            "project_ref=\(project.displayName)",
            "project_id=\(project.projectId)",
            "recovery_action=\(decision.action.rawValue)",
            "recovery_urgency=\(decision.urgency.rawValue)",
            "reason_code=\(decision.reasonCode)",
            "requires_user_action=\(decision.requiresUserAction)",
            "policy_reason=\(decision.reasonCode)",
            "governance_reason=\(capped(heartbeatRecoveryFollowUpPolicyReason(decision: decision), maxChars: 220))",
            "blocked_summary=\(capped(heartbeatRecoveryFollowUpDetailLine(decision: decision), maxChars: 240))"
        ]
        tokens.append(contentsOf: heartbeatPortfolioTokenLines(card: portfolioCard))

        if let grantRequestId = permissionSignal?.grantRequestId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !grantRequestId.isEmpty {
            tokens.append("grant_request_id=\(grantRequestId)")
        }
        if let capability = permissionSignal?.capability?.trimmingCharacters(in: .whitespacesAndNewlines),
           !capability.isEmpty {
            tokens.append("grant_capability=\(capability)")
        }
        if let queueSignal {
            tokens.append("queue_depth=\(queueSignal.queued)")
            tokens.append("queue_oldest_wait_ms=\(max(0, queueSignal.oldestQueuedMs))")
        }
        if let reviewTrigger = decision.queuedReviewTrigger?.rawValue {
            tokens.append("review_trigger=\(reviewTrigger)")
        }
        if let reviewLevel = decision.queuedReviewLevel?.rawValue {
            tokens.append("review_level_hint=\(reviewLevel)")
        }
        if let runKind = decision.queuedReviewRunKind?.rawValue {
            tokens.append("review_run_kind=\(runKind)")
        }
        if let governanceTruth = XTGovernanceTruthPresentation.truthLine(
            configuredExecutionTier: governance.configuredBundle.executionTier.rawValue,
            effectiveExecutionTier: governance.effectiveBundle.executionTier.rawValue,
            configuredSupervisorTier: governance.configuredBundle.supervisorInterventionTier.rawValue,
            effectiveSupervisorTier: governance.effectiveBundle.supervisorInterventionTier.rawValue,
            reviewPolicyMode: governance.effectiveBundle.reviewPolicyMode.rawValue,
            progressHeartbeatSeconds: governance.effectiveBundle.schedule.progressHeartbeatSeconds,
            reviewPulseSeconds: governance.effectiveBundle.schedule.reviewPulseSeconds,
            brainstormReviewSeconds: governance.effectiveBundle.schedule.brainstormReviewSeconds,
            compatSource: governance.compatSource.rawValue
        ) {
            tokens.append("governance_truth=\(capped(governanceTruth, maxChars: 220))")
        }

        return tokens.joined(separator: " · ")
    }
}
