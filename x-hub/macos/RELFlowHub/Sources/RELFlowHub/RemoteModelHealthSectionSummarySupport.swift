import Foundation
import RELFlowHubCore

struct RemoteModelHealthSectionSummaryPresentation: Equatable {
    var scanningCount: Int
    var availableCount: Int
    var reviewCount: Int
    var quotaCount: Int
    var authCount: Int
    var networkCount: Int
    var providerCount: Int
    var configCount: Int
    var unscannedCount: Int
    var text: String
}

enum RemoteModelHealthSectionSummarySupport {
    static func presentation(
        models: [RemoteModelEntry],
        healthSnapshot: RemoteKeyHealthSnapshot,
        scanningKeyReferences: Set<String>
    ) -> RemoteModelHealthSectionSummaryPresentation? {
        guard !models.isEmpty else { return nil }

        let healthByKeyReference = Dictionary(
            uniqueKeysWithValues: healthSnapshot.records.map { ($0.keyReference, $0) }
        )

        var scanningCount = 0
        var availableCount = 0
        var reviewCount = 0
        var quotaCount = 0
        var authCount = 0
        var networkCount = 0
        var providerCount = 0
        var configCount = 0
        var unscannedCount = 0

        for model in models {
            let keyReference = RemoteModelStorage.keyReference(for: model)
            if scanningKeyReferences.contains(keyReference) {
                scanningCount += 1
            }

            guard let health = healthByKeyReference[keyReference] else {
                unscannedCount += 1
                continue
            }

            switch health.state {
            case .healthy:
                availableCount += 1
            case .degraded, .unknownStale:
                reviewCount += 1
            case .blockedQuota:
                quotaCount += 1
            case .blockedAuth:
                authCount += 1
            case .blockedNetwork:
                networkCount += 1
            case .blockedProvider:
                providerCount += 1
            case .blockedConfig:
                configCount += 1
            }
        }

        let parts = [
            scanningCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionScanning(scanningCount) : nil,
            HubUIStrings.Settings.RemoteModels.sectionAvailable(availableCount),
            reviewCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionReview(reviewCount) : nil,
            quotaCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionQuota(quotaCount) : nil,
            authCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionAuth(authCount) : nil,
            networkCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionNetwork(networkCount) : nil,
            providerCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionProvider(providerCount) : nil,
            configCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionConfig(configCount) : nil,
            unscannedCount > 0 ? HubUIStrings.Settings.RemoteModels.sectionUnscanned(unscannedCount) : nil,
        ]
        .compactMap { $0 }

        return RemoteModelHealthSectionSummaryPresentation(
            scanningCount: scanningCount,
            availableCount: availableCount,
            reviewCount: reviewCount,
            quotaCount: quotaCount,
            authCount: authCount,
            networkCount: networkCount,
            providerCount: providerCount,
            configCount: configCount,
            unscannedCount: unscannedCount,
            text: HubUIStrings.Settings.RemoteModels.sectionSummary(parts)
        )
    }
}
