import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func reconciledManagedLocalModelSnapshots(
        catalog: ModelCatalogSnapshot,
        state: ModelStateSnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default,
        sandboxed: Bool = SharedPaths.isSandboxedProcess()
    ) -> (catalog: ModelCatalogSnapshot, state: ModelStateSnapshot, removedModelIDs: Set<String>) {
        var removedModelIDs: Set<String> = []

        let reconciledCatalogModels = catalog.models.compactMap { entry -> ModelCatalogEntry? in
            if shouldPrepareManagedLocalModelDuringReconcile(
                entry,
                sandboxed: sandboxed,
                baseDir: baseDir
            ) {
                do {
                    return try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        entry,
                        sandboxed: sandboxed,
                        baseDir: baseDir,
                        fileManager: fileManager
                    )
                } catch {
                    HubDiagnostics.log(
                        "local_model_reconcile_prepare_failed model=\(entry.id) error=\(error.localizedDescription)"
                    )
                }
            }
            if let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                entry,
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                return updated
            }
            if shouldPruneMissingManagedLocalModel(
                modelPath: entry.modelPath,
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                removedModelIDs.insert(entry.id)
                return nil
            }
            return entry
        }

        var reconciledCatalog = catalog
        if reconciledCatalogModels != catalog.models {
            reconciledCatalog.models = reconciledCatalogModels
            reconciledCatalog.updatedAt = Date().timeIntervalSince1970
        }

        let catalogByID = Dictionary(uniqueKeysWithValues: reconciledCatalog.models.map { ($0.id, $0) })
        var reconciledStateModels: [HubModel] = []
        reconciledStateModels.reserveCapacity(state.models.count)

        for model in state.models {
            if removedModelIDs.contains(model.id) {
                continue
            }
            if let catalogEntry = catalogByID[model.id] {
                var updatedModel = model
                updatedModel.name = catalogEntry.name
                updatedModel.backend = catalogEntry.backend
                updatedModel.runtimeProviderID = catalogEntry.runtimeProviderID
                updatedModel.quant = catalogEntry.quant
                updatedModel.contextLength = catalogEntry.contextLength
                updatedModel.maxContextLength = catalogEntry.maxContextLength
                updatedModel.paramsB = catalogEntry.paramsB
                updatedModel.roles = catalogEntry.roles
                updatedModel.modelPath = catalogEntry.modelPath
                updatedModel.note = catalogEntry.note
                updatedModel.modelFormat = catalogEntry.modelFormat
                updatedModel.defaultLoadProfile = catalogEntry.defaultLoadProfile
                updatedModel.taskKinds = catalogEntry.taskKinds
                updatedModel.inputModalities = catalogEntry.inputModalities
                updatedModel.outputModalities = catalogEntry.outputModalities
                updatedModel.offlineReady = catalogEntry.offlineReady
                updatedModel.voiceProfile = catalogEntry.voiceProfile
                updatedModel.resourceProfile = catalogEntry.resourceProfile
                updatedModel.trustProfile = catalogEntry.trustProfile
                updatedModel.processorRequirements = catalogEntry.processorRequirements
                reconciledStateModels.append(updatedModel)
                continue
            }
            if let synthesized = Self.synthesizedCatalogEntry(from: model),
               shouldPrepareManagedLocalModelDuringReconcile(
                    synthesized,
                    sandboxed: sandboxed,
                    baseDir: baseDir
               ) {
                do {
                    let prepared = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        synthesized,
                        sandboxed: sandboxed,
                        baseDir: baseDir,
                        fileManager: fileManager
                    )
                    var updatedModel = model
                    updatedModel.modelPath = prepared.modelPath
                    updatedModel.note = prepared.note
                    reconciledStateModels.append(updatedModel)
                    continue
                } catch {
                    HubDiagnostics.log(
                        "local_model_reconcile_prepare_failed model=\(model.id) error=\(error.localizedDescription)"
                    )
                }
            }
            if let synthesized = Self.synthesizedCatalogEntry(from: model),
               let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                    synthesized,
                    baseDir: baseDir,
                    fileManager: fileManager
               ) {
                var updatedModel = model
                updatedModel.modelPath = updated.modelPath
                updatedModel.note = updated.note
                reconciledStateModels.append(updatedModel)
                continue
            }
            if shouldPruneMissingManagedLocalModel(
                modelPath: model.modelPath ?? "",
                baseDir: baseDir,
                fileManager: fileManager
            ) {
                removedModelIDs.insert(model.id)
                continue
            }
            reconciledStateModels.append(model)
        }

        var reconciledState = state
        if reconciledStateModels != state.models {
            reconciledState.models = reconciledStateModels
            reconciledState.updatedAt = Date().timeIntervalSince1970
        }

        return (reconciledCatalog, reconciledState, removedModelIDs)
    }
}
