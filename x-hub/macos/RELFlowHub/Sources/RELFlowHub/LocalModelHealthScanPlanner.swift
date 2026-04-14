import Foundation
import RELFlowHubCore

struct LocalModelHealthScanJob {
    var model: HubModel
    var mode: LocalModelHealthScanMode
    var updatesTrialStatus: Bool
}

enum LocalModelHealthScanPlanner {
    private static let recentHealthyWindow: TimeInterval = 7 * 24 * 60 * 60
    private static let optionalRecentHealthyLimit = 2

    static func jobs(
        for models: [HubModel],
        requestedMode: LocalModelHealthScanMode,
        explicitlyLimited: Bool,
        healthByModelID: [String: LocalModelHealthRecord],
        preferredModelIDByTask: [String: String],
        requestedTrialStatusUpdates: Bool,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> [LocalModelHealthScanJob] {
        let shouldSplitFullTrials = requestedMode == .full
            && requestedTrialStatusUpdates
            && !explicitlyLimited
            && models.count > 1
        guard shouldSplitFullTrials else {
            return models.map { model in
                LocalModelHealthScanJob(
                    model: model,
                    mode: requestedMode,
                    updatesTrialStatus: requestedTrialStatusUpdates && requestedMode == .full
                )
            }
        }

        let fullTrialIDs = fullTrialCandidateModelIDs(
            within: models,
            healthByModelID: healthByModelID,
            preferredModelIDByTask: preferredModelIDByTask,
            now: now
        )

        return models.map { model in
            let usesFullTrial = fullTrialIDs.contains(model.id)
            return LocalModelHealthScanJob(
                model: model,
                mode: usesFullTrial ? .full : .preflightOnly,
                updatesTrialStatus: usesFullTrial && requestedTrialStatusUpdates
            )
        }
    }

    static func fullTrialCandidateModelIDs(
        within models: [HubModel],
        healthByModelID: [String: LocalModelHealthRecord],
        preferredModelIDByTask: [String: String],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Set<String> {
        guard !models.isEmpty else { return [] }

        var orderedMandatoryIDs: [String] = []
        var seen = Set<String>()

        func appendMandatory(modelID: String) {
            let normalizedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedModelID.isEmpty else { return }
            guard models.contains(where: { $0.id == normalizedModelID }) else { return }
            guard seen.insert(normalizedModelID).inserted else { return }
            orderedMandatoryIDs.append(normalizedModelID)
        }

        for model in models where model.state == .loaded {
            appendMandatory(modelID: model.id)
        }

        for taskType in HubTaskType.allCases {
            let preferredModelID = preferredModelIDByTask[taskType.rawValue] ?? ""
            let decision = HubTaskRoutingPolicy.decision(
                taskType: taskType,
                models: models,
                preferredModelId: preferredModelID,
                allowAutoLoad: true
            )
            appendMandatory(modelID: decision.modelId)
        }

        let recentHealthyModelIDs = models
            .filter { model in
                guard !seen.contains(model.id),
                      let record = healthByModelID[model.id],
                      let lastSuccessAt = record.lastSuccessAt else {
                    return false
                }
                return lastSuccessAt > 0 && (now - lastSuccessAt) <= recentHealthyWindow
            }
            .sorted { lhs, rhs in
                let lhsSuccess = healthByModelID[lhs.id]?.lastSuccessAt ?? 0
                let rhsSuccess = healthByModelID[rhs.id]?.lastSuccessAt ?? 0
                if lhsSuccess != rhsSuccess {
                    return lhsSuccess > rhsSuccess
                }
                if lhs.state != rhs.state {
                    return stateRank(lhs.state) < stateRank(rhs.state)
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .prefix(optionalRecentHealthyLimit)
            .map(\.id)

        for modelID in recentHealthyModelIDs {
            appendMandatory(modelID: modelID)
        }

        if orderedMandatoryIDs.isEmpty, let firstModel = models.first {
            appendMandatory(modelID: firstModel.id)
        }

        return Set(orderedMandatoryIDs)
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
