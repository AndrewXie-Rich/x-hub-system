import Foundation

actor HubRemoteMemorySnapshotCache {
    struct Key: Hashable, Sendable {
        var mode: String
        var projectId: String?

        init(mode: String, projectId: String?) {
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
        var mode: String
        var projectId: String?
        var source: String
        var storedAtMs: Int64
        var ageMs: Int
        var ttlRemainingMs: Int
        var cachePosture: XTMemoryRemoteSnapshotCachePosture
        var invalidationReason: XTMemoryRemoteSnapshotInvalidationReason?

        var scope: String {
            "mode=\(mode) project_id=\(projectId ?? "(none)")"
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
        let entry = Entry(
            snapshot: snapshot,
            storedAt: now,
            expiresAt: now.addingTimeInterval(ttlSeconds),
            posture: posture,
            lastInvalidationReason: lastInvalidationReasons[key]
        )
        entries[key] = entry
        return metadata(for: key, entry: entry, now: now)
    }

    func invalidate(
        projectId: String?,
        reason: XTMemoryRemoteSnapshotInvalidationReason
    ) {
        let trimmedProjectId = projectId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedProjectId, !trimmedProjectId.isEmpty else {
            recordInvalidation(
                for: Array(entries.keys),
                reason: reason
            )
            entries.removeAll(keepingCapacity: true)
            return
        }
        let invalidatedKeys = entries.keys.filter { $0.projectId == trimmedProjectId }
        recordInvalidation(for: invalidatedKeys, reason: reason)
        entries = entries.filter { $0.key.projectId != trimmedProjectId }
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
