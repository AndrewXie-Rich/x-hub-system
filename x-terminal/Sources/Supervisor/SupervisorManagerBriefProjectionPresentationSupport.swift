import Foundation

extension SupervisorManager {
    func supervisorBriefProjectionBindingRequiredPresentation(
        projects: [AXProjectEntry]
    ) -> SupervisorBriefProjectionUnavailablePresentation {
        let header = "⚠️ Hub Brief 需要项目绑定"
        var lines = [
            header,
            "Hub 统一投影现在按项目生成；我需要你先选中项目，或者直接说项目名后再问一次状态。",
            "按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"
        ]
        let examples = projects
            .prefix(2)
            .map { "“\($0.displayName) 现在状态怎么样”" }
        if !examples.isEmpty {
            lines.append("你可以直接说：\(examples.joined(separator: " / "))。")
        }
        return SupervisorBriefProjectionUnavailablePresentation(
            text: lines.joined(separator: "\n"),
            script: [
                "要给你正式的 Hub 简报，我还需要先绑定项目。",
                examples.isEmpty
                    ? "你先选中项目，或者直接说项目名后再问一次状态。"
                    : "你先选中项目，或者直接说项目名，比如 \(examples[0])。"
            ],
            dedupeKey: "voice-query:hub-brief-binding-required:\(projects.count)"
        )
    }

    func supervisorBriefProjectionUnavailablePresentation(
        projectName: String,
        reasonCode: String?,
        localSignal: SupervisorGovernanceSignalVoicePresentation?,
        contextLines: [String] = [],
        contextScript: [String] = [],
        dedupePrefix: String = "voice-query"
    ) -> SupervisorBriefProjectionUnavailablePresentation {
        let displayProjectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "当前项目"
            : projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureSummary = supervisorBriefProjectionFailureSummary(reasonCode)
        let repairAction = supervisorBriefProjectionFailureRepairAction(reasonCode)
        let normalizedReason = HubRouteStateMachine.normalizedReasonToken(reasonCode) ?? "hub_brief_unavailable"
        let header = "⚠️ Hub Brief 暂不可用 · \(displayProjectName)"

        let sanitizedContextLines = contextLines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var lines = [header] + sanitizedContextLines + [
            "这次没有拿到 Hub 统一投影：\(failureSummary)。",
            "按当前 fail-closed 规则，我先不在 XT 本地即兴拼接 Supervisor brief。"
        ]

        if let localSignal,
           !localSignal.headlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("XT 本地信号：\(localSignal.headlineText)。")
            let action = localSignal.actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !action.isEmpty {
                lines.append("你现在可以先：\(action)。")
            } else {
                lines.append(repairAction)
            }
        } else {
            lines.append(repairAction)
        }

        let sanitizedContextScript = contextScript
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var script = sanitizedContextScript + [
            "Hub 简报当前不可用。\(failureSummary)。",
            repairAction
        ]
        if let localSignal,
           !localSignal.headlineText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let action = localSignal.actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            script = sanitizedContextScript + [
                "Hub 简报当前不可用。\(failureSummary)。",
                !action.isEmpty
                    ? "XT 本地信号提示你先：\(action)。"
                    : repairAction
            ]
        }

        return SupervisorBriefProjectionUnavailablePresentation(
            text: lines.joined(separator: "\n"),
            script: script,
            dedupeKey: "\(dedupePrefix):hub-brief-unavailable:\(displayProjectName):\(normalizedReason)"
        )
    }

    func supervisorBriefProjectionFailureSummary(_ reasonCode: String?) -> String {
        switch HubRouteStateMachine.normalizedReasonToken(reasonCode) {
        case "synchronous_projection_fetch_required":
            return "当前这条本地直答链还没接上 Hub 简报投影查询"
        case "hub_env_missing":
            return "当前 Hub 配对或运行时档案不可用"
        case "supervisor_brief_projection_file_ipc_not_supported":
            return "当前仍在本地 file route，Hub brief 投影还没接上"
        case "client_kit_missing":
            return "Hub client kit 还没准备好"
        case "node_missing":
            return "Hub brief bridge 缺少 Node 运行时"
        case "grpc_route_unavailable",
             "grpc_unavailable",
             "remote_supervisor_brief_projection_failed",
             "supervisor_brief_projection_failed",
             "projection_unavailable":
            return "Hub 没有返回这次统一简报"
        default:
            if let token = HubRouteStateMachine.normalizedReasonToken(reasonCode) {
                if token.contains("timeout") || token.contains("connect") || token.contains("unavailable") {
                    return "Hub 路由当前不可达"
                }
                return "Hub brief 投影失败（\(token)）"
            }
            return "Hub 没有返回这次统一简报"
        }
    }

    func supervisorBriefProjectionFailureRepairAction(_ reasonCode: String?) -> String {
        switch HubRouteStateMachine.normalizedReasonToken(reasonCode) {
        case "synchronous_projection_fetch_required":
            return "等 Hub brief 投影查询链接上后再问一次状态；当前我不会在 XT 本地补写这份简报。"
        case "hub_env_missing":
            return "先修复 Hub 配对或运行 doctor / repair，再重新问一次状态。"
        case "supervisor_brief_projection_file_ipc_not_supported":
            return "先切回可用的 Hub pairing route，再重新问一次状态。"
        case "client_kit_missing", "node_missing":
            return "先修复 Hub 本地 runtime / bridge，再重新问一次状态。"
        default:
            return "先打开 Hub Diagnostics & Recovery 检查路由，再重新问一次状态。"
        }
    }

    func supervisorBriefProjectionUnavailableReply(
        presentation: SupervisorBriefProjectionUnavailablePresentation,
        fromVoice: Bool
    ) -> SupervisorBriefProjectionVoiceReply {
        let spokenOutcome: SupervisorSpeechSynthesizer.Outcome
        if !fromVoice {
            spokenOutcome = .suppressed("not_voice_triggered")
        } else {
            spokenOutcome = dispatchSupervisorBriefProjectionUnavailablePresentation(
                presentation,
                trigger: .userQueryReply,
                source: "brief_projection_unavailable_reply"
            )
        }
        return SupervisorBriefProjectionVoiceReply(
            text: presentation.text,
            spokenOutcome: spokenOutcome
        )
    }

    func dispatchSupervisorBriefProjectionUnavailablePresentation(
        _ presentation: SupervisorBriefProjectionUnavailablePresentation,
        trigger: SupervisorVoiceJobTrigger,
        source: String
    ) -> SupervisorSpeechSynthesizer.Outcome {
        if presentation.script.isEmpty {
            return speakSupervisorVoiceReply(presentation.text)
        }
        let job = SupervisorVoiceTTSJob(
            trigger: trigger,
            priority: .normal,
            script: presentation.script,
            dedupeKey: presentation.dedupeKey
        )
        return dispatchSupervisorVoiceJob(
            job,
            preferences: currentVoicePreferences(),
            source: source,
            suppressRapidSameSourceRepeat: false,
            cancelPendingHeartbeat: true
        )
    }

    private func localSupervisorBriefReply(
        focus: SupervisorFocusedProjectSelection,
        fromVoice: Bool
    ) -> SupervisorBriefProjectionVoiceReply? {
        localSupervisorBriefReply(
            projectName: focus.project.displayName,
            fromVoice: fromVoice
        )
    }

    private func localSupervisorBriefReply(
        projectName: String,
        fromVoice: Bool
    ) -> SupervisorBriefProjectionVoiceReply? {
        guard let signal = heartbeatGovernanceVoicePresentation() else { return nil }

        let replyText = renderLocalSupervisorGovernanceVoiceReply(
            signal,
            projectName: projectName
        )
        let spokenOutcome: SupervisorSpeechSynthesizer.Outcome
        if !fromVoice {
            spokenOutcome = .suppressed("not_voice_triggered")
        } else {
            let script = heartbeatScriptPrefixedWithMemoryReadiness(
                SupervisorVoiceScriptBuilder.governanceSignalHeartbeatScript(
                    signal: signal,
                    progressLine: nil,
                    nextStepLine: nil
                )
            )
            if script.isEmpty {
                spokenOutcome = speakSupervisorVoiceReply(replyText)
            } else {
                let job = SupervisorVoiceTTSJob(
                    trigger: .userQueryReply,
                    priority: .normal,
                    script: script,
                    dedupeKey: "voice-query:local-brief:\(signal.fingerprint)\(heartbeatMemoryReadinessDedupeSuffix())"
                )
                spokenOutcome = dispatchSupervisorVoiceJob(
                    job,
                    preferences: currentVoicePreferences(),
                    source: "brief_projection_local_voice_reply",
                    suppressRapidSameSourceRepeat: false,
                    cancelPendingHeartbeat: true
                )
            }
        }
        return SupervisorBriefProjectionVoiceReply(
            text: replyText,
            spokenOutcome: spokenOutcome
        )
    }

    func renderSupervisorBriefProjectionVoiceReply(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot,
        projectName: String
    ) -> String {
        if let governedReviewSignal = projectionGovernedReviewVoicePresentation(
            from: projection,
            projectName: projectName
        ) {
            return renderSupervisorGovernanceBrief(
                projectName: projectName,
                headline: governedReviewSignal.headlineText,
                detail: governedReviewSignal.detailText,
                metadata: governedReviewSignal.metadataText,
                action: governedReviewSignal.actionText
            )
        }

        var lines = ["🧭 Supervisor Brief · \(projectName)"]
        if let memoryLine = supervisorMemoryReadinessBriefTextLine() {
            lines.append(memoryLine)
        }
        let topline = projection.topline.trimmingCharacters(in: .whitespacesAndNewlines)
        let blocker = projection.criticalBlocker.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = projection.nextBestAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = projection.cardSummary.trimmingCharacters(in: .whitespacesAndNewlines)

        if !topline.isEmpty {
            lines.append(topline)
        } else if !summary.isEmpty {
            lines.append(summary)
        }
        if !blocker.isEmpty {
            lines.append("阻塞：\(SupervisorBlockerPresentation.label(blocker))")
        }
        if projection.pendingGrantCount > 0 {
            lines.append("待授权：\(projection.pendingGrantCount)")
        }
        if let routeHint = projectionRouteTruthHint(from: projection) {
            lines.append(routeHint)
        }
        if !next.isEmpty {
            lines.append("下一步：\(next)")
        }
        return lines.joined(separator: "\n")
    }

    private func projectionLooksLikeRouteRepairAttention(
        _ projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> Bool {
        let fields = [
            projection.projectionId,
            projection.cardSummary,
            projection.topline,
            projection.nextBestAction,
            projection.criticalBlocker,
            projection.evidenceRefs.joined(separator: " ")
        ]
        let tokens = [
            "route-repair",
            "route_repair",
            "route repair",
            "route:repair",
            "route diagnose",
            "model route",
            "模型路由"
        ]
        return fields.contains { field in
            let normalizedField = normalizedLookupKey(field)
            return tokens.contains { token in
                normalizedField.contains(normalizedLookupKey(token))
            }
        }
    }

    private func projectionRouteRepairWatchItem(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> AXRouteRepairProjectWatchItem? {
        guard projectionLooksLikeRouteRepairAttention(projection),
              let project = allProjects().first(where: {
                  $0.projectId.compare(
                      projection.projectId,
                      options: .caseInsensitive
                  ) == .orderedSame
              }) else {
            return nil
        }
        return AXRouteRepairLogStore.watchItems(for: [project], limit: 1).first
    }

    private func projectionRouteTruthHint(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String? {
        guard let item = projectionRouteRepairWatchItem(from: projection),
              let hint = AXRouteRepairLogStore.watchRouteTruthHint(
                for: item.digest,
                paidAccessSnapshot: appModel?.hubRemotePaidAccessSnapshot
              )?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !hint.isEmpty else {
            return nil
        }
        return hint
    }

    private func projectionRouteTruthSpokenHint(
        from projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> String? {
        guard let hint = projectionRouteTruthHint(from: projection)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !hint.isEmpty else {
            return nil
        }
        let withoutPeriod = hint.hasSuffix("。") ? String(hint.dropLast()) : hint
        let trimmed = withoutPeriod.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "更像 "
        if trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(prefix.count))
        }
        return trimmed
    }

    func enrichProjectionVoiceScriptWithRouteTruthHint(
        _ lines: [String],
        projection: HubIPCClient.SupervisorBriefProjectionSnapshot
    ) -> [String] {
        guard let routeHint = projectionRouteTruthSpokenHint(from: projection),
              !routeHint.isEmpty else {
            return lines
        }

        let normalizedHint = normalizedLookupKey(routeHint)
        let directionToken = normalizedLookupKey("方向上更像")
        if lines.contains(where: { line in
            let normalized = normalizedLookupKey(line)
            return normalized.contains(directionToken) || normalized.contains(normalizedHint)
        }) {
            return lines
        }

        let actionPrefixes = [
            normalizedLookupKey("建议下一步"),
            normalizedLookupKey("你现在只需要"),
            normalizedLookupKey("如果你现在要介入")
        ]

        var enriched: [String] = []
        var inserted = false
        for line in lines {
            let normalized = normalizedLookupKey(line)
            if !inserted,
               actionPrefixes.contains(where: { normalized.contains($0) }) {
                enriched.append("方向上更像：\(routeHint)")
                inserted = true
            }
            enriched.append(line)
        }

        if !inserted {
            enriched.append("方向上更像：\(routeHint)")
        }
        return enriched
    }

    private func renderLocalSupervisorGovernanceVoiceReply(
        _ signal: SupervisorGovernanceSignalVoicePresentation,
        projectName: String
    ) -> String {
        renderSupervisorGovernanceBrief(
            projectName: projectName,
            headline: signal.headlineText,
            detail: signal.detailText,
            metadata: signal.metadataText,
            action: signal.actionText
        )
    }

    func renderSupervisorGovernanceOverviewBrief(
        _ overview: SupervisorSignalCenterOverviewPresentation,
        projectName: String
    ) -> String {
        renderSupervisorGovernanceBrief(
            projectName: projectName,
            headline: overview.headlineText,
            detail: overview.detailText,
            metadata: overview.metadataText,
            action: overview.focusAction?.label
        )
    }

    private func workbenchGovernanceOverview() -> SupervisorSignalCenterOverviewPresentation? {
        if let overview = heartbeatSignalCenterOverviewPresentation(),
           overview.priority != .stable {
            return overview
        }

        let frontstageGrants = frontstagePendingHubGrants
        let frontstageApprovals = frontstagePendingSupervisorSkillApprovals
        let frontstageCandidateReviews = frontstageSupervisorCandidateReviews

        let grantPresentation = SupervisorPendingHubGrantPresentation.board(
            grants: frontstageGrants,
            source: pendingHubGrantSource,
            hasFreshSnapshot: hasFreshPendingHubGrantSnapshot,
            updatedAt: pendingHubGrantUpdatedAt,
            recentSkillActivities: frontstageRecentSupervisorSkillActivities,
            inFlightGrantIDs: pendingHubGrantActionsInFlight,
            hubInteractive: appModel?.hubInteractive ?? false,
            focusedRowAnchor: nil
        )
        if let firstGrant = grantPresentation.rows.first {
            return SupervisorSignalCenterOverviewPresentation(
                priority: .immediate,
                priorityText: SupervisorHeartbeatPriority.immediate.label,
                priorityTone: .warning,
                headlineText: "Hub 待处理授权",
                detailText: firstGrant.nextActionText ?? firstGrant.summary,
                metadataText: [
                    "\(grantPresentation.rows.count) 项待处理",
                    grantPresentation.snapshotText,
                    firstGrant.ageText
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.pendingHubGrantBoardAnchorID),
                    label: "查看授权板",
                    tone: .warning
                )
            )
        }

        let approvalPresentation = SupervisorPendingSkillApprovalPresentation.board(
            approvals: frontstageApprovals,
            focusedRowAnchor: nil
        )
        if approvalPresentation.rows.first != nil {
            return pendingSupervisorSkillOverviewPresentation(from: approvalPresentation)
        }

        let candidateReviewPresentation = SupervisorCandidateReviewPresentation.board(
            items: frontstageCandidateReviews,
            source: supervisorCandidateReviewSource,
            hasFreshSnapshot: hasFreshSupervisorCandidateReviewSnapshot,
            updatedAt: supervisorCandidateReviewUpdatedAt,
            inFlightRequestIDs: supervisorCandidateReviewActionsInFlight,
            hubInteractive: appModel?.hubInteractive ?? false,
            projectNamesByID: frontstageSupervisorCandidateReviewProjectNames,
            focusedRowAnchor: nil
        )
        if let firstCandidateReview = candidateReviewPresentation.rows.first {
            return SupervisorSignalCenterOverviewPresentation(
                priority: .attention,
                priorityText: SupervisorHeartbeatPriority.attention.label,
                priorityTone: .accent,
                headlineText: "候选记忆待审查",
                detailText: firstCandidateReview.summary,
                metadataText: [
                    "\(candidateReviewPresentation.rows.count) 项待处理",
                    candidateReviewPresentation.snapshotText,
                    firstCandidateReview.reviewStateText,
                    firstCandidateReview.ageText
                ]
                .filter { !$0.isEmpty }
                .joined(separator: " · "),
                focusAction: SupervisorSignalCenterOverviewActionDescriptor(
                    action: .scrollToBoard(SupervisorFocusPresentation.candidateReviewBoardAnchorID),
                    label: "查看候选审查",
                    tone: .accent
                )
            )
        }

        return nil
    }

    func prependWorkbenchGovernanceBriefIfAvailable(
        to lines: inout [String]
    ) {
        guard let governanceOverview = workbenchGovernanceOverview() else { return }
        lines.append(
            renderSupervisorGovernanceOverviewBrief(
                governanceOverview,
                projectName: "当前工作台"
            )
        )
        lines.append("")
    }

    private func renderSupervisorGovernanceBrief(
        projectName: String,
        headline: String,
        detail: String,
        metadata: String,
        action: String?
    ) -> String {
        var lines = ["🧭 Supervisor Brief · \(projectName)"]
        if let memoryLine = supervisorMemoryReadinessBriefTextLine() {
            lines.append(memoryLine)
        }

        let normalizedHeadline = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMetadata = metadata.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAction = action?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !normalizedHeadline.isEmpty {
            lines.append(normalizedHeadline)
        }
        if !normalizedDetail.isEmpty {
            lines.append(normalizedDetail)
        }
        if !normalizedMetadata.isEmpty {
            lines.append(normalizedMetadata)
        }
        if !normalizedAction.isEmpty {
            lines.append("查看：\(normalizedAction)")
        }

        return lines.joined(separator: "\n")
    }

    func supervisorMemoryReadinessBriefTextLine() -> String? {
        guard let readiness = currentSupervisorMemoryAssemblyReadinessForLanguageLayer(),
              !readiness.ready else {
            return nil
        }

        let topIssue = readiness.issues.first?.summary.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if topIssue.isEmpty {
            return "当前项目背景记忆还没喂够，我先不做战略纠偏；如果要纠偏，请先补长期目标和完成标准、关键决策原因、当前卡点与已试动作、以及可作为依据的日志或结果。"
        }
        return "当前项目背景记忆还没喂够（\(capped(topIssue, maxChars: 28))），我先不做战略纠偏；如果要纠偏，请先补长期目标和完成标准、关键决策原因、当前卡点与已试动作、以及可作为依据的日志或结果。"
    }

    func heartbeatSignalCenterOverviewPresentation() -> SupervisorSignalCenterOverviewPresentation? {
        guard let appModel else { return nil }

        let selectedAutomationProject = SupervisorViewStateSupport.selectedAutomationProject(
            appModel: appModel
        )
        let selectedAutomationRecipe = SupervisorViewStateSupport.selectedAutomationRecipe(
            appModel: appModel,
            selectedAutomationProject: selectedAutomationProject
        )
        let selectedAutomationLastLaunchRef = SupervisorViewStateSupport.selectedAutomationLastLaunchRef(
            appModel: appModel,
            supervisor: self,
            selectedAutomationProject: selectedAutomationProject
        )

        return SupervisorSignalCenterOverviewPresentationMapper.map(
            pendingHubGrantPresentation: SupervisorViewRuntimePresentationSupport.pendingHubGrantBoardPresentation(
                supervisor: self,
                hubInteractive: appModel.hubInteractive,
                focusedRowAnchor: nil
            ),
            pendingSkillApprovalPresentation: SupervisorViewRuntimePresentationSupport.pendingSkillApprovalBoardPresentation(
                supervisor: self,
                focusedRowAnchor: nil
            ),
            candidateReviewPresentation: SupervisorViewRuntimePresentationSupport.supervisorCandidateReviewBoardPresentation(
                supervisor: self,
                hubInteractive: appModel.hubInteractive,
                focusedRowAnchor: nil
            ),
            doctorPresentation: SupervisorViewRuntimePresentationSupport.doctorBoardPresentation(
                supervisor: self,
                appModel: appModel
            ),
            projectCreationPresentation: projectCreationStatusPresentation(),
            runtimeActivityPresentation: SupervisorRuntimeActivityPresentation.map(
                entries: frontstageRuntimeActivityEntries
            ),
            automationPresentation: SupervisorViewRuntimePresentationSupport.automationRuntimePresentation(
                supervisor: self,
                appModel: appModel,
                selectedProject: selectedAutomationProject,
                selectedRecipe: selectedAutomationRecipe,
                selectedLastLaunchRef: selectedAutomationLastLaunchRef
            ),
            laneHealthPresentation: SupervisorViewRuntimePresentationSupport.laneHealthBoardPresentation(
                supervisor: self,
                appModel: appModel,
                filter: .all,
                focusedLaneID: nil
            )
        )
    }
}
