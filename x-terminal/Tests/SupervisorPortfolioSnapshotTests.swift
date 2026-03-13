import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioSnapshotTests {
    @Test
    func snapshotBuildsCountsCriticalQueueAndSortedCards() {
        let now = Date(timeIntervalSince1970: 1_773_000_000).timeIntervalSince1970
        let digests: [SupervisorManager.SupervisorMemoryProjectDigest] = [
            .init(
                projectId: "p-auth",
                displayName: "Auth Project",
                runtimeState: "进行中",
                source: "registry_summary",
                goal: "Enable paid model",
                currentState: "等待授权批准",
                nextStep: "Approve paid model access",
                blocker: "grant_required",
                updatedAt: now - 30,
                recentMessageCount: 2
            ),
            .init(
                projectId: "p-blocked",
                displayName: "Blocked Project",
                runtimeState: "阻塞中",
                source: "local_project_memory+registry",
                goal: "Run require-real",
                currentState: "等待 RR02 样本",
                nextStep: "Run RR02 on paired XT",
                blocker: "Missing require-real sample",
                updatedAt: now - 400,
                recentMessageCount: 4
            ),
            .init(
                projectId: "p-done",
                displayName: "Done Project",
                runtimeState: "已完成",
                source: "local_project_memory+registry",
                goal: "Ship validated mainline",
                currentState: "已完成",
                nextStep: "(暂无)",
                blocker: "(无)",
                updatedAt: now - 120,
                recentMessageCount: 8
            ),
            .init(
                projectId: "p-active",
                displayName: "Active Project",
                runtimeState: "进行中",
                source: "local_project_memory+registry",
                goal: "Build portfolio view",
                currentState: "Implementing portfolio capsule",
                nextStep: "Wire UI board",
                blocker: "(无)",
                updatedAt: now - 60,
                recentMessageCount: 3
            ),
        ]

        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: digests, now: now)

        #expect(snapshot.counts.awaitingAuthorization == 1)
        #expect(snapshot.counts.blocked == 1)
        #expect(snapshot.counts.completed == 1)
        #expect(snapshot.counts.active == 1)
        #expect(snapshot.projects.count == 4)
        #expect(snapshot.projects.first?.projectId == "p-blocked")
        #expect(snapshot.projects[1].projectId == "p-auth")
        #expect(snapshot.criticalQueue.count == 2)
        #expect(snapshot.criticalQueue.first?.projectId == "p-blocked")
    }

    @Test
    func snapshotUsesRuntimeStateAsFallbackCurrentActionAndFreshnessBuckets() {
        let now = Date(timeIntervalSince1970: 1_773_100_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-idle",
            displayName: "Idle Project",
            runtimeState: "排队中（等待 Hub 执行）",
            source: "registry_summary",
            goal: "Queue follow-up",
            currentState: "(暂无)",
            nextStep: "(暂无)",
            blocker: "(无)",
            updatedAt: now - 900,
            recentMessageCount: 1
        )

        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(snapshot.projects.first?.currentAction == "排队中（等待 Hub 执行）")
        #expect(snapshot.projects.first?.projectState == .idle)
        #expect(snapshot.projects.first?.memoryFreshness == .ttlCached)
        #expect(snapshot.projects.first?.nextStep == "继续当前任务")
    }

    @Test
    func projectUpdatedEventMapsAuthorizationAndBlockedSeverities() {
        let now = Date(timeIntervalSince1970: 1_773_200_000).timeIntervalSince1970
        let authEntry = AXProjectEntry(
            projectId: "p-auth",
            rootPath: "/tmp/p-auth",
            displayName: "Auth Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "awaiting authorization",
            currentStateSummary: "等待授权批准",
            nextStepSummary: "Approve paid model access",
            blockerSummary: "grant_required",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let blockedEntry = AXProjectEntry(
            projectId: "p-blocked",
            rootPath: "/tmp/p-blocked",
            displayName: "Blocked Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "rr02 pending",
            currentStateSummary: "等待 RR02 样本",
            nextStepSummary: "Run RR02 now",
            blockerSummary: "Missing require-real sample",
            lastSummaryAt: now,
            lastEventAt: now
        )

        let authEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(from: authEntry, kind: .updated, now: now)
        let blockedEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(from: blockedEntry, kind: .updated, now: now)

        #expect(authEvent.eventType == .awaitingAuthorization)
        #expect(authEvent.severity == .authorizationRequired)
        #expect(authEvent.actionTitle.contains("待授权"))
        #expect(blockedEvent.eventType == .blocked)
        #expect(blockedEvent.severity == .briefCard)
        #expect(blockedEvent.actionTitle.contains("阻塞"))
    }
}
