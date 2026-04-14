import Foundation

struct SupervisorDoctorBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var releaseBlockLine: String
    var skillDoctorTruthStatusLine: String?
    var skillDoctorTruthTone: SupervisorHeaderControlTone
    var skillDoctorTruthDetailLine: String?
    var memoryReadinessLine: String
    var memoryReadinessTone: SupervisorHeaderControlTone
    var memoryIssueSummaryLine: String?
    var memoryIssueDetailLine: String?
    var projectMemoryAdvisoryLine: String?
    var projectMemoryAdvisoryTone: SupervisorHeaderControlTone
    var projectMemoryAdvisoryDetailLine: String?
    var memoryContinuitySummaryLine: String?
    var memoryContinuityDetailLine: String?
    var canonicalRetryStatusLine: String?
    var canonicalRetryTone: SupervisorHeaderControlTone
    var canonicalRetryMetaLine: String?
    var canonicalRetryDetailLine: String?
    var emptyStateText: String?
    var reportLine: String?
}

enum SupervisorDoctorBoardPresentationMapper {
    static func map(
        doctorStatusLine: String,
        doctorReport: SupervisorDoctorReport?,
        doctorHasBlockingFindings: Bool,
        releaseBlockedByDoctorWithoutReport: Int,
        memoryReadiness: SupervisorMemoryAssemblyReadiness,
        skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection? = nil,
        projectMemoryReadiness: XTProjectMemoryAssemblyReadiness? = nil,
        projectMemoryProjectLabel: String? = nil,
        assemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil,
        turnContextAssembly: SupervisorTurnContextAssemblyResult? = nil,
        canonicalRetryFeedback: SupervisorManager.CanonicalMemoryRetryFeedback?,
        suggestionCards: [SupervisorDoctorSuggestionCard],
        doctorReportPath: String
    ) -> SupervisorDoctorBoardPresentation {
        let icon: (String, SupervisorHeaderControlTone)
        if doctorReport == nil {
            icon = ("questionmark.shield", .neutral)
        } else if doctorHasBlockingFindings {
            icon = ("xmark.shield.fill", .danger)
        } else if (doctorReport?.summary.warningCount ?? 0) > 0 {
            icon = ("exclamationmark.shield.fill", .warning)
        } else {
            icon = ("checkmark.shield.fill", .success)
        }

        let readinessTone = SupervisorMemoryBoardPresentationMapper.readinessTone(memoryReadiness)
        let projectMemoryAdvisoryTone = projectMemoryAdvisoryTone(projectMemoryReadiness)
        let issueSummary = memoryReadiness.issues
            .prefix(2)
            .map(\.summary)
            .joined(separator: " · ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let issueDetailLine = memoryIssueDetailLine(memoryReadiness)
        let trimmedReportPath = doctorReportPath.trimmingCharacters(in: .whitespacesAndNewlines)

        return SupervisorDoctorBoardPresentation(
            iconName: icon.0,
            iconTone: icon.1,
            title: "Supervisor 体检",
            statusLine: doctorSummaryLine(
                rawStatusLine: doctorStatusLine,
                doctorReport: doctorReport,
                doctorHasBlockingFindings: doctorHasBlockingFindings
            ),
            releaseBlockLine: releaseBlockLine(
                releaseBlockedByDoctorWithoutReport: releaseBlockedByDoctorWithoutReport,
                doctorReport: doctorReport
            ),
            skillDoctorTruthStatusLine: skillDoctorTruthStatusLine(skillDoctorTruthProjection),
            skillDoctorTruthTone: skillDoctorTruthTone(skillDoctorTruthProjection),
            skillDoctorTruthDetailLine: skillDoctorTruthDetailLine(skillDoctorTruthProjection),
            memoryReadinessLine: memoryReadinessLine(memoryReadiness),
            memoryReadinessTone: readinessTone,
            memoryIssueSummaryLine: issueSummary.isEmpty ? nil : issueSummary,
            memoryIssueDetailLine: issueDetailLine,
            projectMemoryAdvisoryLine: projectMemoryAdvisoryLine(
                projectMemoryReadiness,
                projectLabel: projectMemoryProjectLabel
            ),
            projectMemoryAdvisoryTone: projectMemoryAdvisoryTone,
            projectMemoryAdvisoryDetailLine: projectMemoryAdvisoryDetailLine(projectMemoryReadiness),
            memoryContinuitySummaryLine: memoryContinuitySummaryLine(assemblySnapshot),
            memoryContinuityDetailLine: memoryContinuityDetailLine(
                assemblySnapshot,
                turnContextAssembly: turnContextAssembly
            ),
            canonicalRetryStatusLine: canonicalRetryStatusLine(canonicalRetryFeedback),
            canonicalRetryTone: canonicalRetryFeedback?.tone ?? .neutral,
            canonicalRetryMetaLine: canonicalRetryMetaLine(canonicalRetryFeedback),
            canonicalRetryDetailLine: canonicalRetryDetailLine(canonicalRetryFeedback),
            emptyStateText: emptyStateText(
                doctorReport: doctorReport,
                suggestionCards: suggestionCards,
                skillDoctorTruthProjection: skillDoctorTruthProjection
            ),
            reportLine: trimmedReportPath.isEmpty ? nil : "最新体检报告已生成。"
        )
    }

    private static func skillDoctorTruthTone(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> SupervisorHeaderControlTone {
        guard let projection else { return .neutral }
        if projection.blockedSkillCount > 0 {
            return .danger
        }
        if projection.grantRequiredSkillCount > 0 || projection.approvalRequiredSkillCount > 0 {
            return .warning
        }
        return .success
    }

    private static func skillDoctorTruthStatusLine(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> String? {
        guard let projection else { return nil }
        if projection.blockedSkillCount > 0 {
            return "技能 doctor truth：\(projection.blockedSkillCount) 个技能当前不可运行。"
        }
        if projection.grantRequiredSkillCount > 0 || projection.approvalRequiredSkillCount > 0 {
            return "技能 doctor truth：\(projection.grantRequiredSkillCount) 个待 Hub grant，\(projection.approvalRequiredSkillCount) 个待本地确认。"
        }
        return "技能 doctor truth：当前 typed capability / readiness 已就绪。"
    }

    private static func skillDoctorTruthDetailLine(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> String? {
        guard let projection else { return nil }

        let summary = XTDoctorSkillDoctorTruthPresentation.summary(projection: projection)
        let currentRunnable = doctorTruthSummaryLine("当前可直接运行", in: summary.lines)
        let grantRequired = doctorTruthSummaryLine("待 Hub grant", in: summary.lines)
        let localApproval = doctorTruthSummaryLine("待本地确认", in: summary.lines)
        let blocked = doctorTruthSummaryLine("当前阻塞", in: summary.lines)
        let capabilityBand = doctorTruthSummaryLine("能力分层", in: summary.lines)
        let skillCount = doctorTruthSummaryLine("技能计数", in: summary.lines)

        let parts: [String?]
        if projection.blockedSkillCount > 0 {
            parts = [currentRunnable, blocked, skillCount]
        } else if projection.grantRequiredSkillCount > 0 || projection.approvalRequiredSkillCount > 0 {
            parts = [currentRunnable, grantRequired, localApproval, skillCount]
        } else {
            parts = [currentRunnable, capabilityBand, skillCount]
        }

        let normalized = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return nil }
        return normalized.joined(separator: "；")
    }

    private static func doctorTruthSummaryLine(
        _ label: String,
        in lines: [String]
    ) -> String? {
        lines.first(where: { $0.hasPrefix("\(label)：") })?.nonEmptyDoctorBoardScalar
    }

    private static func emptyStateText(
        doctorReport: SupervisorDoctorReport?,
        suggestionCards: [SupervisorDoctorSuggestionCard],
        skillDoctorTruthProjection: XTUnifiedDoctorSkillDoctorTruthProjection?
    ) -> String? {
        guard suggestionCards.isEmpty else { return nil }
        guard doctorReport != nil else {
            return "尚未生成体检报告，运行一次预检后可查看修复建议卡片。"
        }
        if let skillDoctorTruthProjection,
           (
               skillDoctorTruthProjection.blockedSkillCount > 0
                || skillDoctorTruthProjection.grantRequiredSkillCount > 0
                || skillDoctorTruthProjection.approvalRequiredSkillCount > 0
           ) {
            let outstanding = skillDoctorTruthOutstandingLine(skillDoctorTruthProjection)
            return "当前没有通用 doctor 修复卡；先按技能 doctor truth 的\(outstanding)提示处理。"
        }
        return "未发现可执行修复项。"
    }

    private static func skillDoctorTruthOutstandingLine(
        _ projection: XTUnifiedDoctorSkillDoctorTruthProjection
    ) -> String {
        var parts: [String] = []
        if projection.blockedSkillCount > 0 {
            parts.append("阻塞")
        }
        if projection.grantRequiredSkillCount > 0 {
            parts.append("Hub grant")
        }
        if projection.approvalRequiredSkillCount > 0 {
            parts.append("本地确认")
        }
        guard !parts.isEmpty else { return "能力" }
        return parts.joined(separator: " / ")
    }

    private static func memoryIssueDetailLine(
        _ memoryReadiness: SupervisorMemoryAssemblyReadiness
    ) -> String? {
        guard let issue = memoryReadiness.issues.first(where: {
            $0.code == "memory_canonical_sync_delivery_failed"
        }) else {
            return nil
        }

        let detailLines = issue.detail
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !detailLines.isEmpty else { return nil }

        let summaries = detailLines.prefix(2).compactMap(canonicalSyncIssueLineSummary)
        guard !summaries.isEmpty else { return nil }
        return "最近 canonical memory 同步失败：\(summaries.joined(separator: "；"))。"
    }

    private static func doctorSummaryLine(
        rawStatusLine: String,
        doctorReport: SupervisorDoctorReport?,
        doctorHasBlockingFindings: Bool
    ) -> String {
        if doctorReport == nil {
            return "尚未生成体检报告"
        }
        if doctorHasBlockingFindings {
            return "体检发现阻塞项"
        }
        if (doctorReport?.summary.warningCount ?? 0) > 0 {
            return "体检已通过，但仍有提醒"
        }
        if rawStatusLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "体检检查通过"
        }
        return "体检检查通过"
    }

    private static func releaseBlockLine(
        releaseBlockedByDoctorWithoutReport: Int,
        doctorReport: SupervisorDoctorReport?
    ) -> String {
        if releaseBlockedByDoctorWithoutReport > 0 {
            return "当前缺少体检报告，发布级检查仍会拦住。"
        }
        if doctorReport == nil {
            return "还没到发布门，但建议先跑一次体检。"
        }
        return "发布级体检门已满足。"
    }

    private static func memoryReadinessLine(
        _ memoryReadiness: SupervisorMemoryAssemblyReadiness
    ) -> String {
        if memoryReadiness.ready {
            return "战略复盘所需记忆已就绪。"
        }
        return "战略复盘还缺 \(memoryReadiness.issues.count) 项关键记忆。"
    }

    private static func projectMemoryAdvisoryTone(
        _ readiness: XTProjectMemoryAssemblyReadiness?
    ) -> SupervisorHeaderControlTone {
        guard let readiness else { return .neutral }
        if readiness.ready {
            return .success
        }
        if readiness.issues.contains(where: { $0.severity == .blocking }) {
            return .danger
        }
        return .warning
    }

    private static func projectMemoryAdvisoryLine(
        _ readiness: XTProjectMemoryAssemblyReadiness?,
        projectLabel: String?
    ) -> String? {
        guard let readiness else { return nil }
        let scope = projectLabel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmptyDoctorBoardScalar ?? "当前 Project AI"
        if readiness.ready {
            return "Project AI memory（advisory）：\(scope) 当前就绪。"
        }
        return "Project AI memory（advisory）：\(scope) 当前需关注。"
    }

    private static func projectMemoryAdvisoryDetailLine(
        _ readiness: XTProjectMemoryAssemblyReadiness?
    ) -> String? {
        guard let readiness else { return nil }

        var parts: [String] = []
        let normalizedStatus = readiness.statusLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedStatus.isEmpty {
            parts.append("状态 \(normalizedStatus)")
        }
        if !readiness.issueCodes.isEmpty {
            parts.append(
                "问题 "
                    + readiness.issueCodes
                        .map(XTDoctorProjectMemoryReadinessPresentation.projectMemoryIssueText)
                        .joined(separator: "、")
            )
        }
        if let topIssue = readiness.topIssue {
            let summary = topIssue.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            if !summary.isEmpty {
                parts.append("重点 \(summary)")
            }
        }

        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func memoryContinuitySummaryLine(
        _ snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> String? {
        guard let snapshot else { return nil }
        let floorText = snapshot.continuityFloorSatisfied
            ? "已满足至少 \(snapshot.rawWindowFloorPairs) 组底线"
            : "还未满足至少 \(snapshot.rawWindowFloorPairs) 组底线"
        return "最近连续对话保留 \(snapshot.rawWindowSelectedPairs) 组，\(floorText)。"
    }

    private static func memoryContinuityDetailLine(
        _ snapshot: SupervisorMemoryAssemblySnapshot?,
        turnContextAssembly: SupervisorTurnContextAssemblyResult?
    ) -> String? {
        guard snapshot != nil || turnContextAssembly != nil else { return nil }

        var parts: [String] = []
        if let snapshot {
            parts = ["来源：\(explainableMemorySourceLabel(snapshot.rawWindowSource))"]
            parts.append("背景分区 \(snapshot.selectedSections.count) 个")
            if snapshot.contextRefsSelected > 0 {
                parts.append("关联引用 \(snapshot.contextRefsSelected) 条")
            }
            if snapshot.evidenceItemsSelected > 0 {
                parts.append("执行证据 \(snapshot.evidenceItemsSelected) 条")
            }
            if snapshot.lowSignalDroppedMessages > 0 {
                parts.append("过滤低信号 \(snapshot.lowSignalDroppedMessages) 条")
            }
            if snapshot.rollingDigestPresent {
                parts.append("已保留滚动摘要")
            }
            if let scopedPromptRecoveryHumanLine = snapshot.scopedPromptRecoveryHumanLine {
                parts.append(scopedPromptRecoveryHumanLine)
            }
            if let remotePromptBudgetHumanLine = snapshot.remotePromptBudgetHumanLine {
                parts.append(remotePromptBudgetHumanLine)
            }
            if let actualizedSelectedServingObjectHumanLine = snapshot.actualizedSelectedServingObjectHumanLine {
                parts.append(actualizedSelectedServingObjectHumanLine)
            }
            if let actualizedExcludedBlockHumanLine = snapshot.actualizedExcludedBlockHumanLine {
                parts.append(actualizedExcludedBlockHumanLine)
            }
            if let mirror = durableCandidateMirrorDoctorLabel(snapshot) {
                parts.append(mirror)
            }
        }
        if let turnContextLine = turnContextDoctorLabel(turnContextAssembly) {
            parts.append(turnContextLine)
        }
        return parts.joined(separator: " · ")
    }

    private static func turnContextDoctorLabel(
        _ assembly: SupervisorTurnContextAssemblyResult?
    ) -> String? {
        guard let assembly else { return nil }
        var parts = [
            "装配重心：\(turnContextPlaneLabel(assembly.dominantPlane))",
            "装配深度：连续对话 \(turnContextDepthLabel(assembly.continuityLaneDepth)) · 个人 \(turnContextDepthLabel(assembly.assistantPlaneDepth)) · 项目 \(turnContextDepthLabel(assembly.projectPlaneDepth)) · 关联 \(turnContextDepthLabel(assembly.crossLinkPlaneDepth))"
        ]
        if !assembly.selectedSlots.isEmpty {
            parts.append("已带入：\(assembly.selectedSlots.map(turnContextSlotLabel).joined(separator: "、"))")
        }
        if !assembly.omittedSlots.isEmpty {
            parts.append("请求未满足：\(assembly.omittedSlots.map(turnContextSlotLabel).joined(separator: "、"))")
        }
        return parts.joined(separator: " · ")
    }

    private static func turnContextPlaneLabel(_ raw: String) -> String {
        switch raw {
        case "assistant_plane":
            return "个人背景主导"
        case "project_plane":
            return "项目背景主导"
        case "assistant_plane + project_plane":
            return "个人与项目背景并重"
        case "project_plane(portfolio_brief)":
            return "项目总览主导"
        case "cross_link_plane":
            return "关联线索主导"
        case "portfolio_brief":
            return "项目总览主导"
        case "continuity_lane":
            return "连续对话主导"
        default:
            return XTMemorySourceTruthPresentation.humanizeToken(raw)
        }
    }

    private static func turnContextDepthLabel(
        _ depth: SupervisorTurnContextPlaneDepth
    ) -> String {
        switch depth {
        case .off:
            return "关闭"
        case .onDemand:
            return "按需"
        case .light:
            return "轻量"
        case .medium:
            return "中等"
        case .full:
            return "完整"
        case .selected:
            return "精选"
        case .portfolioFirst:
            return "总览优先"
        }
    }

    private static func turnContextSlotLabel(
        _ slot: SupervisorTurnContextSlot
    ) -> String {
        switch slot {
        case .dialogueWindow:
            return "最近对话"
        case .personalCapsule:
            return "个人摘要"
        case .focusedProjectCapsule:
            return "当前项目摘要"
        case .portfolioBrief:
            return "项目总览"
        case .crossLinkRefs:
            return "关联线索"
        case .evidencePack:
            return "执行证据"
        }
    }

    private static func durableCandidateMirrorDoctorLabel(
        _ snapshot: SupervisorMemoryAssemblySnapshot
    ) -> String? {
        guard snapshot.durableCandidateMirrorAttempted
                || snapshot.durableCandidateMirrorStatus != .notNeeded else {
            return nil
        }

        var text = "Hub candidate mirror：\(durableCandidateMirrorStatusLabel(snapshot.durableCandidateMirrorStatus))"
        if let target = snapshot.durableCandidateMirrorTarget?.trimmingCharacters(in: .whitespacesAndNewlines),
           !target.isEmpty {
            text += "（\(durableCandidateMirrorTargetLabel(target))）"
        }
        if let error = snapshot.durableCandidateMirrorErrorCode?.trimmingCharacters(in: .whitespacesAndNewlines),
           !error.isEmpty,
           snapshot.durableCandidateMirrorStatus != .mirroredToHub {
            text += " · mirror reason：\(durableCandidateMirrorReasonText(error))"
        }
        return text
    }

    private static func durableCandidateMirrorStatusLabel(
        _ status: SupervisorDurableCandidateMirrorStatus
    ) -> String {
        switch status {
        case .notNeeded:
            return "不需要镜像"
        case .pending:
            return "镜像排队中"
        case .mirroredToHub:
            return "已镜像到 Hub"
        case .localOnly:
            return "仅保留本地 fallback"
        case .hubMirrorFailed:
            return "Hub 镜像失败"
        }
    }

    private static func durableCandidateMirrorTargetLabel(_ raw: String) -> String {
        switch raw {
        case XTSupervisorDurableCandidateMirror.mirrorTarget:
            return "Hub candidate carrier"
        default:
            return raw
        }
    }

    private static func canonicalRetryStatusLine(
        _ feedback: SupervisorManager.CanonicalMemoryRetryFeedback?
    ) -> String? {
        guard let line = feedback?.statusLine.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else { return nil }
        if line.contains("dispatching") {
            return "正在重试 canonical memory 同步。"
        }
        if line.contains("partial") {
            return "canonical memory 已部分同步，仍有失败或等待项。"
        }
        if line.contains("failed") {
            return "canonical memory 重试失败。"
        }
        if line.contains("pending") {
            return "canonical memory 仍在等待同步结果。"
        }
        if line.contains("ok") {
            return "canonical memory 已重试成功。"
        }
        return "canonical memory 同步状态已更新。"
    }

    private static func canonicalRetryMetaLine(
        _ feedback: SupervisorManager.CanonicalMemoryRetryFeedback?
    ) -> String? {
        guard let line = feedback?.metaLine?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !line.isEmpty else { return nil }

        let parts = line
            .components(separatedBy: "·")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .compactMap { part -> String? in
                if part.hasPrefix("attempt:") {
                    return "发起时间：\(part.replacingOccurrences(of: "attempt:", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))"
                }
                if part.hasPrefix("last_status:") {
                    return "最新状态：\(part.replacingOccurrences(of: "last_status:", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines))"
                }
                return nil
            }
        let merged = parts.joined(separator: " · ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func canonicalRetryDetailLine(
        _ feedback: SupervisorManager.CanonicalMemoryRetryFeedback?
    ) -> String? {
        guard let line = feedback?.detailLine?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
              !line.isEmpty else { return nil }

        let groups = line
            .components(separatedBy: "||")
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { group -> String? in
                if group.hasPrefix("ok:") {
                    let payload = group.replacingOccurrences(of: "ok:", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    return "已同步：\(scopeListLabel(payload))"
                }
                if group.hasPrefix("pending:") {
                    let payload = group.replacingOccurrences(of: "pending:", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    return "仍在等待：\(scopeListLabel(payload))"
                }
                if group.hasPrefix("failed:") {
                    let payload = group.replacingOccurrences(of: "failed:", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    return "失败：\(failedScopeListLabel(payload))"
                }
                return nil
            }

        let merged = groups.joined(separator: " · ").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return merged.isEmpty ? nil : merged
    }

    private static func canonicalSyncIssueLineSummary(_ line: String) -> String? {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let scope = tokenValue("scope", in: normalized) ?? ""
        let scopeId = tokenValue("scope_id", in: normalized) ?? ""
        let detail = tailValue("detail", in: normalized) ?? tokenValue("reason", in: normalized) ?? ""
        let scopeLabel = scopeLabel(scope: scope, scopeId: scopeId)
        let detailLabel = canonicalErrorDetailLabel(detail)
        let closureLabel = canonicalSyncClosureRefLabel(normalized)
        guard !scopeLabel.isEmpty else { return nil }
        let summaryLabel = detailLabel.isEmpty ? scopeLabel : "\(scopeLabel)（\(detailLabel)）"
        guard let closureLabel else { return summaryLabel }
        return "\(summaryLabel) [\(closureLabel)]"
    }

    private static func scopeListLabel(_ raw: String) -> String {
        let labels = raw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map(singleScopeLabel)
        return labels.isEmpty ? "暂无" : labels.joined(separator: "、")
    }

    private static func failedScopeListLabel(_ raw: String) -> String {
        let labels = raw
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { item -> String in
                let scopeToken = item.components(separatedBy: " reason=").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? item
                let detailToken = item.components(separatedBy: " detail=").dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let scope = singleScopeLabel(scopeToken)
                let detail = canonicalErrorDetailLabel(detailToken)
                return detail.isEmpty ? scope : "\(scope)（\(detail)）"
            }
        return labels.isEmpty ? "暂无" : labels.joined(separator: "、")
    }

    private static func singleScopeLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "暂无" }

        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return trimmed }
        let kind = parts[0]
        let rest = parts[1]
        if let open = rest.firstIndex(of: "("),
           let close = rest.lastIndex(of: ")"),
           open < close {
            let display = String(rest[rest.index(after: open)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !display.isEmpty {
                return scopeLabel(scope: kind, scopeId: display)
            }
        }
        return scopeLabel(scope: kind, scopeId: rest)
    }

    private static func scopeLabel(scope: String, scopeId: String) -> String {
        let trimmedId = scopeId.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scope {
        case "device":
            return trimmedId.isEmpty ? "设备记忆" : "设备 \(trimmedId)"
        case "project":
            return trimmedId.isEmpty ? "项目记忆" : "项目 \(trimmedId)"
        default:
            return trimmedId.isEmpty ? scope : "\(scope) \(trimmedId)"
        }
    }

    private static func canonicalErrorDetailLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let range = trimmed.range(of: "NSError:") {
            return String(trimmed[range.lowerBound...]).replacingOccurrences(of: "NSError:", with: "")
        }
        if let lastEquals = trimmed.lastIndex(of: "=") {
            let tail = trimmed[trimmed.index(after: lastEquals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty {
                return tail
            }
        }
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }

    private static func tokenValue(_ key: String, in line: String) -> String? {
        let prefix = "\(key)="
        guard let range = line.range(of: prefix) else { return nil }
        let tail = line[range.upperBound...]
        let value = tail.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func tailValue(_ key: String, in line: String) -> String? {
        let prefix = "\(key)="
        guard let range = line.range(of: prefix) else { return nil }
        let value = String(line[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func memorySourceLabel(_ raw: String) -> String {
        XTMemorySourceTruthPresentation.label(raw)
    }

    private static func explainableMemorySourceLabel(_ raw: String) -> String {
        XTMemorySourceTruthPresentation.explainableLabel(raw)
    }

    private static func canonicalSyncClosureRefLabel(_ line: String) -> String? {
        let labels = [
            tokenValue("audit_ref", in: line).map { "audit_ref=\($0)" },
            tokenValue("evidence_ref", in: line).map { "evidence_ref=\($0)" },
            tokenValue("writeback_ref", in: line).map { "writeback_ref=\($0)" }
        ]
        .compactMap { $0 }
        return labels.isEmpty ? nil : labels.joined(separator: " · ")
    }

    private static func durableCandidateMirrorReasonText(_ raw: String) -> String {
        switch normalizedMirrorReasonToken(raw) {
        case "remote_route_not_preferred":
            return "当前远端路由不是首选（remote_route_not_preferred）"
        case "runtime_not_running":
            return "Hub 远端运行时未启动（runtime_not_running）"
        case "hub_append_failed":
            return "Hub append 未成功完成（hub_append_failed）"
        case "candidate_payload_empty":
            return "候选负载为空，Hub 无法接收（candidate_payload_empty）"
        case "supervisor_candidate_session_participation_invalid":
            return "candidate session participation 非法（supervisor_candidate_session_participation_invalid）"
        case "supervisor_candidate_session_participation_denied":
            return "candidate 不允许进入 scoped_write 会话（supervisor_candidate_session_participation_denied）"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func normalizedMirrorReasonToken(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}

private extension String {
    var nonEmptyDoctorBoardScalar: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
