import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func reconciledLocalRuntimeState(
        _ snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?,
        pendingByModelId: [String: PendingCommand],
        successfulLocalLifecycleActionsByModelId: [String: SuccessfulLocalLifecycleAction] = [:],
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> ModelStateSnapshot {
        guard !snapshot.models.isEmpty else { return snapshot }

        let loadedByProvider = loadedLocalModelIDsByProvider(runtimeStatus)
        var models = snapshot.models
        var changed = false

        for index in models.indices {
            let model = models[index]
            guard !LocalModelRuntimeActionPlanner.isRemoteModel(model) else { continue }

            let providerID = LocalModelExecutionProviderResolver.preferredRuntimeProviderID(for: model)
            let runtimeLoaded = loadedByProvider[providerID]?.contains(model.id) ?? false
            let pendingAction = pendingByModelId[model.id]?.action
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let shouldHoldLoadedState = ["load", "warmup", "bench", "prepare_local_model"].contains(pendingAction)
            let lifecycleHint = activeLifecycleStateHint(
                successfulLocalLifecycleActionsByModelId[model.id],
                runtimeStatus: runtimeStatus,
                now: now
            )
            let shouldPreferLoadedState = lifecycleHint == "load" || lifecycleHint == "warmup"
            let shouldPreferAvailableState = lifecycleHint == "unload" || lifecycleHint == "evict"

            if runtimeLoaded, !shouldPreferAvailableState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            if shouldPreferLoadedState {
                if models[index].state != .loaded {
                    models[index].state = .loaded
                    changed = true
                }
                continue
            }

            guard models[index].state == .loaded, !shouldHoldLoadedState else { continue }
            models[index].state = .available
            models[index].memoryBytes = nil
            models[index].tokensPerSec = nil
            changed = true
        }

        guard changed else { return snapshot }
        return ModelStateSnapshot(
            models: models,
            updatedAt: Date().timeIntervalSince1970
        )
    }

    nonisolated static func activeLifecycleStateHint(
        _ action: SuccessfulLocalLifecycleAction?,
        runtimeStatus: AIRuntimeStatus?,
        now: TimeInterval
    ) -> String? {
        guard let action else { return nil }
        let normalizedAction = action.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict"].contains(normalizedAction) else { return nil }
        guard (now - action.finishedAt) <= successfulLifecycleActionGraceSec else { return nil }
        if let runtimeStatus, runtimeStatus.updatedAt >= action.finishedAt {
            return nil
        }
        return normalizedAction
    }

    nonisolated private static func loadedLocalModelIDsByProvider(
        _ runtimeStatus: AIRuntimeStatus?
    ) -> [String: Set<String>] {
        guard let runtimeStatus, runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else { return [:] }

        var loadedByProvider: [String: Set<String>] = [:]
        for providerStatus in runtimeStatus.providers.values {
            let providerID = providerStatus.provider
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !providerID.isEmpty else { continue }

            var loaded = Set(
                providerStatus.loadedModels
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
            for instance in providerStatus.loadedInstances {
                let modelID = instance.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                if !modelID.isEmpty {
                    loaded.insert(modelID)
                }
            }
            loadedByProvider[providerID] = loaded
        }
        return loadedByProvider
    }


    nonisolated static func reconciledLastCommandResults(
        _ results: [String: ModelCommandResult],
        snapshot: ModelStateSnapshot,
        runtimeStatus: AIRuntimeStatus?
    ) -> [String: ModelCommandResult] {
        guard !results.isEmpty,
              let runtimeStatus,
              runtimeStatus.isAlive(ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return results
        }

        let modelByID = Dictionary(uniqueKeysWithValues: snapshot.models.map { ($0.id, $0) })
        return results.filter { modelId, result in
            !shouldClearRecoveredRuntimeFailure(
                result,
                model: modelByID[modelId],
                runtimeStatus: runtimeStatus
            )
        }
    }

    nonisolated static func shouldClearRecoveredRuntimeFailure(
        _ result: ModelCommandResult,
        model: HubModel?,
        runtimeStatus: AIRuntimeStatus
    ) -> Bool {
        guard !result.ok else { return false }

        let action = result.action
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["load", "warmup", "unload", "evict", "bench"].contains(action) else {
            return false
        }

        let message = result.msg.trimmingCharacters(in: .whitespacesAndNewlines)
        if message == LocalModelRuntimeActionPlanner.runtimeStartMessage {
            return true
        }

        guard let model else { return false }
        let providerID = LocalModelRuntimeActionPlanner.providerID(for: model)
        guard runtimeStatus.isProviderReady(providerID, ttl: AIRuntimeStatus.recommendedHeartbeatTTL) else {
            return false
        }

        let providerUnavailablePrefix = "AI 运行时已启动，但 \(providerID) provider 当前不可用"
        return message.hasPrefix(providerUnavailablePrefix)
    }

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

    nonisolated private static func shouldPrepareManagedLocalModelDuringReconcile(
        _ entry: ModelCatalogEntry,
        sandboxed: Bool,
        baseDir: URL
    ) -> Bool {
        guard sandboxed else { return false }
        let normalizedNote = (entry.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedNote == "lmstudio_managed" else { return false }
        return LocalModelManagedStorage.needsManagedPreparation(
            modelPath: entry.modelPath,
            sandboxed: sandboxed,
            baseDir: baseDir
        )
    }

    nonisolated private static func shouldPruneMissingManagedLocalModel(
        modelPath: String,
        baseDir: URL,
        fileManager: FileManager
    ) -> Bool {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }
        guard LocalModelManagedStorage.isManagedPath(trimmedPath, baseDir: baseDir) else {
            return false
        }

        let candidateURL = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        let managedRoot = LocalModelManagedStorage.managedModelsDirectory(baseDir: baseDir).standardizedFileURL
        guard candidateURL.path != managedRoot.path else { return false }
        return !fileManager.fileExists(atPath: candidateURL.path)
    }

}
