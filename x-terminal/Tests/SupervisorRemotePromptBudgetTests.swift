import Foundation
import Testing
@testable import XTerminal

struct SupervisorRemotePromptBudgetTests {
    @Test
    @MainActor
    func compactRemoteMemoryPreservesAnchorAndDeltaWhileDroppingHeavyEvidence() {
        let manager = SupervisorManager.makeForTesting()
        let memory = """
[MEMORY_V1]
[SERVING_PROFILE]
profile=m4_full_scan
[/SERVING_PROFILE]

[PORTFOLIO_BRIEF]
项目总览：亮亮 active；我的世界还原项目 blocked；Alpha Demo pending。
[/PORTFOLIO_BRIEF]

[FOCUSED_PROJECT_ANCHOR_PACK]
goal=让 Supervisor 在远端付费模型路由下优先继续真实对话，而不是因为 prompt 过大立即退回本地直答。
done_definition=远端请求撞到 single request token limit 时自动缩小 prompt 并重试，直到远端可答或真的无路可走。
constraints=保留项目上下文、保留必要个人助理记忆、不能伪造模型执行。
approved_decisions=先修 XT 请求装配，不先抬高 Hub 默认预算。
active_plan=1. 估算预算 2. 收缩记忆 3. 远端重试 4. 失败时才本地兜底
[/FOCUSED_PROJECT_ANCHOR_PACK]

[DELTA_FEED]
latest_change=用户反馈 remote chat 仍被单次预算挡住；优先修 Supervisor remote prompt 预算自适应。
[/DELTA_FEED]

[DIALOGUE_WINDOW]
user: 我现在就是想正常跟 Supervisor 聊天，不要一上来就本地兜底。
assistant: 已识别到 paid model request 超预算，需要优先修 remote prompt 预算。
user: 不要只分析，直接推进。
assistant: 正在推进。
[/DIALOGUE_WINDOW]

[L3_WORKING_SET]
当前工作集：
- 检查 Hub 默认 single_request_token_limit=12000
- 检查 XT Supervisor full prompt + memory_v1 + maxTokens=2048
- 新增 full/compact/slim/rescue 多档重试
- 下一步补测试并重打包
[/L3_WORKING_SET]

[EVIDENCE_PACK]
\(String(repeating: "evidence_line=runtime_receipt_keep_for_audit\n", count: 120))
[/EVIDENCE_PACK]

[L4_RAW_EVIDENCE]
\(String(repeating: "raw_log=0123456789abcdef repeated heavy remote trace for budget pressure\n", count: 240))
[/L4_RAW_EVIDENCE]
[/MEMORY_V1]
"""

        let compacted = manager.compactSupervisorMemoryForRemoteBudgetForTesting(
            memory,
            tokenBudget: 600,
            aggressive: true
        )

        #expect(compacted.contains("[FOCUSED_PROJECT_ANCHOR_PACK]"))
        #expect(compacted.contains("single request token limit"))
        #expect(compacted.contains("[DELTA_FEED]"))
        #expect(!compacted.contains("[L4_RAW_EVIDENCE]"))
        #expect(!compacted.contains("raw_log=0123456789abcdef"))
        #expect(TokenEstimator.estimateTokens(compacted) <= 600)
    }

    @Test
    @MainActor
    func remotePromptVariantsRespectActualSingleRequestBudget() {
        let manager = SupervisorManager.makeForTesting()
        let labels = manager.remotePromptVariantLabelsForTesting(
            userMessage: "继续推进，不要本地兜底。",
            memoryText: """
            [MEMORY_V1]
            [FOCUSED_PROJECT_ANCHOR_PACK]
            goal=让 Supervisor 优先走远端 paid model 正常回答。
            done_definition=如果设备单次额度很低，就直接从更小的 prompt 档位开始。
            [/FOCUSED_PROJECT_ANCHOR_PACK]
            [/MEMORY_V1]
            """,
            singleRequestBudgetTokens: 1000
        )

        #expect(labels == ["rescue"])
    }

    @Test
    @MainActor
    func remotePromptVariantsTrimOutputTokensToFitBudget() {
        let manager = SupervisorManager.makeForTesting()
        let summaries = manager.remotePromptVariantSummariesForTesting(
            userMessage: "继续推进，不要本地兜底。",
            memoryText: """
            [MEMORY_V1]
            [FOCUSED_PROJECT_ANCHOR_PACK]
            goal=让 Supervisor 在额度很紧的时候也尽量先命中远端 paid model。
            done_definition=如果预算很小，就主动压缩 prompt，并把输出上限收紧到还能通过预算 gate 的范围。
            notes=\(String(repeating: "保留必要上下文，不要直接回退到本地。", count: 64))
            [/FOCUSED_PROJECT_ANCHOR_PACK]

            [DIALOGUE_WINDOW]
            \(String(repeating: "user: 不要本地兜底。assistant: 正在继续压缩远端 prompt。\n", count: 40))
            [/DIALOGUE_WINDOW]
            [/MEMORY_V1]
            """,
            singleRequestBudgetTokens: 1_500
        )

        let first = summaries.first
        #expect(first?.label == "rescue")
        #expect((first?.totalTokenEstimate ?? Int.max) <= 1_500)
    }

    @Test
    @MainActor
    func remotePromptBudgetFallsBackToRemoteModelContextWhenDeviceTruthMissing() {
        let manager = SupervisorManager.makeForTesting()
        let remoteModel = HubModel(
            id: "openai/gpt-5.4",
            name: "GPT-5.4",
            backend: "openai",
            quant: "remote",
            contextLength: 8_192,
            paramsB: 0,
            roles: ["general"],
            state: .loaded,
            remoteConfiguredContextLength: 8_192,
            remoteKnownContextLength: 128_000,
            remoteKnownContextSource: "catalog_estimate"
        )

        let budget = manager.effectiveSupervisorRemoteSingleRequestBudgetForTesting(
            pairedDeviceBudgetTokens: nil,
            preferredModelId: "gpt-5.4",
            availableModels: [remoteModel]
        )

        #expect(budget.tokens == 8_192)
        #expect(budget.source == "remote_model_context")
    }

    @Test
    @MainActor
    func remotePromptBudgetUsesConservativeMinimumOfDeviceTruthAndRemoteModelContext() {
        let manager = SupervisorManager.makeForTesting()
        let remoteModel = HubModel(
            id: "openai/gpt-5.4",
            name: "GPT-5.4",
            backend: "openai",
            quant: "remote",
            contextLength: 8_192,
            paramsB: 0,
            roles: ["general"],
            state: .loaded,
            remoteConfiguredContextLength: 8_192,
            remoteKnownContextLength: 128_000,
            remoteKnownContextSource: "catalog_estimate"
        )

        let budget = manager.effectiveSupervisorRemoteSingleRequestBudgetForTesting(
            pairedDeviceBudgetTokens: 12_000,
            preferredModelId: "openai/gpt-5.4",
            availableModels: [remoteModel]
        )

        #expect(budget.tokens == 8_192)
        #expect(budget.source == "paired_device_truth_and_model_context")
    }

    @Test
    func remotePromptBudgetHumanLineShowsBudgetSource() {
        let deviceTruth = SupervisorMemoryAssemblySnapshot(
            source: "remote_budget_test",
            resolutionSource: "doctor",
            updatedAt: 1_741_300_000,
            reviewLevelHint: "strategic",
            requestedProfile: "project_ai_default",
            profileFloor: "project_ai_default",
            resolvedProfile: "project_ai_default",
            attemptedProfiles: ["project_ai_default"],
            progressiveUpgradeCount: 0,
            selectedSections: ["portfolio_brief"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            remotePromptVariantLabel: "compact",
            remotePromptMode: "minimal",
            remotePromptTokenEstimate: 4300,
            remoteResponseTokenLimit: 1024,
            remoteTotalTokenEstimate: 5324,
            remoteSingleRequestBudget: 256,
            remoteSingleRequestBudgetSource: "paired_device_truth"
        )
        let fallback = SupervisorMemoryAssemblySnapshot(
            source: "remote_budget_test",
            resolutionSource: "doctor",
            updatedAt: 1_741_300_000,
            reviewLevelHint: "strategic",
            requestedProfile: "project_ai_default",
            profileFloor: "project_ai_default",
            resolvedProfile: "project_ai_default",
            attemptedProfiles: ["project_ai_default"],
            progressiveUpgradeCount: 0,
            selectedSections: ["portfolio_brief"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            remotePromptVariantLabel: "compact",
            remotePromptMode: "minimal",
            remotePromptTokenEstimate: 4300,
            remoteResponseTokenLimit: 1024,
            remoteTotalTokenEstimate: 5324,
            remoteSingleRequestBudget: 12_000,
            remoteSingleRequestBudgetSource: "default_fallback"
        )
        let modelContext = SupervisorMemoryAssemblySnapshot(
            source: "remote_budget_test",
            resolutionSource: "doctor",
            updatedAt: 1_741_300_000,
            reviewLevelHint: "strategic",
            requestedProfile: "project_ai_default",
            profileFloor: "project_ai_default",
            resolvedProfile: "project_ai_default",
            attemptedProfiles: ["project_ai_default"],
            progressiveUpgradeCount: 0,
            selectedSections: ["portfolio_brief"],
            omittedSections: [],
            contextRefsSelected: 1,
            contextRefsOmitted: 0,
            evidenceItemsSelected: 0,
            evidenceItemsOmitted: 0,
            budgetTotalTokens: nil,
            usedTotalTokens: nil,
            truncatedLayers: [],
            freshness: "fresh",
            cacheHit: false,
            denyCode: nil,
            downgradeCode: nil,
            reasonCode: nil,
            compressionPolicy: "balanced",
            remotePromptVariantLabel: "compact",
            remotePromptMode: "minimal",
            remotePromptTokenEstimate: 4300,
            remoteResponseTokenLimit: 1024,
            remoteTotalTokenEstimate: 5324,
            remoteSingleRequestBudget: 8_192,
            remoteSingleRequestBudgetSource: "paired_device_truth_and_model_context"
        )

        #expect(deviceTruth.remotePromptBudgetHumanLine?.contains("设备单次额度 256") == true)
        #expect(fallback.remotePromptBudgetHumanLine?.contains("默认回退额度 12000") == true)
        #expect(modelContext.remotePromptBudgetHumanLine?.contains("设备单次额度 / 模型窗口 8192") == true)
    }

    @Test
    @MainActor
    func remotePromptVariantSnapshotTracksActuallyServedSections() throws {
        let manager = SupervisorManager.makeForTesting()
        manager.setSupervisorMemoryAssemblySnapshotForTesting(
            makeRemotePromptAssemblySnapshot(
                selectedSections: [
                    "dialogue_window",
                    "portfolio_brief",
                    "focused_project_anchor_pack",
                    "context_refs",
                    "evidence_pack"
                ],
                omittedSections: [],
                servingObjectContract: [
                    "dialogue_window",
                    "portfolio_brief",
                    "focused_project_anchor_pack",
                    "context_refs",
                    "evidence_pack"
                ],
                contextRefsSelected: 3,
                contextRefsOmitted: 1,
                evidenceItemsSelected: 2,
                evidenceItemsOmitted: 1
            )
        )

        let updated = try #require(
            manager.applySupervisorRemotePromptVariantForTesting(
                label: "rescue",
                memoryText: """
                [MEMORY_V1]
                [DIALOGUE_WINDOW]
                user: 不要本地兜底。
                assistant: 正在压缩远端 prompt。
                [/DIALOGUE_WINDOW]

                [FOCUSED_PROJECT_ANCHOR_PACK]
                goal=保持远端 paid model 连续对话。
                [/FOCUSED_PROJECT_ANCHOR_PACK]
                [/MEMORY_V1]
                """,
                promptTokenEstimate: 320,
                maxTokens: 512
            )
        )

        #expect(updated.remotePromptVariantLabel == "rescue")
        #expect(updated.selectedSections == ["dialogue_window", "focused_project_anchor_pack"])
        #expect(updated.omittedSections == ["portfolio_brief", "context_refs", "evidence_pack"])
        #expect(updated.contextRefsSelected == 0)
        #expect(updated.contextRefsOmitted == 4)
        #expect(updated.evidenceItemsSelected == 0)
        #expect(updated.evidenceItemsOmitted == 3)
    }
}

private func makeRemotePromptAssemblySnapshot(
    selectedSections: [String],
    omittedSections: [String],
    servingObjectContract: [String],
    contextRefsSelected: Int,
    contextRefsOmitted: Int,
    evidenceItemsSelected: Int,
    evidenceItemsOmitted: Int
) -> SupervisorMemoryAssemblySnapshot {
    SupervisorMemoryAssemblySnapshot(
        source: "remote_budget_test",
        resolutionSource: "testing",
        updatedAt: 1_741_300_000,
        reviewLevelHint: "strategic",
        requestedProfile: "project_ai_default",
        profileFloor: "project_ai_default",
        resolvedProfile: "project_ai_default",
        attemptedProfiles: ["project_ai_default"],
        progressiveUpgradeCount: 0,
        selectedSections: selectedSections,
        omittedSections: omittedSections,
        servingObjectContract: servingObjectContract,
        contextRefsSelected: contextRefsSelected,
        contextRefsOmitted: contextRefsOmitted,
        evidenceItemsSelected: evidenceItemsSelected,
        evidenceItemsOmitted: evidenceItemsOmitted,
        budgetTotalTokens: nil,
        usedTotalTokens: nil,
        truncatedLayers: [],
        freshness: "fresh",
        cacheHit: false,
        denyCode: nil,
        downgradeCode: nil,
        reasonCode: nil,
        compressionPolicy: "balanced"
    )
}
