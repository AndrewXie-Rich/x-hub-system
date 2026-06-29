import Foundation
import RELFlowHubCore

extension ModelStore {
    func preferredBenchResult(for model: HubModel) -> ModelBenchResult? {
        currentTargetBenchResults(for: model).first
    }

    func currentTargetBenchResult(for model: HubModel, taskKind: String) -> ModelBenchResult? {
        let normalizedTaskKind = taskKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return currentTargetBenchResults(for: model).first {
            normalizedTaskKind.isEmpty || $0.taskKind == normalizedTaskKind
        }
    }

    func currentTargetBenchResults(for model: HubModel) -> [ModelBenchResult] {
        let rows = benchResults(for: model.id)
        guard let requestContext = currentLocalRuntimeRequestContext(for: model) else {
            return rows
        }
        let matching = rows.filter { requestContext.matchesBenchResult($0) }
        return matching.isEmpty ? rows : matching
    }

    func quickBenchMonitorExplanation(for model: HubModel, taskKind: String) -> LocalModelBenchMonitorExplanation? {
        guard !isRemoteModel(model) else { return nil }
        return LocalModelBenchMonitorExplanationBuilder.build(
            model: model,
            taskKind: taskKind,
            requestContext: currentLocalRuntimeRequestContext(for: model),
            benchResult: currentTargetBenchResult(for: model, taskKind: taskKind),
            runtimeStatus: currentRuntimeStatus
        )
    }

    func availableBenchTaskDescriptors(for model: HubModel) -> [LocalTaskRoutingDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        if let cached = availableBenchTaskDescriptorsCache[model.id] {
            return cached
        }
        let startedAt = HubPerformanceTrace.now()
        let inputs = localRuntimeSupportInputs(for: model)
        let descriptors = LocalModelBenchCapabilityPolicy.benchableDescriptors(
            for: model,
            runtimeStatus: currentRuntimeStatus,
            probeLaunchConfig: inputs.probeLaunchConfig,
            pythonPath: inputs.pythonPath
        )
        availableBenchTaskDescriptorsCache[model.id] = descriptors
        HubPerformanceTrace.logSlow(
            "models.projection.bench_descriptors",
            startedAt: startedAt,
            thresholdMs: 12,
            details: "model=\(model.id) provider=\(inputs.providerID) descriptors=\(descriptors.count)"
        )
        return descriptors
    }

    func availableBenchFixtures(for model: HubModel, taskKind: String) -> [LocalBenchFixtureDescriptor] {
        guard !isRemoteModel(model) else { return [] }
        return LocalBenchFixtureCatalog.fixtures(
            for: taskKind,
            providerID: LocalModelRuntimeActionPlanner.providerID(for: model)
        )
    }

    func benchResults(for modelId: String) -> [ModelBenchResult] {
        benchSnapshot.results.filter { $0.modelId == modelId }.sorted {
            if $0.measuredAt == $1.measuredAt {
                return $0.id < $1.id
            }
            return $0.measuredAt > $1.measuredAt
        }
    }
}
