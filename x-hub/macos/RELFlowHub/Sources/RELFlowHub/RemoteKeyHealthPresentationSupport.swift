import Foundation
import SwiftUI
import RELFlowHubCore

struct RemoteKeyHealthPresentation {
    let badgeText: String
    let detailText: String
    let tint: Color
}

struct RemoteKeySlotHealthPresentation: Identifiable {
    let keyReference: String
    let badgeText: String
    let detailText: String
    let tint: Color

    var id: String { keyReference }
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

    static func slotPresentations(
        models: [RemoteModelEntry],
        healthSnapshot: RemoteKeyHealthSnapshot,
        isScanning: (String) -> Bool
    ) -> [RemoteKeySlotHealthPresentation] {
        var orderedKeys: [String] = []
        var seen: Set<String> = []
        for model in models {
            let keyReference = RemoteModelStorage.keyReference(for: model)
            guard !keyReference.isEmpty, seen.insert(keyReference).inserted else { continue }
            orderedKeys.append(keyReference)
        }

        return orderedKeys.map { keyReference in
            if isScanning(keyReference) {
                return RemoteKeySlotHealthPresentation(
                    keyReference: keyReference,
                    badgeText: HubUIStrings.Settings.RemoteModels.healthCheckingBadge,
                    detailText: "正在检测这把 key。",
                    tint: .secondary
                )
            }

            guard let health = healthSnapshot.records.first(where: { $0.keyReference == keyReference }) else {
                return RemoteKeySlotHealthPresentation(
                    keyReference: keyReference,
                    badgeText: HubUIStrings.Settings.RemoteModels.healthStaleBadge,
                    detailText: "这把 key 还没有检测结果。",
                    tint: .secondary
                )
            }

            return RemoteKeySlotHealthPresentation(
                keyReference: keyReference,
                badgeText: badgeText(for: health.state),
                detailText: slotDetailText(for: health),
                tint: tint(for: health.state)
            )
        }
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
        if health.state != .healthy,
           let retryAtText = health.retryAtText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !retryAtText.isEmpty {
            parts.append("预计下次可用：\(retryAtText)")
        }
        parts.append(recommendationDetail(for: health))
        if health.state == .healthy, let lastSuccessAt = timestampText(health.lastSuccessAt) {
            parts.append(HubUIStrings.Settings.RemoteModels.healthLastSuccess(lastSuccessAt))
        } else if let lastCheckedAt = timestampText(health.lastCheckedAt) {
            parts.append(HubUIStrings.Settings.RemoteModels.healthLastChecked(lastCheckedAt))
        }
        return HubUIStrings.Settings.RemoteModels.detailSummary(parts)
    }

    private static func slotDetailText(for health: RemoteKeyHealthRecord) -> String {
        var parts: [String] = []
        let detail = health.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty {
            parts.append(detail)
        }

        switch health.state {
        case .healthy:
            parts.append("当前可用")
        default:
            if let retryAtText = health.retryAtText?.trimmingCharacters(in: .whitespacesAndNewlines),
               !retryAtText.isEmpty {
                parts.append("预计下次可用：\(retryAtText)")
            } else {
                parts.append("预计下次可用：未知")
            }
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
