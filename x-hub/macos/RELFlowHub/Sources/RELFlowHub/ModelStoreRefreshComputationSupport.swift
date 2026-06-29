import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func buildRefreshComputation(
        pendingByModelId: [String: PendingCommand],
        successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction],
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        commandResultDirectories: [URL]? = nil,
        reconcileManagedLocalModels: Bool = true,
        exportableRemoteModels: [RemoteModelEntry]? = nil
    ) -> RefreshComputation {
        let baseCatalog = ModelCatalogStorage.load()
        let base = ModelStateStorage.load()
        let refreshedBase = refreshedBaseModelSnapshots(
            catalog: baseCatalog,
            state: base,
            baseDir: baseDir,
            fileManager: .default,
            reconcileManagedLocalModels: reconcileManagedLocalModels,
            exportableRemoteModels: exportableRemoteModels
        )
        let runtimeStatus = AIRuntimeStatusStorage.load()
        let reconciled = reconciledLocalRuntimeState(
            refreshedBase.state,
            runtimeStatus: runtimeStatus,
            pendingByModelId: pendingByModelId,
            successfulLocalLifecycleActionsByModelId: successfulLocalLifecycleActionsByModelId
        )
        let benchSnapshot = ModelBenchStorage.load()
        let pairedProfilesSnapshot = HubPairedTerminalLocalModelProfilesStorage.load()
        let targetPreferencesSnapshot = LocalModelRuntimeTargetPreferencesStorage.load()
        let targetPreferenceByModelId = Dictionary(
            uniqueKeysWithValues: targetPreferencesSnapshot.preferences.map { ($0.modelId, $0) }
        )
        let requestContextByModelId = buildRequestContextMap(
            models: reconciled.models,
            runtimeStatus: runtimeStatus,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferenceByModelId: targetPreferenceByModelId
        )
        let benchByModelId = buildBenchMap(
            models: reconciled.models,
            benchSnapshot: benchSnapshot,
            requestContextByModelId: requestContextByModelId
        )
        let commandResults = collectCommandResults(directories: commandResultDirectories)
        return RefreshComputation(
            baseCatalogSnapshot: baseCatalog,
            reconciledCatalogSnapshot: refreshedBase.catalog,
            baseSnapshot: base,
            reconciledSnapshot: reconciled,
            runtimeStatus: runtimeStatus,
            benchSnapshot: benchSnapshot,
            pairedProfilesSnapshot: pairedProfilesSnapshot,
            targetPreferenceByModelId: targetPreferenceByModelId,
            requestContextByModelId: requestContextByModelId,
            benchByModelId: benchByModelId,
            decodedCommandResults: commandResults.decoded,
            invalidCommandResultURLs: commandResults.invalid
        )
    }

    nonisolated static func buildRequestContextMap(
        models: [HubModel],
        runtimeStatus: AIRuntimeStatus?,
        pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot,
        targetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference]
    ) -> [String: LocalModelRuntimeRequestContext] {
        var map: [String: LocalModelRuntimeRequestContext] = [:]
        for model in models where !LocalModelRuntimeActionPlanner.isRemoteModel(model) {
            map[model.id] = LocalModelRuntimeRequestContextResolver.resolve(
                model: model,
                runtimeStatus: runtimeStatus,
                pairedProfilesSnapshot: pairedProfilesSnapshot,
                targetPreference: targetPreferenceByModelId[model.id]
            )
        }
        return map
    }

    nonisolated static func buildBenchMap(
        models: [HubModel],
        benchSnapshot: ModelsBenchSnapshot,
        requestContextByModelId: [String: LocalModelRuntimeRequestContext]
    ) -> [String: ModelBenchResult] {
        var map: [String: ModelBenchResult] = [:]
        let benchByModel = Dictionary(grouping: benchSnapshot.results, by: \.modelId)
        for model in models {
            let rows = benchByModel[model.id] ?? []
            guard !rows.isEmpty else { continue }

            if let requestContext = requestContextByModelId[model.id],
               let matching = rows
                .filter({ requestContext.matchesBenchResult($0) })
                .sorted(by: isNewerBenchResult)
                .first {
                map[model.id] = matching
                continue
            }

            if let latest = rows.sorted(by: isNewerBenchResult).first {
                map[model.id] = latest
            }
        }
        return map
    }
}
