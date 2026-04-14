import Foundation
import RELFlowHubCore

struct LocalModelHealthSectionSummaryPresentation: Equatable {
    var scanningCount: Int
    var availableCount: Int
    var reviewCount: Int
    var discouragedCount: Int
    var unscannedCount: Int
    var text: String
}

enum LocalModelHealthSectionSummarySupport {
    static func presentation(
        models: [HubModel],
        healthSnapshot: LocalModelHealthSnapshot,
        scanningModelIDs: Set<String>,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> LocalModelHealthSectionSummaryPresentation? {
        guard !models.isEmpty else { return nil }

        let healthByModelID = Dictionary(
            uniqueKeysWithValues: healthSnapshot.records.map { ($0.modelId, $0) }
        )

        var scanningCount = 0
        var availableCount = 0
        var reviewCount = 0
        var discouragedCount = 0
        var unscannedCount = 0

        for model in models {
            if scanningModelIDs.contains(model.id) {
                scanningCount += 1
            }

            guard let health = healthByModelID[model.id] else {
                unscannedCount += 1
                continue
            }

            switch LocalModelHealthSupport.recommendation(for: health, now: now) {
            case .recommended:
                availableCount += 1
            case .neutral:
                reviewCount += 1
            case .discouraged:
                discouragedCount += 1
            }
        }

        let parts = [
            scanningCount > 0 ? HubUIStrings.Models.LocalHealth.sectionScanning(scanningCount) : nil,
            HubUIStrings.Models.LocalHealth.sectionAvailable(availableCount),
            reviewCount > 0 ? HubUIStrings.Models.LocalHealth.sectionReview(reviewCount) : nil,
            discouragedCount > 0 ? HubUIStrings.Models.LocalHealth.sectionDiscouraged(discouragedCount) : nil,
            unscannedCount > 0 ? HubUIStrings.Models.LocalHealth.sectionUnscanned(unscannedCount) : nil,
        ]
        .compactMap { $0 }

        return LocalModelHealthSectionSummaryPresentation(
            scanningCount: scanningCount,
            availableCount: availableCount,
            reviewCount: reviewCount,
            discouragedCount: discouragedCount,
            unscannedCount: unscannedCount,
            text: HubUIStrings.Models.LocalHealth.sectionSummary(parts)
        )
    }
}
