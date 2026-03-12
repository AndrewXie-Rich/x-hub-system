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
}
