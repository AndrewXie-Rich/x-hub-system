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
                canonicalEntries: ["goal: governed autonomy"],
                workingEntries: ["next: wire UI"]
            ),
            for: key,
            now: storedAt
        )

        let cachedBeforeExpiry = await cache.snapshot(for: key, now: storedAt.addingTimeInterval(14.9))
        #expect(cachedBeforeExpiry?.source == "hub_memory_v1_grpc")
        #expect(cachedBeforeExpiry?.canonicalEntries == ["goal: governed autonomy"])

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

        await cache.store(makeSnapshot(ok: true, source: "hub_a"), for: projectKey, now: now)
        await cache.store(makeSnapshot(ok: true, source: "hub_b"), for: globalKey, now: now)
        await cache.store(makeSnapshot(ok: true, source: "hub_c"), for: otherProjectKey, now: now)

        await cache.invalidate(projectId: "  proj-alpha  ")

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
            now: now
        )

        let cached = await cache.snapshot(for: key, now: now.addingTimeInterval(1))
        #expect(cached == nil)
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
