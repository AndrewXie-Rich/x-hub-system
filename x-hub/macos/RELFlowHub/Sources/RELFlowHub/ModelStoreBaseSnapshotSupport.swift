import Foundation
import RELFlowHubCore

extension ModelStore {
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

}
