import Foundation
import RELFlowHubCore
struct FileStamp: Equatable, Sendable {
    let path: String
    let exists: Bool
    let modifiedAt: TimeInterval
    let size: Int64
}

struct RemoteModelExportCache {
    let remoteModelsStamp: FileStamp
    let remoteKeyHealthStamp: FileStamp
    let models: [RemoteModelEntry]
}

struct CommandResultFile: Sendable {
    let url: URL
    let result: ModelCommandResult
}

struct RefreshComputation: Sendable {
    let baseCatalogSnapshot: ModelCatalogSnapshot
    let reconciledCatalogSnapshot: ModelCatalogSnapshot
    let baseSnapshot: ModelStateSnapshot
    let reconciledSnapshot: ModelStateSnapshot
    let runtimeStatus: AIRuntimeStatus?
    let benchSnapshot: ModelsBenchSnapshot
    let pairedProfilesSnapshot: HubPairedTerminalLocalModelProfilesSnapshot
    let targetPreferenceByModelId: [String: LocalModelRuntimeTargetPreference]
    let requestContextByModelId: [String: LocalModelRuntimeRequestContext]
    let benchByModelId: [String: ModelBenchResult]
    let decodedCommandResults: [CommandResultFile]
    let invalidCommandResultURLs: [URL]
}

extension ModelStore {
    func refresh(reconcileManagedModels: Bool = true) {
        if reconcileManagedModels {
            forceManagedModelReconcileOnNextRefresh = true
        }
        refreshRequestedRevision &+= 1
        scheduleRefreshIfNeeded()
    }

    func resetDerivedUICaches() {
        localRuntimeSupportInputsCache.removeAll(keepingCapacity: true)
        localRuntimePresentationCache.removeAll(keepingCapacity: true)
        localRuntimeActionBlockedMessageCache.removeAll(keepingCapacity: true)
        availableBenchTaskDescriptorsCache.removeAll(keepingCapacity: true)
        availableLocalRuntimeTargetOptionsCache.removeAll(keepingCapacity: true)
    }

    func scheduleRefreshIfNeeded() {
        guard refreshTask == nil else { return }

        let revision = refreshRequestedRevision
        let pendingSnapshot = pendingByModelId
        let lifecycleSnapshot = successfulLocalLifecycleActionsByModelId
        let baseDir = refreshBaseDir
        let commandResultDirectories = commandResultDirectories
        let reconcileManagedModels = shouldReconcileManagedModels(now: Date().timeIntervalSince1970)
        let exportableRemoteModels = cachedExportableRemoteModels()
        refreshTask = Task { [weak self] in
            let computation = await Task.detached(priority: .utility) {
                Self.buildRefreshComputation(
                    pendingByModelId: pendingSnapshot,
                    successfulLocalLifecycleActionsByModelId: lifecycleSnapshot,
                    baseDir: baseDir,
                    commandResultDirectories: commandResultDirectories,
                    reconcileManagedLocalModels: reconcileManagedModels,
                    exportableRemoteModels: exportableRemoteModels
                )
            }.value
            self?.finishRefresh(
                revision: revision,
                computation: computation
            )
        }
    }

    func cachedExportableRemoteModels() -> [RemoteModelEntry] {
        let remoteModelsStamp = Self.fileStamp(RemoteModelStorage.url())
        let remoteKeyHealthStamp = Self.fileStamp(RemoteKeyHealthStorage.url())
        if let cached = remoteModelExportCache,
           cached.remoteModelsStamp == remoteModelsStamp,
           cached.remoteKeyHealthStamp == remoteKeyHealthStamp {
            return cached.models
        }

        let models = RemoteModelStorage.exportableEnabledModels()
        remoteModelExportCache = RemoteModelExportCache(
            remoteModelsStamp: Self.fileStamp(RemoteModelStorage.url()),
            remoteKeyHealthStamp: Self.fileStamp(RemoteKeyHealthStorage.url()),
            models: models
        )
        return models
    }

    nonisolated static func fileStamp(_ url: URL) -> FileStamp {
        let normalized = url.standardizedFileURL
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: normalized.path) else {
            return FileStamp(path: normalized.path, exists: false, modifiedAt: 0, size: -1)
        }
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
        return FileStamp(path: normalized.path, exists: true, modifiedAt: modifiedAt, size: size)
    }

    func shouldReconcileManagedModels(now: TimeInterval) -> Bool {
        if forceManagedModelReconcileOnNextRefresh {
            forceManagedModelReconcileOnNextRefresh = false
            lastManagedModelReconcileAt = now
            return true
        }

        guard lastManagedModelReconcileAt > 0 else {
            lastManagedModelReconcileAt = now
            return true
        }

        if now - lastManagedModelReconcileAt >= Self.managedModelReconcileInterval {
            lastManagedModelReconcileAt = now
            return true
        }
        return false
    }

    func finishRefresh(
        revision: UInt64,
        computation: RefreshComputation
    ) {
        refreshTask = nil

        if revision == refreshRequestedRevision {
            applyRefreshComputation(computation)
        } else {
            applyCommandResults(
                computation.decodedCommandResults,
                invalidURLs: computation.invalidCommandResultURLs
            )
            scheduleRefreshIfNeeded()
        }
    }

    func applyRefreshComputation(_ computation: RefreshComputation) {
        resetDerivedUICaches()
        currentRuntimeStatus = computation.runtimeStatus
        snapshot = computation.reconciledSnapshot
        if computation.reconciledCatalogSnapshot != computation.baseCatalogSnapshot {
            ModelCatalogStorage.save(computation.reconciledCatalogSnapshot)
        }
        if computation.reconciledSnapshot != computation.baseSnapshot {
            ModelStateStorage.save(computation.reconciledSnapshot)
        }
        benchSnapshot = computation.benchSnapshot
        currentPairedProfilesSnapshot = computation.pairedProfilesSnapshot
        currentTargetPreferenceByModelId = computation.targetPreferenceByModelId
        benchByModelId = computation.benchByModelId
        currentLocalRuntimeRequestContextByModelId = computation.requestContextByModelId

        reconcilePendingWithState()
        reconcileSuccessfulLifecycleActionsWithRuntimeStatus()
        applyCommandResults(
            computation.decodedCommandResults,
            invalidURLs: computation.invalidCommandResultURLs
        )
        lastResultByModelId = Self.reconciledLastCommandResults(
            lastResultByModelId,
            snapshot: snapshot,
            runtimeStatus: currentRuntimeStatus
        )
    }

    func applyCommandResults(
        _ decodedResults: [CommandResultFile],
        invalidURLs: [URL]
    ) {
        for entry in decodedResults {
            lastResultByModelId[entry.result.modelId] = entry.result
            if let pending = pendingByModelId[entry.result.modelId],
               pending.reqId == entry.result.reqId {
                pendingByModelId.removeValue(forKey: entry.result.modelId)
            }
            try? FileManager.default.removeItem(at: entry.url)
        }

        for url in invalidURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

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

    nonisolated static func collectCommandResults(
        directories: [URL]? = nil
    ) -> (decoded: [CommandResultFile], invalid: [URL]) {
        let directories = directories ?? commandResultDirectoryCandidates()
        guard !directories.isEmpty else { return ([], []) }

        let decoder = JSONDecoder()
        let fileManager = FileManager.default
        var decoded: [CommandResultFile] = []
        var invalid: [URL] = []
        var seenFiles: Set<String> = []

        for directory in directories {
            guard let files = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else {
                continue
            }

            for url in files where url.pathExtension.lowercased() == "json" {
                let standardizedPath = url.standardizedFileURL.path
                guard seenFiles.insert(standardizedPath).inserted else { continue }
                guard let data = try? Data(contentsOf: url) else {
                    invalid.append(url)
                    continue
                }
                guard let result = try? decoder.decode(ModelCommandResult.self, from: data) else {
                    invalid.append(url)
                    continue
                }
                decoded.append(CommandResultFile(url: url, result: result))
            }
        }

        return (decoded, invalid)
    }

    nonisolated static func commandResultDirectoryCandidates() -> [URL] {
        var out: [URL] = []
        var seen: Set<String> = []

        func append(_ url: URL?) {
            guard let url else { return }
            let standardizedPath = url.standardizedFileURL.path
            guard seen.insert(standardizedPath).inserted else { return }
            out.append(url)
        }

        append(SharedPaths.appGroupDirectory()?.appendingPathComponent("model_results", isDirectory: true))
        for base in SharedPaths.hubDirectoryCandidates() {
            append(base.appendingPathComponent("model_results", isDirectory: true))
        }
        return out
    }

}
