import Foundation

private struct HubIPCClientCachedCanonicalMemorySyncStatus {
    var urlPath: String
    var fileSize: UInt64
    var modificationTime: TimeInterval
    var snapshot: HubIPCClient.CanonicalMemorySyncStatusSnapshot
}

private enum HubIPCClientCanonicalMemorySyncStatusStorage {
    static let lock = NSLock()
    static var cache: HubIPCClientCachedCanonicalMemorySyncStatus?
}

extension HubIPCClient {
    static func canonicalMemorySyncStatusSnapshot(
        limit: Int = 120
    ) -> CanonicalMemorySyncStatusSnapshot? {
        let url = HubPaths.baseDir().appendingPathComponent("canonical_memory_sync_status.json")
        let boundedLimit = max(1, min(500, limit))
        guard let signature = canonicalMemorySyncStatusFileSignature(url: url) else {
            withCanonicalMemorySyncStatusCacheLock {
                HubIPCClientCanonicalMemorySyncStatusStorage.cache = nil
            }
            return nil
        }
        if let cached = withCanonicalMemorySyncStatusCacheLock({
            HubIPCClientCanonicalMemorySyncStatusStorage.cache
        }), cached.urlPath == url.path, cached.fileSize == signature.fileSize, cached.modificationTime == signature.modificationTime {
            return boundedCanonicalMemorySyncStatusSnapshot(cached.snapshot, limit: boundedLimit)
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CanonicalMemorySyncStatusSnapshot.self, from: data) else {
            withCanonicalMemorySyncStatusCacheLock {
                HubIPCClientCanonicalMemorySyncStatusStorage.cache = nil
            }
            return nil
        }
        let items = decoded.items
            .sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
                return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
            }
        let snapshot = CanonicalMemorySyncStatusSnapshot(
            schemaVersion: decoded.schemaVersion,
            updatedAtMs: max(0, decoded.updatedAtMs),
            items: items
        )
        withCanonicalMemorySyncStatusCacheLock {
            HubIPCClientCanonicalMemorySyncStatusStorage.cache = HubIPCClientCachedCanonicalMemorySyncStatus(
                urlPath: url.path,
                fileSize: signature.fileSize,
                modificationTime: signature.modificationTime,
                snapshot: snapshot
            )
        }
        return boundedCanonicalMemorySyncStatusSnapshot(snapshot, limit: boundedLimit)
    }

    static func recordCanonicalMemorySyncStatus(
        scopeKind: String,
        scopeId: String,
        displayName: String?,
        result: CanonicalMemorySyncDispatchResult
    ) {
        let normalizedScopeKind = normalized(scopeKind) ?? ""
        let normalizedScopeId = normalized(scopeId) ?? ""
        guard !normalizedScopeKind.isEmpty, !normalizedScopeId.isEmpty else { return }

        let updatedAtMs = Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
        let item = CanonicalMemorySyncStatusItem(
            scopeKind: normalizedScopeKind,
            scopeId: normalizedScopeId,
            displayName: normalized(displayName) ?? "",
            source: normalized(result.source) ?? "unknown",
            ok: result.ok,
            updatedAtMs: max(0, updatedAtMs),
            reasonCode: normalizedReasonCode(result.reasonCode, fallback: result.ok ? nil : "canonical_memory_sync_failed"),
            detail: normalized(result.detail),
            deliveryState: normalized(result.deliveryState),
            auditRefs: optionalNonEmptyStrings(orderedUniqueNormalizedStrings(result.auditRefs)),
            evidenceRefs: optionalNonEmptyStrings(orderedUniqueNormalizedStrings(result.evidenceRefs)),
            writebackRefs: optionalNonEmptyStrings(orderedUniqueNormalizedStrings(result.writebackRefs))
        )
        let existing = canonicalMemorySyncStatusSnapshot(limit: 500)
        var deduped: [String: CanonicalMemorySyncStatusItem] = [:]
        for current in existing?.items ?? [] {
            deduped[current.id] = current
        }
        deduped[item.id] = item
        let merged = deduped.values.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
            return lhs.id.localizedCaseInsensitiveCompare(rhs.id) == .orderedAscending
        }
        let payload = CanonicalMemorySyncStatusSnapshot(
            schemaVersion: "canonical_memory_sync_status.v1",
            updatedAtMs: max(0, updatedAtMs),
            items: Array(merged.prefix(500))
        )
        let url = HubPaths.baseDir().appendingPathComponent("canonical_memory_sync_status.json")
        if writeLocalSnapshot(payload, to: url) {
            updateCanonicalMemorySyncStatusCache(snapshot: payload, url: url)
        } else {
            withCanonicalMemorySyncStatusCacheLock {
                HubIPCClientCanonicalMemorySyncStatusStorage.cache = nil
            }
        }
    }

    private static func canonicalMemorySyncStatusFileSignature(url: URL) -> (fileSize: UInt64, modificationTime: TimeInterval)? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (fileSize, modificationTime)
    }

    private static func optionalNonEmptyStrings(_ values: [String]) -> [String]? {
        values.isEmpty ? nil : values
    }

    private static func boundedCanonicalMemorySyncStatusSnapshot(
        _ snapshot: CanonicalMemorySyncStatusSnapshot,
        limit: Int
    ) -> CanonicalMemorySyncStatusSnapshot {
        CanonicalMemorySyncStatusSnapshot(
            schemaVersion: snapshot.schemaVersion,
            updatedAtMs: snapshot.updatedAtMs,
            items: Array(snapshot.items.prefix(limit))
        )
    }

    private static func updateCanonicalMemorySyncStatusCache(
        snapshot: CanonicalMemorySyncStatusSnapshot,
        url: URL
    ) {
        guard let signature = canonicalMemorySyncStatusFileSignature(url: url) else {
            withCanonicalMemorySyncStatusCacheLock {
                HubIPCClientCanonicalMemorySyncStatusStorage.cache = nil
            }
            return
        }
        withCanonicalMemorySyncStatusCacheLock {
            HubIPCClientCanonicalMemorySyncStatusStorage.cache = HubIPCClientCachedCanonicalMemorySyncStatus(
                urlPath: url.path,
                fileSize: signature.fileSize,
                modificationTime: signature.modificationTime,
                snapshot: snapshot
            )
        }
    }

    private static func withCanonicalMemorySyncStatusCacheLock<T>(_ body: () -> T) -> T {
        HubIPCClientCanonicalMemorySyncStatusStorage.lock.lock()
        defer { HubIPCClientCanonicalMemorySyncStatusStorage.lock.unlock() }
        return body()
    }

    static func mergedCanonicalMemorySyncResult(
        primary: CanonicalMemorySyncDispatchResult,
        secondary: CanonicalMemorySyncDispatchResult?
    ) -> CanonicalMemorySyncDispatchResult {
        if primary.ok {
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: primary.source,
                deliveryState: primary.deliveryState,
                auditRefs: primary.auditRefs,
                evidenceRefs: primary.evidenceRefs,
                writebackRefs: primary.writebackRefs,
                detail: primary.detail
            )
        }
        if let secondary, secondary.ok {
            return CanonicalMemorySyncDispatchResult(
                ok: true,
                source: secondary.source,
                deliveryState: secondary.deliveryState,
                auditRefs: secondary.auditRefs,
                evidenceRefs: secondary.evidenceRefs,
                writebackRefs: secondary.writebackRefs,
                detail: secondary.detail
            )
        }

        let sources = [normalized(primary.source), normalized(secondary?.source)]
            .compactMap { $0 }
        let details = [
            normalized(primary.detail).map { "primary=\($0)" },
            normalized(secondary?.detail).map { "secondary=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")

        return CanonicalMemorySyncDispatchResult(
            ok: false,
            source: sources.isEmpty ? "unknown" : sources.joined(separator: "+"),
            deliveryState: normalized(primary.deliveryState) ?? normalized(secondary?.deliveryState),
            auditRefs: orderedUniqueNormalizedStrings(primary.auditRefs + (secondary?.auditRefs ?? [])),
            evidenceRefs: orderedUniqueNormalizedStrings(primary.evidenceRefs + (secondary?.evidenceRefs ?? [])),
            writebackRefs: orderedUniqueNormalizedStrings(primary.writebackRefs + (secondary?.writebackRefs ?? [])),
            reasonCode: normalizedReasonCode(
                primary.reasonCode,
                fallback: secondary?.reasonCode
            ),
            detail: details.isEmpty ? nil : details
        )
    }
}
