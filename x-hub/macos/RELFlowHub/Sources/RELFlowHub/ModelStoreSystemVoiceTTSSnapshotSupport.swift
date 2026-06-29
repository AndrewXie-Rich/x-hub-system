import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func refreshedSystemVoiceTTSModelSnapshots(
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
}
