import Foundation
import RELFlowHubCore

extension ModelStore {
    func upsertCatalogModel(_ entry: ModelCatalogEntry) {
        var cur = ModelStateStorage.load()
        if let idx = cur.models.firstIndex(where: { $0.id == entry.id }) {
            // Keep state/memory/tps; update metadata.
            cur.models[idx].name = entry.name
            cur.models[idx].backend = entry.backend
            cur.models[idx].runtimeProviderID = entry.runtimeProviderID
            cur.models[idx].quant = entry.quant
            cur.models[idx].contextLength = entry.contextLength
            cur.models[idx].paramsB = entry.paramsB
            cur.models[idx].modelPath = entry.modelPath
            cur.models[idx].roles = entry.roles
            cur.models[idx].note = entry.note
            cur.models[idx].modelFormat = entry.modelFormat
            cur.models[idx].taskKinds = entry.taskKinds
            cur.models[idx].inputModalities = entry.inputModalities
            cur.models[idx].outputModalities = entry.outputModalities
            cur.models[idx].offlineReady = entry.offlineReady
            cur.models[idx].voiceProfile = entry.voiceProfile
            cur.models[idx].resourceProfile = entry.resourceProfile
            cur.models[idx].trustProfile = entry.trustProfile
            cur.models[idx].processorRequirements = entry.processorRequirements
        } else {
            cur.models.append(
                HubModel(
                    id: entry.id,
                    name: entry.name,
                    backend: entry.backend,
                    runtimeProviderID: entry.runtimeProviderID,
                    quant: entry.quant,
                    contextLength: entry.contextLength,
                    paramsB: entry.paramsB,
                    roles: entry.roles,
                    state: .available,
                    modelPath: entry.modelPath,
                    note: entry.note,
                    modelFormat: entry.modelFormat,
                    taskKinds: entry.taskKinds,
                    inputModalities: entry.inputModalities,
                    outputModalities: entry.outputModalities,
                    offlineReady: entry.offlineReady,
                    voiceProfile: entry.voiceProfile,
                    resourceProfile: entry.resourceProfile,
                    trustProfile: entry.trustProfile,
                    processorRequirements: entry.processorRequirements
                )
            )
        }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur
    }

    func catalogEntry(for model: HubModel) -> ModelCatalogEntry? {
        if let catalogModel = ModelCatalogStorage.load().models.first(where: { $0.id == model.id }) {
            return catalogModel
        }
        return Self.synthesizedCatalogEntry(from: model)
    }

    nonisolated static func synthesizedCatalogEntry(from model: HubModel) -> ModelCatalogEntry? {
        let modelPath = (model.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelPath.isEmpty else { return nil }
        return ModelCatalogEntry(
            id: model.id,
            name: model.name,
            backend: model.backend,
            runtimeProviderID: model.runtimeProviderID,
            quant: model.quant,
            contextLength: model.contextLength,
            maxContextLength: model.maxContextLength,
            paramsB: model.paramsB,
            modelPath: modelPath,
            roles: model.roles,
            note: model.note,
            modelFormat: model.modelFormat,
            defaultLoadProfile: model.defaultLoadProfile,
            taskKinds: model.taskKinds,
            inputModalities: model.inputModalities,
            outputModalities: model.outputModalities,
            offlineReady: model.offlineReady,
            voiceProfile: model.voiceProfile,
            resourceProfile: model.resourceProfile,
            trustProfile: model.trustProfile,
            processorRequirements: model.processorRequirements
        )
    }

    func applyPreparedCatalogEntry(_ entry: ModelCatalogEntry) {
        var catalog = ModelCatalogStorage.load()
        if let index = catalog.models.firstIndex(where: { $0.id == entry.id }) {
            catalog.models[index] = entry
        } else {
            catalog.models.append(entry)
        }
        ModelCatalogStorage.save(catalog)
        upsertCatalogModel(entry)
    }

    func backfillRuntimeProviderIDsIfNeeded() {
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()

        var catalog = ModelCatalogStorage.load()
        let updatedCatalogModels = catalog.models.map {
            LocalModelExecutionProviderResolver.backfilled($0, helperBinaryPath: helperBinaryPath)
        }
        if updatedCatalogModels != catalog.models {
            catalog.models = updatedCatalogModels
            catalog.updatedAt = Date().timeIntervalSince1970
            ModelCatalogStorage.save(catalog)
        }

        var state = ModelStateStorage.load()
        let updatedStateModels = state.models.map {
            LocalModelExecutionProviderResolver.backfilled($0, helperBinaryPath: helperBinaryPath)
        }
        if updatedStateModels != state.models {
            state.models = updatedStateModels
            state.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(state)
        }
    }

}
