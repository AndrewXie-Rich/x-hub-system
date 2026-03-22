import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorGuidanceInjectionStoreTests {

    @Test
    func latestPendingAckSkipsNonRequiredAndAcceptedItems() throws {
        let root = try makeProjectRoot(named: "guidance-store-pending")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-observe",
                injectedAtMs: 100,
                ackRequired: false,
                ackStatus: .pending
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-accepted",
                injectedAtMs: 200,
                ackRequired: true,
                ackStatus: .accepted
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-pending",
                injectedAtMs: 300,
                ackRequired: true,
                ackStatus: .pending
            ),
            for: ctx
        )

        let latest = SupervisorGuidanceInjectionStore.latest(for: ctx)
        let pending = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx)

        #expect(latest?.injectionId == "guidance-pending")
        #expect(pending?.injectionId == "guidance-pending")
    }

    @Test
    func acknowledgePersistsAckStatusNoteAndTimestamp() throws {
        let root = try makeProjectRoot(named: "guidance-store-ack")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-ack",
                injectedAtMs: 100,
                ackRequired: true,
                ackStatus: .pending
            ),
            for: ctx
        )

        try SupervisorGuidanceInjectionStore.acknowledge(
            injectionId: "guidance-ack",
            status: .rejected,
            note: "need smaller scope first",
            atMs: 450,
            for: ctx
        )

        let stored = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(stored.ackStatus == .rejected)
        #expect(stored.ackRequired)
        #expect(stored.ackNote == "need smaller scope first")
        #expect(stored.ackUpdatedAtMs == 450)
    }

    @Test
    func upsertKeepsNewestFirstAndTrimsToMaxItems() throws {
        let root = try makeProjectRoot(named: "guidance-store-trim")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        for index in 0..<70 {
            try SupervisorGuidanceInjectionStore.upsert(
                makeGuidance(
                    injectionId: "guidance-\(index)",
                    injectedAtMs: Int64(index + 1),
                    ackRequired: index % 2 == 0,
                    ackStatus: .pending
                ),
                for: ctx
            )
        }

        let snapshot = SupervisorGuidanceInjectionStore.load(for: ctx)
        #expect(snapshot.items.count == 64)
        #expect(snapshot.items.first?.injectionId == "guidance-69")
        #expect(snapshot.items.last?.injectionId == "guidance-6")
        #expect(snapshot.updatedAtMs == 70)
    }

    @Test
    func deferredGuidanceBecomesActionableAgainWhenRetryIsDue() throws {
        let root = try makeProjectRoot(named: "guidance-store-retry-due")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-retry-due",
                injectedAtMs: 100,
                ackRequired: true,
                ackStatus: .pending,
                expiresAtMs: 10_000_000,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 2
            ),
            for: ctx
        )

        try SupervisorGuidanceInjectionStore.acknowledge(
            injectionId: "guidance-retry-due",
            status: .deferred,
            note: "need a later safe point",
            atMs: 1_000,
            for: ctx
        )

        let stored = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(stored.ackStatus == .deferred)
        #expect(stored.retryCount == 1)
        #expect(stored.retryAtMs > 1_000)
        #expect(SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx, nowMs: stored.retryAtMs - 1) == nil)
        #expect(
            SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx, nowMs: stored.retryAtMs)?.injectionId
            == "guidance-retry-due"
        )
    }

    @Test
    func latestPendingAckFallsBackToOlderActionableItemWhenNewestIsDeferredOrExpired() throws {
        let root = try makeProjectRoot(named: "guidance-store-fallback")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-older-pending",
                injectedAtMs: 100,
                ackRequired: true,
                ackStatus: .pending,
                expiresAtMs: 10_000
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-newer-expired",
                injectedAtMs: 300,
                ackRequired: true,
                ackStatus: .pending,
                expiresAtMs: 350
            ),
            for: ctx
        )
        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-newest-deferred",
                injectedAtMs: 500,
                ackRequired: true,
                ackStatus: .deferred,
                expiresAtMs: 10_000,
                retryAtMs: 9_000,
                retryCount: 1,
                maxRetryCount: 2
            ),
            for: ctx
        )

        let pending = SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx, nowMs: 400)
        #expect(pending?.injectionId == "guidance-older-pending")
    }

    @Test
    func expiredGuidanceIsNotReturnedAsActionablePendingAck() throws {
        let root = try makeProjectRoot(named: "guidance-store-expired")
        defer { try? FileManager.default.removeItem(at: root) }

        let ctx = AXProjectContext(root: root)
        try ctx.ensureDirs()

        try SupervisorGuidanceInjectionStore.upsert(
            makeGuidance(
                injectionId: "guidance-expired",
                injectedAtMs: 100,
                ackRequired: true,
                ackStatus: .pending,
                expiresAtMs: 500,
                retryAtMs: 0,
                retryCount: 0,
                maxRetryCount: 1
            ),
            for: ctx
        )

        #expect(SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx, nowMs: 499)?.injectionId == "guidance-expired")
        #expect(SupervisorGuidanceInjectionStore.latestPendingAck(for: ctx, nowMs: 500) == nil)
        let stored = try #require(SupervisorGuidanceInjectionStore.latest(for: ctx))
        #expect(SupervisorGuidanceInjectionStore.lifecycleSummary(for: stored, nowMs: 500) == "expired")
    }

    private func makeProjectRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeGuidance(
        injectionId: String,
        injectedAtMs: Int64,
        ackRequired: Bool,
        ackStatus: SupervisorGuidanceAckStatus,
        expiresAtMs: Int64 = 0,
        retryAtMs: Int64 = 0,
        retryCount: Int = 0,
        maxRetryCount: Int = 0
    ) -> SupervisorGuidanceInjectionRecord {
        SupervisorGuidanceInjectionBuilder.build(
            injectionId: injectionId,
            reviewId: "review-\(injectionId)",
            projectId: "proj-guidance-store",
            targetRole: .coder,
            deliveryMode: .priorityInsert,
            interventionMode: .suggestNextSafePoint,
            safePointPolicy: .nextToolBoundary,
            guidanceText: "guidance for \(injectionId)",
            ackStatus: ackStatus,
            ackRequired: ackRequired,
            ackNote: "",
            injectedAtMs: injectedAtMs,
            ackUpdatedAtMs: 0,
            expiresAtMs: expiresAtMs,
            retryAtMs: retryAtMs,
            retryCount: retryCount,
            maxRetryCount: maxRetryCount,
            auditRef: "audit-\(injectionId)"
        )
    }
}
