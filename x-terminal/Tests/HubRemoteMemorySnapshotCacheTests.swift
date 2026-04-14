import Foundation
import Testing
@testable import XTerminal

struct HubRemoteMemorySnapshotCacheTests {
    @Test
    func cachesSuccessfulSnapshotsUntilTTLExpires() async {
        let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15)
        let key = HubRemoteMemorySnapshotCache.Key(mode: "project", projectId: "proj-alpha")
        let storedAt = Date(timeIntervalSince1970: 1_772_400_000)

        await cache.store(
            makeSnapshot(
                ok: true,
                source: "hub_memory_v1_grpc",
                canonicalEntries: ["goal: governed A-Tiers"],
                workingEntries: ["next: wire UI"]
            ),
            for: key,
            posture: .continuitySafe,
            now: storedAt
        )

        let cachedBeforeExpiry = await cache.snapshot(for: key, now: storedAt.addingTimeInterval(14.9))
        #expect(cachedBeforeExpiry?.source == "hub_memory_v1_grpc")
        #expect(cachedBeforeExpiry?.canonicalEntries == ["goal: governed A-Tiers"])

        let cachedAfterExpiry = await cache.snapshot(for: key, now: storedAt.addingTimeInterval(15.1))
        #expect(cachedAfterExpiry == nil)
    }

    @Test
    func invalidateProjectClearsAllModesForThatProject() async {
        let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15)
        let now = Date(timeIntervalSince1970: 1_772_400_100)

        let projectKey = HubRemoteMemorySnapshotCache.Key(mode: "project", projectId: "proj-alpha")
        let globalKey = HubRemoteMemorySnapshotCache.Key(mode: "global", projectId: "proj-alpha")
        let otherProjectKey = HubRemoteMemorySnapshotCache.Key(mode: "project", projectId: "proj-beta")

        await cache.store(makeSnapshot(ok: true, source: "hub_a"), for: projectKey, posture: .continuitySafe, now: now)
        await cache.store(makeSnapshot(ok: true, source: "hub_b"), for: globalKey, posture: .continuitySafe, now: now)
        await cache.store(makeSnapshot(ok: true, source: "hub_c"), for: otherProjectKey, posture: .continuitySafe, now: now)

        await cache.invalidate(projectId: "  proj-alpha  ", reason: .manualRefresh)

        #expect(await cache.snapshot(for: projectKey, now: now) == nil)
        #expect(await cache.snapshot(for: globalKey, now: now) == nil)
        #expect(await cache.snapshot(for: otherProjectKey, now: now)?.source == "hub_c")
    }

    @Test
    func doesNotRetainFailedSnapshots() async {
        let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15)
        let key = HubRemoteMemorySnapshotCache.Key(mode: "project", projectId: "proj-alpha")
        let now = Date(timeIntervalSince1970: 1_772_400_200)

        await cache.store(
            makeSnapshot(ok: false, source: "hub_memory_v1_grpc", reasonCode: "timeout"),
            for: key,
            posture: .continuitySafe,
            now: now
        )

        let cached = await cache.snapshot(for: key, now: now.addingTimeInterval(1))
        #expect(cached == nil)
    }

    @Test
    func snapshotRecordReportsScopeAgeAndTTL() async throws {
        let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15)
        let key = HubRemoteMemorySnapshotCache.Key(mode: "project_chat", projectId: "proj-cache")
        let storedAt = Date(timeIntervalSince1970: 1_772_400_300)

        await cache.store(
            makeSnapshot(ok: true, source: "hub_memory_v1_grpc"),
            for: key,
            posture: .continuitySafe,
            now: storedAt
        )

        let record = try #require(
            await cache.snapshotRecord(for: key, now: storedAt.addingTimeInterval(6))
        )

        #expect(record.snapshot.source == "hub_memory_v1_grpc")
        #expect(record.metadata.mode == "project_chat")
        #expect(record.metadata.projectId == "proj-cache")
        #expect(record.metadata.scope == "mode=project_chat project_id=proj-cache")
        #expect(record.metadata.storedAtMs == 1_772_400_300_000)
        #expect(record.metadata.ageMs == 6_000)
        #expect(record.metadata.ttlRemainingMs == 9_000)
        #expect(record.metadata.cachePosture == .continuitySafe)
        #expect(record.metadata.upstreamTruthClass == "hub_durable_truth")
        #expect(record.metadata.cacheRole == "xt_remote_snapshot_ttl_cache")
        #expect(record.metadata.fastPathSource == .xtRemoteSnapshotCache)
        #expect(record.metadata.invalidationReason == nil)
        #expect(record.metadata.provenanceLabel == "hub_durable_truth_via_xt_ttl_cache")
    }

    @Test
    func storeCarriesForwardLastInvalidationReasonIntoFreshMetadata() async throws {
        let cache = HubRemoteMemorySnapshotCache(ttlSeconds: 15)
        let key = HubRemoteMemorySnapshotCache.Key(mode: "project_chat", projectId: "proj-refresh")
        let now = Date(timeIntervalSince1970: 1_772_400_360)

        await cache.store(
            makeSnapshot(ok: true, source: "hub_memory_v1_grpc"),
            for: key,
            posture: .resumeSafe,
            now: now
        )
        await cache.invalidate(key: key, reason: .manualRefresh)

        let metadata = try #require(
            await cache.store(
                makeSnapshot(ok: true, source: "hub_memory_v1_grpc"),
                for: key,
                posture: .resumeSafe,
                now: now.addingTimeInterval(1)
            )
        )

        #expect(metadata.cachePosture == .resumeSafe)
        #expect(metadata.invalidationReason == .manualRefresh)
    }

    private func makeSnapshot(
        ok: Bool,
        source: String,
        canonicalEntries: [String] = [],
        workingEntries: [String] = [],
        reasonCode: String? = nil
    ) -> HubRemoteMemorySnapshotResult {
        HubRemoteMemorySnapshotResult(
            ok: ok,
            source: source,
            canonicalEntries: canonicalEntries,
            workingEntries: workingEntries,
            reasonCode: reasonCode,
            logLines: []
        )
    }
}
