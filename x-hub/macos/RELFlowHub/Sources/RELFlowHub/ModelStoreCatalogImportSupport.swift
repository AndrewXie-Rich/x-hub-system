import Foundation
import RELFlowHubCore

extension ModelStore {
    func importCatalogEntries(
        _ entries: [ModelCatalogEntry],
        autoBenchNewModels: Bool
    ) async -> [String] {
        guard !entries.isEmpty else { return [] }

        let preparedEntries = await Task.detached(priority: .utility) {
            let sandboxed = SharedPaths.isSandboxedProcess()
            let baseDir = SharedPaths.ensureHubDirectory()
            var prepared: [ModelCatalogEntry] = []
            prepared.reserveCapacity(entries.count)
            for entry in entries {
                do {
                    let resolved = try LocalModelManagedStorage.preparedCatalogEntryIfNeeded(
                        entry,
                        sandboxed: sandboxed,
                        baseDir: baseDir
                    )
                    prepared.append(resolved)
                } catch {
                    HubDiagnostics.log("local_model_prepare_failed model=\(entry.id) error=\(error.localizedDescription)")
                }
            }
            return prepared
        }.value
        guard !preparedEntries.isEmpty else { return [] }

        var catalog = ModelCatalogStorage.load()
        var newModelIDs: [String] = []
        var verificationModelIDs: [String] = []
        let healthByModelID = Dictionary(
            uniqueKeysWithValues: LocalModelHealthStorage.load().records.map { ($0.modelId, $0) }
        )
        let helperBinaryPath = LocalHelperBridgeDiscovery.discoverHelperBinary()

        for rawEntry in preparedEntries {
            let entry = LocalModelExecutionProviderResolver.backfilled(
                rawEntry,
                helperBinaryPath: helperBinaryPath
            )
            if let existingIndex = catalog.models.firstIndex(where: { $0.id == entry.id }) {
                let existing = catalog.models[existingIndex]
                if importedCatalogEntryNeedsVerification(
                    existing: existing,
                    incoming: entry,
                    health: healthByModelID[entry.id]
                ) {
                    verificationModelIDs.append(entry.id)
                }
                catalog.models[existingIndex] = entry
            } else {
                catalog.models.append(entry)
                newModelIDs.append(entry.id)
                verificationModelIDs.append(entry.id)
            }
            upsertCatalogModel(entry)
        }

        catalog.updatedAt = Date().timeIntervalSince1970
        ModelCatalogStorage.save(catalog)

        let base = SharedPaths.appGroupDirectory() ?? SharedPaths.ensureHubDirectory()
        _ = LocalProviderPackRegistry.syncAutoManagedPacks(
            baseDir: base,
            catalog: catalog,
            helperBinaryPath: helperBinaryPath
        )

        let verificationIDs = Array(NSOrderedSet(array: verificationModelIDs)) as? [String] ?? verificationModelIDs
        if !verificationIDs.isEmpty {
            HubStore.shared.preflightLocalModelHealth(for: verificationIDs)
        }

        if autoBenchNewModels {
            for modelID in verificationIDs {
                scheduleDefaultBenchIfNeeded(forModelId: modelID)
            }
        }

        return verificationIDs.isEmpty ? newModelIDs : verificationIDs
    }

    private func importedCatalogEntryNeedsVerification(
        existing: ModelCatalogEntry,
        incoming: ModelCatalogEntry,
        health: LocalModelHealthRecord?
    ) -> Bool {
        if existing != incoming {
            return true
        }
        switch LocalModelHealthSupport.effectiveState(for: health) {
        case .healthy?:
            return false
        case .degraded?, .blockedReadiness?, .blockedRuntime?, .unknownStale?, nil:
            return true
        }
    }

    func scheduleDefaultBenchIfNeeded(forModelId modelId: String) {
        guard let model = snapshot.models.first(where: { $0.id == modelId }) else { return }
        if preferredBenchResult(for: model) != nil {
            return
        }
        enqueue(action: "bench", modelId: modelId)
    }
}
