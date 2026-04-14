import Foundation
import RELFlowHubCore

struct LocalLibraryStatusSummary: Equatable {
    var totalCount: Int
    var loadedCount: Int
    var localReadyCount: Int
    var localBlockedCount: Int
    var remoteCount: Int
}

enum LocalLibraryStatusSummaryBuilder {
    typealias ReadinessEvaluator = (HubModel) -> LocalLibraryRuntimeReadiness

    @MainActor
    static func build(
        models: [HubModel],
        readinessEvaluator: ReadinessEvaluator? = nil
    ) -> LocalLibraryStatusSummary {
        let resolvedReadinessEvaluator = readinessEvaluator ?? { model in
            LocalLibraryRuntimeReadinessResolver.readiness(for: model)
        }

        var summary = LocalLibraryStatusSummary(
            totalCount: models.count,
            loadedCount: 0,
            localReadyCount: 0,
            localBlockedCount: 0,
            remoteCount: 0
        )

        for model in models {
            if model.state == .loaded {
                summary.loadedCount += 1
            }

            if LocalModelRuntimeActionPlanner.isRemoteModel(model) {
                summary.remoteCount += 1
                continue
            }

            switch resolvedReadinessEvaluator(model).state {
            case .ready:
                summary.localReadyCount += 1
            case .unavailable:
                summary.localBlockedCount += 1
            }
        }

        return summary
    }
}
