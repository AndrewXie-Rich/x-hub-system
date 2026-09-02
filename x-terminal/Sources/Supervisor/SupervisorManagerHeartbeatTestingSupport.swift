import Foundation

extension SupervisorManager {
    @discardableResult
    func runHeartbeatAutoProgressForTesting(
        reason: String = "timer",
        now: Date = Date()
    ) -> [String] {
        let projects = knownProjects()
        let queueSignals = queuedProjectSignals(for: projects, now: now.timeIntervalSince1970)
        let permissionSignals = collectPermissionSignals(for: projects)
        return heartbeatAutoProgressActions(
            reason: reason,
            now: now,
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals
        ).map(\.summaryLine)
    }

    func emitHeartbeatCycleForTesting(
        force: Bool = true,
        reason: String = "test"
    ) {
        emitHeartbeatIfNeeded(force: force, reason: reason)
    }

    func emitHeartbeatForTesting(
        force: Bool = true,
        reason: String = "test",
        now: Date = Date()
    ) async -> HeartbeatVoiceTestEmission {
        let projects = allProjects()
        let projectCreationPresentation = projectCreationStatusPresentation()
        guard !projects.isEmpty || projectCreationPresentation != nil else {
            return HeartbeatVoiceTestEmission(
                path: "none",
                outcome: "suppressed:no_projects",
                script: []
            )
        }
        let queueSignals = queuedProjectSignals(for: projects, now: now.timeIntervalSince1970)
        let permissionSignals = collectPermissionSignals(for: projects)
        let governanceRepairSignals = collectGovernanceRepairSignals(for: projects)
        let progressActions = heartbeatAutoProgressActions(
            reason: reason,
            now: now,
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals
        )
        let blockerProjects: [(projectId: String, blocker: String)] = projects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        let blockerFingerprint = blockerProjects
            .map { "\($0.projectId)|\($0.blocker)" }
            .joined(separator: "\n")
        let blockerSignal = evaluateBlockerSignal(
            now: now.timeIntervalSince1970,
            blockerCount: blockerProjects.count,
            blockerFingerprint: blockerFingerprint
        )
        let hubLoadSignal = heartbeatHubLoadSignal()
        let governedReviewSignal = scheduleGovernedReviewFromHeartbeat(
            projects: projects,
            blockerProjects: blockerProjects,
            now: now
        )
        let recoveryFollowUpSignal = reason == "timer"
            ? self.scheduleRecoveryFollowUpFromHeartbeat(
                projects: projects,
                queueSignals: queueSignals,
                permissionSignals: permissionSignals,
                now: now
            )
            : nil
        let nextStepSummary = buildHeartbeatNextStepSummary(
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSignals: governanceRepairSignals,
            hubLoadSignal: hubLoadSignal,
            maxItems: 4,
            now: now.timeIntervalSince1970
        )
        let routeAttentionSignal = heartbeatRouteAttentionSignal(
            item: heartbeatLeadRouteRepairAttentionItem(projects: projects),
            now: now.timeIntervalSince1970
        )
        let fallbackJob = heartbeatVoiceJob(
            reason: reason,
            changed: force,
            projects: projects,
            blockerProjects: blockerProjects,
            blockerSignal: blockerSignal,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSignals: governanceRepairSignals,
            queueSignals: queueSignals,
            progressActions: progressActions,
            nextStepSummary: nextStepSummary,
            routeAttentionSignal: routeAttentionSignal
        )
        let request = heartbeatProjectionRequest(
            reason: reason,
            changed: force,
            projects: projects,
            blockerProjects: blockerProjects,
            blockerSignal: blockerSignal,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSignals: governanceRepairSignals,
            queueSignals: queueSignals,
            progressActions: progressActions,
            nextStepSummary: nextStepSummary
        )
        if let request,
           backgroundSupervisorServicesEnabled || supervisorBriefProjectionRequestOverride != nil,
           let projectionResolution = await self.heartbeatProjectionVoiceResolution(
               request: request,
               blockerSignal: blockerSignal,
               projects: projects,
               governedReviewSignal: governedReviewSignal
           ) {
            let job: SupervisorVoiceTTSJob
            let path: String
            switch projectionResolution {
            case .projection(let projectionJob):
                job = projectionJob
                path = "projection"
            case .unavailable(let unavailableJob):
                job = unavailableJob
                path = "projection_unavailable"
            }
            let outcome = supervisorSpeechSynthesizer.speak(
                job: job,
                preferences: currentVoicePreferences()
            )
            recordHeartbeatRouteAttentionAlertIfNeeded(
                routeAttentionSignal,
                reason: reason,
                blockerCount: blockerProjects.count,
                permissionCount: permissionSignals.count,
                queueCount: queueSignals.count,
                now: now.timeIntervalSince1970
            )
            return HeartbeatVoiceTestEmission(
                path: path,
                outcome: heartbeatVoiceTestOutcomeLabel(outcome),
                script: job.script
            )
        }
        guard let fallbackJob else {
            return HeartbeatVoiceTestEmission(
                path: "fallback",
                outcome: "suppressed:empty_script",
                script: []
            )
        }
        let outcome = supervisorSpeechSynthesizer.speak(
            job: fallbackJob,
            preferences: currentVoicePreferences()
        )
        recordHeartbeatRouteAttentionAlertIfNeeded(
            routeAttentionSignal,
            reason: reason,
            blockerCount: blockerProjects.count,
            permissionCount: permissionSignals.count,
            queueCount: queueSignals.count,
            now: now.timeIntervalSince1970
        )
        return HeartbeatVoiceTestEmission(
            path: "fallback",
            outcome: heartbeatVoiceTestOutcomeLabel(outcome),
            script: fallbackJob.script
        )
    }

    func heartbeatFocusActionURLForTesting(
        reason: String = "test",
        now: Date = Date(),
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil
    ) -> String? {
        let projects = allProjects()
        let projectCreationPresentation = projectCreationStatusPresentation()
        guard !projects.isEmpty || projectCreationPresentation != nil else { return nil }
        let queueSignals = queuedProjectSignals(for: projects, now: now.timeIntervalSince1970)
        let permissionSignals = collectPermissionSignals(for: projects)
        let governanceRepairSignals = collectGovernanceRepairSignals(for: projects)
        let blockerProjects: [(projectId: String, blocker: String)] = projects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        if reason == "timer" {
            _ = scheduleGovernedReviewFromHeartbeat(
                projects: projects,
                blockerProjects: blockerProjects,
                now: now
            )
        }
        let recoveryFollowUpSignal = reason == "timer"
            ? scheduleRecoveryFollowUpFromHeartbeat(
                projects: projects,
                queueSignals: queueSignals,
                permissionSignals: permissionSignals,
                now: now
            )
            : nil
        let progressActions = heartbeatAutoProgressActions(
            reason: reason,
            now: now,
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals
        )
        return self.resolvedHeartbeatFocusActionURL(
            projects: projects,
            progressActions: progressActions,
            blockerProjects: blockerProjects,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: nil,
            governanceRepairSignals: governanceRepairSignals,
            queueSignals: queueSignals,
            hubLoadSignal: heartbeatHubLoadSignal(),
            doctorPresentation: doctorPresentation,
            now: now.timeIntervalSince1970
        )
    }

    func buildHeartbeatNotificationPresentationForTesting(
        timeText: String = "10:00",
        reason: String = "test",
        projectCount: Int,
        changed: Bool,
        blockerCount: Int,
        blockerStreak: Int,
        blockerEscalated: Bool,
        blockerCooldownRemainingSec: Int = 0,
        topSummary: String,
        queueSummary: String,
        permissionSummary: String,
        recoveryAction: HeartbeatRecoveryAction? = nil,
        recoveryUrgency: HeartbeatRecoveryUrgency = .active,
        recoveryReasonCode: String? = nil,
        recoveryRequiresUserAction: Bool? = nil,
        recoveryProjectId: String = "project-recovery",
        recoveryProjectName: String = "Recovery Runtime",
        recoverySummary: String = "",
        recoveryDetail: String = "",
        recoveryPriorityReason: String = "",
        governedReviewSummary: String = "",
        governedReviewDetail: String = "",
        governedReviewLevel: SupervisorReviewLevel? = nil,
        governanceRepairSummary: String = "",
        hubLoadSummary: String = "",
        progressSummary: String,
        nextStepSummary: String,
        queuePendingCount: Int,
        permissionPendingCount: Int,
        governanceRepairCount: Int = 0,
        focusActionURL: String? = nil,
        routeDiagnoseShouldAlert: Bool? = nil,
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil,
        governedReviewProjectMemoryStatusLine: String? = nil,
        governedReviewProjectMemoryMetadataText: String? = nil
    ) -> HeartbeatNotificationPresentation {
        let governedReviewSignal = governedReviewLevel.map { reviewLevel in
            HeartbeatGovernedReviewSignal(
                projectId: "project-governed-review",
                projectName: "Governed Review",
                trigger: reviewLevel == .r3Rescue ? .preDoneSummary : .noProgressWindow,
                runKind: reviewLevel == .r1Pulse ? .pulse : (reviewLevel == .r2Strategic ? .brainstorm : .eventDriven),
                reviewLevel: reviewLevel,
                causeLabel: reviewLevel == .r3Rescue ? "完成声明证据偏弱" : "长时间无进展",
                summaryLine: governedReviewSummary.isEmpty
                    ? "• Governed Review：已排队\(heartbeatGovernedReviewLevelLabel(reviewLevel))"
                    : governedReviewSummary,
                detailLine: governedReviewDetail.isEmpty
                    ? "• 依据：heartbeat 已自动排队治理审查。"
                    : governedReviewDetail,
                projectMemoryStatusLine: governedReviewProjectMemoryStatusLine,
                projectMemoryMetadataText: governedReviewProjectMemoryMetadataText,
                actionURL: focusActionURL
            )
        }
        let recoveryFollowUpSignal = recoveryAction.map { action in
            let trimmedRecoveryPriorityReason = recoveryPriorityReason
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedReasonCode: String
            if let recoveryReasonCode {
                let trimmed = recoveryReasonCode.trimmingCharacters(in: .whitespacesAndNewlines)
                normalizedReasonCode = trimmed.isEmpty
                    ? "heartbeat_recovery_follow_up"
                    : trimmed
            } else {
                switch action {
                case .requestGrantFollowUp:
                    normalizedReasonCode = "grant_follow_up_required"
                case .replayFollowUp:
                    normalizedReasonCode = "restart_drain_requires_follow_up_replay"
                case .resumeRun:
                    normalizedReasonCode = "resume_run_required"
                case .repairRoute:
                    normalizedReasonCode = "route_repair_required"
                case .rehydrateContext:
                    normalizedReasonCode = "context_rehydrate_required"
                case .queueStrategicReview:
                    normalizedReasonCode = "queue_strategic_review_required"
                case .holdForUser:
                    normalizedReasonCode = "hold_for_user"
                }
            }
            let defaultSummary: String
            switch action {
            case .requestGrantFollowUp:
                defaultSummary = "\(recoveryProjectName) 需要 grant / 授权跟进"
            case .replayFollowUp:
                defaultSummary = "\(recoveryProjectName) 需要重放 follow-up / 续跑链"
            case .resumeRun:
                defaultSummary = "\(recoveryProjectName) 需要受控恢复执行"
            case .repairRoute:
                defaultSummary = "\(recoveryProjectName) 需要 route / dispatch 修复"
            case .rehydrateContext:
                defaultSummary = "\(recoveryProjectName) 需要重建项目上下文"
            case .queueStrategicReview:
                defaultSummary = "\(recoveryProjectName) 需要排队治理复盘"
            case .holdForUser:
                defaultSummary = "\(recoveryProjectName) 需要等待用户 / operator"
            }
            let defaultDetail: String
            switch action {
            case .requestGrantFollowUp:
                defaultDetail = "系统会先发起所需 grant 跟进，待放行后再继续恢复执行。"
            case .replayFollowUp:
                defaultDetail = "系统会在当前 drain 收口后，重放挂起的 follow-up / 续跑链，再确认执行是否恢复。"
            case .resumeRun:
                defaultDetail = "系统会先尝试受控恢复执行，再观察 lane 活性是否恢复。"
            case .repairRoute:
                defaultDetail = "系统会先修复当前 route / dispatch 健康，再尝试恢复执行。"
            case .rehydrateContext:
                defaultDetail = "系统会先重建项目上下文，再继续下一次执行尝试。"
            case .queueStrategicReview:
                defaultDetail = "系统会先排队一次治理复盘，再确认是否继续自动推进。"
            case .holdForUser:
                defaultDetail = "系统会先停在当前边界，等待你或 operator 补齐缺失输入。"
            }
            return HeartbeatRecoveryFollowUpSignal(
                projectId: recoveryProjectId,
                projectName: recoveryProjectName,
                action: action,
                urgency: recoveryUrgency,
                reasonCode: normalizedReasonCode,
                requiresUserAction: recoveryRequiresUserAction ?? (action == .requestGrantFollowUp),
                summaryLine: recoverySummary.isEmpty ? defaultSummary : recoverySummary,
                detailLine: recoveryDetail.isEmpty ? defaultDetail : recoveryDetail,
                priorityReasonLine: trimmedRecoveryPriorityReason.isEmpty
                    ? nil
                    : trimmedRecoveryPriorityReason,
                actionURL: focusActionURL
            )
        }
        return buildHeartbeatNotificationPresentation(
            timeText: timeText,
            reason: reason,
            projectCount: projectCount,
            changed: changed,
            blockerCount: blockerCount,
            blockerSignal: BlockerSignal(
                streak: blockerStreak,
                escalated: blockerEscalated,
                cooldownRemainingSec: blockerCooldownRemainingSec
            ),
            topSummary: topSummary,
            queueSummary: queueSummary,
            permissionSummary: permissionSummary,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSummary: governanceRepairSummary,
            hubLoadSummary: hubLoadSummary,
            hubLoadSignal: nil,
            progressSummary: progressSummary,
            nextStepSummary: nextStepSummary,
            queuePendingCount: queuePendingCount,
            permissionPendingCount: permissionPendingCount,
            governanceRepairCount: governanceRepairCount,
            focusActionURL: focusActionURL,
            routeDiagnoseShouldAlert: routeDiagnoseShouldAlert,
            doctorPresentation: doctorPresentation
        )
    }

    func buildHeartbeatNextStepSummaryForTesting(
        now: Date = Date(),
        reason: String = "test",
        maxItems: Int = 4
    ) -> String {
        let projects = allProjects()
        let queueSignals = queuedProjectSignals(for: projects, now: now.timeIntervalSince1970)
        let permissionSignals = collectPermissionSignals(for: projects)
        let governanceRepairSignals = collectGovernanceRepairSignals(for: projects)
        let blockerProjects: [(projectId: String, blocker: String)] = projects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        if reason == "timer" {
            _ = scheduleGovernedReviewFromHeartbeat(
                projects: projects,
                blockerProjects: blockerProjects,
                now: now
            )
        }
        let recoveryFollowUpSignal = reason == "timer"
            ? scheduleRecoveryFollowUpFromHeartbeat(
                projects: projects,
                queueSignals: queueSignals,
                permissionSignals: permissionSignals,
                now: now
            )
            : nil
        return buildHeartbeatNextStepSummary(
            projects: projects,
            queueSignals: queueSignals,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: nil,
            governanceRepairSignals: governanceRepairSignals,
            hubLoadSignal: heartbeatHubLoadSignal(),
            maxItems: maxItems,
            now: now.timeIntervalSince1970
        )
    }

    func conciseHeartbeatNextStepForTesting(_ text: String) -> String? {
        conciseHeartbeatNextStep(text)
    }

    private func heartbeatVoiceTestOutcomeLabel(
        _ outcome: SupervisorSpeechSynthesizer.Outcome
    ) -> String {
        switch outcome {
        case .spoken:
            return "spoken"
        case .suppressed(let reason):
            return "suppressed:\(reason)"
        }
    }
}
