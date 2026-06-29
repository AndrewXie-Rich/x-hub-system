import Foundation
import RELFlowHubCore

extension ModelStore {
    func removeModel(modelId: String, deleteLocalFiles: Bool) {
        let rid = modelId

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

        var cat = ModelCatalogStorage.load()
        let removedEntry = cat.models.first(where: { $0.id == rid })
        cat.models.removeAll { $0.id == rid }
        ModelCatalogStorage.save(cat)

        var cur = curBefore
        cur.models.removeAll { $0.id == rid }
        cur.updatedAt = Date().timeIntervalSince1970
        ModelStateStorage.save(cur)
        snapshot = cur

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
