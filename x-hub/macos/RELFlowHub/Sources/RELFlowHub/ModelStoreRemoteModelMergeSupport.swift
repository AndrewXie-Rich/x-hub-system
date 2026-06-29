import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func mergeRemoteModels(
        _ base: ModelStateSnapshot,
        exportableRemoteModels: [RemoteModelEntry]? = nil
    ) -> ModelStateSnapshot {
        let remote = exportableRemoteModels ?? RemoteModelStorage.exportableEnabledModels()
        let localOnly = base.models.filter { !LocalModelRuntimeActionPlanner.isRemoteModel($0) }

        if remote.isEmpty {
            if localOnly.count == base.models.count {
                return base
            }
            return ModelStateSnapshot(models: localOnly, updatedAt: Date().timeIntervalSince1970)
        }

        var merged = localOnly
        for r in remote {
            if merged.contains(where: { $0.id == r.id }) {
                continue
            }
            let m = HubModel(
                id: r.id,
                name: r.name,
                backend: r.backend,
                quant: "remote",
                contextLength: max(512, r.contextLength),
                paramsB: 0.0,
                roles: nil,
                state: .loaded,
                memoryBytes: nil,
                tokensPerSec: nil,
                modelPath: nil,
                note: r.note
            )
            merged.append(m)
        }

        if merged == base.models {
            return base
        }
        return ModelStateSnapshot(models: merged, updatedAt: Date().timeIntervalSince1970)
    }
}
