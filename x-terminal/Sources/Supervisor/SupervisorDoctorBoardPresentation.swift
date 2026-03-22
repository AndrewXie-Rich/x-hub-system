import Foundation

struct SupervisorDoctorBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var statusLine: String
    var releaseBlockLine: String
    var memoryReadinessLine: String
    var memoryReadinessTone: SupervisorHeaderControlTone
    var memoryIssueSummaryLine: String?
    var memoryIssueDetailLine: String?
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
        assemblySnapshot: SupervisorMemoryAssemblySnapshot? = nil,
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
            memoryReadinessLine: memoryReadinessLine(memoryReadiness),
            memoryReadinessTone: readinessTone,
            memoryIssueSummaryLine: issueSummary.isEmpty ? nil : issueSummary,
            memoryIssueDetailLine: issueDetailLine,
            memoryContinuitySummaryLine: memoryContinuitySummaryLine(assemblySnapshot),
            memoryContinuityDetailLine: memoryContinuityDetailLine(assemblySnapshot),
            canonicalRetryStatusLine: canonicalRetryStatusLine(canonicalRetryFeedback),
            canonicalRetryTone: canonicalRetryFeedback?.tone ?? .neutral,
            canonicalRetryMetaLine: canonicalRetryMetaLine(canonicalRetryFeedback),
            canonicalRetryDetailLine: canonicalRetryDetailLine(canonicalRetryFeedback),
            emptyStateText: suggestionCards.isEmpty
                ? (doctorReport == nil
                    ? "尚未生成体检报告，运行一次预检后可查看修复建议卡片。"
                    : "未发现可执行修复项。")
                : nil,
            reportLine: trimmedReportPath.isEmpty ? nil : "最新体检报告已生成。"
        )
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
        _ snapshot: SupervisorMemoryAssemblySnapshot?
    ) -> String? {
        guard let snapshot else { return nil }

        var parts = ["来源：\(memorySourceLabel(snapshot.rawWindowSource))"]
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
        if let mirror = durableCandidateMirrorDoctorLabel(snapshot) {
            parts.append(mirror)
        }
        return parts.joined(separator: " · ")
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
            text += " · reason=\(error)"
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
        guard !scopeLabel.isEmpty else { return nil }
        return detailLabel.isEmpty ? scopeLabel : "\(scopeLabel)（\(detailLabel)）"
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
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "", "(none)":
            return "暂无"
        case "hub":
            return "Hub"
        case "hub_memory":
            return "Hub 记忆"
        case "local":
            return "本地"
        case "local_fallback":
            return "本地回退"
        case "mixed":
            return "混合上下文"
        case "xt_cache":
            return "本地对话缓存"
        default:
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "_", with: " ")
        }
    }
}
