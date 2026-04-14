import Foundation

public extension Notification.Name {
    static let relflowhubRemoteModelsChanged = Notification.Name("relflowhub.remoteModelsChanged")
}

public enum RemoteModelKnownContextSource: String, Codable, Equatable, Sendable {
    case providerReported = "provider_reported"
    case catalogEstimate = "catalog_estimate"
}

public struct RemoteModelEntry: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var groupDisplayName: String?
    public var backend: String
    public var contextLength: Int
    public var enabled: Bool
    public var baseURL: String?
    // Optional indirection for API keys shared across multiple remote models.
    // When set, the key is stored/read from Keychain using this account instead of `id`.
    public var apiKeyRef: String?
    // Local alias used by Hub/Coder. Upstream provider calls use this value when set.
    public var upstreamModelId: String?
    // Optional protocol hint for OpenAI-compatible providers, e.g. "responses".
    public var wireAPI: String?
    // Decrypted API key in memory only. It is never persisted to disk.
    public var apiKey: String?
    // Encrypted API key payload for disk persistence fallback.
    public var apiKeyCiphertext: String?
    public var note: String?
    public var knownContextLength: Int?
    public var knownContextSource: RemoteModelKnownContextSource?

    public init(
        id: String,
        name: String,
        groupDisplayName: String? = nil,
        backend: String,
        contextLength: Int = 8192,
        enabled: Bool = true,
        baseURL: String? = nil,
        apiKeyRef: String? = nil,
        upstreamModelId: String? = nil,
        wireAPI: String? = nil,
        apiKey: String? = nil,
        apiKeyCiphertext: String? = nil,
        note: String? = nil,
        knownContextLength: Int? = nil,
        knownContextSource: RemoteModelKnownContextSource? = nil
    ) {
        self.id = id
        self.name = name
        self.groupDisplayName = groupDisplayName
        self.backend = backend
        self.contextLength = contextLength
        self.enabled = enabled
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.upstreamModelId = upstreamModelId
        self.wireAPI = wireAPI
        self.apiKey = apiKey
        self.apiKeyCiphertext = apiKeyCiphertext
        self.note = note
        if let knownContextLength, knownContextLength > 0 {
            self.knownContextLength = max(512, knownContextLength)
            self.knownContextSource = knownContextSource
        } else {
            self.knownContextLength = nil
            self.knownContextSource = nil
        }
    }

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case groupDisplayName
        case backend
        case contextLength
        case enabled
        case baseURL
        case apiKeyRef
        case upstreamModelId
        case wireAPI
        case apiKey
        case apiKeyCiphertext
        case note
        case knownContextLength
        case knownContextSource
    }
}

public extension RemoteModelEntry {
    var effectiveProviderModelID: String {
        let upstream = (upstreamModelId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !upstream.isEmpty {
            return upstream
        }
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveGroupDisplayName: String? {
        let explicit = (groupDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }

        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            return nil
        }

        let providerModel = effectiveProviderModelID
        let normalizedCandidate = normalizedRemoteModelDisplayToken(candidate)
        if normalizedCandidate == normalizedRemoteModelDisplayToken(providerModel)
            || normalizedCandidate == normalizedRemoteModelDisplayToken(id.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return nil
        }
        return candidate
    }

    var nestedDisplayName: String {
        let candidate = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerModel = effectiveProviderModelID
        let alias = (effectiveGroupDisplayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !candidate.isEmpty,
           normalizedRemoteModelDisplayToken(candidate) != normalizedRemoteModelDisplayToken(alias) {
            return candidate
        }
        if !providerModel.isEmpty {
            return providerModel
        }
        return id.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func normalizedRemoteModelDisplayToken(_ raw: String) -> String {
    raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .unicodeScalars
        .filter(CharacterSet.alphanumerics.contains)
        .map(String.init)
        .joined()
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
        exportableEnabledModels(
            from: load(),
            healthSnapshot: RemoteKeyHealthStorage.load()
        )
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
            switch RemoteProviderEndpoints.resolvedOpenAIWireAPI(model.wireAPI, backend: backend) {
            case .responses:
                return RemoteProviderEndpoints.openAIResponsesURL(
                    baseURL: model.baseURL,
                    backend: backend
                ) != nil
            case .chatCompletions:
                return RemoteProviderEndpoints.openAIChatCompletionsURL(
                    baseURL: model.baseURL,
                    backend: backend
                ) != nil
            }
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
            let groupDisplayName = trimmed(m.groupDisplayName)

            if groupDisplayName.isEmpty, let legacyAlias = m.effectiveGroupDisplayName {
                m.groupDisplayName = legacyAlias
                needsResave = true
            }

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
        NotificationCenter.default.post(name: .relflowhubRemoteModelsChanged, object: nil)
    }

    public static func upsert(_ entry: RemoteModelEntry) -> RemoteModelSnapshot {
        var cur = load()
        let prepared = disambiguatedEntryForUpsert(entry, existing: cur.models)
        if let idx = cur.models.firstIndex(where: { normalizedLookupToken($0.id) == normalizedLookupToken(prepared.id) }) {
            var merged = prepared
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
            if trimmed(merged.groupDisplayName).isEmpty {
                merged.groupDisplayName = cur.models[idx].groupDisplayName
            }
            if trimmed(merged.upstreamModelId).isEmpty {
                merged.upstreamModelId = cur.models[idx].upstreamModelId
            }
            if trimmed(merged.wireAPI).isEmpty {
                merged.wireAPI = cur.models[idx].wireAPI
            }
            cur.models[idx] = merged
        } else {
            cur.models.append(prepared)
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

    public static func remove(ids rawIDs: [String]) -> RemoteModelSnapshot {
        let ids = Set(rawIDs.map(trimmed).filter { !$0.isEmpty })
        guard !ids.isEmpty else { return load() }

        var cur = load()
        let removed = cur.models.filter { ids.contains(trimmed($0.id)) }
        guard !removed.isEmpty else { return cur }

        cur.models.removeAll { ids.contains(trimmed($0.id)) }
        save(cur)

        if KeychainStore.hasSharedAccessGroup {
            let removedAccounts = Set(removed.map { keyReference(for: $0) }.filter { !$0.isEmpty })
            for account in removedAccounts {
                let stillUsed = cur.models.contains { keyReference(for: $0) == account }
                if !stillUsed {
                    _ = KeychainStore.delete(account: account)
                }
            }
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
        let enabled = exportableEnabledModels(
            from: snap,
            healthSnapshot: RemoteKeyHealthStorage.load()
        )
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

        var remoteEntries: [HubModel] = []
        for r in enabled {
            let rid = r.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if rid.isEmpty { continue }
            if seenIds.contains(rid) {
                // Prefer a local entry when ids collide.
                continue
            }
            if let projectedModel = hubStateModel(for: r) {
                remoteEntries.append(projectedModel)
            }
        }

        let merged = localOnly + remoteEntries
        if merged != base.models {
            ModelStateStorage.save(ModelStateSnapshot(models: merged, updatedAt: Date().timeIntervalSince1970))
        }
    }

    static func exportableEnabledModels(
        from snap: RemoteModelSnapshot,
        healthSnapshot: RemoteKeyHealthSnapshot?
    ) -> [RemoteModelEntry] {
        let healthByKey = Dictionary(
            uniqueKeysWithValues: (healthSnapshot?.records ?? []).map { ($0.keyReference, $0) }
        )

        return snap.models
            .filter(isExecutionReadyRemoteModel)
            .sorted { lhs, rhs in
                let lhsKey = keyReference(for: lhs)
                let rhsKey = keyReference(for: rhs)
                let lhsHealth = healthByKey[lhsKey]
                let rhsHealth = healthByKey[rhsKey]
                let lhsPriority = RemoteKeyHealthSupport.sortPriority(for: lhsHealth)
                let rhsPriority = RemoteKeyHealthSupport.sortPriority(for: rhsHealth)
                if lhsPriority != rhsPriority {
                    return lhsPriority < rhsPriority
                }

                if (lhsHealth != nil || rhsHealth != nil), lhsKey != rhsKey {
                    let lhsRecency = RemoteKeyHealthSupport.recency(for: lhsHealth)
                    let rhsRecency = RemoteKeyHealthSupport.recency(for: rhsHealth)
                    if lhsRecency != rhsRecency {
                        return lhsRecency > rhsRecency
                    }
                    if lhsKey.localizedCaseInsensitiveCompare(rhsKey) != .orderedSame {
                        return lhsKey.localizedCaseInsensitiveCompare(rhsKey) == .orderedAscending
                    }
                }

                let lhsBackend = lhs.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rhsBackend = rhs.backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lhsBackend != rhsBackend {
                    return lhsBackend < rhsBackend
                }

                let lhsName = lhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rhsName = rhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lhsName != rhsName {
                    return lhsName < rhsName
                }

                let lhsID = lhs.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let rhsID = rhs.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return lhsID < rhsID
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

    private static func normalizedLookupToken(_ raw: String?) -> String {
        trimmed(raw).lowercased()
    }

    private static func disambiguatedEntryForUpsert(
        _ entry: RemoteModelEntry,
        existing models: [RemoteModelEntry]
    ) -> RemoteModelEntry {
        var prepared = entry
        let resolvedKeyReference = disambiguatedKeyReference(for: prepared, existing: models)
        let requestedKeyReference = trimmed(prepared.apiKeyRef)
        if !resolvedKeyReference.isEmpty,
           !requestedKeyReference.isEmpty || normalizedLookupToken(resolvedKeyReference) != normalizedLookupToken(prepared.id) {
            prepared.apiKeyRef = resolvedKeyReference
        }

        let resolvedModelID = disambiguatedModelID(for: prepared, existing: models)
        if !resolvedModelID.isEmpty {
            prepared.id = resolvedModelID
        }
        return prepared
    }

    private static func disambiguatedKeyReference(
        for entry: RemoteModelEntry,
        existing models: [RemoteModelEntry]
    ) -> String {
        let requested = keyReference(for: entry)
        guard !requested.isEmpty else { return "" }

        let requestedToken = normalizedLookupToken(requested)
        let incomingKey = trimmed(entry.apiKey)
        let exactMatches = models.filter { normalizedLookupToken(keyReference(for: $0)) == requestedToken }
        if exactMatches.isEmpty {
            return requested
        }
        if !incomingKey.isEmpty,
           exactMatches.contains(where: { trimmed($0.apiKey) == incomingKey }) {
            return requested
        }

        let namespaceBase = numericDisambiguationBase(requested)
        let namespaceToken = normalizedLookupToken(namespaceBase)
        let namespaceMatches = models.filter {
            normalizedLookupToken(numericDisambiguationBase(keyReference(for: $0))) == namespaceToken
        }
        if !incomingKey.isEmpty,
           let existingMatch = namespaceMatches.first(where: { trimmed($0.apiKey) == incomingKey }) {
            return keyReference(for: existingMatch)
        }

        let used = Set(namespaceMatches.map { keyReference(for: $0) })
        return nextDisambiguatedValue(base: namespaceBase, used: used)
    }

    private static func disambiguatedModelID(
        for entry: RemoteModelEntry,
        existing models: [RemoteModelEntry]
    ) -> String {
        let requested = trimmed(entry.id)
        guard !requested.isEmpty else { return UUID().uuidString }

        let requestedToken = normalizedLookupToken(requested)
        let exactMatches = models.filter { normalizedLookupToken($0.id) == requestedToken }
        if exactMatches.isEmpty {
            return requested
        }
        if exactMatches.contains(where: { sameRemoteUpsertSlot($0, entry) }) {
            return requested
        }

        let namespaceBase = numericDisambiguationBase(requested)
        let namespaceToken = normalizedLookupToken(namespaceBase)
        let namespaceMatches = models.filter {
            normalizedLookupToken(numericDisambiguationBase($0.id)) == namespaceToken
        }
        if let existingMatch = namespaceMatches.first(where: { sameRemoteUpsertSlot($0, entry) }) {
            return trimmed(existingMatch.id)
        }

        let used = Set(namespaceMatches.map(\.id))
        return nextDisambiguatedValue(base: namespaceBase, used: used)
    }

    private static func sameRemoteUpsertSlot(_ lhs: RemoteModelEntry, _ rhs: RemoteModelEntry) -> Bool {
        if normalizedLookupToken(RemoteProviderEndpoints.canonicalBackend(lhs.backend))
            != normalizedLookupToken(RemoteProviderEndpoints.canonicalBackend(rhs.backend)) {
            return false
        }
        if normalizedLookupToken(normalizedBaseURL(lhs.baseURL))
            != normalizedLookupToken(normalizedBaseURL(rhs.baseURL)) {
            return false
        }
        if normalizedLookupToken(providerModelId(for: lhs))
            != normalizedLookupToken(providerModelId(for: rhs)) {
            return false
        }
        return normalizedLookupToken(keyReference(for: lhs))
            == normalizedLookupToken(keyReference(for: rhs))
    }

    private static func normalizedBaseURL(_ raw: String?) -> String {
        var value = trimmed(raw)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    private static func numericDisambiguationBase(_ raw: String) -> String {
        let value = trimmed(raw)
        guard !value.isEmpty,
              let hashIndex = value.lastIndex(of: "#"),
              hashIndex < value.index(before: value.endIndex) else {
            return value
        }

        let suffix = value[value.index(after: hashIndex)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else {
            return value
        }
        return String(value[..<hashIndex])
    }

    private static func nextDisambiguatedValue(base rawBase: String, used: Set<String>) -> String {
        let base = trimmed(rawBase)
        guard !base.isEmpty else { return UUID().uuidString }

        let usedTokens = Set(used.map(normalizedLookupToken))
        if !usedTokens.contains(normalizedLookupToken(base)) {
            return base
        }

        var index = 2
        while true {
            let candidate = "\(base)#\(index)"
            if !usedTokens.contains(normalizedLookupToken(candidate)) {
                return candidate
            }
            index += 1
        }
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

    static func endpointHost(for remote: RemoteModelEntry) -> String? {
        guard let raw = remote.baseURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw) else {
            return nil
        }
        let host = (url.host ?? url.absoluteString).trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty ? nil : host
    }

    static func hubStateModel(for remote: RemoteModelEntry) -> HubModel? {
        let rid = remote.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rid.isEmpty else { return nil }

        let backend = remote.backend.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !backend.isEmpty else { return nil }

        let configuredContextLength = max(512, remote.contextLength)
        let knownContextLength = {
            guard let known = remote.knownContextLength, known > 0 else { return nil as Int? }
            return max(configuredContextLength, known)
        }()
        let nestedDisplayName = remote.nestedDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerModelID = providerModelId(for: remote)
        let groupDisplayName = trimmed(remote.effectiveGroupDisplayName)
        let keyReference = keyReference(for: remote)
        let note = trimmed(remote.note)

        return HubModel(
            id: rid,
            name: nestedDisplayName.isEmpty ? rid : nestedDisplayName,
            backend: backend,
            quant: "remote",
            contextLength: configuredContextLength,
            maxContextLength: knownContextLength ?? configuredContextLength,
            paramsB: 0.0,
            roles: nil,
            state: .loaded,
            memoryBytes: nil,
            tokensPerSec: nil,
            modelPath: nil,
            note: note.isEmpty ? nil : note,
            remoteConfiguredContextLength: configuredContextLength,
            remoteKnownContextLength: knownContextLength,
            remoteKnownContextSource: remote.knownContextSource?.rawValue,
            remoteGroupDisplayName: groupDisplayName.isEmpty ? nil : groupDisplayName,
            remoteProviderModelID: providerModelID.isEmpty ? nil : providerModelID,
            remoteKeyReference: keyReference.isEmpty ? nil : keyReference,
            remoteEndpointHost: endpointHost(for: remote)
        )
    }
}
