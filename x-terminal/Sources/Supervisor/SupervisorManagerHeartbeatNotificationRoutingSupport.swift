import Foundation

extension SupervisorManager {
    func pushHubHeartbeatNotification(
        timeText: String,
        reason: String,
        projectCount: Int,
        changed: Bool,
        blockerCount: Int,
        blockerSignal: BlockerSignal,
        focusActionURL: String?,
        topSummary: String,
        queueSummary: String,
        permissionSummary: String,
        recoveryFollowUpSignal recoverySignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal reviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSummary: String,
        hubLoadSummary: String,
        hubLoadSignal: HeartbeatHubLoadSignal?,
        progressSummary: String,
        nextStepSummary: String,
        queuePendingCount: Int,
        permissionPendingCount: Int,
        governanceRepairCount: Int,
        routeAttentionSignal: HeartbeatRouteAttentionSignal?
    ) {
        let presentation = buildHeartbeatNotificationPresentation(
            timeText: timeText,
            reason: reason,
            projectCount: projectCount,
            changed: changed,
            blockerCount: blockerCount,
            blockerSignal: blockerSignal,
            topSummary: topSummary,
            queueSummary: queueSummary,
            permissionSummary: permissionSummary,
            recoveryFollowUpSignal: recoverySignal,
            governedReviewSignal: reviewSignal,
            governanceRepairSummary: governanceRepairSummary,
            hubLoadSummary: hubLoadSummary,
            hubLoadSignal: hubLoadSignal,
            progressSummary: progressSummary,
            nextStepSummary: nextStepSummary,
            queuePendingCount: queuePendingCount,
            permissionPendingCount: permissionPendingCount,
            governanceRepairCount: governanceRepairCount,
            focusActionURL: focusActionURL,
            routeDiagnoseShouldAlert: routeAttentionSignal?.shouldAlertOnTimer
        )
        let dedupeKey = "x_terminal_supervisor_heartbeat"
        guard presentation.unread else {
            HubIPCClient.removeNotification(dedupeKey: dedupeKey)
            return
        }
        guard shouldMirrorNotificationToHub(actionURL: focusActionURL) else {
            HubIPCClient.removeNotification(dedupeKey: dedupeKey)
            return
        }
        HubIPCClient.pushNotification(
            source: "X-Terminal",
            title: presentation.title,
            body: presentation.body,
            dedupeKey: dedupeKey,
            actionURL: focusActionURL,
            unread: presentation.unread
        )
    }

    func heartbeatDoctorBoardPresentation() -> SupervisorDoctorBoardPresentation? {
        guard let appModel else { return nil }
        return SupervisorViewRuntimePresentationSupport.doctorBoardPresentation(
            supervisor: self,
            appModel: appModel
        )
    }

    func heartbeatSkillDoctorTruthNotificationEntry(
        doctorPresentation: SupervisorDoctorBoardPresentation?
    ) -> SupervisorHeartbeatEntryPresentation? {
        SupervisorHeartbeatPresentation.map(
            entries: [],
            doctorPresentation: doctorPresentation
        ).entries.first { entry in
            entry.id == "skill_doctor_truth_blocked" || entry.id == "skill_doctor_truth_pending"
        }
    }

    func heartbeatSkillDoctorTruthNotificationOperationHint(
        _ entry: SupervisorHeartbeatEntryPresentation
    ) -> String {
        switch entry.headlineText {
        case "技能能力阻塞":
            return "点开这条提醒会进入 Supervisor 体检，优先处理技能 doctor truth 里的阻塞项。"
        case "技能授权待补齐":
            return "点开这条提醒会进入 Supervisor 体检，优先补齐技能 doctor truth 里的 Hub grant 和本地确认项。"
        default:
            return "点开这条提醒会进入 Supervisor 体检，先按技能 doctor truth 的提示继续处理。"
        }
    }

    func heartbeatNotificationHasRouteDiagnoseAction(
        _ focusActionURL: String?
    ) -> Bool {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return false
        }

        switch route {
        case let .project(projectRoute):
            return projectRoute.focusTarget == .routeDiagnose
        default:
            return false
        }
    }

    func heartbeatNotificationAuthorizationDestination(
        _ focusActionURL: String?
    ) -> HeartbeatAuthorizationNotificationDestination? {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return nil
        }

        let focusTarget: XTDeepLinkFocusTarget?
        switch route {
        case .project(let projectRoute):
            focusTarget = projectRoute.focusTarget
        case .supervisor(let supervisorRoute):
            focusTarget = supervisorRoute.focusTarget
        default:
            focusTarget = nil
        }

        switch focusTarget {
        case .grant:
            return .grant
        case .approval:
            return .approval
        case .toolApproval:
            return .toolApproval
        case .candidateReview, .skillRecord, .projectCreationBoard, .routeDiagnose, nil:
            return nil
        }
    }

    func heartbeatNotificationRouteRepairDestination(
        _ focusActionURL: String?,
        nextStepSummary: String
    ) -> HeartbeatRouteRepairNotificationDestination? {
        guard heartbeatRouteDiagnoseHighlight(nextStepSummary: nextStepSummary) != nil else {
            return nil
        }
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return nil
        }

        switch route {
        case .supervisorModelSettings:
            return .modelSettings
        case .settings(let settingsRoute):
            return settingsRoute.sectionId == "diagnostics" ? .xtDiagnostics : nil
        case .hubSetup(let hubRoute):
            switch hubRoute.sectionId {
            case "connection_log":
                return .hubConnectionLog
            case "troubleshoot":
                return .hubRecovery
            default:
                return nil
            }
        case .project(let projectRoute):
            return projectRoute.focusTarget == .routeDiagnose ? .routeDiagnose : nil
        default:
            return nil
        }
    }

    func heartbeatNotificationHasGovernanceRepairAction(
        _ focusActionURL: String?
    ) -> Bool {
        let raw = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty,
              let url = URL(string: raw),
              let route = XTDeepLinkParser.parse(url) else {
            return false
        }

        switch route {
        case let .project(projectRoute):
            return projectRoute.governanceDestination != nil
        default:
            return false
        }
    }

    func heartbeatNotificationHasHubLoadAction(
        _ focusActionURL: String?,
        hubLoadSignal: HeartbeatHubLoadSignal?
    ) -> Bool {
        let focus = focusActionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hubAction = hubLoadSignal?.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !focus.isEmpty && !hubAction.isEmpty && focus == hubAction
    }

    func heartbeatRouteDiagnoseHighlight(
        nextStepSummary: String
    ) -> String? {
        let lines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )

        if let routeLine = lines.first(where: { $0.contains("模型路由：") || $0.contains("/route diagnose") }) {
            return routeLine
        }
        return nil
    }

    func heartbeatGovernanceRepairHighlight(
        governanceRepairSummary: String,
        nextStepSummary: String
    ) -> String? {
        let summaryLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: governanceRepairSummary
        )
        if let first = summaryLines.first {
            return first
        }

        let lines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )

        if let governanceLine = lines.first(where: {
            $0.contains("治理修复：")
                || $0.contains("A-Tier")
                || $0.contains("S-Tier")
                || $0.contains("Heartbeat / Review")
                || $0.contains("Execution Tier")
                || $0.contains("Supervisor Tier")
                || $0.contains("Heartbeat & Review")
                || $0.contains("Project Governance")
        }) {
            return governanceLine
        }
        return nil
    }

    func heartbeatPermissionNotificationHighlight(
        permissionSummary: String,
        nextStepSummary: String
    ) -> String? {
        let permissionLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: permissionSummary
        )
        if let first = permissionLines.first {
            return first
        }

        let nextStepLines = SupervisorHeartbeatPresentation.userFacingSanitizedLines(
            from: nextStepSummary
        )
        if let permissionStep = nextStepLines.first(where: {
            $0.contains("授权") || $0.contains("审批") || $0.contains("批准")
        }) {
            return permissionStep
        }
        return nextStepLines.first
    }

    func buildHeartbeatNotificationPresentation(
        timeText: String,
        reason: String,
        projectCount: Int,
        changed: Bool,
        blockerCount: Int,
        blockerSignal: BlockerSignal,
        topSummary: String,
        queueSummary: String,
        permissionSummary: String,
        recoveryFollowUpSignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSummary: String,
        hubLoadSummary: String,
        hubLoadSignal: HeartbeatHubLoadSignal?,
        progressSummary: String,
        nextStepSummary: String,
        queuePendingCount: Int,
        permissionPendingCount: Int,
        governanceRepairCount: Int,
        focusActionURL: String?,
        routeDiagnoseShouldAlert: Bool? = nil,
        doctorPresentation: SupervisorDoctorBoardPresentation? = nil
    ) -> HeartbeatNotificationPresentation {
        let doctorPresentation = doctorPresentation ?? heartbeatDoctorBoardPresentation()
        let skillDoctorTruthHeartbeat = heartbeatSkillDoctorTruthNotificationEntry(
            doctorPresentation: doctorPresentation
        )
        let memoryReadinessLine = supervisorMemoryReadinessBriefTextLine()
        let projectMemoryAdvisoryLines = heartbeatProjectMemoryAdvisoryLines()
        let voiceReadinessSignal = heartbeatVoiceReadinessSignal()
        let authorizationDestination = heartbeatNotificationAuthorizationDestination(
            focusActionURL
        )
        let routeRepairDestination = heartbeatNotificationRouteRepairDestination(
            focusActionURL,
            nextStepSummary: nextStepSummary
        )
        let governanceRepairAction = heartbeatNotificationHasGovernanceRepairAction(focusActionURL)
        let projectCreationPresentation = projectCreationStatusPresentation()
        let hubLoadAction = heartbeatNotificationHasHubLoadAction(
            focusActionURL,
            hubLoadSignal: hubLoadSignal
        )
        let reasonText = SupervisorHeartbeatPresentation.userFacingReasonText(for: reason)
        let topSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: topSummary,
            emptyPlaceholder: "（无）"
        )
        let queueSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: queueSummary,
            emptyPlaceholder: "（无）"
        )
        let permissionSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: permissionSummary,
            emptyPlaceholder: "（无）"
        )
        let governanceRepairSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: governanceRepairSummary,
            emptyPlaceholder: "（无）"
        )
        let projectCreationSummaryText = projectCreationPresentation.map {
            heartbeatProjectCreationSummaryText($0)
        } ?? "（无）"
        let progressSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: progressSummary,
            emptyPlaceholder: "（本轮无需介入）"
        )
        let nextStepSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: nextStepSummary,
            emptyPlaceholder: "（暂无）"
        )
        let governedReviewSummaryText = governedReviewSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: heartbeatGovernedReviewContentLines($0).joined(separator: "\n"),
                emptyPlaceholder: "（无）"
            )
        } ?? "（无）"
        let voiceReadinessSummaryText = voiceReadinessSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: $0.overallSummary,
                emptyPlaceholder: "（无）"
            )
        } ?? "（无）"
        let voiceReadinessNextStepText = voiceReadinessSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: $0.nextStep,
                emptyPlaceholder: heartbeatVoiceReadinessDefaultNextStepText($0)
            )
        }
        let voiceReadinessSectionHeading = voiceReadinessSignal.map {
            heartbeatVoiceReadinessSectionTitle($0)
        } ?? "语音就绪："
        let hubLoadSummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: hubLoadSummary,
            emptyPlaceholder: "（无）"
        )
        let projectMemoryAdvisorySummaryText = SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
            from: projectMemoryAdvisoryLines.joined(separator: "\n"),
            emptyPlaceholder: "（无）"
        )
        let skillDoctorTruthSummaryText = skillDoctorTruthHeartbeat.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: $0.detailLines.joined(separator: "\n"),
                emptyPlaceholder: "（无）"
            )
        } ?? "（无）"
        let recoverySummaryText = recoveryFollowUpSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: [$0.summaryLine, $0.detailLine, $0.priorityReasonLine]
                    .compactMap { $0 }
                    .joined(separator: "\n"),
                emptyPlaceholder: "（无）"
            )
        } ?? "（无）"
        let recoverySystemNextStepText = recoveryFollowUpSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: $0.detailLine,
                emptyPlaceholder: heartbeatRecoveryFollowUpDigestNextStep($0)
            )
        }
        let hubLoadNextStepText = hubLoadSignal.map {
            SupervisorHeartbeatPresentation.userFacingSanitizedBlock(
                from: $0.nextStep,
                emptyPlaceholder: "打开 Hub 诊断并检查并发、模型加载和当前队列。"
            )
        }
        let permissionHighlight = heartbeatPermissionNotificationHighlight(
            permissionSummary: permissionSummary,
            nextStepSummary: nextStepSummary
        )
        let permissionNextStepText =
            SupervisorHeartbeatPresentation.userFacingSanitizedLines(from: nextStepSummary)
                .first(where: { line in
                    line.contains("授权") || line.contains("审批") || line.contains("批准")
                }) ?? permissionHighlight
        let routeDiagnoseHighlight = routeRepairDestination != nil
            ? heartbeatRouteDiagnoseHighlight(nextStepSummary: nextStepSummary)
            : nil
        let governanceRepairHighlight = governanceRepairAction
            ? heartbeatGovernanceRepairHighlight(
                governanceRepairSummary: governanceRepairSummary,
                nextStepSummary: nextStepSummary
            )
            : nil
        let projectCreationWhatChangedText = projectCreationPresentation.map {
            heartbeatProjectCreationWhatChangedText($0)
        }
        let shouldHighlightProjectCreation = projectCreationPresentation != nil
            && blockerCount == 0
            && recoveryFollowUpSignal == nil
            && permissionPendingCount == 0
            && governanceRepairCount == 0
            && governedReviewSignal == nil
            && progressSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let digestLeadText: (String) -> String = { block in
            block
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? block
        }
        let digestWhatChangedText = [
            recoverySummaryText,
            governanceRepairSummaryText,
            permissionSummaryText,
            skillDoctorTruthHeartbeat?.digest.whatChangedText ?? "",
            governedReviewSummaryText,
            shouldHighlightProjectCreation ? (projectCreationWhatChangedText ?? "（无）") : "（无）",
            voiceReadinessSummaryText,
            hubLoadSummaryText,
            projectMemoryAdvisorySummaryText,
            topSummaryText,
            progressSummaryText,
            queueSummaryText
        ].first(where: {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty
                && trimmed != "（无）"
                && trimmed != "（暂无）"
                && trimmed != "（本轮无需介入）"
        }).map(digestLeadText) ?? (changed ? "项目状态出现了新的变化。" : "当前没有新的高风险变化。")
        let digestWhyImportantText: String
        if blockerCount > 0 {
            digestWhyImportantText = blockerSignal.escalated
                ? "阻塞已经持续多个心跳窗口，再不处理就会继续拖慢交付。"
                : "当前项目推进已经被 blocker 挡住，系统不会把静默等待误判成健康。"
        } else if let recoveryFollowUpSignal {
            digestWhyImportantText = heartbeatRecoveryFollowUpWhyImportantText(
                recoveryFollowUpSignal
            )
        } else if authorizationDestination != nil, permissionPendingCount > 0 {
            digestWhyImportantText = "当前推进被授权或审批挡住，在你处理前系统不会越权继续执行。"
        } else if governanceRepairAction || governanceRepairCount > 0 {
            digestWhyImportantText = "当前治理边界已经影响执行，必须先修好再继续推进。"
        } else if let skillDoctorTruthHeartbeat {
            digestWhyImportantText = skillDoctorTruthHeartbeat.digest.whyImportantText
        } else if let governedReviewSignal {
            digestWhyImportantText = heartbeatGovernedReviewDigestWhyImportantText(
                governedReviewSignal
            )
        } else if let projectCreationPresentation, shouldHighlightProjectCreation {
            digestWhyImportantText = heartbeatProjectCreationWhyImportantText(
                projectCreationPresentation
            )
        } else if routeRepairDestination != nil {
            digestWhyImportantText = "这说明当前路由与真实可用执行面可能不一致，继续推进前最好先确认。"
        } else if let voiceReadinessSignal {
            digestWhyImportantText = heartbeatVoiceReadinessWhyImportantText(
                voiceReadinessSignal
            )
        } else if hubLoadSignal != nil {
            digestWhyImportantText = "Hub 侧资源已经吃紧，可能影响队列、模型加载和运行稳定性。"
        } else if projectMemoryAdvisoryLines.count > 1 {
            digestWhyImportantText = projectMemoryAdvisoryLines[1]
        } else if !progressSummary.isEmpty {
            digestWhyImportantText = "项目还在持续推进，目前更多是观察而不是立即接管。"
        } else if queuePendingCount > 0 {
            digestWhyImportantText = "任务仍在排队或等待恢复，不一定是故障，但值得继续留意。"
        } else {
            digestWhyImportantText = "当前没有新的高风险或高优先级治理信号，系统保持持续观察。"
        }
        let digestNextStepText: String
        if let recoveryFollowUpSignal {
            digestNextStepText = digestLeadText(
                recoverySystemNextStepText
                    ?? heartbeatRecoveryFollowUpDigestNextStep(recoveryFollowUpSignal)
            )
        } else if let authorizationDestination,
           permissionPendingCount > 0 {
            digestNextStepText = digestLeadText(
                permissionNextStepText ?? authorizationDestination.defaultRecommendation
            )
        } else if routeRepairDestination != nil {
            digestNextStepText = digestLeadText(routeDiagnoseHighlight ?? nextStepSummaryText)
        } else if governanceRepairAction {
            digestNextStepText = digestLeadText(
                governanceRepairHighlight ?? "系统会把你带到治理设置，修好执行边界后再继续推进。"
            )
        } else if let skillDoctorTruthHeartbeat {
            digestNextStepText = digestLeadText(
                skillDoctorTruthHeartbeat.digest.systemNextStepText
            )
        } else if let governedReviewSignal {
            digestNextStepText = digestLeadText(
                heartbeatGovernedReviewDigestNextStepText(governedReviewSignal)
            )
        } else if let projectCreationPresentation, shouldHighlightProjectCreation {
            digestNextStepText = heartbeatProjectCreationActionText(projectCreationPresentation)
        } else if hubLoadAction, hubLoadSignal != nil {
            digestNextStepText = digestLeadText(
                hubLoadNextStepText ?? "打开 Hub 诊断并检查并发、模型加载和当前队列。"
            )
        } else if let voiceReadinessSignal {
            digestNextStepText = digestLeadText(
                voiceReadinessNextStepText
                    ?? heartbeatVoiceReadinessDefaultNextStepText(voiceReadinessSignal)
            )
        } else if projectMemoryAdvisoryLines.count > 2 {
            digestNextStepText = projectMemoryAdvisoryLines[2]
        } else {
            digestNextStepText = nextStepSummaryText == "（暂无）"
                ? "系统会继续观察当前项目，有实质变化再提醒你。"
                : digestLeadText(nextStepSummaryText)
        }
        let title: String
        let unread: Bool
        if blockerCount > 0, blockerSignal.escalated {
            title = "🚨 Supervisor 升级提醒：\(blockerCount) 个阻塞已持续 \(blockerSignal.streak) 次心跳"
            unread = true
        } else if let governedReviewSignal,
                  governedReviewSignal.reviewLevel == .r3Rescue {
            title = "🚨 Supervisor 心跳：救援审查已排队"
            unread = true
        } else if let recoveryFollowUpSignal {
            title = heartbeatRecoveryFollowUpNotificationTitle(recoveryFollowUpSignal)
            unread = true
        } else if !progressSummary.isEmpty {
            title = "🚀 Supervisor 心跳：已主动推进项目"
            unread = true
        } else if blockerCount > 0, blockerSignal.streak <= 1 {
            title = "🚧 Supervisor 心跳：检测到 \(blockerCount) 个阻塞"
            unread = true
        } else if blockerCount > 0 {
            title = "🚧 Supervisor 心跳：阻塞持续（静默）"
            unread = false
        } else if permissionPendingCount > 0 {
            title = "🛂 Supervisor 心跳：\(permissionPendingCount) 个权限申请待处理"
            unread = true
        } else if governanceRepairCount > 0 {
            title = "🛠️ Supervisor 心跳：\(governanceRepairCount) 个治理修复待处理"
            unread = true
        } else if let skillDoctorTruthHeartbeat {
            switch skillDoctorTruthHeartbeat.headlineText {
            case "技能能力阻塞":
                title = "⛔️ Supervisor 心跳：技能能力阻塞"
            case "技能授权待补齐":
                title = "⚠️ Supervisor 心跳：技能授权待补齐"
            default:
                title = "⚠️ Supervisor 心跳：技能 doctor truth 需要处理"
            }
            unread = true
        } else if let governedReviewSignal {
            switch governedReviewSignal.reviewLevel {
            case .r1Pulse:
                title = "🧭 Supervisor 心跳：治理脉冲已排队"
            case .r2Strategic:
                title = "🧭 Supervisor 心跳：治理审查已排队"
            case .r3Rescue:
                title = "🚨 Supervisor 心跳：救援审查已排队"
            }
            unread = true
        } else if let projectCreationPresentation, shouldHighlightProjectCreation {
            let disposition = heartbeatProjectCreationNotificationDisposition(
                projectCreationPresentation,
                changed: changed
            )
            title = disposition.title
            unread = disposition.unread
        } else if let voiceReadinessSignal {
            title = heartbeatVoiceReadinessNotificationTitle(voiceReadinessSignal)
            unread = !voiceReadinessSignal.readyForFirstTask || changed
        } else if let hubLoadSignal {
            switch hubLoadSignal.severity {
            case .critical:
                title = "🔥 Supervisor 心跳：Hub 负载过高"
                unread = true
            case .high:
                title = "🌡️ Supervisor 心跳：Hub 负载偏高"
                unread = true
            case .elevated:
                title = "📈 Supervisor 心跳：Hub 负载需要关注"
                unread = changed
            case .normal:
                title = "Supervisor 心跳：状态稳定（静默）"
                unread = false
            }
        } else if queuePendingCount > 0 {
            title = "⏳ Supervisor 心跳：\(queuePendingCount) 个项目排队中"
            unread = changed
        } else if let routeRepairDestination {
            if let routeDiagnoseShouldAlert {
                title = routeDiagnoseShouldAlert
                    ? routeRepairDestination.notificationTitle
                    : "🧭 Supervisor 心跳：模型路由仍需关注（静默）"
                unread = routeDiagnoseShouldAlert
            } else {
                title = routeRepairDestination.notificationTitle
                unread = true
            }
        } else if memoryReadinessLine != nil {
            title = "⚠️ Supervisor 心跳：战略记忆供给不足"
            unread = true
        } else if !projectMemoryAdvisoryLines.isEmpty {
            title = "⚠️ Supervisor 心跳：Project AI 记忆需补强（advisory）"
            unread = changed
        } else if changed {
            title = "Supervisor 心跳：项目有更新（静默）"
            unread = false
        } else {
            title = "Supervisor 心跳：状态稳定（静默）"
            unread = false
        }

        var blockerLines: [String] = []
        blockerLines.append(blockerCount > 0 ? "阻塞项目数：\(blockerCount)" : "阻塞项目数：0")
        if blockerCount > 0 {
            blockerLines.append("阻塞连续心跳：\(max(1, blockerSignal.streak)) 次")
            if blockerSignal.escalated {
                blockerLines.append("升级状态：已触发升级提醒")
            } else if blockerSignal.cooldownRemainingSec > 0 {
                let mins = max(1, Int(ceil(Double(blockerSignal.cooldownRemainingSec) / 60.0)))
                blockerLines.append("升级冷却中：约 \(mins) 分钟后可再次升级提醒")
            }
        }
        var bodyLines = [
            "时间：\(timeText)",
            "原因：\(reasonText)",
            "发生了什么：\(digestWhatChangedText)",
            "为什么重要：\(digestWhyImportantText)",
            "系统下一步：\(digestNextStepText)",
            "项目总数：\(projectCount)",
            blockerLines.joined(separator: "\n"),
            "排队项目数：\(queuePendingCount)",
            "待授权项目数：\(permissionPendingCount)",
            "待治理审查项目数：\(governedReviewSignal == nil ? 0 : 1)",
            "待治理修复项目数：\(governanceRepairCount)"
        ]
        if let recoveryFollowUpSignal {
            bodyLines.append("操作提示：")
            bodyLines.append(
                heartbeatRecoveryFollowUpOperationHint(
                    recoveryFollowUpSignal,
                    authorizationDestination: authorizationDestination
                )
            )
            bodyLines.append("优先建议：")
            bodyLines.append(
                heartbeatRecoveryFollowUpPriorityRecommendation(
                    recoveryFollowUpSignal,
                    authorizationDestination: authorizationDestination,
                    permissionHighlight: permissionHighlight
                )
            )
        } else if let authorizationDestination,
           permissionPendingCount > 0 {
            bodyLines.append("操作提示：")
            bodyLines.append(authorizationDestination.operationHint)
            bodyLines.append("优先建议：")
            bodyLines.append(permissionHighlight ?? authorizationDestination.defaultRecommendation)
        } else if let routeRepairDestination {
            bodyLines.append("操作提示：")
            bodyLines.append(routeRepairDestination.operationHint)
            if let routeDiagnoseHighlight {
                bodyLines.append("优先建议：")
                bodyLines.append(routeDiagnoseHighlight)
            }
        } else if governanceRepairAction {
            bodyLines.append("操作提示：")
            bodyLines.append("点开这条提醒会直接进入项目治理设置，并定位到对应的治理子页。")
            if let governanceRepairHighlight {
                bodyLines.append("优先建议：")
                bodyLines.append(governanceRepairHighlight)
            }
        } else if let skillDoctorTruthHeartbeat {
            bodyLines.append("操作提示：")
            bodyLines.append(
                heartbeatSkillDoctorTruthNotificationOperationHint(skillDoctorTruthHeartbeat)
            )
            bodyLines.append("优先建议：")
            bodyLines.append(skillDoctorTruthHeartbeat.digest.systemNextStepText)
        } else if let governedReviewSignal {
            bodyLines.append("操作提示：")
            bodyLines.append(heartbeatGovernedReviewOperationHint(governedReviewSignal))
            bodyLines.append("优先建议：")
            bodyLines.append(heartbeatGovernedReviewNotificationNextStep(governedReviewSignal))
        } else if let projectCreationPresentation, shouldHighlightProjectCreation {
            bodyLines.append("操作提示：")
            bodyLines.append(heartbeatProjectCreationOperationHint(projectCreationPresentation))
            bodyLines.append("优先建议：")
            bodyLines.append(heartbeatProjectCreationActionText(projectCreationPresentation))
        } else if hubLoadAction, hubLoadSignal != nil {
            bodyLines.append("操作提示：")
            bodyLines.append("点开这条提醒会直接进入 Hub 诊断页，检查并发、模型加载和当前队列。")
            bodyLines.append("优先建议：")
            bodyLines.append(
                hubLoadNextStepText ?? "打开 Hub 诊断并检查并发、模型加载和当前队列。"
            )
        } else if let voiceReadinessSignal {
            bodyLines.append("操作提示：")
            bodyLines.append(heartbeatVoiceReadinessOperationHint(voiceReadinessSignal))
            bodyLines.append("优先建议：")
            bodyLines.append(
                voiceReadinessNextStepText
                    ?? heartbeatVoiceReadinessDefaultNextStepText(voiceReadinessSignal)
            )
        }
        if let memoryReadinessLine {
            bodyLines.append("战略纠偏状态：")
            bodyLines.append(memoryReadinessLine)
        }
        if !projectMemoryAdvisoryLines.isEmpty {
            bodyLines.append("Project AI 记忆（advisory）：")
            bodyLines.append(contentsOf: projectMemoryAdvisoryLines)
        }
        bodyLines.append(contentsOf: [
            "主动推进：",
            progressSummaryText,
            "重点看板：",
            topSummaryText,
            "排队态势：",
            queueSummaryText,
            "权限申请：",
            permissionSummaryText,
            "Recovery 跟进：",
            recoverySummaryText,
            "治理审查：",
            governedReviewSummaryText,
            "治理修复：",
            governanceRepairSummaryText,
            "技能 Doctor Truth：",
            skillDoctorTruthSummaryText,
            "项目创建：",
            projectCreationSummaryText,
            voiceReadinessSectionHeading,
            voiceReadinessSummaryText,
            "Hub 负载：",
            hubLoadSummaryText,
            "Coder 下一步建议：",
            nextStepSummaryText
        ])
        return HeartbeatNotificationPresentation(
            title: title,
            body: bodyLines.joined(separator: "\n"),
            unread: unread
        )
    }

}
