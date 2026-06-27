import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated private static func mergeRemoteModels(
        _ base: ModelStateSnapshot,
        exportableRemoteModels: [RemoteModelEntry]? = nil
    ) -> ModelStateSnapshot {
        let remote = exportableRemoteModels ?? RemoteModelStorage.exportableEnabledModels()
        // Keep local models (with a modelPath). Remove stale remote entries before re-adding.
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

    nonisolated static func refreshedBaseModelSnapshots(
        catalog: ModelCatalogSnapshot,
        state: ModelStateSnapshot,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default,
        reconcileManagedLocalModels: Bool = true,
        systemVoiceTTSBinaryPath: String = systemVoiceTTSDefaultBinaryPath,
        exportableRemoteModels: [RemoteModelEntry]? = nil
    ) -> (catalog: ModelCatalogSnapshot, state: ModelStateSnapshot) {
        guard reconcileManagedLocalModels else {
            return (
                catalog: catalog,
                state: mergeRemoteModels(state, exportableRemoteModels: exportableRemoteModels)
            )
        }

        let systemVoiceSnapshots = refreshedSystemVoiceTTSModelSnapshots(
            catalog: catalog,
            state: state,
            baseDir: baseDir,
            fileManager: fileManager,
            binaryPath: systemVoiceTTSBinaryPath
        )

        let reconciled = reconciledManagedLocalModelSnapshots(
            catalog: systemVoiceSnapshots.catalog,
            state: systemVoiceSnapshots.state,
            baseDir: baseDir,
            fileManager: fileManager
        )
        return (
            catalog: reconciled.catalog,
            state: mergeRemoteModels(reconciled.state, exportableRemoteModels: exportableRemoteModels)
        )
    }

    nonisolated private static func refreshedSystemVoiceTTSModelSnapshots(
        catalog: ModelCatalogSnapshot,
        state: ModelStateSnapshot,
        baseDir: URL,
        fileManager: FileManager,
        binaryPath: String
    ) -> (catalog: ModelCatalogSnapshot, state: ModelStateSnapshot) {
        guard isSystemVoiceTTSAvailable(binaryPath: binaryPath, fileManager: fileManager) else {
            return snapshotsRemovingSystemVoiceTTSIfPresent(catalog: catalog, state: state)
        }

        let modelDirectory = baseDir
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(systemVoiceTTSModelID, isDirectory: true)
        do {
            try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        } catch {
            HubDiagnostics.log(
                "system_voice_tts_bootstrap_directory_failed error=\(error.localizedDescription)"
            )
            return (catalog, state)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            HubDiagnostics.log("system_voice_tts_bootstrap_directory_missing path=\(modelDirectory.path)")
            return (catalog, state)
        }

        let entry = systemVoiceTTSCatalogEntry(modelPath: modelDirectory.path)
        let stateModel = systemVoiceTTSStateModel(from: entry)

        var updatedCatalog = catalog
        let catalogChanged = upsertSystemVoiceTTSCatalogEntry(entry, into: &updatedCatalog.models)
        if catalogChanged {
            updatedCatalog.updatedAt = Date().timeIntervalSince1970
        }

        var updatedState = state
        let stateChanged = upsertSystemVoiceTTSStateModel(stateModel, into: &updatedState.models)
        if stateChanged {
            updatedState.updatedAt = Date().timeIntervalSince1970
        }

        return (updatedCatalog, updatedState)
    }

    nonisolated private static func snapshotsRemovingSystemVoiceTTSIfPresent(
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

    nonisolated private static func isSystemVoiceTTSAvailable(
        binaryPath: String,
        fileManager: FileManager
    ) -> Bool {
        let trimmed = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.contains("/") || trimmed.hasPrefix(".") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return fileManager.isExecutableFile(atPath: expanded)
        }

        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in pathValue.split(separator: ":") {
            let path = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(trimmed)
                .path
            if fileManager.isExecutableFile(atPath: path) {
                return true
            }
        }
        return false
    }

    nonisolated private static func systemVoiceTTSCatalogEntry(modelPath: String) -> ModelCatalogEntry {
        ModelCatalogEntry(
            id: systemVoiceTTSModelID,
            name: "macOS System Voice TTS",
            backend: "transformers",
            quant: "system",
            contextLength: 6000,
            maxContextLength: 6000,
            paramsB: 0.0,
            modelPath: modelPath,
            roles: ["tts", "voice"],
            note: systemVoiceTTSNote,
            modelFormat: "system_voice",
            defaultLoadProfile: LocalModelLoadProfile(contextLength: 6000),
            taskKinds: ["text_to_speech"],
            inputModalities: ["text"],
            outputModalities: ["audio"],
            offlineReady: true,
            voiceProfile: ModelVoiceProfile(
                languageHints: ["multi", "zh", "en"],
                styleHints: ["neutral", "clear", "warm", "calm"],
                engineHints: ["system_voice"]
            ),
            resourceProfile: ModelResourceProfile(
                preferredDevice: "cpu",
                memoryFloorMB: 64,
                dtype: "system"
            ),
            trustProfile: ModelTrustProfile(
                allowSecretInput: false,
                allowRemoteExport: false
            ),
            processorRequirements: ModelProcessorRequirements(
                tokenizerRequired: false,
                processorRequired: false,
                featureExtractorRequired: false
            )
        )
    }

    nonisolated private static func systemVoiceTTSStateModel(from entry: ModelCatalogEntry) -> HubModel {
        HubModel(
            id: entry.id,
            name: entry.name,
            backend: entry.backend,
            runtimeProviderID: entry.runtimeProviderID,
            quant: entry.quant,
            contextLength: entry.contextLength,
            maxContextLength: entry.maxContextLength,
            paramsB: entry.paramsB,
            roles: entry.roles,
            state: .available,
            modelPath: entry.modelPath,
            note: entry.note,
            modelFormat: entry.modelFormat,
            defaultLoadProfile: entry.defaultLoadProfile,
            taskKinds: entry.taskKinds,
            inputModalities: entry.inputModalities,
            outputModalities: entry.outputModalities,
            offlineReady: entry.offlineReady,
            voiceProfile: entry.voiceProfile,
            resourceProfile: entry.resourceProfile,
            trustProfile: entry.trustProfile,
            processorRequirements: entry.processorRequirements
        )
    }

    nonisolated private static func upsertSystemVoiceTTSCatalogEntry(
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

    nonisolated private static func upsertSystemVoiceTTSStateModel(
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
