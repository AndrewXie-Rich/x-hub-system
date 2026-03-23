import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioProjectPresentationTests {

    @Test
    func mapBuildsSelectedProjectRowWithGovernanceAndActionabilityTags() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-alpha",
            displayName: "Project Alpha",
            projectState: .awaitingAuthorization,
            runtimeState: "pending",
            currentAction: "Waiting for approval",
            topBlocker: "grant_required",
            nextStep: "Approve the pending grant",
            memoryFreshness: .ttlCached,
            updatedAt: 42,
            recentMessageCount: 5
        )
        let actionability = [
            SupervisorPortfolioActionabilityItem(
                projectId: "project-alpha",
                projectName: "Project Alpha",
                kind: .decisionBlocker,
                priority: .now,
                reasonSummary: "grant_required",
                recommendedNextAction: "Approve the pending grant",
                whyItMatters: "Execution is paused.",
                staleAgeHours: 1
            )
        ]
        let governed = AXProjectGovernedAuthorityPresentation(
            deviceAuthorityConfigured: true,
            localAutoApproveConfigured: true,
            governedReadableRootCount: 2,
            pairedDeviceId: "device-1"
        )
        let templatePreview = AXProjectGovernanceTemplatePreview(
            configuredProfile: .safe,
            effectiveProfile: .agent,
            configuredDeviceAuthorityPosture: .projectBound,
            effectiveDeviceAuthorityPosture: .deviceGoverned,
            configuredSupervisorScope: .focusedProject,
            effectiveSupervisorScope: .deviceGoverned,
            configuredGrantPosture: .guidedAuto,
            effectiveGrantPosture: .envelopeAuto,
            configuredProfileSummary: "configured",
            effectiveProfileSummary: "effective",
            configuredDeviceAuthorityDetail: "configured authority",
            effectiveDeviceAuthorityDetail: "effective authority",
            configuredSupervisorScopeDetail: "configured scope",
            effectiveSupervisorScopeDetail: "effective scope",
            configuredGrantDetail: "configured grant",
            effectiveGrantDetail: "effective grant",
            configuredDeviationReasons: [],
            effectiveDeviationReasons: [],
            runtimeSummary: "runtime drift"
        )
        let latestUIReview = XTUIReviewPresentation(
            reviewRef: "local://.xterminal/ui_review/reviews/project-alpha.json",
            bundleRef: "local://.xterminal/ui_observation/bundles/project-alpha.json",
            verdict: .attentionNeeded,
            confidence: .medium,
            sufficientEvidence: true,
            objectiveReady: false,
            issueCodes: ["critical_action_not_visible"],
            summary: "attention needed",
            updatedAtMs: 123,
            interactiveTargetCount: 3,
            criticalActionExpected: true,
            criticalActionVisible: false,
            checks: [],
            reviewFileURL: nil,
            bundleFileURL: nil,
            screenshotFileURL: nil,
            visibleTextFileURL: nil,
            recentHistory: [],
            trend: nil,
            comparison: nil
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: actionability,
            isSelected: true,
            governed: governed,
            templatePreview: templatePreview,
            latestUIReview: latestUIReview
        )

        #expect(presentation.id == "project-alpha")
        #expect(presentation.stateText == "待授权")
        #expect(presentation.stateTone == .danger)
        #expect(presentation.freshnessText == "缓存")
        #expect(presentation.freshnessTone == .warning)
        #expect(presentation.recentText == "最近 5 条")
        #expect(presentation.selectionButtonTitle == "已选中")
        #expect(presentation.isSelected)
        #expect(presentation.actionabilityTags.map(\.title) == ["决策阻塞"])
        #expect(presentation.actionabilityTags.map(\.tone) == [.danger])
        #expect(
            presentation.governanceTags.map(\.title) ==
                ["安全", "运行时 Agent", "设备级受治理", "包络预授权", "本地自动批", "可读路径 2"]
        )
        #expect(
            presentation.governanceTags.map(\.tone) ==
                [.success, .warning, .success, .warning, .warning, .accent]
        )
        #expect(presentation.uiReviewSummaryLine == "UI review · 需关注 · 未看到关键操作")
        #expect(presentation.uiReviewTone == .warning)
        #expect(presentation.actionLine == "当前动作：Waiting for approval")
        #expect(presentation.nextLine == "下一步：Approve the pending grant")
        #expect(presentation.blockerLine == "阻塞：grant_required")
    }

    @Test
    func mapBuildsMinimalRowWhenOnlyReadableRootsAreAvailable() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-beta",
            displayName: "Project Beta",
            projectState: .idle,
            runtimeState: "idle",
            currentAction: "Waiting",
            topBlocker: "",
            nextStep: "Resume later",
            memoryFreshness: .fresh,
            updatedAt: 10,
            recentMessageCount: 0
        )
        let governed = AXProjectGovernedAuthorityPresentation(
            deviceAuthorityConfigured: false,
            localAutoApproveConfigured: false,
            governedReadableRootCount: 1,
            pairedDeviceId: ""
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: [],
            isSelected: false,
            governed: governed,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.stateTone == .neutral)
        #expect(presentation.freshnessTone == .success)
        #expect(presentation.stateText == "暂停中")
        #expect(presentation.freshnessText == "新鲜")
        #expect(presentation.recentText == "最近 0 条")
        #expect(presentation.selectionButtonTitle == "查看")
        #expect(!presentation.isSelected)
        #expect(presentation.actionabilityTags.isEmpty)
        #expect(presentation.governanceTags.map(\.title) == ["可读路径 1"])
        #expect(presentation.uiReviewSummaryLine == nil)
        #expect(presentation.uiReviewTone == nil)
        #expect(presentation.blockerLine == nil)
    }

    @Test
    func mapMarksSpecGapActionabilityAsWarningTag() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-spec",
            displayName: "Project Spec",
            projectState: .active,
            runtimeState: "active",
            currentAction: "规格待补齐：goal / milestones",
            topBlocker: "formal_spec_missing: goal / milestones",
            nextStep: "补齐 formal spec 字段：goal / milestones",
            memoryFreshness: .fresh,
            updatedAt: 20,
            recentMessageCount: 1,
            missingSpecFields: [.goal, .milestones]
        )
        let actionability = [
            SupervisorPortfolioActionabilityItem(
                projectId: "project-spec",
                projectName: "Project Spec",
                kind: .specGap,
                priority: .now,
                reasonSummary: "formal_spec_missing: goal / milestones",
                recommendedNextAction: "补齐 Project Spec 的正式规格字段：goal / milestones。",
                whyItMatters: "Spec gaps keep routing unstable.",
                staleAgeHours: 1
            )
        ]

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: actionability,
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.actionabilityTags.map(\.title) == ["规格缺口"])
        #expect(presentation.actionabilityTags.map(\.tone) == [.warning])
    }

    @Test
    func mapAddsDecisionRailGovernanceTags() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-rails",
            displayName: "Project Rails",
            projectState: .active,
            runtimeState: "active",
            currentAction: "Using approved stack",
            topBlocker: "",
            nextStep: "Continue implementation",
            memoryFreshness: .fresh,
            updatedAt: 30,
            recentMessageCount: 2,
            shadowedBackgroundNoteCount: 2,
            weakOnlyBackgroundNoteCount: 1
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: [],
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.governanceTags.map(\.title) == ["正式决策优先 2", "弱约束"])
        #expect(presentation.governanceTags.map(\.tone) == [.warning, .neutral])
    }

    @Test
    func mapMarksDecisionRailActionabilityAsWarningTag() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-rail-action",
            displayName: "Project Rail Action",
            projectState: .active,
            runtimeState: "active",
            currentAction: "Using approved stack",
            topBlocker: "",
            nextStep: "Continue implementation",
            memoryFreshness: .fresh,
            updatedAt: 40,
            recentMessageCount: 2
        )
        let actionability = [
            SupervisorPortfolioActionabilityItem(
                projectId: "project-rail-action",
                projectName: "Project Rail Action",
                kind: .decisionRail,
                priority: .today,
                reasonSummary: "1 条被遮蔽背景说明",
                recommendedNextAction: "检查 Project Rail Action 的1 条被遮蔽背景说明，确认它在已批准决策下继续保持非约束。",
                whyItMatters: "Decision precedence needs cleanup.",
                staleAgeHours: 1
            )
        ]

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: actionability,
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.actionabilityTags.map(\.title) == ["决策护栏"])
        #expect(presentation.actionabilityTags.map(\.tone) == [.warning])
    }

    @Test
    func mapMarksDecisionAssistActionabilityAsWarningTag() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-assist-action",
            displayName: "Project Assist Action",
            projectState: .blocked,
            runtimeState: "blocked",
            currentAction: "默认建议待确认",
            topBlocker: "default_proposal_pending",
            nextStep: "审阅待定默认建议",
            memoryFreshness: .fresh,
            updatedAt: 45,
            recentMessageCount: 2
        )
        let actionability = [
            SupervisorPortfolioActionabilityItem(
                projectId: "project-assist-action",
                projectName: "Project Assist Action",
                kind: .decisionAssist,
                priority: .now,
                reasonSummary: "test_stack proposal_with_timeout_escalation: swift_testing_contract_default",
                recommendedNextAction: "检查 Project Assist Action 的决策辅助：swift_testing_contract_default。如果一直没有决定，15m 后升级处理。",
                whyItMatters: "已经有一个可逆的低风险默认方案。",
                staleAgeHours: 1
            )
        ]

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: actionability,
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.actionabilityTags.map(\.title) == ["决策建议"])
        #expect(presentation.actionabilityTags.map(\.tone) == [.warning])
    }

    @Test
    func mapAddsDecisionAssistGovernanceTag() {
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "project-proposal",
                blockerId: "blk-test-stack",
                category: .testStack,
                reversible: true,
                riskLevel: .low,
                timeoutEscalationAfterMs: 900_000
            ),
            nowMs: 1_778_300_000_000
        )
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-proposal",
            displayName: "Project Proposal",
            projectState: .blocked,
            runtimeState: "blocked",
            currentAction: "默认建议待确认：swift_testing_contract_default（proposal_pending）",
            topBlocker: "default_proposal_pending:test_stack=swift_testing_contract_default",
            nextStep: "审阅待定默认建议：swift_testing_contract_default，确认后再走 governed adoption",
            memoryFreshness: .fresh,
            updatedAt: 50,
            recentMessageCount: 2,
            decisionAssist: assist
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: [],
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.governanceTags.map(\.title) == ["测试栈建议"])
        #expect(presentation.governanceTags.map(\.tone) == [.warning])
    }

    @Test
    func mapAddsArchiveCandidateGovernanceTag() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-archive",
            displayName: "Project Archive",
            projectState: .completed,
            runtimeState: "completed",
            currentAction: "记忆收口：rolled_up=2; archived=3; kept_decisions=1",
            topBlocker: "",
            nextStep: "审阅 archive rollup",
            memoryFreshness: .fresh,
            updatedAt: 60,
            recentMessageCount: 0,
            memoryCompactionSignal: SupervisorMemoryCompactionSignal(
                rollupSummary: "rolled_up=2; archived=3; kept_decisions=1; kept_milestones=1; traceable_refs=2; archive_candidate=true",
                rolledUpCount: 2,
                archivedCount: 3,
                keptDecisionCount: 1,
                keptMilestoneCount: 1,
                archiveCandidate: true
            )
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: [],
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.governanceTags.map(\.title) == ["归档候选 3"])
        #expect(presentation.governanceTags.map(\.tone) == [.warning])
    }

    @Test
    func mapAddsRollupGovernanceTagForActiveProject() {
        let card = SupervisorPortfolioProjectCard(
            projectId: "project-rollup",
            displayName: "Project Rollup",
            projectState: .active,
            runtimeState: "active",
            currentAction: "记忆收口：rolled_up=4; archived=0; kept_decisions=1",
            topBlocker: "",
            nextStep: "Continue implementation",
            memoryFreshness: .fresh,
            updatedAt: 65,
            recentMessageCount: 2,
            memoryCompactionSignal: SupervisorMemoryCompactionSignal(
                rollupSummary: "rolled_up=4; archived=0; kept_decisions=1; kept_milestones=0; traceable_refs=1; archive_candidate=false",
                rolledUpCount: 4,
                archivedCount: 0,
                keptDecisionCount: 1,
                keptMilestoneCount: 0,
                archiveCandidate: false
            )
        )

        let presentation = SupervisorPortfolioProjectRowPresentationMapper.map(
            card: card,
            actionabilityItems: [],
            isSelected: false,
            governed: nil,
            templatePreview: nil,
            latestUIReview: nil
        )

        #expect(presentation.governanceTags.map(\.title) == ["已收口 4"])
        #expect(presentation.governanceTags.map(\.tone) == [.accent])
    }
}
