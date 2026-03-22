import Foundation
import Testing
@testable import XTerminal

struct SupervisorProjectCapsuleTests {
    @Test
    func capsuleBuildsStableContractFromDigest() throws {
        let now = Date(timeIntervalSince1970: 1_773_700_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-auth",
            displayName: "Auth Project",
            runtimeState: "implementation",
            source: "local_project_memory+registry",
            goal: "Enable paid model",
            currentState: "等待授权批准",
            nextStep: "Approve paid model access",
            blocker: "grant_required",
            updatedAt: now - 42,
            recentMessageCount: 3
        )

        let capsule = SupervisorProjectCapsuleBuilder.build(
            from: digest,
            now: now,
            evidenceRefs: ["build/reports/xt_w3_31_sample.json"]
        )

        #expect(capsule.schemaVersion == "xt.supervisor_project_capsule.v1")
        #expect(capsule.projectId == "p-auth")
        #expect(capsule.projectState == .awaitingAuthorization)
        #expect(capsule.currentPhase == "implementation")
        #expect(capsule.currentAction == "等待授权批准")
        #expect(capsule.topBlocker == "grant_required")
        #expect(capsule.nextStep == "Approve paid model access")
        #expect(capsule.memoryFreshness == .fresh)
        #expect(capsule.evidenceRefs == ["build/reports/xt_w3_31_sample.json"])
        #expect(capsule.statusDigest.contains("goal=Enable paid model"))
        #expect(capsule.auditRef.contains("supervisor_project_capsule:"))

        let card = SupervisorProjectCapsuleBuilder.card(from: capsule, recentMessageCount: digest.recentMessageCount)
        #expect(card.projectState == .awaitingAuthorization)
        #expect(card.runtimeState == "implementation")
        #expect(card.currentAction == "等待授权批准")
    }

    @Test
    func capsuleFreshnessAndCompletedStateMapCorrectly() {
        let now = Date(timeIntervalSince1970: 1_773_800_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-done",
            displayName: "Done Project",
            runtimeState: "completed",
            source: "registry_summary",
            goal: "Ship release",
            currentState: "已完成",
            nextStep: "(暂无)",
            blocker: "(无)",
            updatedAt: now - 2_400,
            recentMessageCount: 0
        )

        let capsule = SupervisorProjectCapsuleBuilder.build(from: digest, now: now)

        #expect(capsule.projectState == .completed)
        #expect(capsule.memoryFreshness == .stale)
        #expect(capsule.topBlocker == "(无)")
        #expect(capsule.nextStep == "继续当前任务")
    }

    @Test
    func queuedRuntimeMapsToIdleCapsuleState() {
        let now = Date(timeIntervalSince1970: 1_773_900_000).timeIntervalSince1970
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-queued",
            displayName: "Queued Project",
            runtimeState: "排队中（等待 Hub 执行）",
            source: "registry_summary",
            goal: "Queue follow-up",
            currentState: "(暂无)",
            nextStep: "(暂无)",
            blocker: "(无)",
            updatedAt: now - 120,
            recentMessageCount: 1
        )

        let capsule = SupervisorProjectCapsuleBuilder.build(from: digest, now: now)
        let card = SupervisorProjectCapsuleBuilder.card(from: capsule, recentMessageCount: digest.recentMessageCount)

        #expect(capsule.projectState == .idle)
        #expect(capsule.currentAction == "排队中（等待 Hub 执行）")
        #expect(card.projectState == .idle)
    }

    @Test
    func capsuleCarriesDecisionAssistIntoPortfolioCard() {
        let now = Date(timeIntervalSince1970: 1_773_910_000).timeIntervalSince1970
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

        let capsule = SupervisorProjectCapsuleBuilder.build(from: digest, now: now)
        let card = SupervisorProjectCapsuleBuilder.card(from: capsule, recentMessageCount: digest.recentMessageCount)

        #expect(capsule.decisionAssist?.blockerCategory == .testStack)
        #expect(capsule.decisionAssist?.recommendedOption == "swift_testing_contract_default")
        #expect(card.decisionAssist?.governanceMode == .proposalWithTimeoutEscalation)
        #expect(card.decisionAssist?.timeoutEscalationAfterMs == 900_000)
    }

    @Test
    func capsuleCarriesMemoryCompactionSignalIntoPortfolioCard() {
        let now = Date(timeIntervalSince1970: 1_776_100_800).timeIntervalSince1970
        let rollup = SupervisorMemoryCompactionRollup(
            schemaVersion: SupervisorMemoryCompactionRollup.schemaVersion,
            projectId: "p-archive",
            periodStartMs: 1_776_000_000_000,
            periodEndMs: 1_776_100_000_000,
            rollupSummary: "rolled_up=2; archived=3; kept_decisions=1; kept_milestones=1; traceable_refs=2; archive_candidate=true",
            rolledUpNodeIds: ["current-0", "recommendation-0"],
            archivedNodeIds: ["recent-0", "recent-1", "recent-2"],
            keptDecisionIds: ["dec_archive"],
            keptMilestoneIds: ["mvp"],
            keptAuditRefs: ["audit_archive"],
            keptReleaseGateRefs: ["build/reports/archive_gate.json"],
            archivedRefs: ["audit_archive", "build/reports/archive_gate.json"],
            archiveCandidate: true,
            policyReasons: ["completed_project"],
            decisionNodeLoss: 0,
            updatedAtMs: 1_776_100_000_000
        )
        let digest = SupervisorManager.SupervisorMemoryProjectDigest(
            projectId: "p-archive",
            displayName: "Archive Project",
            runtimeState: "completed",
            source: "local_project_memory+memory_compaction_rollup",
            goal: "Close the finished project cleanly",
            currentState: "记忆收口：rolled_up=2; archived=3; kept_decisions=1",
            nextStep: "审阅 archive rollup",
            blocker: "(无)",
            updatedAt: now - 120,
            recentMessageCount: 0,
            memoryCompactionRollup: rollup
        )

        let capsule = SupervisorProjectCapsuleBuilder.build(from: digest, now: now)
        let card = SupervisorProjectCapsuleBuilder.card(from: capsule, recentMessageCount: digest.recentMessageCount)

        #expect(capsule.memoryCompactionSignal?.archiveCandidate == true)
        #expect(capsule.memoryCompactionSignal?.archivedCount == 3)
        #expect(capsule.memoryCompactionSignal?.rolledUpCount == 2)
        #expect(card.memoryCompactionSignal?.archiveCandidate == true)
        #expect(card.memoryCompactionSignal?.keptDecisionCount == 1)
        #expect(card.memoryCompactionSignal?.keptMilestoneCount == 1)
    }
}
