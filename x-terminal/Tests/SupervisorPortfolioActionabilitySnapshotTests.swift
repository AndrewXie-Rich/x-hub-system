import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioActionabilitySnapshotTests {
    @Test
    func snapshotSurfacesTodayQueueDecisionBlockersMissingNextStepStalledAndZombieProjects() {
        let now = Date(timeIntervalSince1970: 1_773_900_000).timeIntervalSince1970
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: now,
            counts: SupervisorPortfolioProjectCounts(active: 3, blocked: 1, awaitingAuthorization: 1, completed: 0, idle: 1),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-auth",
                    displayName: "Auth Project",
                    projectState: .awaitingAuthorization,
                    runtimeState: "进行中",
                    currentAction: "等待产品审批",
                    topBlocker: "decision pending: approve release scope",
                    nextStep: "Approve release scope",
                    memoryFreshness: .fresh,
                    updatedAt: now - 60 * 60,
                    recentMessageCount: 3
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-missing",
                    displayName: "Missing Next",
                    projectState: .active,
                    runtimeState: "进行中",
                    currentAction: "Spec capsule refreshed",
                    topBlocker: "",
                    nextStep: "继续当前任务",
                    memoryFreshness: .fresh,
                    updatedAt: now - 2 * 60 * 60,
                    recentMessageCount: 2
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-stalled",
                    displayName: "Stalled Project",
                    projectState: .blocked,
                    runtimeState: "阻塞中",
                    currentAction: "等待 RR02 样本",
                    topBlocker: "Missing RR02 sample",
                    nextStep: "Run RR02 on paired XT",
                    memoryFreshness: .stale,
                    updatedAt: now - 48 * 60 * 60,
                    recentMessageCount: 1
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-zombie",
                    displayName: "Zombie Project",
                    projectState: .idle,
                    runtimeState: "待命",
                    currentAction: "Queue paused",
                    topBlocker: "",
                    nextStep: "Decide archive vs resume",
                    memoryFreshness: .stale,
                    updatedAt: now - 9 * 24 * 60 * 60,
                    recentMessageCount: 0
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-active",
                    displayName: "Active Project",
                    projectState: .active,
                    runtimeState: "进行中",
                    currentAction: "Landing dashboard bindings",
                    topBlocker: "",
                    nextStep: "Review actionability bindings",
                    memoryFreshness: .fresh,
                    updatedAt: now - 4 * 60 * 60,
                    recentMessageCount: 4
                ),
            ]
        )

        let actionability = snapshot.actionabilitySnapshot(now: now)

        #expect(actionability.schemaVersion == "xt.supervisor_portfolio_actionability_snapshot.v1")
        #expect(actionability.projectsChangedLast24h == 3)
        #expect(actionability.decisionBlockerProjectsCount == 1)
        #expect(actionability.projectsMissingSpec == 0)
        #expect(actionability.projectsMissingNextStep == 1)
        #expect(actionability.stalledProjects == 1)
        #expect(actionability.zombieProjects == 1)
        #expect(actionability.actionableToday == 5)
        #expect(actionability.recommendedActions.first?.projectId == "p-auth")
        #expect(actionability.recommendedActions.first?.recommendedNextAction == "Approve release scope")
    }

    @Test
    func missingNextStepRemainsVisibleEvenWhenRuntimeStateLooksHealthy() {
        let now = Date(timeIntervalSince1970: 1_773_901_000).timeIntervalSince1970
        let card = SupervisorPortfolioProjectCard(
            projectId: "p-missing",
            displayName: "Missing Next",
            projectState: .active,
            runtimeState: "进行中",
            currentAction: "Checkpoint finished",
            topBlocker: "",
            nextStep: "继续当前任务",
            memoryFreshness: .fresh,
            updatedAt: now - 15 * 60,
            recentMessageCount: 1
        )

        let actionability = SupervisorPortfolioActionabilitySnapshotBuilder.build(from: [card], now: now)

        #expect(actionability.projectsMissingNextStep == 1)
        #expect(actionability.actionableToday == 1)
        #expect(actionability.recommendedActions.first?.kind == .missingNextStep)
        #expect(actionability.recommendedActions.first?.recommendedNextAction.contains("Define one concrete next step") == true)
    }

    @Test
    func specGapProjectsSurfaceAsActionableTodayBeforeGenericFollowUps() {
        let now = Date(timeIntervalSince1970: 1_776_001_000).timeIntervalSince1970
        let cards = [
            SupervisorPortfolioProjectCard(
                projectId: "p-spec",
                displayName: "Spec Gap Project",
                projectState: .active,
                runtimeState: "进行中",
                currentAction: "规格待补齐：goal / tech_stack",
                topBlocker: "formal_spec_missing: goal / tech_stack",
                nextStep: "补齐 formal spec 字段：goal / tech_stack",
                memoryFreshness: .fresh,
                updatedAt: now - 3_600,
                recentMessageCount: 2,
                missingSpecFields: [.goal, .approvedTechStack]
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-active",
                displayName: "Active Project",
                projectState: .active,
                runtimeState: "进行中",
                currentAction: "Landing dashboard bindings",
                topBlocker: "",
                nextStep: "Review dashboard bindings",
                memoryFreshness: .fresh,
                updatedAt: now - 1_800,
                recentMessageCount: 3
            )
        ]

        let actionability = SupervisorPortfolioActionabilitySnapshotBuilder.build(from: cards, now: now)

        #expect(actionability.projectsMissingSpec == 1)
        #expect(actionability.actionableToday == 2)
        #expect(actionability.recommendedActions.first?.projectId == "p-spec")
        #expect(actionability.recommendedActions.first?.kind == .specGap)
        #expect(actionability.recommendedActions.first?.reasonSummary == "formal_spec_missing: goal / tech_stack")
        #expect(actionability.recommendedActions.first?.recommendedNextAction.contains("goal / tech_stack") == true)
    }

    @Test
    func decisionRailSignalsSurfaceBeforeGenericActiveFollowUps() {
        let now = Date(timeIntervalSince1970: 1_776_050_000).timeIntervalSince1970
        let cards = [
            SupervisorPortfolioProjectCard(
                projectId: "p-rails",
                displayName: "Decision Rails Project",
                projectState: .active,
                runtimeState: "进行中",
                currentAction: "Using approved stack with shadowed notes still present",
                topBlocker: "",
                nextStep: "Continue implementation",
                memoryFreshness: .fresh,
                updatedAt: now - 1_800,
                recentMessageCount: 2,
                shadowedBackgroundNoteCount: 2,
                weakOnlyBackgroundNoteCount: 1
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-active",
                displayName: "Active Project",
                projectState: .active,
                runtimeState: "进行中",
                currentAction: "Ship the next dashboard patch",
                topBlocker: "",
                nextStep: "Ship the next dashboard patch",
                memoryFreshness: .fresh,
                updatedAt: now - 900,
                recentMessageCount: 3
            )
        ]

        let actionability = SupervisorPortfolioActionabilitySnapshotBuilder.build(from: cards, now: now)

        #expect(actionability.actionableToday == 2)
        #expect(actionability.recommendedActions.map(\.projectId) == ["p-rails", "p-active"])
        #expect(actionability.recommendedActions.first?.kind == .decisionRail)
        #expect(actionability.recommendedActions.first?.reasonSummary == "2 条被遮蔽背景说明 + 1 条弱约束偏好")
        #expect(actionability.recommendedActions.first?.recommendedNextAction.contains("转成正式决策") == true)
    }

    @Test
    func decisionAssistSignalsSurfaceBeforeGenericDecisionBlockers() {
        let now = Date(timeIntervalSince1970: 1_776_060_000).timeIntervalSince1970
        let assist = SupervisorDecisionBlockerAssistEngine.build(
            context: SupervisorDecisionBlockerContext(
                projectId: "p-assist",
                blockerId: "blk-test-stack",
                category: .testStack,
                reversible: true,
                riskLevel: .low,
                timeoutEscalationAfterMs: 900_000
            ),
            nowMs: 1_776_060_000_000
        )
        let cards = [
            SupervisorPortfolioProjectCard(
                projectId: "p-assist",
                displayName: "Assist Project",
                projectState: .blocked,
                runtimeState: "阻塞中",
                currentAction: "默认建议待确认：swift_testing_contract_default（proposal_pending）",
                topBlocker: "default_proposal_pending:test_stack=swift_testing_contract_default",
                nextStep: "审阅待定默认建议：swift_testing_contract_default，确认后再走 governed adoption",
                memoryFreshness: .fresh,
                updatedAt: now - 1_200,
                recentMessageCount: 2,
                decisionAssist: assist
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-blocked",
                displayName: "Generic Blocker",
                projectState: .blocked,
                runtimeState: "阻塞中",
                currentAction: "需要拍板：是否切换备用模型",
                topBlocker: "decision pending: choose fallback model",
                nextStep: "Pick the fallback model and resume execution",
                memoryFreshness: .fresh,
                updatedAt: now - 900,
                recentMessageCount: 1
            )
        ]

        let actionability = SupervisorPortfolioActionabilitySnapshotBuilder.build(from: cards, now: now)

        #expect(actionability.decisionBlockerProjectsCount == 2)
        #expect(actionability.actionableToday == 2)
        #expect(actionability.recommendedActions.map(\.projectId) == ["p-assist", "p-blocked"])
        #expect(actionability.recommendedActions.first?.kind == .decisionAssist)
        #expect(actionability.recommendedActions.first?.reasonSummary == "test_stack proposal_with_timeout_escalation: swift_testing_contract_default")
        #expect(actionability.recommendedActions.first?.recommendedNextAction == "检查 Assist Project 的决策辅助：swift_testing_contract_default。如果一直没有决定，15m 后升级处理。")
        #expect(actionability.recommendedActions.first?.whyItMatters.contains("可逆的低风险默认方案") == true)
    }

    @Test
    func decisionProposalSurfacesWhileCompletedArchiveRollupStaysOutOfTodayQueue() {
        let now = Date(timeIntervalSince1970: 1_776_101_000).timeIntervalSince1970
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: now,
            counts: SupervisorPortfolioProjectCounts(active: 0, blocked: 1, awaitingAuthorization: 0, completed: 1, idle: 0),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-proposal",
                    displayName: "Proposal Project",
                    projectState: .blocked,
                    runtimeState: "阻塞中",
                    currentAction: "默认建议待确认：swift_testing_contract_default（proposal_pending）",
                    topBlocker: "default_proposal_pending:test_stack=swift_testing_contract_default",
                    nextStep: "审阅待定默认建议：swift_testing_contract_default，确认后再走 governed adoption",
                    memoryFreshness: .fresh,
                    updatedAt: now - 20 * 60,
                    recentMessageCount: 2
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-archive",
                    displayName: "Archive Candidate",
                    projectState: .completed,
                    runtimeState: "completed",
                    currentAction: "记忆收口：rolled_up=4; archived=2; kept_decisions=1",
                    topBlocker: "",
                    nextStep: "审阅 archive rollup：关键 decision/milestone/gate refs 已保留，可按 archive 模式收口",
                    memoryFreshness: .fresh,
                    updatedAt: now - 10 * 60,
                    recentMessageCount: 0
                )
            ]
        )

        let actionability = snapshot.actionabilitySnapshot(now: now)

        #expect(actionability.projectsChangedLast24h == 2)
        #expect(actionability.decisionBlockerProjectsCount == 1)
        #expect(actionability.projectsMissingSpec == 0)
        #expect(actionability.actionableToday == 1)
        #expect(actionability.recommendedActions.count == 1)
        #expect(actionability.recommendedActions.first?.projectId == "p-proposal")
        #expect(actionability.recommendedActions.first?.kind == .decisionBlocker)
        #expect(actionability.recommendedActions.first?.recommendedNextAction.contains("swift_testing_contract_default") == true)
    }

    @Test
    func blockedDecisionItemsSortAheadOfAwaitingAuthorizationAndIdleWork() {
        let now = Date(timeIntervalSince1970: 1_776_201_000).timeIntervalSince1970
        let cards = [
            SupervisorPortfolioProjectCard(
                projectId: "p-blocked",
                displayName: "Blocked First",
                projectState: .blocked,
                runtimeState: "阻塞中",
                currentAction: "需要拍板：是否切换备用模型",
                topBlocker: "decision pending: choose fallback model",
                nextStep: "Pick the fallback model and resume execution",
                memoryFreshness: .fresh,
                updatedAt: now - 3_600,
                recentMessageCount: 3
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-auth",
                displayName: "Auth Second",
                projectState: .awaitingAuthorization,
                runtimeState: "待授权",
                currentAction: "等待 grant 批准",
                topBlocker: "grant_required",
                nextStep: "Approve paid route access",
                memoryFreshness: .fresh,
                updatedAt: now - 1_800,
                recentMessageCount: 2
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-active",
                displayName: "Active Third",
                projectState: .active,
                runtimeState: "进行中",
                currentAction: "继续整理 Portfolio UI",
                topBlocker: "",
                nextStep: "Ship the next UI polish patch",
                memoryFreshness: .fresh,
                updatedAt: now - 900,
                recentMessageCount: 4
            ),
            SupervisorPortfolioProjectCard(
                projectId: "p-idle",
                displayName: "Idle Fourth",
                projectState: .idle,
                runtimeState: "待命",
                currentAction: "等待重新激活",
                topBlocker: "",
                nextStep: "Decide archive vs resume",
                memoryFreshness: .stale,
                updatedAt: now - 9 * 24 * 3_600,
                recentMessageCount: 0
            )
        ]

        let actionability = SupervisorPortfolioActionabilitySnapshotBuilder.build(from: cards, now: now)
        let orderedProjectIDs = actionability.recommendedActions.map(\.projectId)

        #expect(orderedProjectIDs == ["p-blocked", "p-auth", "p-active", "p-idle"])
    }
}
