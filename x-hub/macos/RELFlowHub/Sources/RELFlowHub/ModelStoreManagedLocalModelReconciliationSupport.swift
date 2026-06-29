import Foundation
import RELFlowHubCore

extension ModelStore {
    func relinkManagedLocalModelsIfNeeded() {
        guard SharedPaths.isSandboxedProcess() else { return }

        let baseDir = SharedPaths.ensureHubDirectory()
        let fileManager = FileManager.default

        var catalog = ModelCatalogStorage.load()
        var catalogChanged = false
        for index in catalog.models.indices {
            guard let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                catalog.models[index],
                baseDir: baseDir,
                fileManager: fileManager
            ) else {
                continue
            }
            catalog.models[index] = updated
            catalogChanged = true
        }
        if catalogChanged {
            ModelCatalogStorage.save(catalog)
        }

        var state = ModelStateStorage.load()
        var stateChanged = false
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, $0) })
        for index in state.models.indices {
            let model = state.models[index]
            if let catalogEntry = catalogByID[model.id] {
                let updatedPath = catalogEntry.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
                if !updatedPath.isEmpty, updatedPath != (model.modelPath ?? "") {
                    state.models[index].modelPath = updatedPath
                    stateChanged = true
                }
                if catalogEntry.note != model.note {
                    state.models[index].note = catalogEntry.note
                    stateChanged = true
                }
                continue
            }
            guard let synthesized = Self.synthesizedCatalogEntry(from: model),
                  let updated = LocalModelManagedStorage.relinkedCatalogEntryIfManagedCopyExists(
                    synthesized,
                    baseDir: baseDir,
                    fileManager: fileManager
                  ) else {
                continue
            }
            state.models[index].modelPath = updated.modelPath
            state.models[index].note = updated.note
            stateChanged = true
        }
        if stateChanged {
            state.updatedAt = Date().timeIntervalSince1970
            ModelStateStorage.save(state)
        }
    }

    func pruneMissingManagedLocalModelsIfNeeded() {
        guard SharedPaths.isSandboxedProcess() else { return }

        let catalog = ModelCatalogStorage.load()
        let state = ModelStateStorage.load()
        let reconciled = Self.reconciledManagedLocalModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: SharedPaths.ensureHubDirectory(),
            fileManager: .default
        )
        if reconciled.catalog.models != catalog.models {
            ModelCatalogStorage.save(reconciled.catalog)
        }
        if reconciled.state.models != state.models {
            ModelStateStorage.save(reconciled.state)
        }
    }
}
