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

    func updateRoles(modelId: String, roles: [String]) {
        let rid = modelId
        let cleaned: [String] = {
            var out: [String] = []
            var seen: Set<String> = []
            for r0 in roles {
                let r = r0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if r.isEmpty { continue }
                if seen.contains(r) { continue }
                seen.insert(r)
                out.append(r)
            }
            return out
        }()

        // Update catalog (for routing/runtime).
        var cat = ModelCatalogStorage.load()
        if let idx = cat.models.firstIndex(where: { $0.id == rid }) {
            cat.models[idx].roles = cleaned
            ModelCatalogStorage.save(cat)
            upsertCatalogModel(cat.models[idx])
            return
        }

        // If not in catalog yet, best-effort synthesize an entry from the current state.
        let cur = ModelStateStorage.load()
        guard let m = cur.models.first(where: { $0.id == rid }) else {
            return
        }
        guard let mp = m.modelPath, !mp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No model path means runtime can't load it anyway.
            var cur2 = cur
            if let idx = cur2.models.firstIndex(where: { $0.id == rid }) {
                cur2.models[idx].roles = cleaned
                cur2.updatedAt = Date().timeIntervalSince1970
                ModelStateStorage.save(cur2)
                snapshot = cur2
            }
            return
        }

        let entry = ModelCatalogEntry(
            id: m.id,
            name: m.name,
            backend: m.backend,
            runtimeProviderID: m.runtimeProviderID,
            quant: m.quant,
            contextLength: m.contextLength,
            paramsB: m.paramsB,
            modelPath: mp,
            roles: cleaned,
            note: m.note,
            modelFormat: m.modelFormat,
            taskKinds: m.taskKinds,
            inputModalities: m.inputModalities,
            outputModalities: m.outputModalities,
            offlineReady: m.offlineReady,
            voiceProfile: m.voiceProfile,
            resourceProfile: m.resourceProfile,
            trustProfile: m.trustProfile,
            processorRequirements: m.processorRequirements
        )
        cat.models.append(entry)
        ModelCatalogStorage.save(cat)
        upsertCatalogModel(entry)
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

    func removeModel(modelId: String, deleteLocalFiles: Bool) {
        let rid = modelId

        // Capture current info before mutation.
        let curBefore = ModelStateStorage.load()
        let stateModel = curBefore.models.first(where: { $0.id == rid })
        let localDeletionURL = deleteLocalFiles
            ? Self.deletableLocalModelURL(
                modelPath: removedModelPath(
                    removedEntry: nil,
                    stateModel: stateModel
                ),
                note: removedModelNote(
                    removedEntry: nil,
                    stateModel: stateModel
                )
            )
            : nil

        // 1) Remove from catalog.
        var cat = ModelCatalogStorage.load()
        let removedEntry = cat.models.first(where: { $0.id == rid })
        cat.models.removeAll { $0.id == rid }
        ModelCatalogStorage.save(cat)

        // 2) Remove from state snapshot.
        var cur = curBefore
        cur.models.removeAll { $0.id == rid }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur

        // 3) Clear pending/result UI state.
        pendingByModelId.removeValue(forKey: rid)
        lastResultByModelId.removeValue(forKey: rid)
        successfulLocalLifecycleActionsByModelId.removeValue(forKey: rid)
        currentLocalRuntimeRequestContextByModelId.removeValue(forKey: rid)
        LocalModelRuntimeTargetPreferencesStorage.remove(modelId: rid)

        if benchSnapshot.results.contains(where: { $0.modelId == rid }) {
            benchSnapshot = ModelsBenchSnapshot(
                schemaVersion: benchSnapshot.schemaVersion,
                results: benchSnapshot.results.filter { $0.modelId != rid },
                updatedAt: Date().timeIntervalSince1970
            )
            ModelBenchStorage.save(benchSnapshot)
        }

        guard deleteLocalFiles else { return }
        let finalDeletionURL = localDeletionURL
            ?? Self.deletableLocalModelURL(
                modelPath: removedModelPath(removedEntry: removedEntry, stateModel: stateModel),
                note: removedModelNote(removedEntry: removedEntry, stateModel: stateModel)
            )
        if let finalDeletionURL {
            try? FileManager.default.removeItem(at: finalDeletionURL)
        }
    }

    func canDeleteLocalFiles(for model: HubModel) -> Bool {
        Self.deletableLocalModelURL(modelPath: model.modelPath ?? "", note: model.note ?? "") != nil
    }

    private func removedModelPath(
        removedEntry: ModelCatalogEntry?,
        stateModel: HubModel?
    ) -> String {
        (removedEntry?.modelPath ?? stateModel?.modelPath ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removedModelNote(
        removedEntry: ModelCatalogEntry?,
        stateModel: HubModel?
    ) -> String {
        (removedEntry?.note ?? stateModel?.note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func deletableLocalModelURL(
        modelPath: String,
        note: String
    ) -> URL? {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }

        let url = URL(fileURLWithPath: trimmedPath).standardizedFileURL
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard url.path != "/" else { return nil }
        guard url.path != SharedPaths.realHomeDirectory().standardizedFileURL.path else { return nil }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue {
            guard directoryLooksLikeLocalModel(url, note: note, fileManager: fileManager) else {
                return nil
            }
            return url
        }

        let ext = url.pathExtension.lowercased()
        return ["gguf", "safetensors", "bin"].contains(ext) ? url : nil
    }

    private static func directoryLooksLikeLocalModel(
        _ url: URL,
        note: String,
        fileManager: FileManager
    ) -> Bool {
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedNote == "managed_copy"
            || normalizedNote == "lmstudio_managed"
            || normalizedNote == "lmstudio_managed_copy" {
            return true
        }

        guard let entries = try? fileManager.contentsOfDirectory(atPath: url.path) else {
            return false
        }
        let lowered = Set(entries.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        let markerFiles: Set<String> = [
            "config.json",
            "xhub_model_manifest.json",
            "model.safetensors.index.json",
            "consolidated.safetensors.index.json",
            "weights.npz",
            "processor_config.json",
            "preprocessor_config.json",
            "tokenizer.json",
            "tokenizer_config.json",
        ]
        if !lowered.isDisjoint(with: markerFiles) {
            return true
        }

        return lowered.contains(where: { name in
            name.hasSuffix(".gguf") || name.hasSuffix(".safetensors")
        })
    }

}
