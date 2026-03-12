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
}
