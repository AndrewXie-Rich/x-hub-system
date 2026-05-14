import Foundation

struct HubProviderKeyAccountRuntimeMetadataSnapshot: Equatable, Sendable {
    var accountKey: String
    var provider: String
    var authType: String
    var oauthSourceKey: String
    var requiredRefreshMetadata: [String]
}

enum HubProviderKeyAccountRuntimeMetadataSnapshotStore {
    private static let fileName = "hub_provider_keys.json"
    private static let cacheQueue = DispatchQueue(label: "hub_provider_key_runtime_metadata.cache")
    private static var cachedSnapshot: [String: HubProviderKeyAccountRuntimeMetadataSnapshot] = [:]

    static func load(
        allowCompatibilityFallback: Bool = false
    ) -> [String: HubProviderKeyAccountRuntimeMetadataSnapshot] {
        let cached = cacheQueue.sync(execute: { cachedSnapshot })
        if !cached.isEmpty {
            return cached
        }
        guard allowCompatibilityFallback else {
            return [:]
        }

        let snapshot = loadCompatibilitySnapshotFromFile()
        if !snapshot.isEmpty {
            cacheQueue.sync {
                cachedSnapshot = snapshot
            }
        }
        return snapshot
    }

    static func refreshFromHub(
        allowCompatibilityFallback: Bool = false
    ) async -> [String: HubProviderKeyAccountRuntimeMetadataSnapshot] {
        guard let runtimeSnapshot = await HubProviderKeysClient.getProviderKeyRuntimeSnapshot() else {
            return load(allowCompatibilityFallback: allowCompatibilityFallback)
        }
        let snapshot = Dictionary(
            uniqueKeysWithValues: runtimeSnapshot.accounts.map { account in
                (
                    account.accountKey,
                    HubProviderKeyAccountRuntimeMetadataSnapshot(
                        accountKey: account.accountKey,
                        provider: account.provider,
                        authType: account.authType,
                        oauthSourceKey: account.oauthSourceKey,
                        requiredRefreshMetadata: account.requiredRefreshMetadata
                    )
                )
            }
        )
        cacheQueue.sync {
            cachedSnapshot = snapshot
        }
        return snapshot
    }

    static func resetForTesting() {
        cacheQueue.sync {
            cachedSnapshot = [:]
        }
    }

    private static func loadCompatibilitySnapshotFromFile() -> [String: HubProviderKeyAccountRuntimeMetadataSnapshot] {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let snapshot = parseSnapshot(raw)
            if !snapshot.isEmpty {
                return snapshot
            }
        }
        return [:]
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = [HubPaths.baseDir()]
        candidates.append(contentsOf: HubPaths.candidateBaseDirs())

        var seen: Set<String> = []
        return candidates
            .map { $0.appendingPathComponent(fileName) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func parseSnapshot(_ raw: [String: Any]) -> [String: HubProviderKeyAccountRuntimeMetadataSnapshot] {
        guard let providers = raw["providers"] as? [String: Any] else { return [:] }
        var out: [String: HubProviderKeyAccountRuntimeMetadataSnapshot] = [:]

        for providerValue in providers.values {
            guard let providerObject = providerValue as? [String: Any],
                  let accounts = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }
            for account in accounts {
                guard let snapshot = parseAccount(account) else { continue }
                out[snapshot.accountKey] = snapshot
            }
        }

        return out
    }

    private static func parseAccount(_ raw: [String: Any]) -> HubProviderKeyAccountRuntimeMetadataSnapshot? {
        let accountKey = stringValue(raw["account_key"])
        guard !accountKey.isEmpty else { return nil }

        let provider = stringValue(raw["provider"])
        let authType = stringValue(raw["auth_type"]).isEmpty ? "api_key" : stringValue(raw["auth_type"])
        let oauthSourceKey = stringValue(raw["oauth_source_key"])

        return HubProviderKeyAccountRuntimeMetadataSnapshot(
            accountKey: accountKey,
            provider: provider,
            authType: authType,
            oauthSourceKey: oauthSourceKey,
            requiredRefreshMetadata: requiredRefreshMetadata(
                provider: provider,
                authType: authType,
                oauthSourceKey: oauthSourceKey,
                raw: raw
            )
        )
    }

    private static func requiredRefreshMetadata(
        provider: String,
        authType: String,
        oauthSourceKey: String,
        raw: [String: Any]
    ) -> [String] {
        guard normalizedToken(authType) == "oauth" else { return [] }

        let source = normalizedToken(oauthSourceKey).isEmpty
            ? normalizedToken(provider)
            : normalizedToken(oauthSourceKey)
        let requiredFields: [String]
        switch source {
        case "gemini", "gemini-cli", "google", "antigravity":
            requiredFields = ["client_id", "client_secret", "token_uri"]
        default:
            return []
        }

        let refreshConfig = raw["oauth_refresh_config"] as? [String: Any] ?? [:]
        let presentFields = Set(refreshConfig.keys.map(normalizedRefreshMetadataKey(_:)))
        return requiredFields.filter { !presentFields.contains($0) }
    }

    private static func normalizedRefreshMetadataKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    private static func stringValue(_ raw: Any?) -> String {
        if let value = raw as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let value = raw as? NSNumber {
            return value.stringValue
        }
        return ""
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
