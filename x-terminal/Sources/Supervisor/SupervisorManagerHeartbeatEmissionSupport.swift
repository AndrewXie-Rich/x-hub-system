import Foundation

extension SupervisorManager {
    func emitHeartbeatIfNeeded(force: Bool, reason: String) {
        let trace = XTPerformanceTrace.begin(
            "supervisor_heartbeat",
            "force=\(force) reason=\(reason)"
        )
        var traceOutcome = "started"
        defer {
            XTPerformanceTrace.end(trace, traceOutcome)
        }
        let projects = allProjects()
        let operationalProjects = knownProjects()
        let projectCreationPresentation = projectCreationStatusPresentation()
        guard !operationalProjects.isEmpty || projectCreationPresentation != nil else {
            traceOutcome = "skipped empty"
            return
        }
        let heartbeatScopeProjects = projects.isEmpty ? operationalProjects : projects

        let now = Date().timeIntervalSince1970
        let queueSignals = queuedProjectSignals(for: heartbeatScopeProjects, now: now)
        let permissionSignals = collectPermissionSignals(for: heartbeatScopeProjects)
        let governanceRepairSignals = collectGovernanceRepairSignals(for: heartbeatScopeProjects)

        let queueFingerprint = queueSignals
            .map { "\($0.project.projectId):\($0.queued):\($0.inFlight)" }
            .joined(separator: "|")
        let permissionFingerprint = permissionSignals
            .map { "\($0.projectId):\($0.kind.rawValue):\($0.summary)" }
            .joined(separator: "|")
        let governanceFingerprint = governanceRepairSignals
            .map { "\($0.projectId):\($0.destination.rawValue):\($0.summary)" }
            .joined(separator: "|")
        let voiceReadinessSignal = heartbeatVoiceReadinessSignal()
        let voiceFingerprint = voiceReadinessSignal.map {
            [
                $0.readyForFirstTask ? "ready" : "fail_closed",
                $0.reasonCode,
                $0.overallSummary,
                $0.nextStep
            ]
            .map { $0.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "|")
        } ?? ""
        let projectCreationFingerprint = projectCreationPresentation.map {
            [
                $0.reasonCode,
                $0.headlineText,
                $0.detailText,
                $0.metadataText,
                $0.recommendedCommands.joined(separator: "|")
            ]
            .joined(separator: "|")
            .replacingOccurrences(of: "\n", with: " ")
        } ?? ""
        let routeAttentionItem = heartbeatLeadRouteRepairAttentionItem(projects: projects)
        let routeAttentionSnapshotToken = heartbeatRouteAttentionAlertToken(routeAttentionItem)
        let laneHealthFingerprint = supervisorLaneHealthSnapshot?.fingerprint ?? ""
        let snapshot = heartbeatScopeProjects.map { p in
            [
                p.projectId,
                p.statusDigest ?? "",
                p.currentStateSummary ?? "",
                p.nextStepSummary ?? "",
                p.blockerSummary ?? "",
            ].joined(separator: "|")
        }.joined(separator: "\n") + "\n[queue]\(queueFingerprint)\n[perm]\(permissionFingerprint)\n[gov]\(governanceFingerprint)\n[voice]\(voiceFingerprint)\n[project_creation]\(projectCreationFingerprint)\n[route]\(routeAttentionSnapshotToken)\n[lane]\(laneHealthFingerprint)"

        let dueByTime = (now - lastHeartbeatAt) >= heartbeatIntervalSec
        let changed = snapshot != lastHeartbeatSnapshot
        let criticalForce = reason == "project_created" || reason == "project_removed"

        if force {
            if !criticalForce && !changed {
                traceOutcome = "skipped unchanged force=true"
                return
            }
            if !criticalForce && (now - lastHeartbeatAt) < forceHeartbeatMinIntervalSec {
                traceOutcome = "skipped cooldown force=true"
                return
            }
        } else if !dueByTime {
            traceOutcome = "skipped not_due"
            return
        }

        let operationalQueueSignals = queuedProjectSignals(for: operationalProjects, now: now)
        let operationalPermissionSignals = collectPermissionSignals(for: operationalProjects)
        let internalProgressActions = heartbeatAutoProgressActions(
            reason: reason,
            now: Date(timeIntervalSince1970: now),
            projects: operationalProjects,
            queueSignals: operationalQueueSignals,
            permissionSignals: operationalPermissionSignals
        )
        let visibleProjectIDs = Set(projects.map(\.projectId))
        let progressActions = internalProgressActions.filter { visibleProjectIDs.contains($0.projectId) }
        let progressSummary = progressActions.prefix(4).map(\.summaryLine).joined(separator: "\n")

        let queueSummary = queueSignals.prefix(4).map { signal -> String in
            let waitMin = max(1, Int(ceil(Double(signal.oldestQueuedMs) / 60_000.0)))
            if signal.inFlight > 0 {
                return "• \(signal.project.displayName)：\(signal.queued) 个待执行（Hub 正在处理中）"
            }
            return "• \(signal.project.displayName)：\(signal.queued) 个排队中（最长约 \(waitMin) 分钟）"
        }.joined(separator: "\n")
        let permissionSummary = permissionSignals.prefix(4).map { signal -> String in
            let ageText: String
            if let createdAt = signal.createdAt, createdAt > 0 {
                ageText = "（\(idleDurationText(max(0, now - createdAt)))）"
            } else {
                ageText = ""
            }
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionText = action.isEmpty ? "" : "（打开：\(action)）"
            return "• \(signal.projectName)：\(signal.summary)\(ageText)\(actionText)"
        }.joined(separator: "\n")
        let governanceRepairSummary = governanceRepairSignals.prefix(4).map { signal -> String in
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionText = action.isEmpty ? "" : "（打开：\(action)）"
            return "• \(signal.projectName)：\(capped(signal.summary, maxChars: 96))\(actionText)"
        }.joined(separator: "\n")
        let laneHealthLine = supervisorLaneHealthStatusLine
        let laneHotspots = supervisorLaneHealthSnapshot?.lanes
            .filter { $0.status == .failed || $0.status == .stalled || $0.status == .blocked }
            .prefix(4)
            .map { lane in
                "• \(frontstageLaneHotspotSummary(for: lane))"
            }.joined(separator: "\n") ?? ""
        let hubLoadSignal = heartbeatHubLoadSignal()
        let hubLoadSummary = hubLoadSignal.map { heartbeatHubLoadContentLine($0) } ?? ""
        let routeAttentionSignal = heartbeatRouteAttentionSignal(
            item: routeAttentionItem,
            now: now
        )

        lastHeartbeatSnapshot = snapshot
        lastHeartbeatAt = now
        recordHeartbeatGovernanceRepairRuntimeIfNeeded(signals: governanceRepairSignals)

        let operationalBlockerProjects: [(projectId: String, blocker: String)] = operationalProjects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        let governedReviewSignal = scheduleGovernedReviewFromHeartbeat(
            projects: operationalProjects,
            blockerProjects: operationalBlockerProjects,
            now: Date(timeIntervalSince1970: now)
        )
        let recoveryFollowUpSignal = reason == "timer"
            ? self.scheduleRecoveryFollowUpFromHeartbeat(
                projects: operationalProjects,
                queueSignals: operationalQueueSignals,
                permissionSignals: operationalPermissionSignals,
                now: Date(timeIntervalSince1970: now)
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
            now: now
        )

        guard !projects.isEmpty || projectCreationPresentation != nil else {
            traceOutcome = "skipped no_visible_projects"
            return
        }

        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        let time = fmt.string(from: Date(timeIntervalSince1970: now))

        var topLines: [String] = []
        if let voiceReadinessSignal {
            let icon = heartbeatVoiceReadinessTopBoardIcon(voiceReadinessSignal)
            let label = heartbeatVoiceReadinessTopBoardLabel(voiceReadinessSignal)
            topLines.append("• \(label)：\(icon) \(capped(voiceReadinessSignal.overallSummary, maxChars: 60))")
        }
        if let hubLoadSignal {
            let icon: String
            switch hubLoadSignal.severity {
            case .critical:
                icon = "🔥"
            case .high:
                icon = "🌡️"
            case .elevated:
                icon = "📈"
            case .normal:
                icon = "✅"
            }
            topLines.append("• Hub Runtime：\(icon) \(capped(hubLoadSignal.overallSummary, maxChars: 60))")
        }
        if let projectCreationPresentation {
            topLines.append(
                "• Supervisor：📁 \(heartbeatProjectCreationWhatChangedText(projectCreationPresentation))"
            )
        }
        topLines.append(contentsOf: projects.map { p in
            let blocker = (p.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let next = (p.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let runtime = runtimeStatus(for: p, now: now)
            if !blocker.isEmpty {
                return "• \(p.displayName)：🚧 \(capped(blocker, maxChars: 60))"
            }
            if !next.isEmpty {
                if runtime.state == .paused {
                    return "• \(p.displayName)：⏸️ \(capped(runtime.text, maxChars: 60))"
                }
                return "• \(p.displayName)：➡️ \(capped(next, maxChars: 60))"
            }
            switch runtime.state {
            case .blocked:
                return "• \(p.displayName)：🚧 \(capped(runtime.text, maxChars: 60))"
            case .paused:
                return "• \(p.displayName)：⏸️ \(capped(runtime.text, maxChars: 60))"
            case .running:
                return "• \(p.displayName)：✅ \(capped(runtime.text, maxChars: 60))"
            }
        })
        let top = Array(topLines.prefix(4)).joined(separator: "\n")

        let blockerProjects: [(projectId: String, blocker: String)] = projects.compactMap { project in
            let blocker = (project.blockerSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !blocker.isEmpty else { return nil }
            return (project.projectId, blocker)
        }
        let blockerCount = blockerProjects.count
        let blockerFingerprint = blockerProjects
            .map { "\($0.projectId)|\($0.blocker)" }
            .joined(separator: "\n")
        let blockerSignal = evaluateBlockerSignal(
            now: now,
            blockerCount: blockerCount,
            blockerFingerprint: blockerFingerprint
        )
        let focusActionURL = self.resolvedHeartbeatFocusActionURL(
            projects: projects,
            progressActions: progressActions,
            blockerProjects: blockerProjects,
            permissionSignals: permissionSignals,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSignals: governanceRepairSignals,
            queueSignals: queueSignals,
            hubLoadSignal: hubLoadSignal,
            now: now
        )
        let strategicStatusBlock = supervisorMemoryReadinessBriefTextLine()
            .map { "战略纠偏状态：\($0)\n" } ?? ""
        let projectMemoryAdvisorySummary = heartbeatProjectMemoryAdvisoryLines()
            .joined(separator: "\n")
        let voiceReadinessSummary = voiceReadinessSignal.map { heartbeatVoiceReadinessContentLine($0) } ?? ""
        let voiceReadinessCountLabel = voiceReadinessSignal.map {
            heartbeatVoiceReadinessCountLabel($0)
        } ?? "语音修复项"
        let voiceReadinessStateText = voiceReadinessSignal.map {
            heartbeatVoiceReadinessStateText($0)
        } ?? "无"
        let voiceReadinessSectionHeading = voiceReadinessSignal.map {
            heartbeatVoiceReadinessSectionTitle($0)
        } ?? "语音就绪："
        let governedReviewSummary = governedReviewSignal.map {
            heartbeatGovernedReviewContentLines($0).joined(separator: "\n")
        } ?? ""
        let recoveryFollowUpSummary = recoveryFollowUpSignal.map {
            [$0.summaryLine, $0.detailLine].joined(separator: "\n")
        } ?? ""
        let projectCreationSummary = projectCreationPresentation.map {
            heartbeatProjectCreationSummaryText($0)
        } ?? ""

        let content = """
🫀 Supervisor Heartbeat (\(time))
原因：\(reason)
项目总数：\(projects.count)
\(changed ? "变化：检测到项目状态更新" : "变化：无重大状态变化")
\(queueSignals.isEmpty ? "排队项目：0" : "排队项目：\(queueSignals.count)")
\(permissionSignals.isEmpty ? "待授权项目：0" : "待授权项目：\(permissionSignals.count)")
\(governedReviewSignal == nil ? "待治理审查项目：0" : "待治理审查项目：1")
\(governanceRepairSignals.isEmpty ? "待治理修复项目：0" : "待治理修复项目：\(governanceRepairSignals.count)")
\(voiceReadinessSignal == nil ? "语音修复项：0" : "\(voiceReadinessCountLabel)：1（\(voiceReadinessStateText)）")
\(strategicStatusBlock)\(laneHealthLine)

主动推进：
\(progressSummary.isEmpty ? "（本轮无需介入）" : progressSummary)

重点看板：
\(top)

排队态势：
\(queueSummary.isEmpty ? "（无）" : queueSummary)

权限申请：
\(permissionSummary.isEmpty ? "（无）" : permissionSummary)

Recovery 跟进：
\(recoveryFollowUpSummary.isEmpty ? "（无）" : recoveryFollowUpSummary)

治理审查：
\(governedReviewSummary.isEmpty ? "（无）" : governedReviewSummary)

治理修复：
\(governanceRepairSummary.isEmpty ? "（无）" : governanceRepairSummary)

项目创建：
\(projectCreationSummary.isEmpty ? "（无）" : projectCreationSummary)

\(voiceReadinessSectionHeading)
\(voiceReadinessSummary.isEmpty ? "（无）" : voiceReadinessSummary)

Hub 负载：
\(hubLoadSummary.isEmpty ? "（无）" : hubLoadSummary)

Project AI 记忆（advisory）：
\(projectMemoryAdvisorySummary.isEmpty ? "（无）" : projectMemoryAdvisorySummary)

Lane 健康巡检：
\(laneHealthLine)
\(laneHotspots.isEmpty ? "（无异常泳道）" : laneHotspots)

Coder 下一步建议：
\(nextStepSummary.isEmpty ? "（暂无）" : nextStepSummary)
"""

        recordHeartbeatEntry(
            reason: reason,
            projectCount: projects.count,
            changed: changed,
            content: content,
            focusActionURL: focusActionURL
        )
        pushHubHeartbeatNotification(
            timeText: time,
            reason: reason,
            projectCount: projects.count,
            changed: changed,
            blockerCount: blockerCount,
            blockerSignal: blockerSignal,
            focusActionURL: focusActionURL,
            topSummary: top,
            queueSummary: queueSummary,
            permissionSummary: permissionSummary,
            recoveryFollowUpSignal: recoveryFollowUpSignal,
            governedReviewSignal: governedReviewSignal,
            governanceRepairSummary: governanceRepairSummary,
            hubLoadSummary: hubLoadSummary,
            hubLoadSignal: hubLoadSignal,
            progressSummary: progressSummary,
            nextStepSummary: nextStepSummary,
            queuePendingCount: queueSignals.count,
            permissionPendingCount: permissionSignals.count,
            governanceRepairCount: governanceRepairSignals.count,
            routeAttentionSignal: routeAttentionSignal
        )
        speakSupervisorHeartbeatUpdate(
            reason: reason,
            changed: changed,
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
        recordHeartbeatRouteAttentionAlertIfNeeded(
            routeAttentionSignal,
            reason: reason,
            blockerCount: blockerCount,
            permissionCount: permissionSignals.count,
            queueCount: queueSignals.count,
            now: now
        )
        traceOutcome = "emitted projects=\(projects.count) changed=\(changed) queue=\(queueSignals.count) permission=\(permissionSignals.count)"
    }
}
