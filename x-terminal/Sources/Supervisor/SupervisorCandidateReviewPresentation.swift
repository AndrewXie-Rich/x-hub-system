import Foundation

struct SupervisorCandidateReviewRowPresentation: Equatable, Identifiable {
    var id: String
    var anchorID: String
    var title: String
    var ageText: String
    var summary: String
    var reviewStateText: String
    var scopeText: String?
    var draftText: String?
    var evidenceText: String
    var isFocused: Bool
    var isInFlight: Bool
    var actionDescriptors: [SupervisorCardActionDescriptor]
}

struct SupervisorCandidateReviewBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var snapshotText: String
    var freshnessWarningText: String?
    var footerNote: String?
    var emptyStateText: String?
    var rows: [SupervisorCandidateReviewRowPresentation]

    var isEmpty: Bool {
        rows.isEmpty
    }
}

enum SupervisorCandidateReviewPresentation {
    static func board(
        items: [HubIPCClient.SupervisorCandidateReviewItem],
        source: String,
        hasFreshSnapshot: Bool,
        updatedAt: TimeInterval,
        inFlightRequestIDs: Set<String>,
        hubInteractive: Bool,
        projectNamesByID: [String: String],
        focusedRowAnchor: String?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorCandidateReviewBoardPresentation {
        SupervisorCandidateReviewBoardPresentation(
            iconName: items.isEmpty ? "tray" : "square.stack.3d.up.badge.a.fill",
            iconTone: items.isEmpty ? .neutral : .accent,
            title: "Supervisor 候选记忆审查：\(items.count)",
            snapshotText: snapshotText(
                source: source,
                hasFreshSnapshot: hasFreshSnapshot,
                updatedAt: updatedAt,
                now: now
            ),
            freshnessWarningText: hasFreshSnapshot
                ? nil
                : "暂未拿到新鲜 candidate review 快照。",
            footerNote: items.isEmpty
                ? nil
                : "先把候选记忆转入审查，再决定是否推进 durable memory promotion。",
            emptyStateText: items.isEmpty ? "当前没有待转入审查的候选记忆。" : nil,
            rows: items.map {
                row(
                    $0,
                    inFlightRequestIDs: inFlightRequestIDs,
                    hubInteractive: hubInteractive,
                    projectNamesByID: projectNamesByID,
                    isFocused: focusedRowAnchor == SupervisorFocusPresentation.candidateReviewRowAnchor($0),
                    now: now
                )
            }
        )
    }

    static func row(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        inFlightRequestIDs: Set<String>,
        hubInteractive: Bool,
        projectNamesByID: [String: String],
        isFocused: Bool,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorCandidateReviewRowPresentation {
        let requestId = normalizedScalar(item.requestId)
        let inFlight = !requestId.isEmpty && inFlightRequestIDs.contains(requestId)
        let canAct = hubInteractive && !requestId.isEmpty
        let projectLabel = projectLabel(item, projectNamesByID: projectNamesByID)
        let summary = nonEmpty(item.summaryLine)
            ?? fallbackSummary(item)

        return SupervisorCandidateReviewRowPresentation(
            id: item.id,
            anchorID: SupervisorFocusPresentation.candidateReviewRowAnchor(item),
            title: "\(projectLabel) · \(max(0, item.candidateCount)) 条候选记忆",
            ageText: ageText(item, now: now),
            summary: summary,
            reviewStateText: "状态：\(stateText(item.reviewState))",
            scopeText: scopeText(item, projectNamesByID: projectNamesByID),
            draftText: draftText(item),
            evidenceText: evidenceText(item),
            isFocused: isFocused,
            isInFlight: inFlight,
            actionDescriptors: SupervisorCardActionResolver.candidateReviewActions(
                item,
                inFlight: inFlight,
                canAct: canAct
            )
        )
    }

    static func snapshotText(
        source: String,
        hasFreshSnapshot: Bool,
        updatedAt: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String {
        let sourceText = normalizedScalar(source).isEmpty ? "Hub" : normalizedScalar(source)
        let freshness = hasFreshSnapshot ? "快照新鲜" : "快照偏旧"
        guard updatedAt > 0 else {
            return "来源：\(sourceText) · \(freshness)"
        }
        return "来源：\(sourceText) · 更新 \(SupervisorEventLoopFeedPresentation.relativeTimeText(updatedAt, now: now)) · \(freshness)"
    }

    static func stateText(_ raw: String) -> String {
        switch normalizedScalar(raw).lowercased() {
        case "pending_review":
            return "待转入审查"
        case "staged":
            return "已转入审查"
        case "in_review":
            return "审查中"
        case "promoted":
            return "已提升"
        default:
            let normalized = normalizedScalar(raw)
            return normalized.isEmpty ? "未知" : normalized.replacingOccurrences(of: "_", with: " ")
        }
    }

    private static func projectLabel(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        projectNamesByID: [String: String]
    ) -> String {
        let ids = candidateProjectIDs(item)
        if ids.count == 1, let only = ids.first {
            let display = nonEmpty(projectNamesByID[only]) ?? only
            return display
        }
        if ids.count > 1 {
            return "\(ids.count) 个项目"
        }
        let scopes = item.scopes
            .map(normalizedScalar)
            .filter { !$0.isEmpty }
        if let first = scopes.first {
            return first
        }
        return "未绑定项目"
    }

    private static func scopeText(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        projectNamesByID: [String: String]
    ) -> String? {
        let ids = candidateProjectIDs(item)
        let projectLabels = ids.map { nonEmpty(projectNamesByID[$0]) ?? $0 }
        let scopeLabels = item.scopes
            .map(normalizedScalar)
            .filter { !$0.isEmpty }
        let recordTypes = item.recordTypes
            .map(normalizedScalar)
            .filter { !$0.isEmpty }
        let parts = [
            projectLabels.isEmpty ? nil : "项目：\(projectLabels.joined(separator: "、"))",
            scopeLabels.isEmpty ? nil : "scope：\(scopeLabels.joined(separator: ", "))",
            recordTypes.isEmpty ? nil : "records：\(recordTypes.joined(separator: ", "))"
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func draftText(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String? {
        let changeId = nonEmpty(item.pendingChangeId)
        let status = nonEmpty(item.pendingChangeStatus)
        guard changeId != nil || status != nil else { return nil }
        return [
            changeId.map { "draft：\($0)" },
            status.map { "status=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func evidenceText(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String {
        let requestId = nonEmpty(item.requestId) ?? item.id
        let evidenceRef = nonEmpty(item.evidenceRef)
        return [
            "handoff：\(requestId)",
            evidenceRef.map { "evidence=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }

    private static func ageText(
        _ item: HubIPCClient.SupervisorCandidateReviewItem,
        now: TimeInterval
    ) -> String {
        let createdAt = [item.latestEmittedAtMs, item.stageUpdatedAtMs, item.createdAtMs]
            .first(where: { $0 > 0 }) ?? 0
        guard createdAt > 0 else { return "待处理" }
        return SupervisorEventLoopFeedPresentation.relativeTimeText(createdAt / 1000.0, now: now)
    }

    private static func fallbackSummary(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> String {
        let recordTypes = item.recordTypes
            .map(normalizedScalar)
            .filter { !$0.isEmpty }
        let summaryCore = recordTypes.isEmpty
            ? "候选记忆已就绪，等待 Supervisor 审查。"
            : "候选记忆类型：\(recordTypes.joined(separator: ", "))。"
        let promotion = nonEmpty(item.durablePromotionState)
            ?? nonEmpty(item.promotionBoundary)
        guard let promotion else { return summaryCore }
        return "\(summaryCore) promotion=\(promotion)"
    }

    private static func candidateProjectIDs(
        _ item: HubIPCClient.SupervisorCandidateReviewItem
    ) -> [String] {
        var ids = [normalizedScalar(item.projectId)] + item.projectIds.map(normalizedScalar)
        ids = ids.filter { !$0.isEmpty }
        return Array(NSOrderedSet(array: ids)) as? [String] ?? ids
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ raw: String?) -> String? {
        let trimmed = normalizedScalar(raw ?? "")
        return trimmed.isEmpty ? nil : trimmed
    }
}
