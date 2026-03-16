import Foundation

struct XTUIReviewCheckPresentation: Equatable {
    let code: String
    let status: XTUIReviewCheckStatus
    let detail: String

    var statusLabel: String {
        switch status {
        case .pass:
            return "通过"
        case .warning:
            return "关注"
        case .fail:
            return "失败"
        case .notApplicable:
            return "不适用"
        }
    }

    var codeLabel: String {
        friendlyIssueLabel(code)
    }
}

struct XTUIReviewHistoryItemPresentation: Equatable {
    let reviewID: String
    let reviewRef: String
    let bundleRef: String
    let verdict: XTUIReviewVerdict
    let confidence: XTUIReviewConfidence
    let objectiveReady: Bool
    let issueCodes: [String]
    let summary: String
    let updatedAtMs: Int64
    let interactiveTargetCount: Int
    let criticalActionExpected: Bool
    let criticalActionVisible: Bool
    let reviewFileURL: URL?
    let bundleFileURL: URL?
    let screenshotFileURL: URL?
    let visibleTextFileURL: URL?

    var verdictLabel: String {
        switch verdict {
        case .ready:
            return "可行动"
        case .attentionNeeded:
            return "需关注"
        case .insufficientEvidence:
            return "证据不足"
        }
    }

    func relativeUpdatedText(now: Date = Date()) -> String {
        let nowMs = Int64((now.timeIntervalSince1970 * 1_000.0).rounded())
        let deltaSec = max(0, Int((nowMs - updatedAtMs) / 1_000))
        if deltaSec < 60 {
            return "刚刚"
        }
        if deltaSec < 3_600 {
            return "\(max(1, deltaSec / 60))分钟前"
        }
        if deltaSec < 86_400 {
            return "\(max(1, deltaSec / 3_600))小时前"
        }
        return "\(max(1, deltaSec / 86_400))天前"
    }

    var issueLabels: [String] {
        let cleaned = issueCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return ["核心检查通过"]
        }
        return cleaned.map(friendlyIssueLabel)
    }

    var issueSummary: String {
        issueLabels.joined(separator: " · ")
    }

    var hasAnyOpenableArtifact: Bool {
        reviewFileURL != nil || bundleFileURL != nil || screenshotFileURL != nil || visibleTextFileURL != nil
    }
}

enum XTUIReviewTrendStatus: Equatable {
    case improved
    case stable
    case regressed
}

struct XTUIReviewTrendPresentation: Equatable {
    let status: XTUIReviewTrendStatus
    let headline: String
    let detail: String
}

enum XTUIReviewDiffTone: Equatable {
    case improved
    case stable
    case regressed
}

struct XTUIReviewDiffMetricPresentation: Equatable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let tone: XTUIReviewDiffTone
}

struct XTUIReviewDiffPresentation: Equatable {
    let addedIssueLabels: [String]
    let resolvedIssueLabels: [String]
    let metrics: [XTUIReviewDiffMetricPresentation]

    var isEmpty: Bool {
        addedIssueLabels.isEmpty && resolvedIssueLabels.isEmpty && metrics.isEmpty
    }
}

protocol XTUIReviewTrendComparable {
    var verdict: XTUIReviewVerdict { get }
    var objectiveReady: Bool { get }
    var issueCodes: [String] { get }
    var interactiveTargetCount: Int { get }
    var criticalActionExpected: Bool { get }
    var criticalActionVisible: Bool { get }
}

struct XTUIReviewPresentation: Equatable {
    let reviewRef: String
    let bundleRef: String
    let verdict: XTUIReviewVerdict
    let confidence: XTUIReviewConfidence
    let sufficientEvidence: Bool
    let objectiveReady: Bool
    let issueCodes: [String]
    let summary: String
    let updatedAtMs: Int64
    let interactiveTargetCount: Int
    let criticalActionExpected: Bool
    let criticalActionVisible: Bool
    let checks: [XTUIReviewCheckPresentation]
    let reviewFileURL: URL?
    let bundleFileURL: URL?
    let screenshotFileURL: URL?
    let visibleTextFileURL: URL?
    let recentHistory: [XTUIReviewHistoryItemPresentation]
    let trend: XTUIReviewTrendPresentation?
    let comparison: XTUIReviewDiffPresentation?

    var verdictLabel: String {
        switch verdict {
        case .ready:
            return "可行动"
        case .attentionNeeded:
            return "需关注"
        case .insufficientEvidence:
            return "证据不足"
        }
    }

    var confidenceLabel: String {
        switch confidence {
        case .high:
            return "高"
        case .medium:
            return "中"
        case .low:
            return "低"
        }
    }

    var evidenceLabel: String {
        sufficientEvidence ? "证据充分" : "证据不足"
    }

    var objectiveLabel: String {
        objectiveReady ? "可直接用于执行" : "暂不建议直接执行"
    }

    var issueLabels: [String] {
        let cleaned = issueCodes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else {
            return ["核心检查通过"]
        }
        return cleaned.map(friendlyIssueLabel)
    }

    var issueSummary: String {
        issueLabels.joined(separator: " · ")
    }

    var compactStatusText: String {
        "UI review · \(verdictLabel) · \(issueSummary)"
    }

    var hasAnyOpenableArtifact: Bool {
        reviewFileURL != nil || bundleFileURL != nil || screenshotFileURL != nil || visibleTextFileURL != nil
    }

    var interactiveTargetSummary: String {
        interactiveTargetCount > 0
            ? "识别到 \(interactiveTargetCount) 个可交互目标"
            : "未识别可交互目标"
    }

    var criticalActionSummary: String {
        guard criticalActionExpected else {
            return "当前页面无需关键动作检查"
        }
        return criticalActionVisible ? "关键动作可见" : "关键动作缺失"
    }

    func relativeUpdatedText(now: Date = Date()) -> String {
        let nowMs = Int64((now.timeIntervalSince1970 * 1_000.0).rounded())
        let deltaSec = max(0, Int((nowMs - updatedAtMs) / 1_000))
        if deltaSec < 60 {
            return "刚刚"
        }
        if deltaSec < 3_600 {
            return "\(max(1, deltaSec / 60))分钟前"
        }
        if deltaSec < 86_400 {
            return "\(max(1, deltaSec / 3_600))小时前"
        }
        return "\(max(1, deltaSec / 86_400))天前"
    }

    var absoluteUpdatedText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: Double(updatedAtMs) / 1_000.0))
    }

    var updatedText: String {
        "\(absoluteUpdatedText) · \(relativeUpdatedText())"
    }

    static func loadHistory(
        for ctx: AXProjectContext,
        limit: Int = 20
    ) -> [XTUIReviewHistoryItemPresentation] {
        XTUIReviewStore.loadRecentBrowserPageReviews(for: ctx, limit: max(1, limit))
            .map { historyItem(from: $0, ctx: ctx) }
    }

    static func loadLatestBrowserPage(for ctx: AXProjectContext) -> XTUIReviewPresentation? {
        guard let latest = XTUIReviewStore.loadLatestBrowserPageReference(for: ctx) else {
            return nil
        }
        let review = XTUIReviewStore.loadLatestBrowserPageReview(for: ctx)
        let bundle = XTUIObservationStore.loadBundle(ref: latest.bundleRef, for: ctx)
        let recentHistory = loadHistory(for: ctx, limit: 4)
            .filter { $0.reviewID != latest.reviewID }
            .prefix(3)
            .map { $0 }
        let trend: XTUIReviewTrendPresentation?
        let comparison: XTUIReviewDiffPresentation?
        if let currentReview = review,
           let previous = XTUIReviewStore.loadRecentBrowserPageReviews(for: ctx, limit: 4)
            .first(where: { $0.review.reviewID != latest.reviewID }) {
            trend = XTUIReviewTrendPresentation.compare(
                latest: currentReview,
                previous: previous.review
            )
            comparison = XTUIReviewDiffPresentation.compare(
                latest: currentReview,
                previous: previous.review
            )
        } else {
            trend = nil
            comparison = nil
        }
        return XTUIReviewPresentation(
            reviewRef: latest.reviewRef,
            bundleRef: latest.bundleRef,
            verdict: latest.verdict,
            confidence: latest.confidence,
            sufficientEvidence: latest.sufficientEvidence,
            objectiveReady: latest.objectiveReady,
            issueCodes: latest.issueCodes,
            summary: latest.summary,
            updatedAtMs: latest.updatedAtMs,
            interactiveTargetCount: review?.interactiveTargetCount ?? 0,
            criticalActionExpected: review?.criticalActionExpected ?? false,
            criticalActionVisible: review?.criticalActionVisible ?? false,
            checks: review?.checks.map {
                XTUIReviewCheckPresentation(code: $0.code, status: $0.status, detail: $0.detail)
            } ?? [],
            reviewFileURL: latest.reviewRef.isEmpty ? nil : XTUIObservationStore.resolveLocalRef(latest.reviewRef, for: ctx),
            bundleFileURL: latest.bundleRef.isEmpty ? nil : XTUIObservationStore.resolveLocalRef(latest.bundleRef, for: ctx),
            screenshotFileURL: bundle.flatMap { resolvedExistingURL(for: $0.pixelLayer.fullRef, ctx: ctx) },
            visibleTextFileURL: bundle.flatMap { resolvedExistingURL(for: $0.textLayer.visibleTextRef, ctx: ctx) },
            recentHistory: recentHistory,
            trend: trend,
            comparison: comparison
        )
    }
}

extension XTUIReviewHistoryItemPresentation: XTUIReviewTrendComparable {}
extension XTUIReviewPresentation: XTUIReviewTrendComparable {}

extension XTUIReviewRecord: XTUIReviewTrendComparable {}

extension XTUIReviewTrendPresentation {
    static func compare<Latest: XTUIReviewTrendComparable, Previous: XTUIReviewTrendComparable>(
        latest: Latest,
        previous: Previous
    ) -> XTUIReviewTrendPresentation {
        let latestScore = trendScore(for: latest)
        let previousScore = trendScore(for: previous)
        let status: XTUIReviewTrendStatus
        if latestScore < previousScore {
            status = .improved
        } else if latestScore > previousScore {
            status = .regressed
        } else {
            status = .stable
        }

        let headline: String
        switch status {
        case .improved:
            headline = "较上次改善"
        case .stable:
            headline = "与上次基本一致"
        case .regressed:
            headline = "较上次退化"
        }

        var parts: [String] = []
        parts.append("结论 \(previous.verdict.rawValue) -> \(latest.verdict.rawValue)")
        parts.append("问题数 \(previous.issueCodes.count) -> \(latest.issueCodes.count)")
        if previous.interactiveTargetCount != latest.interactiveTargetCount {
            parts.append("可交互目标 \(previous.interactiveTargetCount) -> \(latest.interactiveTargetCount)")
        }
        let previousCritical = criticalActionLabel(expected: previous.criticalActionExpected, visible: previous.criticalActionVisible)
        let latestCritical = criticalActionLabel(expected: latest.criticalActionExpected, visible: latest.criticalActionVisible)
        if previousCritical != latestCritical {
            parts.append("关键动作 \(previousCritical) -> \(latestCritical)")
        }
        if previous.objectiveReady != latest.objectiveReady {
            parts.append("可执行 \(previous.objectiveReady) -> \(latest.objectiveReady)")
        }

        return XTUIReviewTrendPresentation(
            status: status,
            headline: headline,
            detail: parts.joined(separator: " · ")
        )
    }
}

extension XTUIReviewDiffPresentation {
    static func compare<Latest: XTUIReviewTrendComparable, Previous: XTUIReviewTrendComparable>(
        latest: Latest,
        previous: Previous
    ) -> XTUIReviewDiffPresentation {
        let latestIssueCodes = normalizedIssueCodes(latest.issueCodes)
        let previousIssueCodes = normalizedIssueCodes(previous.issueCodes)
        let latestIssueSet = Set(latestIssueCodes)
        let previousIssueSet = Set(previousIssueCodes)

        let addedIssueLabels = latestIssueCodes
            .filter { !previousIssueSet.contains($0) }
            .map(friendlyIssueLabel)
        let resolvedIssueLabels = previousIssueCodes
            .filter { !latestIssueSet.contains($0) }
            .map(friendlyIssueLabel)

        var metrics: [XTUIReviewDiffMetricPresentation] = []

        if previous.verdict != latest.verdict {
            metrics.append(
                XTUIReviewDiffMetricPresentation(
                    id: "verdict",
                    label: "结论",
                    detail: "\(friendlyVerdictLabel(previous.verdict)) -> \(friendlyVerdictLabel(latest.verdict))",
                    tone: deltaTone(oldScore: verdictScore(previous.verdict), newScore: verdictScore(latest.verdict))
                )
            )
        }

        if previous.objectiveReady != latest.objectiveReady {
            metrics.append(
                XTUIReviewDiffMetricPresentation(
                    id: "objective_ready",
                    label: "可执行性",
                    detail: previous.objectiveReady
                        ? "由可直接执行变为暂不建议直接执行"
                        : "由暂不建议直接执行变为可直接执行",
                    tone: deltaTone(oldScore: previous.objectiveReady ? 0 : 1, newScore: latest.objectiveReady ? 0 : 1)
                )
            )
        }

        if previous.interactiveTargetCount != latest.interactiveTargetCount {
            let delta = latest.interactiveTargetCount - previous.interactiveTargetCount
            metrics.append(
                XTUIReviewDiffMetricPresentation(
                    id: "interactive_target_count",
                    label: "交互目标",
                    detail: "\(previous.interactiveTargetCount) -> \(latest.interactiveTargetCount) (\(signedDelta(delta)))",
                    tone: delta > 0 ? .improved : .regressed
                )
            )
        }

        let previousCritical = criticalActionState(expected: previous.criticalActionExpected, visible: previous.criticalActionVisible)
        let latestCritical = criticalActionState(expected: latest.criticalActionExpected, visible: latest.criticalActionVisible)
        if previousCritical != latestCritical {
            metrics.append(
                XTUIReviewDiffMetricPresentation(
                    id: "critical_action",
                    label: "关键动作",
                    detail: "\(previousCritical.label) -> \(latestCritical.label)",
                    tone: deltaTone(oldScore: previousCritical.score, newScore: latestCritical.score)
                )
            )
        }

        return XTUIReviewDiffPresentation(
            addedIssueLabels: addedIssueLabels,
            resolvedIssueLabels: resolvedIssueLabels,
            metrics: metrics
        )
    }
}

private func historyItem(
    from item: XTUIReviewStoredRecord,
    ctx: AXProjectContext
) -> XTUIReviewHistoryItemPresentation {
    let bundle = XTUIObservationStore.loadBundle(ref: item.review.bundleRef, for: ctx)
    return XTUIReviewHistoryItemPresentation(
        reviewID: item.review.reviewID,
        reviewRef: item.reviewRef,
        bundleRef: item.review.bundleRef,
        verdict: item.review.verdict,
        confidence: item.review.confidence,
        objectiveReady: item.review.objectiveReady,
        issueCodes: item.review.issueCodes,
        summary: item.review.summary,
        updatedAtMs: item.review.createdAtMs,
        interactiveTargetCount: item.review.interactiveTargetCount,
        criticalActionExpected: item.review.criticalActionExpected,
        criticalActionVisible: item.review.criticalActionVisible,
        reviewFileURL: XTUIObservationStore.resolveLocalRef(item.reviewRef, for: ctx),
        bundleFileURL: item.review.bundleRef.isEmpty ? nil : XTUIObservationStore.resolveLocalRef(item.review.bundleRef, for: ctx),
        screenshotFileURL: bundle.flatMap { resolvedExistingURL(for: $0.pixelLayer.fullRef, ctx: ctx) },
        visibleTextFileURL: bundle.flatMap { resolvedExistingURL(for: $0.textLayer.visibleTextRef, ctx: ctx) }
    )
}

private func trendScore(for item: some XTUIReviewTrendComparable) -> Int {
    let verdictScore = verdictScore(item.verdict)
    let objectivePenalty = item.objectiveReady ? 0 : 20
    let issuePenalty = item.issueCodes.count * 4
    let targetPenalty = item.interactiveTargetCount == 0 ? 3 : 0
    let criticalPenalty = item.criticalActionExpected && !item.criticalActionVisible ? 6 : 0
    return verdictScore + objectivePenalty + issuePenalty + targetPenalty + criticalPenalty
}

private func verdictScore(_ verdict: XTUIReviewVerdict) -> Int {
    switch verdict {
    case .ready:
        return 0
    case .attentionNeeded:
        return 100
    case .insufficientEvidence:
        return 200
    }
}

private func criticalActionLabel(expected: Bool, visible: Bool) -> String {
    guard expected else { return "不适用" }
    return visible ? "可见" : "缺失"
}

private struct XTUIReviewCriticalActionState: Equatable {
    let label: String
    let score: Int
}

private func criticalActionState(expected: Bool, visible: Bool) -> XTUIReviewCriticalActionState {
    guard expected else {
        return XTUIReviewCriticalActionState(label: "不适用", score: 0)
    }
    if visible {
        return XTUIReviewCriticalActionState(label: "可见", score: 0)
    }
    return XTUIReviewCriticalActionState(label: "缺失", score: 1)
}

private func deltaTone(oldScore: Int, newScore: Int) -> XTUIReviewDiffTone {
    if newScore < oldScore {
        return .improved
    }
    if newScore > oldScore {
        return .regressed
    }
    return .stable
}

private func signedDelta(_ value: Int) -> String {
    if value > 0 {
        return "+\(value)"
    }
    return "\(value)"
}

private func resolvedExistingURL(for ref: String, ctx: AXProjectContext) -> URL? {
    guard let url = XTUIObservationStore.resolveLocalRef(ref, for: ctx),
          FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }
    return url
}

private func normalizedIssueCodes(_ codes: [String]) -> [String] {
    Array(
        Set(
            codes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    )
    .sorted()
}

private func friendlyVerdictLabel(_ verdict: XTUIReviewVerdict) -> String {
    switch verdict {
    case .ready:
        return "可行动"
    case .attentionNeeded:
        return "需关注"
    case .insufficientEvidence:
        return "证据不足"
    }
}

private func friendlyIssueLabel(_ code: String) -> String {
    switch code {
    case "pixel_capture_available":
        return "像素截图"
    case "structure_capture_available":
        return "结构抓取"
    case "visible_text_available":
        return "可见文本"
    case "runtime_capture_available":
        return "运行时证据"
    case "interactive_target_present":
        return "可交互目标"
    case "pixel_capture_missing":
        return "缺少像素截图"
    case "structure_capture_missing":
        return "缺少结构抓取"
    case "visible_text_missing":
        return "缺少可见文本"
    case "runtime_capture_missing":
        return "缺少运行时证据"
    case "interactive_target_missing":
        return "未识别可交互目标"
    case "critical_action_not_visible":
        return "未看到关键操作"
    default:
        return code.replacingOccurrences(of: "_", with: " ")
    }
}
