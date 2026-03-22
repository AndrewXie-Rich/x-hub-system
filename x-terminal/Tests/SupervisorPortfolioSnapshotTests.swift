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
    func snapshotCarriesSpecGapFieldsIntoPortfolioCard() {
        let now = Date(timeIntervalSince1970: 1_773_150_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-spec",
            displayName: "Spec Project",
            runtimeState: "进行中",
            source: "local_project_memory+spec_capsule",
            goal: "Ship spec coverage",
            currentState: "规格待补齐：goal / milestones",
            nextStep: "补齐 formal spec 字段：goal / milestones",
            blocker: "formal_spec_missing: goal / milestones",
            updatedAt: now - 120,
            recentMessageCount: 2,
            missingSpecFields: [.goal, .milestones]
        )

        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(snapshot.projects.first?.missingSpecFields == [.goal, .milestones])
    }

    @Test
    func snapshotCarriesDecisionRailSignalsIntoPortfolioCard() {
        let now = Date(timeIntervalSince1970: 1_773_160_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-rails",
            displayName: "Decision Rails Project",
            runtimeState: "进行中",
            source: "local_project_memory+decision_track+background_preference_track",
            goal: "Keep decision rails visible",
            currentState: "Use approved tech stack",
            nextStep: "Continue implementation",
            blocker: "(无)",
            updatedAt: now - 60,
            recentMessageCount: 2,
            shadowedBackgroundNoteCount: 2,
            weakOnlyBackgroundNoteCount: 1
        )

        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(snapshot.projects.first?.shadowedBackgroundNoteCount == 2)
        #expect(snapshot.projects.first?.weakOnlyBackgroundNoteCount == 1)
        #expect(snapshot.projects.first?.hasDecisionRailSignal == true)
    }

    @Test
    func snapshotCarriesDecisionAssistIntoPortfolioCard() {
        let now = Date(timeIntervalSince1970: 1_773_165_000).timeIntervalSince1970
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "p-proposal",
                blockerId: "blk-test-stack",
                category: .testStack,
                reversible: true,
                riskLevel: .low,
                timeoutEscalationAfterMs: 900_000
            ),
            nowMs: 1_778_300_000_000
        )
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-proposal",
            displayName: "Proposal Project",
            runtimeState: "阻塞中",
            source: "local_project_memory+decision_blocker_assist",
            goal: "Pick a governed default",
            currentState: "默认建议待确认：swift_testing_contract_default（proposal_pending）",
            nextStep: "审阅待定默认建议：swift_testing_contract_default，确认后再走 governed adoption",
            blocker: "default_proposal_pending:test_stack=swift_testing_contract_default",
            updatedAt: now - 60,
            recentMessageCount: 2,
            decisionAssist: assist
        )

        let snapshot = SupervisorPortfolioSnapshotBuilder.build(from: [digest], now: now)

        #expect(snapshot.projects.first?.decisionAssist?.blockerCategory == .testStack)
        #expect(snapshot.projects.first?.decisionAssist?.recommendedOption == "swift_testing_contract_default")
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

    @Test
    func projectUpdatedEventUsesDecisionRailSignalForActionFirstProgress() {
        let now = Date(timeIntervalSince1970: 1_773_220_000).timeIntervalSince1970
        let entry = AXProjectEntry(
            projectId: "p-rail",
            rootPath: "/tmp/p-rail",
            displayName: "Decision Rail Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "in_progress",
            currentStateSummary: "Implementing locked stack",
            nextStepSummary: "Continue current task",
            blockerSummary: "(无)",
            lastSummaryAt: now,
            lastEventAt: now
        )

        let event = SupervisorPortfolioSnapshotBuilder.makeActionEvent(
            from: entry,
            kind: .updated,
            shadowedBackgroundNoteCount: 2,
            weakOnlyBackgroundNoteCount: 1,
            now: now
        )

        #expect(event.eventType == .progressed)
        #expect(event.severity == .briefCard)
        #expect(event.actionTitle.contains("决策边界待清理"))
        #expect(event.actionSummary == "Decision rail cleanup: 2 shadowed background notes + 1 weak-only preference")
        #expect(event.nextAction.contains("either formalize them or keep them explicitly non-binding"))
    }

    @Test
    func projectUpdatedCompletedEventUsesMemoryCompactionSignal() {
        let now = Date(timeIntervalSince1970: 1_773_230_000).timeIntervalSince1970
        let entry = AXProjectEntry(
            projectId: "p-archive",
            rootPath: "/tmp/p-archive",
            displayName: "Archive Project",
            lastOpenedAt: now,
            manualOrderIndex: nil,
            pinned: false,
            statusDigest: "completed",
            currentStateSummary: "已完成",
            nextStepSummary: "(暂无)",
            blockerSummary: "(无)",
            lastSummaryAt: now,
            lastEventAt: now
        )
        let archiveSignal = SupervisorMemoryCompactionSignal(
            rollupSummary: "rolled_up=2; archived=3; kept_decisions=1; archive_candidate=true",
            rolledUpCount: 2,
            archivedCount: 3,
            keptDecisionCount: 1,
            keptMilestoneCount: 0,
            archiveCandidate: true
        )
        let rollupSignal = SupervisorMemoryCompactionSignal(
            rollupSummary: "rolled_up=4; archived=0; kept_decisions=1; archive_candidate=false",
            rolledUpCount: 4,
            archivedCount: 0,
            keptDecisionCount: 1,
            keptMilestoneCount: 0,
            archiveCandidate: false
        )

        let archiveEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(
            from: entry,
            kind: .updated,
            memoryCompactionSignal: archiveSignal,
            now: now
        )
        let rollupEvent = SupervisorPortfolioSnapshotBuilder.makeActionEvent(
            from: entry,
            kind: .updated,
            memoryCompactionSignal: rollupSignal,
            now: now + 1
        )

        #expect(archiveEvent.eventType == .completed)
        #expect(archiveEvent.actionTitle.contains("归档候选"))
        #expect(archiveEvent.actionSummary.contains("archived=3"))
        #expect(archiveEvent.nextAction.contains("归档"))
        #expect(rollupEvent.eventType == .completed)
        #expect(rollupEvent.actionTitle.contains("已收口"))
        #expect(rollupEvent.actionSummary.contains("rolled_up=4"))
        #expect(rollupEvent.nextAction.contains("收口"))
    }
}
