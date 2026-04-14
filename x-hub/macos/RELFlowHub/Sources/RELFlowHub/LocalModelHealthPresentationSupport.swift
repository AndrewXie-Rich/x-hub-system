import Foundation
import SwiftUI
import RELFlowHubCore

struct LocalModelHealthPresentation {
    let badgeText: String
    let detailText: String
    let tint: Color
}

enum LocalModelHealthPresentationSupport {
    static func presentation(
        health: LocalModelHealthRecord?,
        isScanning: Bool
    ) -> LocalModelHealthPresentation? {
        if isScanning {
            return LocalModelHealthPresentation(
                badgeText: HubUIStrings.Models.LocalHealth.scanningBadge,
                detailText: HubUIStrings.Models.LocalHealth.scanningDetail,
                tint: .secondary
            )
        }

        guard let health else { return nil }
        let state = LocalModelHealthSupport.effectiveState(for: health) ?? .unknownStale
        return LocalModelHealthPresentation(
            badgeText: badgeText(for: state),
            detailText: detailText(for: health, effectiveState: state),
            tint: tint(for: state)
        )
    }

    static func sorted(
        _ models: [HubModel],
        healthSnapshot: LocalModelHealthSnapshot
    ) -> [HubModel] {
        let healthByModelID = Dictionary(
            uniqueKeysWithValues: healthSnapshot.records.map { ($0.modelId, $0) }
        )

        return models.sorted { lhs, rhs in
            let lhsHealth = healthByModelID[lhs.id]
            let rhsHealth = healthByModelID[rhs.id]
            let lhsPriority = LocalModelHealthSupport.sortPriority(for: lhsHealth)
            let rhsPriority = LocalModelHealthSupport.sortPriority(for: rhsHealth)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            let lhsState = stateRank(lhs.state)
            let rhsState = stateRank(rhs.state)
            if lhsState != rhsState {
                return lhsState < rhsState
            }

            let lhsRecency = LocalModelHealthSupport.recency(for: lhsHealth)
            let rhsRecency = LocalModelHealthSupport.recency(for: rhsHealth)
            if lhsRecency != rhsRecency {
                return lhsRecency > rhsRecency
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func shouldSurfaceRescanAction(
        health: LocalModelHealthRecord?,
        isScanning: Bool
    ) -> Bool {
        guard !isScanning else { return false }
        switch LocalModelHealthSupport.effectiveState(for: health) {
        case .degraded?, .unknownStale?, .blockedReadiness?, .blockedRuntime?:
            return true
        case .healthy?, nil:
            return false
        }
    }

    private static func badgeText(for state: LocalModelHealthState) -> String {
        switch state {
        case .healthy:
            return HubUIStrings.Models.LocalHealth.recommendedBadge
        case .degraded, .unknownStale:
            return HubUIStrings.Models.LocalHealth.reviewBadge
        case .blockedReadiness, .blockedRuntime:
            return HubUIStrings.Models.LocalHealth.discouragedBadge
        }
    }

    private static func tint(for state: LocalModelHealthState) -> Color {
        switch state {
        case .healthy:
            return .green
        case .degraded:
            return .yellow
        case .unknownStale:
            return .secondary
        case .blockedReadiness:
            return .orange
        case .blockedRuntime:
            return .red
        }
    }

    private static func detailText(
        for health: LocalModelHealthRecord,
        effectiveState: LocalModelHealthState
    ) -> String {
        var parts: [String] = []
        let detail = health.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            parts.append(detail)
        }
        parts.append(recommendationDetail(for: effectiveState))
        if effectiveState == .healthy, let lastSuccessAt = timestampText(health.lastSuccessAt) {
            parts.append(HubUIStrings.Models.LocalHealth.lastSuccess(lastSuccessAt))
        } else if let lastCheckedAt = timestampText(health.lastCheckedAt) {
            parts.append(HubUIStrings.Models.LocalHealth.lastChecked(lastCheckedAt))
        }
        return HubUIStrings.Models.LocalHealth.detailSummary(parts)
    }

    private static func recommendationDetail(for state: LocalModelHealthState) -> String {
        switch state {
        case .healthy:
            return HubUIStrings.Models.LocalHealth.recommendedDetail
        case .degraded:
            return HubUIStrings.Models.LocalHealth.reviewDetail
        case .unknownStale:
            return HubUIStrings.Models.LocalHealth.staleDetail
        case .blockedReadiness, .blockedRuntime:
            return HubUIStrings.Models.LocalHealth.discouragedDetail
        }
    }

    private static func timestampText(_ raw: TimeInterval?) -> String? {
        guard let raw, raw > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: raw))
    }

    private static func stateRank(_ state: HubModelState) -> Int {
        switch state {
        case .loaded:
            return 0
        case .sleeping:
            return 1
        case .available:
            return 2
        }
    }
}
