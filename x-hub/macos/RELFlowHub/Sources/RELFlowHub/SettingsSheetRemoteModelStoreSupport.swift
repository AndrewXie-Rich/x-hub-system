import Foundation
import RELFlowHubCore

extension SettingsSheetView {
    static func sortedRemoteModels(_ models: [RemoteModelEntry]) -> [RemoteModelEntry] {
        RemoteModelPresentationSupport.sorted(models)
    }

    nonisolated static func makeRemoteModelGroupsSnapshot(
        from models: [RemoteModelEntry],
        healthSnapshot: RemoteKeyHealthSnapshot
    ) -> [RemoteModelKeyGroup] {
        RemoteModelPresentationSupport.groups(
            from: models,
            healthSnapshot: healthSnapshot
        )
        .map { group in
            RemoteModelKeyGroup(
                id: group.id,
                keyReference: group.keyReference,
                title: group.title,
                detail: group.detail,
                models: group.models,
                loadedCount: group.loadedCount,
                availableCount: group.availableCount,
                needsSetupCount: group.needsSetupCount,
                enabledCount: group.enabledCount
            )
        }
    }

    func rebuildRemoteModelGroupsSnapshot() {
        let models = remoteModels
        let healthSnapshot = store.remoteKeyHealthSnapshot
        remoteModelGroupsBuildTask?.cancel()
        remoteModelGroupsBuildTask = Task { @MainActor in
            let groups = await Task.detached(priority: .utility) {
                Self.makeRemoteModelGroupsSnapshot(
                    from: models,
                    healthSnapshot: healthSnapshot
                )
            }.value
            guard !Task.isCancelled else { return }
            remoteModelGroupsSnapshot = groups
        }
    }

    func reloadRemoteModels() {
        remoteModels = Self.sortedRemoteModels(RemoteModelStorage.load().models)
        rebuildRemoteModelGroupsSnapshot()
        if selectedSettingsPage == .models && providerQuotaOperationsExpanded {
            rebuildRemoteQuotaProjectionSnapshot()
        }
    }

    func upsertRemoteModel(_ entry: RemoteModelEntry) {
        upsertRemoteModels([entry])
    }

    func upsertRemoteModels(_ entries: [RemoteModelEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            _ = RemoteModelStorage.upsert(entry)
        }
        remoteModels = Self.sortedRemoteModels(RemoteModelStorage.load().models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    func removeRemoteModel(id: String) {
        let snap = RemoteModelStorage.remove(id: id)
        remoteModels = Self.sortedRemoteModels(snap.models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    func removeRemoteModelGroup(_ group: RemoteModelKeyGroup) {
        let snap = RemoteModelStorage.remove(ids: group.models.map(\.id))
        remoteModels = Self.sortedRemoteModels(snap.models)
        rebuildRemoteModelGroupsSnapshot()
        ModelStore.shared.refresh()
    }

    func updateRemoteModelGroupDisplayName(_ group: RemoteModelKeyGroup, displayName: String) {
        let normalized = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelIDs = Set(group.models.map(\.id))
        guard !modelIDs.isEmpty else { return }

        for index in remoteModels.indices where modelIDs.contains(remoteModels[index].id) {
            remoteModels[index].groupDisplayName = normalized.isEmpty ? nil : normalized
        }
        remoteModels = Self.sortedRemoteModels(remoteModels)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    func setRemoteModelsEnabled(_ modelIDs: [String], enabled: Bool) {
        let ids = Set(modelIDs)
        guard !ids.isEmpty else { return }

        var updated = remoteModels
        var changed = false
        for index in updated.indices where ids.contains(updated[index].id) {
            if enabled {
                var candidate = updated[index]
                candidate.enabled = true
                guard RemoteModelStorage.isExecutionReadyRemoteModel(candidate) else { continue }
            }

            if updated[index].enabled != enabled {
                updated[index].enabled = enabled
                changed = true
            }
        }

        guard changed else { return }
        remoteModels = Self.sortedRemoteModels(updated)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    private func persistRemoteModels() {
        let snap = RemoteModelSnapshot(models: remoteModels, updatedAt: Date().timeIntervalSince1970)
        RemoteModelStorage.save(snap)
        ModelStore.shared.refresh()
    }

    func importRemoteCatalog(_ result: ImportRemoteCatalogResult) {
        let apiKey = result.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { return }

        let apiKeyRef = "remote_catalog:default"

        let baseURL = RemoteCatalogClient.defaultBaseURL.absoluteString
        let idPrefix = normalizeModelPrefix(result.idPrefix)

        var imported: [RemoteModelEntry] = []
        for raw in result.modelIds {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let baseModelId = normalizeRemoteCatalogModelID(trimmed)
            if baseModelId.isEmpty { continue }

            let fullId: String = {
                if idPrefix.isEmpty { return baseModelId }
                let a = baseModelId.lowercased()
                let p = idPrefix.lowercased()
                if a.hasPrefix(p) { return baseModelId }
                return idPrefix + baseModelId
            }()

            let entry = RemoteModelEntry(
                id: fullId,
                name: remoteCatalogDisplayName(modelId: baseModelId),
                backend: "remote_catalog",
                contextLength: remoteCatalogContextLength(modelId: baseModelId),
                enabled: result.enabled,
                baseURL: baseURL,
                apiKeyRef: apiKeyRef,
                upstreamModelId: baseModelId,
                apiKey: apiKey,
                note: HubUIStrings.Settings.RemoteModels.remoteCatalogNote,
                knownContextLength: remoteCatalogContextLength(modelId: baseModelId),
                knownContextSource: .catalogEstimate
            )
            imported.append(entry)
        }

        if imported.isEmpty {
            return
        }

        var updated = remoteModels
        if result.replaceExisting {
            updated.removeAll { RemoteProviderEndpoints.isRemoteCatalogBackend($0.backend) }
        }
        for m in imported {
            if let idx = updated.firstIndex(where: { $0.id == m.id }) {
                updated[idx] = m
            } else {
                updated.append(m)
            }
        }
        remoteModels = Self.sortedRemoteModels(updated)
        rebuildRemoteModelGroupsSnapshot()
        persistRemoteModels()
    }

    private func normalizeModelPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        // Normalize to "provider/".
        if !s.hasSuffix("/") {
            s += "/"
        }
        return s
    }

    private func normalizeRemoteCatalogModelID(_ raw: String) -> String {
        RemoteProviderEndpoints.stripModelRef(raw)
    }

    private func remoteCatalogDisplayName(modelId: String) -> String {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let map: [String: String] = [
            "gpt-5.1-codex": "GPT-5.1 Codex",
            "gpt-5.1-codex-mini": "GPT-5.1 Codex Mini",
            "gpt-5.1-codex-max": "GPT-5.1 Codex Max",
            "gpt-5.2": "GPT-5.2",
            "gpt-5.1": "GPT-5.1",
            "claude-opus-4-5": "Claude Opus 4.5",
            "gemini-3-pro": "Gemini 3 Pro",
            "gemini-3-flash": "Gemini 3 Flash",
            "glm-4.7": "GLM-4.7",
        ]
        if let v = map[t.lowercased()] {
            return v
        }
        return t
    }

    private func remoteCatalogContextLength(modelId: String) -> Int {
        let t = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return 128_000 }
        let map: [String: Int] = [
            "gpt-5.1-codex": 400_000,
            "gpt-5.1-codex-mini": 400_000,
            "gpt-5.1-codex-max": 400_000,
            "gpt-5.2": 400_000,
            "gpt-5.1": 400_000,
            "claude-opus-4-5": 200_000,
            "gemini-3-pro": 1_048_576,
            "gemini-3-flash": 1_048_576,
            "glm-4.7": 204_800,
        ]
        return map[t] ?? 128_000
    }

    var remoteModelGroups: [RemoteModelKeyGroup] {
        remoteModelGroupsSnapshot
    }
}
