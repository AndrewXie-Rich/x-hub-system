import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorMemoryAwareConversationRoutingTests {

    @Test
    func preflightKeepsOnlyOperationalRuntimeQueriesLocal() {
        let manager = SupervisorManager.makeForTesting()

        let modelRoute = manager.directSupervisorPreflightReplyIfApplicableForTesting("你现在是什么模型")
        let memoryTruth = manager.directSupervisorPreflightReplyIfApplicableForTesting("这些记忆都来自Hub吗")
        let constitutionTruth = manager.directSupervisorPreflightReplyIfApplicableForTesting("X-宪章现在有生效吗")
        let contextTruth = manager.directSupervisorPreflightReplyIfApplicableForTesting("你现在能看到多少轮上下文")
        let identity = manager.directSupervisorPreflightReplyIfApplicableForTesting("你是谁")
        let capability = manager.directSupervisorPreflightReplyIfApplicableForTesting("你能做什么")
        let projectBrief = manager.directSupervisorPreflightReplyIfApplicableForTesting("简单说下亮亮现在怎么样，卡在哪，下一步怎么走")

        #expect(modelRoute != nil)
        #expect(memoryTruth != nil)
        #expect(constitutionTruth != nil)
        #expect(contextTruth != nil)
        #expect(identity == nil)
        #expect(capability == nil)
        #expect(projectBrief == nil)
    }

    @Test
    func executionIntakeIsPrimedBeforeRemoteMemoryAwareResponse() {
        let manager = SupervisorManager.makeForTesting()

        let preflight = manager.directSupervisorPreflightReplyIfApplicableForTesting("帮我做个贪食蛇游戏")
        manager.primeSupervisorMemoryAwareConversationStateIfNeededForTesting("帮我做个贪食蛇游戏")

        #expect(preflight == nil)
        #expect(manager.pendingSupervisorExecutionIntakeGoalSummaryForTesting()?.contains("贪食蛇") == true)
    }

    @Test
    func capabilityReplyMentionsCanonicalSyncRecovery() {
        let manager = SupervisorManager.makeForTesting()

        let reply = manager.directSupervisorReplyIfApplicableForTesting("你能做什么")

        #expect(reply?.contains("重试 canonical sync") == true)
        #expect(reply?.contains("/doctor") == true)
        #expect(reply?.contains("/xt-ready incidents status") == true)
    }

    @Test
    func memoryRuntimeTruthReplyUsesDeterministicSnapshotAndContractFacts() {
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            SupervisorMemoryAssemblySnapshot(
                source: "mixed",
                resolutionSource: "hub_memory",
                updatedAt: 1,
                reviewLevelHint: "r1_pulse",
                requestedProfile: XTMemoryServingProfile.m1Execute.rawValue,
                profileFloor: XTMemoryServingProfile.m1Execute.rawValue,
                resolvedProfile: XTMemoryServingProfile.m2PlanReview.rawValue,
                attemptedProfiles: [XTMemoryServingProfile.m2PlanReview.rawValue],
                progressiveUpgradeCount: 0,
                focusedProjectId: nil,
                rawWindowProfile: XTSupervisorRecentRawContextProfile.standard12Pairs.rawValue,
                rawWindowFloorPairs: 8,
                rawWindowCeilingPairs: 12,
                rawWindowSelectedPairs: 12,
                eligibleMessages: 24,
                lowSignalDroppedMessages: 2,
                rawWindowSource: "mixed",
                rollingDigestPresent: true,
                continuityFloorSatisfied: true,
                truncationAfterFloor: false,
                continuityTraceLines: [],
                lowSignalDropSampleLines: [],
                selectedSections: ["l1_canonical", "l2_observations", "l3_working_set"],
                omittedSections: [],
                contextRefsSelected: 1,
                contextRefsOmitted: 0,
                evidenceItemsSelected: 0,
                evidenceItemsOmitted: 0,
                budgetTotalTokens: nil,
                usedTotalTokens: nil,
                truncatedLayers: [],
                freshness: nil,
                cacheHit: nil,
                denyCode: nil,
                downgradeCode: nil,
                reasonCode: nil,
                compressionPolicy: "protect_anchor_then_delta_then_portfolio"
            )
        )

        let reply = manager.directSupervisorReplyIfApplicableForTesting(
            "记忆是否都来自Hub，X-宪章有生效吗，你现在能看到多少轮上下文"
        )

        #expect(reply?.contains("这类问题我按本地 runtime truth 回") == true)
        #expect(reply?.contains("durable truth 目标：Hub Writer + Gate") == true)
        #expect(reply?.contains("当前 Supervisor 记忆装配来源：Hub 快照 + 本地 overlay（快照拼接，非 durable 真相）") == true)
        #expect(reply?.contains("X-宪章：已生效；当前会以 `[L0_CONSTITUTION]` 注入") == true)
        #expect(reply?.contains("L4 原始证据：当前 supervisor contract 默认不直接下发") == true)
        #expect(reply?.contains("硬底线 8 个来回") == true)
        #expect(reply?.contains("最近一次实际带入 12 组") == true)
    }
}
