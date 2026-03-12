import Foundation

public struct RemoteModelEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var backend: String
    public var contextLength: Int
    public var enabled: Bool
    public var baseURL: String?
    // Optional indirection for API keys shared across multiple remote models.
    // When set, the key is stored/read from Keychain using this account instead of `id`.
    public var apiKeyRef: String?
    // Local alias used by Hub/Coder. Upstream provider calls use this value when set.
    public var upstreamModelId: String?
    // Decrypted API key in memory only. It is never persisted to disk.
    public var apiKey: String?
    // Encrypted API key payload for disk persistence fallback.
    public var apiKeyCiphertext: String?
    public var note: String?

    public init(
        id: String,
        name: String,
        backend: String,
        contextLength: Int = 8192,
        enabled: Bool = true,
        baseURL: String? = nil,
        apiKeyRef: String? = nil,
        upstreamModelId: String? = nil,
        apiKey: String? = nil,
        apiKeyCiphertext: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.backend = backend
        self.contextLength = contextLength
        self.enabled = enabled
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.upstreamModelId = upstreamModelId
        self.apiKey = apiKey
        self.apiKeyCiphertext = apiKeyCiphertext
        self.note = note
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case backend
        case contextLength
        case enabled
        case baseURL
        case apiKeyRef
        case upstreamModelId
        case apiKey
        case apiKeyCiphertext
        case note
    }
}

public struct RemoteModelSnapshot: Codable, Sendable, Equatable {
    public var models: [RemoteModelEntry]
    public var updatedAt: Double

    public init(models: [RemoteModelEntry], updatedAt: Double) {
        self.models = models
        self.updatedAt = updatedAt
    }

    public static func empty() -> RemoteModelSnapshot {
        RemoteModelSnapshot(models: [], updatedAt: Date().timeIntervalSince1970)
    }
}

public enum RemoteModelStorage {
    public static let fileName = "remote_models.json"

    public static func syncEnabledRemoteModelsIntoModelState() {
        let snap = load()
        syncEnabledRemoteModelsIntoModelState(snap)
    }

    public static func exportableEnabledModels() -> [RemoteModelEntry] {
        exportableEnabledModels(from: load())
    }

    public static func exportableEnabledModels(from snap: RemoteModelSnapshot) -> [RemoteModelEntry] {
        snap.models.filter(isExecutionReadyRemoteModel)
    }

    public static func isExecutionReadyRemoteModel(_ model: RemoteModelEntry) -> Bool {
        guard model.enabled else { return false }
        let modelID = trimmed(model.id)
        guard !modelID.isEmpty else { return false }

        let apiKey = trimmed(model.apiKey)
        guard !apiKey.isEmpty else { return false }
        guard hasValidExplicitBaseURL(model.baseURL) else { return false }

        let providerModel = providerModelId(for: model)
        guard !providerModel.isEmpty else { return false }

        let backend = RemoteProviderEndpoints.canonicalBackend(model.backend)
        switch backend {
        case "anthropic":
            return RemoteProviderEndpoints.anthropicMessagesURL(baseURL: model.baseURL) != nil
        case "gemini":
            return RemoteProviderEndpoints.geminiGenerateURL(
                baseURL: model.baseURL,
                modelId: providerModel,
                apiKey: apiKey
            ) != nil
        default:
            return RemoteProviderEndpoints.openAIChatCompletionsURL(
                baseURL: model.baseURL,
                backend: backend
            ) != nil
        }
    }

    public static func url() -> URL {
        if let g = SharedPaths.appGroupDirectory() {
            return g.appendingPathComponent(fileName)
        }
        // Keep remote_models.json co-located with models_state.json so both the app UI
        // and headless components (gRPC server / python runtime) converge on one base dir.
        //
        // NOTE: Sandboxed builds may not be able to write to global /private/tmp without
        // a temporary-exception entitlement. The Hub directory (container/home/app-group)
        // is always writable and is already where models_state.json lives.
        return SharedPaths.ensureHubDirectory().appendingPathComponent(fileName)
    }

    public static func load() -> RemoteModelSnapshot {
        let primaryURL = url()
        guard let sourceURL = readableSnapshotURL(),
              let data = try? Data(contentsOf: sourceURL),
              var obj = try? JSONDecoder().decode(RemoteModelSnapshot.self, from: data) else {
            return .empty()
        }

        var needsResave = false
        for i in obj.models.indices {
            var m = obj.models[i]
            let account = keyReference(for: m)
            let fileKey = trimmed(m.apiKey)
            let ciphertext = trimmed(m.apiKeyCiphertext)

            var resolvedKey = ""
            // Prefer the encrypted-on-disk ciphertext first so startup/refresh loops don't
            // trigger Keychain prompts. Keychain is only used as a migration/last-resort path.
            if !ciphertext.isEmpty {
                if let decrypted = RemoteSecretsStore.decrypt(ciphertext) {
                    resolvedKey = trimmed(decrypted)
                } else {
                    // Ciphertext cannot be decrypted with current secret key.
                    m.apiKeyCiphertext = nil
                    needsResave = true
                }
            }

            if resolvedKey.isEmpty, !fileKey.isEmpty {
                // Legacy plaintext migration path.
                resolvedKey = fileKey
                needsResave = true
            }

            if resolvedKey.isEmpty, KeychainStore.hasSharedAccessGroup, !account.isEmpty, let kc = KeychainStore.get(account: account) {
                resolvedKey = trimmed(kc)
            }

            if !resolvedKey.isEmpty {
                m.apiKey = resolvedKey
                // IMPORTANT: do NOT mirror secrets back into Keychain on every load.
                // ModelStore.refresh() calls RemoteModelStorage.load() frequently, and Keychain
                // access can trigger repeated password prompts (especially in sandboxed builds).
                //
                // Keychain remains a migration/optional persistence path handled in save()/UI flows.
                if trimmed(m.apiKeyCiphertext).isEmpty,
                   let encrypted = RemoteSecretsStore.encrypt(resolvedKey) {
                    m.apiKeyCiphertext = encrypted
                    needsResave = true
                }
            } else {
                m.apiKey = nil
            }

            if !fileKey.isEmpty {
                // Never persist plaintext back to disk.
                needsResave = true
            }

            obj.models[i] = m
        }

        if needsResave || sourceURL.path != primaryURL.path {
            save(obj)
        }

        return obj
    }

    public static func save(_ snap: RemoteModelSnapshot) {
        var cur = snap
        cur.updatedAt = Date().timeIntervalSince1970
        let url = url()

        for i in cur.models.indices {
            var m = cur.models[i]
            let key = trimmed(m.apiKey)
            let account = keyReference(for: m)

            if !key.isEmpty {
                if KeychainStore.hasSharedAccessGroup, !account.isEmpty {
                    _ = KeychainStore.set(account: account, value: key)
                }
                if let encrypted = RemoteSecretsStore.encrypt(key) {
                    m.apiKeyCiphertext = encrypted
                }
            } else if trimmed(m.apiKeyCiphertext).isEmpty,
                      KeychainStore.hasSharedAccessGroup,
                      !account.isEmpty,
                      let kc = KeychainStore.get(account: account),
                      let encrypted = RemoteSecretsStore.encrypt(kc) {
                m.apiKeyCiphertext = encrypted
            }

            // Never persist plaintext API keys.
            m.apiKey = nil
            cur.models[i] = m
        }

        if let data = try? JSONEncoder().encode(cur) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }

        // Keep models_state.json authoritative for both local and remote models.
        // This makes headless operation (gRPC-only Hub) work even when the UI isn't refreshing ModelStore.
        syncEnabledRemoteModelsIntoModelState(cur)
    }

    public static func upsert(_ entry: RemoteModelEntry) -> RemoteModelSnapshot {
        var cur = load()
        if let idx = cur.models.firstIndex(where: { $0.id == entry.id }) {
            var merged = entry
            let hasIncomingKey = !trimmed(entry.apiKey).isEmpty
            if !hasIncomingKey {
                merged.apiKey = cur.models[idx].apiKey
                if trimmed(merged.apiKeyCiphertext).isEmpty {
                    merged.apiKeyCiphertext = cur.models[idx].apiKeyCiphertext
                }
                if trimmed(merged.apiKeyRef).isEmpty {
                    merged.apiKeyRef = cur.models[idx].apiKeyRef
                }
            }
            if trimmed(merged.upstreamModelId).isEmpty {
                merged.upstreamModelId = cur.models[idx].upstreamModelId
            }
            cur.models[idx] = merged
        } else {
            cur.models.append(entry)
        }
        save(cur)
        return load()
    }

    public static func remove(id: String) -> RemoteModelSnapshot {
        var cur = load()
        let removed = cur.models.first { $0.id == id }
        cur.models.removeAll { $0.id == id }
        save(cur)

        let acct = keyReference(for: removed)
        if KeychainStore.hasSharedAccessGroup, !acct.isEmpty {
            let stillUsed = cur.models.contains { m in
                keyReference(for: m) == acct
            }
            if !stillUsed {
                _ = KeychainStore.delete(account: acct)
            }
        }

        return load()
    }

    public static func removeGroup(keyReference rawKeyReference: String) -> RemoteModelSnapshot {
        let groupKey = trimmed(rawKeyReference)
        guard !groupKey.isEmpty else { return load() }

        var cur = load()
        let removedAny = cur.models.contains { keyReference(for: $0) == groupKey }
        guard removedAny else { return cur }

        cur.models.removeAll { keyReference(for: $0) == groupKey }
        save(cur)

        if KeychainStore.hasSharedAccessGroup {
            _ = KeychainStore.delete(account: groupKey)
        }

        return load()
    }

    public static func keyReference(for model: RemoteModelEntry?) -> String {
        guard let model else { return "" }
        return trimmed(model.apiKeyRef).isEmpty ? trimmed(model.id) : trimmed(model.apiKeyRef)
    }

    private static func readableSnapshotURL() -> URL? {
        let primary = url()
        if decodeSnapshot(at: primary) != nil {
            return primary
        }
        for legacy in legacyURLs() {
            if decodeSnapshot(at: legacy) != nil {
                return legacy
            }
        }
        return nil
    }

    private static func decodeSnapshot(at url: URL) -> RemoteModelSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RemoteModelSnapshot.self, from: data)
    }

    private static func syncEnabledRemoteModelsIntoModelState(_ snap: RemoteModelSnapshot) {
        // Only include enabled remote models that can actually be executed now.
        let enabled = exportableEnabledModels(from: snap)
        if enabled.isEmpty {
            // Best-effort: prune any stale remote entries.
            let base = ModelStateStorage.load()
            let localOnly = base.models.filter { !isRemoteStateModel($0) }
            if localOnly != base.models {
                ModelStateStorage.save(ModelStateSnapshot(models: localOnly, updatedAt: Date().timeIntervalSince1970))
            }
            return
        }

        let base = ModelStateStorage.load()
        let localOnly = base.models.filter { !isRemoteStateModel($0) }
        var seenIds: Set<String> = []
        for m in localOnly {
            let id = m.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty {
                seenIds.insert(id)
            }
        }

        let remoteSorted = enabled.sorted {
            let ab = $0.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let bb = $1.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ab != bb { return ab < bb }
            let an = $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let bn = $1.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if an != bn { return an < bn }
            let ai = $0.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let bi = $1.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ai < bi
        }

        var remoteEntries: [HubModel] = []
        for r in remoteSorted {
            let rid = r.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if rid.isEmpty { continue }
            if seenIds.contains(rid) {
                // Prefer a local entry when ids collide.
                continue
            }
            let backend = r.backend.trimmingCharacters(in: .whitespacesAndNewlines)
            if backend.isEmpty { continue }
            let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
            remoteEntries.append(
                HubModel(
                    id: rid,
                    name: name.isEmpty ? rid : name,
                    backend: backend,
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
            )
        }

        let merged = localOnly + remoteEntries
        if merged != base.models {
            ModelStateStorage.save(ModelStateSnapshot(models: merged, updatedAt: Date().timeIntervalSince1970))
        }
    }

    private static func isRemoteStateModel(_ m: HubModel) -> Bool {
        let backend = m.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if backend.isEmpty || backend == "mlx" {
            return false
        }
        let mp = (m.modelPath ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return mp.isEmpty
    }

    private static func legacyURLs() -> [URL] {
        let primary = url().path
        var cands: [URL] = []

        if let container = SharedPaths.containerDataDirectory()?.appendingPathComponent("RELFlowHub", isDirectory: true) {
            cands.append(container.appendingPathComponent(fileName))
        }
        cands.append(SharedPaths.sandboxHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(fileName))
        cands.append(URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(fileName))
        cands.append(SharedPaths.realHomeDirectory().appendingPathComponent("RELFlowHub", isDirectory: true).appendingPathComponent(fileName))
        cands.append(SharedPaths.ensureHubDirectory().appendingPathComponent(fileName))

        var out: [URL] = []
        var seen: Set<String> = []
        for u in cands {
            let p = u.path
            if p == primary { continue }
            if seen.contains(p) { continue }
            seen.insert(p)
            out.append(u)
        }
        return out
    }

    private static func trimmed(_ raw: String?) -> String {
        (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasValidExplicitBaseURL(_ raw: String?) -> Bool {
        let trimmedBase = trimmed(raw)
        guard !trimmedBase.isEmpty else { return true }
        let candidate = trimmedBase.replacingOccurrences(of: "{model}", with: "model")
        guard let comps = URLComponents(string: candidate) else { return false }
        guard let scheme = comps.scheme?.trimmingCharacters(in: .whitespacesAndNewlines),
              !scheme.isEmpty else { return false }
        guard let host = comps.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty else { return false }
        return true
    }

    private static func providerModelId(for remote: RemoteModelEntry) -> String {
        let raw = trimmed(remote.upstreamModelId)
        let model = raw.isEmpty ? trimmed(remote.id) : raw
        let backend = RemoteProviderEndpoints.canonicalBackend(remote.backend)
        if backend == "gemini" || backend == "remote_catalog" {
            return RemoteProviderEndpoints.stripModelRef(model)
        }
        if model.hasPrefix("models/") {
            return RemoteProviderEndpoints.stripModelRef(model)
        }
        return model
    }
}
