import Foundation

struct HubProviderKeyImportSourceStatusSnapshot: Equatable, Sendable {
    var sourceKey: String
    var kind: String
    var sourceRef: String
    var state: String
    var lastSyncAtMs: Double
    var lastImportedCount: Int
    var ownedAccountCount: Int
    var lastErrorCount: Int
    var lastErrors: [String]
}

struct HubProviderKeyImportSnapshot: Equatable, Sendable {
    var sources: [HubProviderKeyImportSourceStatusSnapshot]
    var accountSourceOwners: [String: [String]]

    func sources(forAccountKey accountKey: String) -> [HubProviderKeyImportSourceStatusSnapshot] {
        let normalized = normalizedToken(accountKey)
        guard !normalized.isEmpty else { return [] }
        let owners = Set(accountSourceOwners[normalized] ?? [])
        guard !owners.isEmpty else { return [] }
        return sources.filter { owners.contains($0.sourceKey) }
    }

    private func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum HubProviderKeyImportSnapshotStore {
    private static let fileName = "hub_provider_keys.json"
    private static let cacheQueue = DispatchQueue(label: "hub_provider_key_import_snapshot.cache")
    private static var cachedSnapshot: HubProviderKeyImportSnapshot?

    static func load(
        allowCompatibilityFallback: Bool = false
    ) -> HubProviderKeyImportSnapshot? {
        if let cached = cacheQueue.sync(execute: { cachedSnapshot }) {
            return cached
        }
        guard allowCompatibilityFallback else {
            return nil
        }

        let snapshot = loadCompatibilitySnapshotFromFile()
        if let snapshot {
            cacheQueue.sync {
                cachedSnapshot = snapshot
            }
        }
        return snapshot
    }

    static func refreshFromHub(
        allowCompatibilityFallback: Bool = false
    ) async -> HubProviderKeyImportSnapshot? {
        guard let runtimeSnapshot = await HubProviderKeysClient.getProviderKeyRuntimeSnapshot() else {
            return load(allowCompatibilityFallback: allowCompatibilityFallback)
        }
        let snapshot = snapshot(from: runtimeSnapshot)
        cacheQueue.sync {
            cachedSnapshot = snapshot
        }
        return snapshot
    }

    static func resetForTesting() {
        cacheQueue.sync {
            cachedSnapshot = nil
        }
    }

    private static func loadCompatibilitySnapshotFromFile() -> HubProviderKeyImportSnapshot? {
        for url in candidateURLs() {
            guard let data = try? Data(contentsOf: url),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let snapshot = parseSnapshot(raw) else {
                continue
            }
            return snapshot
        }
        return nil
    }

    private static func snapshot(from runtimeSnapshot: HubProviderKeysClient.ProviderRuntimeSnapshot) -> HubProviderKeyImportSnapshot {
        let sources = runtimeSnapshot.importSourceStatuses
            .sorted { $0.sourceKey < $1.sourceKey }
            .map { status in
                HubProviderKeyImportSourceStatusSnapshot(
                    sourceKey: status.sourceKey,
                    kind: status.kind,
                    sourceRef: status.sourceRef,
                    state: status.state,
                    lastSyncAtMs: status.lastSyncAtMs,
                    lastImportedCount: status.lastImportedCount,
                    ownedAccountCount: status.ownedAccountCount,
                    lastErrorCount: max(status.lastErrorCount, status.lastErrors.count),
                    lastErrors: status.lastErrors
                )
            }

        let accountOwners = Dictionary(
            uniqueKeysWithValues: runtimeSnapshot.accounts.map { account in
                (normalizedToken(account.accountKey), account.sourceOwners)
            }
        )

        return HubProviderKeyImportSnapshot(
            sources: sources,
            accountSourceOwners: accountOwners
        )
    }

    private static func candidateURLs() -> [URL] {
        var candidates: [URL] = [HubPaths.baseDir()]
        candidates.append(contentsOf: HubPaths.candidateBaseDirs())

        var seen: Set<String> = []
        return candidates
            .map { $0.appendingPathComponent(fileName) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func parseSnapshot(_ raw: [String: Any]) -> HubProviderKeyImportSnapshot? {
        let sourceMap = raw["import_source_statuses"] as? [String: Any] ?? [:]
        let sources = sourceMap
            .sorted { $0.key < $1.key }
            .compactMap { sourceKey, sourceValue -> HubProviderKeyImportSourceStatusSnapshot? in
                guard let sourceObject = sourceValue as? [String: Any] else { return nil }
                let inferred = parseImportSourceKey(sourceKey)
                let kind = firstNonEmpty(stringValue(sourceObject["kind"]), inferred?.kind ?? "")
                let sourceRef = firstNonEmpty(stringValue(sourceObject["source_ref"]), inferred?.sourceRef ?? "")
                guard !kind.isEmpty, !sourceRef.isEmpty else { return nil }
                let lastErrors = stringArrayValue(sourceObject["last_errors"])
                return HubProviderKeyImportSourceStatusSnapshot(
                    sourceKey: sourceKey,
                    kind: kind,
                    sourceRef: sourceRef,
                    state: stringValue(sourceObject["state"]).isEmpty ? "pending" : stringValue(sourceObject["state"]),
                    lastSyncAtMs: doubleValue(sourceObject["last_sync_at_ms"]),
                    lastImportedCount: intValue(sourceObject["last_imported_count"]),
                    ownedAccountCount: intValue(sourceObject["owned_account_count"]),
                    lastErrorCount: max(intValue(sourceObject["last_error_count"]), lastErrors.count),
                    lastErrors: lastErrors
                )
            }

        let accountOwners = parseAccountSourceOwners(raw["providers"])
        guard !sources.isEmpty || !accountOwners.isEmpty else { return nil }
        return HubProviderKeyImportSnapshot(
            sources: sources,
            accountSourceOwners: accountOwners
        )
    }

    private static func parseAccountSourceOwners(_ raw: Any?) -> [String: [String]] {
        guard let providers = raw as? [String: Any] else { return [:] }
        var out: [String: [String]] = [:]

        for providerValue in providers.values {
            guard let providerObject = providerValue as? [String: Any],
                  let accounts = providerObject["accounts"] as? [[String: Any]] else {
                continue
            }
            for account in accounts {
                let accountKey = normalizedToken(stringValue(account["account_key"]))
                guard !accountKey.isEmpty else { continue }
                let owners = stringArrayValue(account["source_owners"])
                if owners.isEmpty { continue }
                out[accountKey] = owners
            }
        }

        return out
    }

    private struct ParsedImportSourceKey {
        var kind: String
        var sourceRef: String
    }

    private static func parseImportSourceKey(_ raw: String) -> ParsedImportSourceKey? {
        let token = stringValue(raw)
        guard let separator = token.firstIndex(of: ":") else { return nil }
        let kind = stringValue(String(token[..<separator]))
        let sourceRef = stringValue(String(token[token.index(after: separator)...]))
        guard !kind.isEmpty, !sourceRef.isEmpty else { return nil }
        return ParsedImportSourceKey(kind: kind, sourceRef: sourceRef)
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

    private static func stringArrayValue(_ raw: Any?) -> [String] {
        guard let values = raw as? [Any] else { return [] }
        var out: [String] = []
        var seen: Set<String> = []
        for value in values {
            let normalized = stringValue(value)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            out.append(normalized)
        }
        return out
    }

    private static func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? NSNumber { return value.intValue }
        return 0
    }

    private static func doubleValue(_ raw: Any?) -> Double {
        if let value = raw as? Double { return value }
        if let value = raw as? Int { return Double(value) }
        if let value = raw as? NSNumber { return value.doubleValue }
        return 0
    }

    private static func firstNonEmpty(_ values: String...) -> String {
        for value in values where !value.isEmpty {
            return value
        }
        return ""
    }

    private static func normalizedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
