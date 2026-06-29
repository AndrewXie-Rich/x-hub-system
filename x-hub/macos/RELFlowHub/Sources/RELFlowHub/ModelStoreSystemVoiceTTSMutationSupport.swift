import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func snapshotsRemovingSystemVoiceTTSIfPresent(
        catalog: ModelCatalogSnapshot,
        state: ModelStateSnapshot
    ) -> (catalog: ModelCatalogSnapshot, state: ModelStateSnapshot) {
        var updatedCatalog = catalog
        let filteredCatalog = updatedCatalog.models.filter { $0.id != systemVoiceTTSModelID }
        if filteredCatalog != updatedCatalog.models {
            updatedCatalog.models = filteredCatalog
            updatedCatalog.updatedAt = Date().timeIntervalSince1970
        }

        var updatedState = state
        let filteredState = updatedState.models.filter { $0.id != systemVoiceTTSModelID }
        if filteredState != updatedState.models {
            updatedState.models = filteredState
            updatedState.updatedAt = Date().timeIntervalSince1970
        }
        return (updatedCatalog, updatedState)
    }

    nonisolated static func upsertSystemVoiceTTSCatalogEntry(
        _ entry: ModelCatalogEntry,
        into models: inout [ModelCatalogEntry]
    ) -> Bool {
        if let index = models.firstIndex(where: { $0.id == entry.id }) {
            guard models[index] != entry else { return false }
            models[index] = entry
            return true
        }
        models.append(entry)
        return true
    }

    nonisolated static func upsertSystemVoiceTTSStateModel(
        _ model: HubModel,
        into models: inout [HubModel]
    ) -> Bool {
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            guard models[index] != model else { return false }
            models[index] = model
            return true
        }
        models.append(model)
        return true
    }
}
