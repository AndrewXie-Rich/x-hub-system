import Foundation
import RELFlowHubCore

extension ModelStore {
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

        // Update catalog for routing/runtime.
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
}
