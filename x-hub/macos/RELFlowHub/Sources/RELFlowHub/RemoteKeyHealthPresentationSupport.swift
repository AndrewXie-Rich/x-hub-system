import Foundation
import SwiftUI
import RELFlowHubCore

struct RemoteKeyHealthPresentation {
    let badgeText: String
    let detailText: String
    let tint: Color
}

enum RemoteKeyHealthPresentationSupport {
    static func presentation(
        health: RemoteKeyHealthRecord?,
        usageLimitNotice: RemoteKeyUsageLimitNotice?,
        isScanning: Bool
    ) -> RemoteKeyHealthPresentation? {
        if isScanning {
            return RemoteKeyHealthPresentation(
                badgeText: HubUIStrings.Settings.RemoteModels.healthCheckingBadge,
                detailText: HubUIStrings.Settings.RemoteModels.healthCheckingDetail,
                tint: .secondary
            )
        }

        if let health {
            return RemoteKeyHealthPresentation(
                badgeText: badgeText(for: health.state),
                detailText: detailText(for: health),
                tint: tint(for: health.state)
            )
        }

        if let usageLimitNotice {
            return RemoteKeyHealthPresentation(
                badgeText: usageLimitNotice.badgeText,
                detailText: HubUIStrings.Settings.RemoteModels.detailSummary([
                    usageLimitNotice.detailText,
                    HubUIStrings.Settings.RemoteModels.recommendationAvoidDetail
                ]),
                tint: .orange
            )
        }

        return nil
    }

    private static func badgeText(for state: RemoteKeyHealthState) -> String {
        switch state {
        case .healthy:
            return HubUIStrings.Settings.RemoteModels.healthHealthyBadge
        case .degraded:
            return HubUIStrings.Settings.RemoteModels.healthDegradedBadge
        case .blockedQuota:
            return HubUIStrings.Settings.RemoteModels.healthQuotaBadge
        case .blockedAuth:
            return HubUIStrings.Settings.RemoteModels.healthAuthBadge
        case .blockedNetwork:
            return HubUIStrings.Settings.RemoteModels.healthNetworkBadge
        case .blockedProvider:
            return HubUIStrings.Settings.RemoteModels.healthProviderBadge
        case .blockedConfig:
            return HubUIStrings.Settings.RemoteModels.healthConfigBadge
        case .unknownStale:
            return HubUIStrings.Settings.RemoteModels.healthStaleBadge
        }
    }

    private static func tint(for state: RemoteKeyHealthState) -> Color {
        switch state {
        case .healthy:
            return .green
        case .degraded:
            return .yellow
        case .blockedQuota:
            return .orange
        case .blockedAuth, .blockedConfig:
            return .red
        case .blockedNetwork:
            return .blue
        case .blockedProvider:
            return .indigo
        case .unknownStale:
            return .secondary
        }
    }

    private static func detailText(for health: RemoteKeyHealthRecord) -> String {
        var parts: [String] = []
        let detail = health.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            parts.append(detail)
        }
        parts.append(recommendationDetail(for: health))
        if health.state == .healthy, let lastSuccessAt = timestampText(health.lastSuccessAt) {
            parts.append(HubUIStrings.Settings.RemoteModels.healthLastSuccess(lastSuccessAt))
        } else if let lastCheckedAt = timestampText(health.lastCheckedAt) {
            parts.append(HubUIStrings.Settings.RemoteModels.healthLastChecked(lastCheckedAt))
        }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }

    private static func recommendationDetail(for health: RemoteKeyHealthRecord) -> String {
        switch RemoteKeyHealthSupport.recommendation(for: health) {
        case .recommended:
            return HubUIStrings.Settings.RemoteModels.recommendationPreferredDetail
        case .neutral:
            return HubUIStrings.Settings.RemoteModels.recommendationReviewDetail
        case .discouraged:
            return HubUIStrings.Settings.RemoteModels.recommendationAvoidDetail
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
}
