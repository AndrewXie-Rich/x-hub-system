import Foundation
import RELFlowHubCore

extension ModelStore {
    nonisolated static func shouldPrepareManagedLocalModelDuringReconcile(
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

    nonisolated static func shouldPruneMissingManagedLocalModel(
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
