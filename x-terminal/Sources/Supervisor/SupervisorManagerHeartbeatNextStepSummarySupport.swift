import Foundation

extension SupervisorManager {
    func buildHeartbeatNextStepSummary(
        projects: [AXProjectEntry],
        queueSignals: [ProjectQueueSignal],
        permissionSignals: [ProjectPermissionSignal],
        recoveryFollowUpSignal: HeartbeatRecoveryFollowUpSignal?,
        governedReviewSignal: HeartbeatGovernedReviewSignal?,
        governanceRepairSignals: [ProjectGovernanceRepairSignal],
        hubLoadSignal: HeartbeatHubLoadSignal?,
        maxItems: Int,
        now: TimeInterval
    ) -> String {
        let maxCount = max(1, maxItems)
        let queueByProjectId = Dictionary(uniqueKeysWithValues: queueSignals.map { ($0.project.projectId, $0) })
        let orderedProjects = projects.sorted { p1, p2 in
            calculatePriority(p1) > calculatePriority(p2)
        }
        let voiceReadinessSignal = heartbeatVoiceReadinessSignal()

        var lines: [String] = []
        var includedProjectIds = Set<String>()
        var rank = 1

        for signal in permissionSignals {
            if lines.count >= maxCount { break }
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
            lines.append("\(rank). 先处理授权：\(signal.projectName) — \(capped(signal.summary, maxChars: 72))\(actionSuffix)")
            includedProjectIds.insert(signal.projectId)
            rank += 1
        }

        for signal in governanceRepairSignals {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(signal.projectId) { continue }
            let action = signal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
            lines.append("\(rank). 治理修复：\(signal.projectName) — \(capped(signal.summary, maxChars: 88))\(actionSuffix)")
            includedProjectIds.insert(signal.projectId)
            rank += 1
        }

        if let recoveryFollowUpSignal, lines.count < maxCount {
            lines.append("\(rank). \(heartbeatRecoveryFollowUpNextStepLine(recoveryFollowUpSignal))")
            includedProjectIds.insert(recoveryFollowUpSignal.projectId)
            rank += 1
        }

        if let governedReviewSignal, lines.count < maxCount,
           !includedProjectIds.contains(governedReviewSignal.projectId) {
            let action = governedReviewSignal.actionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let actionSuffix = action.isEmpty ? "" : "（打开：\(action)）"
            lines.append(
                "\(rank). 治理审查：\(governedReviewSignal.projectName) — 已排队\(heartbeatGovernedReviewLevelLabel(governedReviewSignal.reviewLevel))（\(heartbeatGovernedReviewRunKindLabel(governedReviewSignal.runKind)) · \(governedReviewSignal.causeLabel)）；建议先打开项目查看这次治理审查\(actionSuffix)"
            )
            includedProjectIds.insert(governedReviewSignal.projectId)
            rank += 1
        }

        if let voiceReadinessSignal, lines.count < maxCount {
            lines.append("\(rank). \(heartbeatVoiceReadinessNextStepLine(voiceReadinessSignal))")
            rank += 1
        }

        if let hubLoadSignal, lines.count < maxCount {
            lines.append("\(rank). \(heartbeatHubLoadNextStepLine(hubLoadSignal))")
            rank += 1
        }

        for queue in queueSignals {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(queue.project.projectId) { continue }
            let mins = max(1, Int(ceil(Double(queue.oldestQueuedMs) / 60_000.0)))
            lines.append("\(rank). 关注排队：\(queue.project.displayName) — 已排队 \(mins) 分钟，建议先清队列")
            includedProjectIds.insert(queue.project.projectId)
            rank += 1
        }

        let routeRepairAttentionItems = heartbeatRouteRepairAttentionItems(
            projects: orderedProjects,
            limit: maxCount
        )
        for item in routeRepairAttentionItems {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(item.projectId) { continue }
            lines.append("\(rank). \(heartbeatRouteRepairSummaryLine(item, now: now))")
            includedProjectIds.insert(item.projectId)
            rank += 1
        }

        let routeMemorySnapshot = heartbeatRouteMemorySnapshot()
        for project in orderedProjects {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(project.projectId) { continue }
            guard let routeNotice = AXProjectModelRouteMemoryStore.heartbeatNotice(
                for: project,
                snapshot: routeMemorySnapshot,
                paidAccessSnapshot: appModel?.hubRemotePaidAccessSnapshot
            ) else { continue }
            lines.append("\(rank). \(routeNotice)")
            includedProjectIds.insert(project.projectId)
            rank += 1
        }

        for project in orderedProjects {
            if lines.count >= maxCount { break }
            if includedProjectIds.contains(project.projectId) { continue }
            let next = (project.nextStepSummary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !next.isEmpty {
                lines.append("\(rank). 常规推进：\(project.displayName) — \(capped(next, maxChars: 72))")
            } else if let queue = queueByProjectId[project.projectId] {
                let mins = max(1, Int(ceil(Double(queue.oldestQueuedMs) / 60_000.0)))
                lines.append("\(rank). 常规推进：\(project.displayName) — 等待 Hub 排队（约 \(mins) 分钟）")
            } else {
                lines.append("\(rank). 常规推进：\(project.displayName) — 继续当前任务并在完成后同步摘要")
            }
            includedProjectIds.insert(project.projectId)
            rank += 1
        }

        return lines.joined(separator: "\n")
    }
}
