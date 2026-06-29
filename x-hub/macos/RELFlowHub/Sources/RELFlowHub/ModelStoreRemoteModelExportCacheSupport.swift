import Foundation
import RELFlowHubCore

extension ModelStore {
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
}
