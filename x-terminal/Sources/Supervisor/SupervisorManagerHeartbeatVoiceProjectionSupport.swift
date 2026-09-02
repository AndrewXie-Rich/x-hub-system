import Foundation

extension SupervisorManager {
    func heartbeatGovernanceVoicePresentation() -> SupervisorGovernanceSignalVoicePresentation? {
        SupervisorGovernanceSignalVoicePresentationMapper.map(
            overview: heartbeatSignalCenterOverviewPresentation()
        )
    }

    private func heartbeatGovernanceVoiceJob(
        signal: SupervisorGovernanceSignalVoicePresentation,
        progressVoiceLine: String?,
        nextStepLine: String?
    ) -> SupervisorVoiceTTSJob {
        SupervisorVoiceTTSJob(
            trigger: signal.trigger,
            priority: heartbeatGovernanceVoicePriority(signal),
            script: heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.governanceSignalHeartbeatScript(
                    signal: signal,
                    progressLine: progressVoiceLine,
                    nextStepLine: nextStepLine
                )
            ),
            dedupeKey: "heartbeat:governance_signal:\(signal.fingerprint)\(heartbeatMemoryReadinessDedupeSuffix())"
        )
    }

    private func heartbeatRecoveryVoiceJob(
        signal: HeartbeatRecoveryFollowUpSignal,
        progressVoiceLine: String?,
        nextStepLine: String?
    ) -> SupervisorVoiceTTSJob {
        let trigger = heartbeatRecoveryVoiceTrigger(signal)
        return SupervisorVoiceTTSJob(
            trigger: trigger,
            priority: heartbeatRecoveryVoicePriority(signal),
            script: heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.recoveryHeartbeatScript(
                    trigger: trigger,
                    projectName: signal.projectName,
                    summary: signal.summaryLine,
                    detail: signal.detailLine,
                    priorityReason: heartbeatRecoveryFollowUpPriorityReasonText(signal),
                    progressLine: progressVoiceLine,
                    nextStepLine: nextStepLine
                )
            ),
            dedupeKey: "heartbeat:recovery:\(signal.projectId):\(signal.action.rawValue):\(signal.reasonCode):\(signal.urgency.rawValue)\(heartbeatMemoryReadinessDedupeSuffix())"
        )
    }

    func heartbeatVoiceJob(
        reason: String,
        changed: Bool,
        projects: [AXProjectEntry],
        blockerProjects: [(projectId: String, blocker: String)],
        blockerSignal: BlockerSignal,
        permissionSignals: [ProjectPermissionSignal],
        recoveryFollowUpSignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSignals: [ProjectGovernanceRepairSignal],
        queueSignals: [ProjectQueueSignal],
        progressActions: [HeartbeatAutoProgressAction],
        nextStepSummary: String,
        routeAttentionSignal: HeartbeatRouteAttentionSignal?
    ) -> SupervisorVoiceTTSJob? {
        let nextStepLine = conciseHeartbeatNextStep(nextStepSummary)
        let voiceReadinessSignal = heartbeatVoiceReadinessSignal()
        let governanceVoiceSignal = heartbeatGovernanceVoicePresentation()
        let governedReviewVoiceSignal = governedReviewSignal.map(heartbeatGovernedReviewVoicePresentation)
        let shouldEmitPassiveSummary = changed || reason != "timer" || !progressActions.isEmpty
        let progressVoiceLine: String? = {
            guard let first = progressActions.first else { return nil }
            switch first.kind {
            case .recover:
                return "我已主动恢复 \(first.projectName)。"
            case .start:
                return "我已主动启动 \(first.projectName)。"
            }
        }()

        if let firstBlocker = blockerProjects.first {
            let projectName = heartbeatProjectName(for: firstBlocker.projectId, in: projects) ?? "当前项目"
            return SupervisorVoiceTTSJob(
                trigger: .blocked,
                priority: blockerSignal.escalated ? .interrupt : .normal,
                script: heartbeatScriptPrefixedWithMemoryReadiness(
                    SupervisorVoiceScriptBuilder.blockedHeartbeatScript(
                        blockerCount: blockerProjects.count,
                        projectName: projectName,
                        blockerSummary: capped(firstBlocker.blocker, maxChars: 36),
                        progressLine: progressVoiceLine,
                        blockerStreak: max(1, blockerSignal.streak),
                        nextStepLine: nextStepLine
                    )
                ),
                dedupeKey: "heartbeat:blocker:\(firstBlocker.projectId):\(capped(firstBlocker.blocker, maxChars: 48)):\(blockerSignal.streak)\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        }

        if let recoveryFollowUpSignal {
            return heartbeatRecoveryVoiceJob(
                signal: recoveryFollowUpSignal,
                progressVoiceLine: progressVoiceLine,
                nextStepLine: nextStepLine
            )
        }

        if let governanceVoiceSignal,
           governanceVoiceSignal.trigger == .authorization,
           shouldEmitPassiveSummary {
            return heartbeatGovernanceVoiceJob(
                signal: governanceVoiceSignal,
                progressVoiceLine: progressVoiceLine,
                nextStepLine: nextStepLine
            )
        }

        if let permission = permissionSignals.first {
            return SupervisorVoiceTTSJob(
                trigger: .blocked,
                priority: .normal,
                script: heartbeatScriptPrefixedWithMemoryReadiness(
                    SupervisorVoiceScriptBuilder.permissionHeartbeatScript(
                        permissionCount: permissionSignals.count,
                        projectName: permission.projectName,
                        summary: capped(permission.summary, maxChars: 36),
                        progressLine: progressVoiceLine,
                        nextStepLine: nextStepLine
                    )
                ),
                dedupeKey: "heartbeat:permission:\(permission.projectId):\(permission.kind.rawValue):\(capped(permission.summary, maxChars: 48))\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        }

        if let repair = governanceRepairSignals.first {
            return SupervisorVoiceTTSJob(
                trigger: .blocked,
                priority: .normal,
                script: heartbeatScriptPrefixedWithMemoryReadiness(
                    SupervisorVoiceScriptBuilder.governanceRepairHeartbeatScript(
                        repairCount: governanceRepairSignals.count,
                        projectName: repair.projectName,
                        summary: repair.summary,
                        progressLine: progressVoiceLine,
                        nextStepLine: nextStepLine
                    )
                ),
                dedupeKey: "heartbeat:governance_repair:\(repair.projectId):\(repair.destination.rawValue):\(capped(repair.summary, maxChars: 48))\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        }

        if let governedReviewVoiceSignal,
           governedReviewSignal != nil,
           shouldEmitPassiveSummary {
            return heartbeatGovernanceVoiceJob(
                signal: governedReviewVoiceSignal,
                progressVoiceLine: progressVoiceLine,
                nextStepLine: nextStepLine
            )
        }

        if let voiceReadinessSignal {
            return SupervisorVoiceTTSJob(
                trigger: voiceReadinessSignal.readyForFirstTask ? .completed : .blocked,
                priority: voiceReadinessSignal.readyForFirstTask ? .quiet : .normal,
                script: heartbeatScriptPrefixedWithMemoryReadiness(
                    SupervisorVoiceScriptBuilder.voiceReadinessHeartbeatScript(
                        kind: voiceReadinessSignal.kind,
                        readyForFirstTask: voiceReadinessSignal.readyForFirstTask,
                        headline: voiceReadinessSignal.headline,
                        summary: voiceReadinessSignal.overallSummary,
                        progressLine: progressVoiceLine,
                        nextStepLine: nextStepLine ?? voiceReadinessSignal.nextStep
                    )
                ),
                dedupeKey: "heartbeat:readiness:\(voiceReadinessSignal.kind.rawValue):\(voiceReadinessSignal.readyForFirstTask ? "ready" : "fail_closed"):\(voiceReadinessSignal.reasonCode):\(capped(voiceReadinessSignal.headline, maxChars: 48))\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        }

        if queueSignals.isEmpty,
           let routeAttentionSignal,
           (reason != "timer" || routeAttentionSignal.shouldAlertOnTimer) {
            let routeReasonRaw = routeAttentionSignal.item.digest.topRouteReason?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let routeReasonDisplay = AXRouteRepairLogStore.userFacingRouteReason(
                routeReasonRaw ?? "",
                includeCode: false
            )
            let routeReason = routeReasonDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : routeReasonDisplay
            let failureActionDisplay = AXRouteRepairLogStore.userFacingActionLabel(
                routeAttentionSignal.item.digest.latestFailure?.actionId ?? ""
            )
            let failureAction = failureActionDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : failureActionDisplay
            let routeHint = AXRouteRepairLogStore.watchRouteTruthHint(
                for: routeAttentionSignal.item.digest,
                paidAccessSnapshot: appModel?.hubRemotePaidAccessSnapshot
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            let followUpVoiceLine = heartbeatRouteRepairVoiceFollowUpLine(
                routeAttentionSignal.statusBarFollowUp
            )
            let routeNextStepLine = heartbeatRouteRepairVoiceNextStepLine(
                routeAttentionSignal.statusBarFollowUp
            ) ?? nextStepLine
            let followUpActionID = heartbeatRouteRepairFollowUpActionID(
                routeAttentionSignal.statusBarFollowUp
            )
            return SupervisorVoiceTTSJob(
                trigger: .completed,
                priority: .normal,
                script: heartbeatScriptPrefixedWithMemoryReadiness(
                    SupervisorVoiceScriptBuilder.routeDiagnoseHeartbeatScript(
                        projectName: routeAttentionSignal.item.projectDisplayName,
                        routeReason: routeReason,
                        failureAction: failureAction,
                        routeHint: routeHint,
                        followUpLine: followUpVoiceLine,
                        progressLine: progressVoiceLine,
                        nextStepLine: routeNextStepLine
                    )
                ),
                dedupeKey: "heartbeat:route_repair:\(routeAttentionSignal.item.projectId):\(capped(routeReasonRaw ?? "", maxChars: 32)):\(capped(routeAttentionSignal.item.digest.latestFailure?.actionId ?? "", maxChars: 40)):\(followUpActionID.isEmpty ? "none" : followUpActionID)\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        }

        if let governanceVoiceSignal,
           shouldEmitPassiveSummary {
            return heartbeatGovernanceVoiceJob(
                signal: governanceVoiceSignal,
                progressVoiceLine: progressVoiceLine,
                nextStepLine: nextStepLine
            )
        }

        guard shouldEmitPassiveSummary else {
            return nil
        }

        let queueCount = queueSignals.count
        let managedProjectCount = projects.count
        let activeProjectCount = projects.reduce(into: 0) { partial, project in
            if SupervisorPortfolioSnapshotBuilder.projectState(from: project) == .active {
                partial += 1
            }
        }
        let leadProjectName = queueSignals.first?.project.displayName ?? projects.first?.displayName ?? "当前项目"
        return SupervisorVoiceTTSJob(
            trigger: .completed,
            priority: .quiet,
            script: heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.stableHeartbeatScript(
                    activeProjectCount: activeProjectCount,
                    managedProjectCount: managedProjectCount,
                    queueCount: queueCount,
                    leadProjectName: leadProjectName,
                    progressLine: progressVoiceLine,
                    nextStepLine: nextStepLine
                )
            ),
            dedupeKey: "heartbeat:summary:\(reason):\(activeProjectCount):\(managedProjectCount):\(queueCount):\(leadProjectName)\(heartbeatMemoryReadinessDedupeSuffix())"
        )
    }

    func heartbeatScriptPrefixedWithMemoryReadiness(
        _ script: [String]
    ) -> [String] {
        guard let readiness = currentSupervisorMemoryAssemblyReadinessForLanguageLayer(),
              !readiness.ready else {
            return script
        }
        let topIssue = readiness.issues.first?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lead: String
        if topIssue.isEmpty {
            lead = "当前项目背景记忆还没喂够，我先不做战略纠偏，只汇报阻塞和下一步。"
        } else {
            lead = "当前项目背景记忆还没喂够，\(capped(topIssue, maxChars: 20))，我先不做战略纠偏，只汇报阻塞和下一步。"
        }
        guard script.first != lead else { return script }
        return [lead] + script
    }

    func heartbeatMemoryReadinessDedupeSuffix() -> String {
        guard let readiness = currentSupervisorMemoryAssemblyReadinessForLanguageLayer(),
              !readiness.ready else {
            return ""
        }
        let issues = readiness.issueCodes.joined(separator: ",")
        return ":memory_underfed:\(issues.isEmpty ? "unspecified" : issues)"
    }

    func heartbeatProjectionRequest(
        reason: String,
        changed: Bool,
        projects: [AXProjectEntry],
        blockerProjects: [(projectId: String, blocker: String)],
        blockerSignal: BlockerSignal,
        permissionSignals: [ProjectPermissionSignal],
        recoveryFollowUpSignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSignals: [ProjectGovernanceRepairSignal],
        queueSignals: [ProjectQueueSignal],
        progressActions: [HeartbeatAutoProgressAction],
        nextStepSummary: String
    ) -> HubIPCClient.SupervisorBriefProjectionRequestPayload? {
        if heartbeatVoiceReadinessSignal() != nil,
           blockerProjects.isEmpty,
           permissionSignals.isEmpty,
           governedReviewSignal == nil,
           governanceRepairSignals.isEmpty {
            return nil
        }
        if recoveryFollowUpSignal != nil {
            return nil
        }
        let focusProjectIdCandidates: [String?] = [
            progressActions.first?.projectId,
            blockerProjects.first?.projectId,
            permissionSignals.first?.projectId,
            governedReviewSignal?.projectId,
            governanceRepairSignals.first?.projectId,
            queueSignals.first?.project.projectId,
            heartbeatLeadRouteRepairAttentionItem(projects: projects)?.projectId,
        ]
        let focusProjectId = focusProjectIdCandidates
            .compactMap { candidate in
                let trimmed = candidate?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .first
        guard let focusProjectId else {
            return nil
        }
        return HubIPCClient.SupervisorBriefProjectionRequestPayload(
            requestId: "heartbeat_brief_\(Int(Date().timeIntervalSince1970 * 1000))_\(UUID().uuidString.lowercased())",
            projectId: focusProjectId,
            runId: nil,
            missionId: nil,
            projectionKind: "progress_brief",
            trigger: heartbeatProjectionTrigger(
                reason: reason,
                changed: changed,
                blockerProjects: blockerProjects,
                blockerSignal: blockerSignal,
                permissionSignals: permissionSignals,
                governedReviewSignal: governedReviewSignal,
                governanceRepairSignals: governanceRepairSignals,
                queueSignals: queueSignals,
                nextStepSummary: nextStepSummary
            ),
            includeTtsScript: true,
            includeCardSummary: false,
            maxEvidenceRefs: 4
        )
    }

    func heartbeatProjectionVoiceResolution(
        request: HubIPCClient.SupervisorBriefProjectionRequestPayload,
        blockerSignal: BlockerSignal,
        projects: [AXProjectEntry],
        governedReviewSignal: HeartbeatGovernedReviewSignal?
    ) async -> HeartbeatProjectionVoiceResolution? {
        let fetcher = supervisorBriefProjectionRequestOverride
            ?? { payload in
                await HubIPCClient.requestSupervisorBriefProjection(payload)
            }
        let result = await fetcher(request)
        guard result.ok, let projection = result.projection else {
            return heartbeatProjectionUnavailableVoiceResolution(
                request: request,
                reasonCode: result.reasonCode,
                projects: projects,
                governedReviewSignal: governedReviewSignal
            )
        }
        let script = projectionVoiceScript(from: projection)
        guard !script.isEmpty else {
            return heartbeatProjectionUnavailableVoiceResolution(
                request: request,
                reasonCode: result.reasonCode ?? "projection_voice_script_missing",
                projects: projects,
                governedReviewSignal: governedReviewSignal
            )
        }
        return .projection(SupervisorVoiceTTSJob(
            trigger: projectionVoiceTrigger(from: projection),
            priority: projectionVoicePriority(from: projection, blockerSignal: blockerSignal),
            script: script,
            dedupeKey: projectionVoiceDedupeKey(from: projection)
        ))
    }

    private func heartbeatProjectionUnavailableVoiceResolution(
        request: HubIPCClient.SupervisorBriefProjectionRequestPayload,
        reasonCode: String?,
        projects: [AXProjectEntry],
        governedReviewSignal: HeartbeatGovernedReviewSignal?
    ) -> HeartbeatProjectionVoiceResolution? {
        let projectName = heartbeatProjectName(
            for: request.projectId,
            in: projects
        ) ?? "当前项目"
        let presentation = supervisorBriefProjectionUnavailablePresentation(
            projectName: projectName,
            reasonCode: reasonCode,
            localSignal: governedReviewSignal.map(heartbeatGovernedReviewVoicePresentation)
                ?? heartbeatGovernanceVoicePresentation()
        )
        let script = heartbeatScriptPrefixedWithMemoryReadiness(presentation.script)
        guard !script.isEmpty else { return nil }
        let normalizedReason = HubRouteStateMachine.normalizedReasonToken(reasonCode) ?? "hub_brief_unavailable"
        return .unavailable(
            SupervisorVoiceTTSJob(
                trigger: request.trigger == "awaiting_authorization" ? .authorization : .blocked,
                priority: .normal,
                script: script,
                dedupeKey: "heartbeat:hub_brief_unavailable:\(request.projectId):\(normalizedReason)\(heartbeatMemoryReadinessDedupeSuffix())"
            )
        )
    }

    func projectionVoiceScript(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> [String] {
        let projectionProjectName = heartbeatProjectName(
            for: projection.projectId,
            in: allProjects()
        ) ?? "当前项目"
        if let governedReviewSignal = projectionGovernedReviewVoicePresentation(
            from: projection,
            projectName: projectionProjectName
        ) {
            return heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.governanceSignalHeartbeatScript(
                    signal: governedReviewSignal,
                    progressLine: nil,
                    nextStepLine: nil
                )
            )
        }

        let ttsScript = projection.ttsScript
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !ttsScript.isEmpty {
            let enrichedScript = enrichProjectionVoiceScriptWithRouteTruthHint(
                ttsScript,
                projection: projection
            )
            return heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.projectionScript(
                    ttsScript: enrichedScript,
                    trigger: projectionVoiceTrigger(from: projection)
                )
            )
        }

        let topline = projection.topline.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocker = projection.criticalBlocker.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = projection.nextBestAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = projection.cardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let enrichedFallbackScript = enrichProjectionVoiceScriptWithRouteTruthHint(
            SupervisorVoiceScriptBuilder.projectionFallbackScript(
                topline: topline,
                blocker: capped(blocker, maxChars: 48),
                pendingGrantCount: projection.pendingGrantCount,
                nextBestAction: capped(next, maxChars: 48),
                summary: summary
            ),
            projection: projection
        )
        return heartbeatScriptPrefixedWithMemoryReadiness(
            SupervisorVoiceScriptBuilder.projectionScript(
                ttsScript: enrichedFallbackScript,
                trigger: projectionVoiceTrigger(from: projection)
            )
        )
    }

    func projectionVoiceTrigger(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> SupervisorVoiceJobTrigger {
        let trigger = projection.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if trigger == "awaiting_authorization" || projection.pendingGrantCount > 0 {
            return .authorization
        }
        if let governedReviewSignal = projectionGovernedReviewVoicePresentation(
            from: projection,
            projectName: heartbeatProjectName(for: projection.projectId, in: allProjects()) ?? "当前项目"
        ) {
            return governedReviewSignal.trigger
        }
        if trigger == "blocked" || !projection.criticalBlocker.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .blocked
        }
        return .completed
    }

    private func projectionVoicePriority(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot,
        blockerSignal: BlockerSignal
    ) -> SupervisorVoiceJobPriority {
        let trigger = projectionVoiceTrigger(from: projection)
        if trigger == .blocked && blockerSignal.escalated {
            return .interrupt
        }
        if projection.status.trimmingCharacters(in: .whitespacesAndNewlines) == "attention_required" {
            return .normal
        }
        switch trigger {
        case .authorization, .blocked:
            return .normal
        case .completed, .userQueryReply:
            return .quiet
        }
    }

    func projectionVoiceDedupeKey(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String {
        let projectionId = projection.projectionId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !projectionId.isEmpty {
            return "hub-brief:\(projectionId)\(heartbeatMemoryReadinessDedupeSuffix())"
        }
        let auditRef = projection.auditRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if !auditRef.isEmpty {
            return "hub-brief:\(auditRef)\(heartbeatMemoryReadinessDedupeSuffix())"
        }
        return "hub-brief:\(projection.projectId):\(projection.trigger):\(Int(projection.generatedAtMs))\(heartbeatMemoryReadinessDedupeSuffix())"
    }
}
