import Foundation
import RELFlowHubCore

enum LocalModelManagedStorage {
    static func managedModelsDirectory(
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> URL {
        baseDir.appendingPathComponent("models", isDirectory: true)
    }

    static func managedModelURL(
        modelID: String,
        modelPath: String,
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> URL {
        let sourceURL = URL(fileURLWithPath: modelPath)
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let leafName = ext.isEmpty ? modelID : "\(modelID).\(ext.lowercased())"
        return managedModelsDirectory(baseDir: baseDir).appendingPathComponent(leafName, isDirectory: ext.isEmpty)
    }

    static func isManagedPath(
        _ modelPath: String,
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> Bool {
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }

        let managedRoot = managedModelsDirectory(baseDir: baseDir).standardizedFileURL.path
        let candidate = URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
        return candidate == managedRoot || candidate.hasPrefix(managedRoot + "/")
    }

    static func needsManagedPreparation(
        modelPath: String,
        sandboxed: Bool = SharedPaths.isSandboxedProcess(),
        baseDir: URL = SharedPaths.ensureHubDirectory()
    ) -> Bool {
        guard sandboxed else { return false }
        let trimmedPath = modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return false }
        return !isManagedPath(trimmedPath, baseDir: baseDir)
    }

    static func preparedCatalogEntryIfNeeded(
        _ entry: ModelCatalogEntry,
        sandboxed: Bool = SharedPaths.isSandboxedProcess(),
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) throws -> ModelCatalogEntry {
        let trimmedPath = entry.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sandboxed, !trimmedPath.isEmpty else { return entry }

        let managedNote = preferredManagedNote(for: entry.note)
        var updated = entry
        if isManagedPath(trimmedPath, baseDir: baseDir) {
            updated.note = managedNote
            return updated
        }

        let destination = managedModelURL(
            modelID: entry.id,
            modelPath: trimmedPath,
            baseDir: baseDir
        )
        if destinationLooksImportable(destination, fileManager: fileManager) {
            updated.modelPath = destination.path
            updated.note = managedNote
            return updated
        }

        let sourceURL = URL(fileURLWithPath: trimmedPath)
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: sourceURL.path])
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)

        updated.modelPath = destination.path
        updated.note = managedNote
        return updated
    }

    static func relinkedCatalogEntryIfManagedCopyExists(
        _ entry: ModelCatalogEntry,
        baseDir: URL = SharedPaths.ensureHubDirectory(),
        fileManager: FileManager = .default
    ) -> ModelCatalogEntry? {
        let trimmedPath = entry.modelPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        guard !isManagedPath(trimmedPath, baseDir: baseDir) else { return nil }

        let destination = managedModelURL(
            modelID: entry.id,
            modelPath: trimmedPath,
            baseDir: baseDir
        )
        guard destinationLooksImportable(destination, fileManager: fileManager) else {
            return nil
        }

        var updated = entry
        updated.modelPath = destination.path
        updated.note = preferredManagedNote(for: entry.note)
        return updated
    }

    static func preferredManagedNote(for note: String?) -> String {
        let normalized = (note ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized == "lmstudio_managed" || normalized == "lmstudio_managed_copy" {
            return "lmstudio_managed_copy"
        }
        return "managed_copy"
    }

    private static func destinationLooksImportable(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue {
            return directoryLooksLikeLocalModel(url, fileManager: fileManager)
        }

        let ext = url.pathExtension.lowercased()
        return ["gguf", "safetensors", "bin"].contains(ext)
    }

    private static func directoryLooksLikeLocalModel(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
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
