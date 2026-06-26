import Foundation

actor HubRemoteMemorySnapshotCache {
    struct Key: Hashable, Sendable {
        var hubProfileID: String
        var mode: String
        var projectId: String?

        init(hubProfileID: String = "hub-default", mode: String, projectId: String?) {
            let trimmedHubProfileID = hubProfileID.trimmingCharacters(in: .whitespacesAndNewlines)
            self.hubProfileID = trimmedHubProfileID.isEmpty ? "hub-default" : trimmedHubProfileID

            let trimmedMode = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            self.mode = trimmedMode.isEmpty ? "project" : trimmedMode

            let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmedProjectId, !trimmedProjectId.isEmpty {
                self.projectId = trimmedProjectId
            } else {
                self.projectId = nil
            }
        }
    }

    struct Metadata: Equatable, Sendable {
        var hubProfileID: String
        var mode: String
        var projectId: String?
        var source: String
        var storedAtMs: Int64
        var ageMs: Int
        var ttlRemainingMs: Int
        var cachePosture: XTMemoryRemoteSnapshotCachePosture
        var invalidationReason: XTMemoryRemoteSnapshotInvalidationReason?

        var scope: String {
            "hub=\(hubProfileID) mode=\(mode) project_id=\(projectId ?? "(none)")"
        }

        var upstreamTruthClass: String {
            switch source {
            case "hub_memory_v1_grpc", "hub_thread":
                return "hub_durable_truth"
            default:
                return "unknown_upstream_truth"
            }
        }

        var cacheRole: String {
            "xt_remote_snapshot_ttl_cache"
        }

        var fastPathSource: XTMemoryFastPathSource {
            .xtRemoteSnapshotCache
        }

        var provenanceLabel: String {
            if upstreamTruthClass == "hub_durable_truth" {
                return "hub_durable_truth_via_xt_ttl_cache"
            }
            return "xt_ttl_cache_unknown_upstream"
        }
    }

    struct SnapshotRecord: Sendable {
        var snapshot: HubRemoteMemorySnapshotResult
        var metadata: Metadata
    }

    private struct Entry: Sendable {
        var snapshot: HubRemoteMemorySnapshotResult
        var storedAt: Date
        var expiresAt: Date
        var posture: XTMemoryRemoteSnapshotCachePosture
        var lastInvalidationReason: XTMemoryRemoteSnapshotInvalidationReason?
    }

    private let ttlSeconds: TimeInterval
    private var entries: [Key: Entry] = [:]
    private var lastInvalidationReasons: [Key: XTMemoryRemoteSnapshotInvalidationReason] = [:]

    init(ttlSeconds: Double = 15.0) {
        self.ttlSeconds = max(1.0, ttlSeconds)
    }

    func snapshot(for key: Key, now: Date = Date()) -> HubRemoteMemorySnapshotResult? {
        snapshotRecord(for: key, now: now)?.snapshot
    }

    func snapshotRecord(for key: Key, now: Date = Date()) -> SnapshotRecord? {
        purgeExpiredEntries(now: now)
        guard let entry = entries[key], entry.expiresAt > now else {
            entries[key] = nil
            return nil
        }
        guard entry.snapshot.ok else {
            entries[key] = nil
            return nil
        }
        return SnapshotRecord(
            snapshot: entry.snapshot,
            metadata: metadata(for: key, entry: entry, now: now)
        )
    }

    @discardableResult
    func store(
        _ snapshot: HubRemoteMemorySnapshotResult,
        for key: Key,
        posture: XTMemoryRemoteSnapshotCachePosture,
        now: Date = Date()
    ) -> Metadata? {
        purgeExpiredEntries(now: now)
        guard snapshot.ok else {
            entries[key] = nil
            return nil
        }
        let invalidationReason = lastInvalidationReasons.removeValue(forKey: key)
        let entry = Entry(
            snapshot: snapshot,
            storedAt: now,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            posture: posture,
            lastInvalidationReason: nil
        )
        entries[key] = entry
        var metadata = metadata(for: key, entry: entry, now: now)
        metadata.invalidationReason = invalidationReason
        return metadata
    }

    func invalidate(
        projectId: String?,
        hubProfileID: String? = nil,
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) {
        let trimmedHubProfileID = hubProfileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedProjectId, !trimmedProjectId.isEmpty else {
            let keys = entries.keys.filter { key in
                guard let trimmedHubProfileID, !trimmedHubProfileID.isEmpty else { return true }
                return key.hubProfileID == trimmedHubProfileID
            }
            recordInvalidation(for: keys, reason: reason)
            if let trimmedHubProfileID, !trimmedHubProfileID.isEmpty {
                entries = entries.filter { $0.key.hubProfileID != trimmedHubProfileID }
            } else {
                entries.removeAll(keepingCapacity: true)
            }
            return
        }
        let invalidatedKeys = entries.keys.filter { key in
            guard key.projectId == trimmedProjectId else { return false }
            guard let trimmedHubProfileID, !trimmedHubProfileID.isEmpty else { return true }
            return key.hubProfileID == trimmedHubProfileID
        }
        recordInvalidation(for: invalidatedKeys, reason: reason)
        entries = entries.filter { item in
            guard item.key.projectId == trimmedProjectId else { return true }
            guard let trimmedHubProfileID, !trimmedHubProfileID.isEmpty else { return false }
            return item.key.hubProfileID != trimmedHubProfileID
        }
    }

    func invalidateAll(reason: XTMemoryRemoteSnapshotInvalidationReason) {
        recordInvalidation(for: Array(entries.keys), reason: reason)
        entries.removeAll(keepingCapacity: true)
    }

    func invalidate(
        key: Key,
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) {
        recordInvalidation(for: [key], reason: reason)
        entries[key] = nil
    }

    private func purgeExpiredEntries(now: Date) {
        entries = entries.filter { $0.value.expiresAt > now }
    }

    private func metadata(for key: Key, entry: Entry, now: Date) -> Metadata {
        Metadata(
            hubProfileID: key.hubProfileID,
            mode: key.mode,
            projectId: key.projectId,
            source: entry.snapshot.source,
            storedAtMs: Int64((entry.storedAt.timeIntervalSince1970 * 1000).rounded()),
            ageMs: max(0, Int((now.timeIntervalSince(entry.storedAt) * 1000).rounded())),
            ttlRemainingMs: max(0, Int((entry.expiresAt.timeIntervalSince(now) * 1000).rounded())),
            cachePosture: entry.posture,
            invalidationReason: entry.lastInvalidationReason
        )
    }

    private func recordInvalidation(
        for keys: [Key],
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) {
        for key in keys {
            lastInvalidationReasons[key] = reason
        }
    }
}
