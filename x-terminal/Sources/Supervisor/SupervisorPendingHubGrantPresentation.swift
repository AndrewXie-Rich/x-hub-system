import Foundation

struct SupervisorPendingHubGrantRowPresentation: Equatable, Identifiable {
    var id: String
    var anchorID: String
    var title: String
    var ageText: String
    var summary: String
    var supplementaryReasonText: String?
    var priorityReasonText: String?
    var nextActionText: String?
    var scopeSummaryText: String?
    var grantIdentifierText: String
    var isFocused: Bool
    var isInFlight: Bool
    var actionDescriptors: [SupervisorCardActionDescriptor]
}

struct SupervisorPendingHubGrantBoardPresentation: Equatable {
    var iconName: String
    var iconTone: SupervisorHeaderControlTone
    var title: String
    var snapshotText: String
    var freshnessWarningText: String?
    var footerNote: String?
    var emptyStateText: String?
    var rows: [SupervisorPendingHubGrantRowPresentation]

    var isEmpty: Bool {
        rows.isEmpty
    }
}

enum SupervisorPendingHubGrantPresentation {
    static func board(
        grants: [SupervisorManager.SupervisorPendingGrant],
        source: String,
        hasFreshSnapshot: Bool,
        updatedAt: TimeInterval,
        inFlightGrantIDs: Set<String>,
        hubInteractive: Bool,
        focusedRowAnchor: String?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorPendingHubGrantBoardPresentation {
        SupervisorPendingHubGrantBoardPresentation(
            iconName: grants.isEmpty ? "checkmark.shield" : "exclamationmark.shield.fill",
            iconTone: grants.isEmpty ? .neutral : .warning,
            title: "Hub 待处理授权：\(grants.count)",
            snapshotText: snapshotText(
                source: source,
                hasFreshSnapshot: hasFreshSnapshot,
                updatedAt: updatedAt,
                now: now
            ),
            freshnessWarningText: hasFreshSnapshot
                ? nil
                : "暂未拿到新鲜 Hub 快照（不会再回退日志推断）。",
            footerNote: grants.isEmpty
                ? nil
                : XTHubGrantPresentation.approvalFooterNote(count: grants.count),
            emptyStateText: grants.isEmpty ? "当前没有待审批的 Hub 授权。" : nil,
            rows: grants.map {
                row(
                    $0,
                    inFlightGrantIDs: inFlightGrantIDs,
                    hubInteractive: hubInteractive,
                    isFocused: focusedRowAnchor == SupervisorFocusPresentation.pendingHubGrantRowAnchor($0),
                    now: now
                )
            }
        )
    }

    static func row(
        _ grant: SupervisorManager.SupervisorPendingGrant,
        inFlightGrantIDs: Set<String>,
        hubInteractive: Bool,
        isFocused: Bool,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> SupervisorPendingHubGrantRowPresentation {
        let normalizedGrantId = normalizedScalar(grant.grantRequestId)
        let resolvedGrantId = normalizedGrantId.isEmpty ? grant.id : normalizedGrantId
        let inFlight = !normalizedGrantId.isEmpty && inFlightGrantIDs.contains(normalizedGrantId)
        let canAct = hubInteractive && !normalizedGrantId.isEmpty

        return SupervisorPendingHubGrantRowPresentation(
            id: grant.id,
            anchorID: SupervisorFocusPresentation.pendingHubGrantRowAnchor(grant),
            title: "P\(grant.priorityRank) · \(grant.projectName) · \(capabilityText(grant))",
            ageText: ageText(grant.createdAt, now: now),
            summary: XTHubGrantPresentation.awaitingSummary(
                capability: grant.capability,
                modelId: grant.modelId
            ),
            supplementaryReasonText: XTHubGrantPresentation.supplementaryReason(
                grant.reason,
                capability: grant.capability,
                modelId: grant.modelId
            ).map { "原因：\($0)" },
            priorityReasonText: nonEmpty(grant.priorityReason).map { "优先级解释：\($0)" },
            nextActionText: nonEmpty(grant.nextAction).map { "建议动作：\($0)" },
            scopeSummaryText: XTHubGrantPresentation.scopeSummary(
                requestedTtlSec: grant.requestedTtlSec,
                requestedTokenCap: grant.requestedTokenCap
            ),
            grantIdentifierText: "授权单号：\(resolvedGrantId)",
            isFocused: isFocused,
            isInFlight: inFlight,
            actionDescriptors: SupervisorCardActionResolver.pendingHubGrantActions(
                grant,
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

    static func capabilityText(
        _ grant: SupervisorManager.SupervisorPendingGrant
    ) -> String {
        XTHubGrantPresentation.capabilityLabel(
            capability: grant.capability,
            modelId: grant.modelId
        )
    }

    static func ageText(
        _ createdAt: TimeInterval?,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> String {
        guard let createdAt, createdAt > 0 else { return "待处理" }
        return SupervisorEventLoopFeedPresentation.relativeTimeText(createdAt, now: now)
    }

    private static func normalizedScalar(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func nonEmpty(_ raw: String) -> String? {
        let trimmed = normalizedScalar(raw)
        return trimmed.isEmpty ? nil : trimmed
    }
}
