import Foundation
import Testing
@testable import XTerminal

struct SupervisorPortfolioOverviewPresentationTests {

    @Test
    func mapBuildsEmptyOverview() {
        let presentation = SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: .empty,
            actionability: .empty,
            projectNotificationStatusLine: nil,
            hasProjectNotificationActivity: false,
            infrastructureStatusLine: "",
            infrastructureTransitionLine: ""
        )

        #expect(presentation.iconName == "square.stack.3d.up")
        #expect(presentation.iconTone == .neutral)
        #expect(presentation.title == "项目总览")
        #expect(presentation.countBadges.map(\.count) == [0, 0, 0, 0])
        #expect(presentation.metricBadgeRows.count == 2)
        #expect(presentation.emptyStateText?.isEmpty == false)
        #expect(presentation.todayQueue == nil)
        #expect(presentation.closeOutQueue == nil)
        #expect(presentation.criticalQueue == nil)
    }

    @Test
    func mapBuildsTodayQueueCriticalQueueAndAuxiliaryLines() {
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: 1_000,
            counts: SupervisorPortfolioProjectCounts(
                active: 2,
                blocked: 1,
                awaitingAuthorization: 1,
                completed: 1,
                idle: 0
            ),
            criticalQueue: [
                SupervisorPortfolioCriticalQueueItem(
                    projectId: "p-auth",
                    projectName: "Auth Project",
                    reason: "authorization_required",
                    severity: .authorizationRequired,
                    nextAction: "Approve grant"
                ),
                SupervisorPortfolioCriticalQueueItem(
                    projectId: "p-blocked",
                    projectName: "Blocked Project",
                    reason: "Missing fixture",
                    severity: .briefCard,
                    nextAction: "Restore fixture"
                )
            ],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-auth",
                    displayName: "Auth Project",
                    projectState: .awaitingAuthorization,
                    runtimeState: "pending",
                    currentAction: "Waiting grant",
                    topBlocker: "grant_required",
                    nextStep: "Approve grant",
                    memoryFreshness: .fresh,
                    updatedAt: 980,
                    recentMessageCount: 2,
                    shadowedBackgroundNoteCount: 1
                )
            ]
        )
        let actionability = SupervisorPortfolioActionabilitySnapshot(
            schemaVersion: SupervisorPortfolioActionabilitySnapshot.schemaVersion,
            updatedAtMs: 1_000_000,
            projectsChangedLast24h: 3,
            decisionBlockerProjectsCount: 1,
            projectsMissingSpec: 1,
            projectsMissingNextStep: 1,
            stalledProjects: 0,
            zombieProjects: 0,
            actionableToday: 2,
            recommendedActions: [
                SupervisorPortfolioActionabilityItem(
                    projectId: "p-auth",
                    projectName: "Auth Project",
                    kind: .decisionBlocker,
                    priority: .now,
                    reasonSummary: "grant_required",
                    recommendedNextAction: "Approve grant",
                    whyItMatters: "Project cannot proceed without approval.",
                    staleAgeHours: 1
                ),
                SupervisorPortfolioActionabilityItem(
                    projectId: "p-active",
                    projectName: "Active Project",
                    kind: .activeFollowUp,
                    priority: .today,
                    reasonSummary: "Ship next patch",
                    recommendedNextAction: "Ship next patch",
                    whyItMatters: "Recent progress already produced a concrete next step.",
                    staleAgeHours: 2
                )
            ]
        )

        let presentation = SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: snapshot,
            actionability: actionability,
            projectNotificationStatusLine: "2 projects changed",
            hasProjectNotificationActivity: true,
            infrastructureStatusLine: "official healthy",
            infrastructureTransitionLine: "failed -> healthy"
        )

        #expect(presentation.iconName == "square.stack.3d.up.fill")
        #expect(presentation.iconTone == .accent)
        #expect(presentation.statusLine == "1 个项目 · 2 个进行中 · 1 个阻塞 · 1 个待授权 · 1 个已完成")
        #expect(presentation.projectNotificationLine == "2 projects changed")
        #expect(presentation.infrastructureStatusLine == "基础设施 · official healthy")
        #expect(presentation.infrastructureTransitionLine == "最近切换 · failed -> healthy")
        #expect(presentation.metricBadgeRows.first?.map(\.title) == ["24h变更", "决策阻塞", "规格缺口", "缺下一步"])
        #expect(presentation.metricBadgeRows.first?.map(\.count) == [3, 1, 1, 1])
        #expect(presentation.metricBadgeRows[1].map(\.title) == ["决策护栏", "停滞", "休眠", "今日动作"])
        #expect(presentation.metricBadgeRows[1].map(\.count) == [1, 0, 0, 2])
        #expect(presentation.todayQueue?.priorityHint == "建议优先处理：Auth Project、Active Project")
        #expect(presentation.todayQueue?.statusLine == "2 个项目建议今天处理 · 决策阻塞 1 个 · 规格缺口 1 个")
        #expect(presentation.todayQueue?.title == "今天优先处理")
        #expect(presentation.todayQueue?.rows.map(\.kindLabel) == ["决策阻塞", "今日动作"])
        #expect(presentation.todayQueue?.rows.map(\.tone) == [.danger, .accent])
        #expect(presentation.todayQueue?.rows.map(\.whyText) == [
            "原因：Project cannot proceed without approval.",
            "原因：Recent progress already produced a concrete next step."
        ])
        #expect(presentation.closeOutQueue == nil)
        #expect(presentation.criticalQueue?.title == "高优先队列")
        #expect(presentation.criticalQueue?.rows.map(\.text) == [
            "Auth Project：authorization_required。下一步：Approve grant",
            "Blocked Project：Missing fixture。下一步：Restore fixture"
        ])
        #expect(presentation.criticalQueue?.rows.map(\.tone) == [.danger, .warning])
        #expect(presentation.emptyStateText == nil)
    }

    @Test
    func mapUsesWarningToneForDecisionRailTodayQueueRow() {
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: 2_000,
            counts: SupervisorPortfolioProjectCounts(
                active: 1,
                blocked: 0,
                awaitingAuthorization: 0,
                completed: 0,
                idle: 0
            ),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-rails",
                    displayName: "Decision Rails Project",
                    projectState: .active,
                    runtimeState: "active",
                    currentAction: "Using approved stack",
                    topBlocker: "",
                    nextStep: "Continue implementation",
                    memoryFreshness: .fresh,
                    updatedAt: 1_980,
                    recentMessageCount: 2,
                    shadowedBackgroundNoteCount: 1
                )
            ]
        )
        let actionability = SupervisorPortfolioActionabilitySnapshot(
            schemaVersion: SupervisorPortfolioActionabilitySnapshot.schemaVersion,
            updatedAtMs: 2_000_000,
            projectsChangedLast24h: 1,
            decisionBlockerProjectsCount: 0,
            projectsMissingSpec: 0,
            projectsMissingNextStep: 0,
            stalledProjects: 0,
            zombieProjects: 0,
            actionableToday: 1,
            recommendedActions: [
                SupervisorPortfolioActionabilityItem(
                    projectId: "p-rails",
                    projectName: "Decision Rails Project",
                    kind: .decisionRail,
                    priority: .today,
                    reasonSummary: "1 条被遮蔽背景说明",
                    recommendedNextAction: "检查 Decision Rails Project 的1 条被遮蔽背景说明，确认它在已批准决策下继续保持非约束。",
                    whyItMatters: "Decision precedence needs cleanup.",
                    staleAgeHours: 1
                )
            ]
        )

        let presentation = SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: snapshot,
            actionability: actionability,
            projectNotificationStatusLine: nil,
            hasProjectNotificationActivity: false,
            infrastructureStatusLine: "",
            infrastructureTransitionLine: ""
        )

        #expect(presentation.todayQueue?.rows.map(\.kindLabel) == ["决策护栏"])
        #expect(presentation.todayQueue?.rows.map(\.tone) == [.warning])
    }

    @Test
    func mapUsesWarningToneForDecisionAssistTodayQueueRow() {
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: 3_000,
            counts: SupervisorPortfolioProjectCounts(
                active: 0,
                blocked: 1,
                awaitingAuthorization: 0,
                completed: 0,
                idle: 0
            ),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-assist",
                    displayName: "Assist Project",
                    projectState: .blocked,
                    runtimeState: "blocked",
                    currentAction: "默认建议待确认",
                    topBlocker: "default_proposal_pending",
                    nextStep: "审阅待定默认建议",
                    memoryFreshness: .fresh,
                    updatedAt: 2_980,
                    recentMessageCount: 2
                )
            ]
        )
        let actionability = SupervisorPortfolioActionabilitySnapshot(
            schemaVersion: SupervisorPortfolioActionabilitySnapshot.schemaVersion,
            updatedAtMs: 3_000_000,
            projectsChangedLast24h: 1,
            decisionBlockerProjectsCount: 1,
            projectsMissingSpec: 0,
            projectsMissingNextStep: 0,
            stalledProjects: 0,
            zombieProjects: 0,
            actionableToday: 1,
            recommendedActions: [
                SupervisorPortfolioActionabilityItem(
                    projectId: "p-assist",
                    projectName: "Assist Project",
                    kind: .decisionAssist,
                    priority: .now,
                    reasonSummary: "test_stack proposal_with_timeout_escalation: swift_testing_contract_default",
                    recommendedNextAction: "检查 Assist Project 的决策辅助：swift_testing_contract_default。如果一直没有决定，15m 后升级处理。",
                    whyItMatters: "已经有一个可逆的低风险默认方案。",
                    staleAgeHours: 1
                )
            ]
        )

        let presentation = SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: snapshot,
            actionability: actionability,
            projectNotificationStatusLine: nil,
            hasProjectNotificationActivity: false,
            infrastructureStatusLine: "",
            infrastructureTransitionLine: ""
        )

        #expect(presentation.todayQueue?.rows.map(\.kindLabel) == ["决策建议"])
        #expect(presentation.todayQueue?.rows.map(\.tone) == [.warning])
    }

    @Test
    func mapAddsMemoryCompactionMetricRowWhenSignalsExist() {
        let snapshot = SupervisorPortfolioSnapshot(
            updatedAt: 4_000,
            counts: SupervisorPortfolioProjectCounts(
                active: 1,
                blocked: 0,
                awaitingAuthorization: 0,
                completed: 2,
                idle: 0
            ),
            criticalQueue: [],
            projects: [
                SupervisorPortfolioProjectCard(
                    projectId: "p-rollup",
                    displayName: "Rollup Project",
                    projectState: .active,
                    runtimeState: "active",
                    currentAction: "记忆收口：rolled_up=4",
                    topBlocker: "",
                    nextStep: "Continue implementation",
                    memoryFreshness: .fresh,
                    updatedAt: 3_980,
                    recentMessageCount: 2,
                    memoryCompactionSignal: SupervisorMemoryCompactionSignal(
                        rollupSummary: "rolled_up=4; archived=0; kept_decisions=1; kept_milestones=0; traceable_refs=1; archive_candidate=false",
                        rolledUpCount: 4,
                        archivedCount: 0,
                        keptDecisionCount: 1,
                        keptMilestoneCount: 0,
                        archiveCandidate: false
                    )
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-archive",
                    displayName: "Archive Project",
                    projectState: .completed,
                    runtimeState: "completed",
                    currentAction: "记忆收口：rolled_up=2; archived=3",
                    topBlocker: "",
                    nextStep: "审阅 archive rollup",
                    memoryFreshness: .fresh,
                    updatedAt: 3_970,
                    recentMessageCount: 0,
                    memoryCompactionSignal: SupervisorMemoryCompactionSignal(
                        rollupSummary: "rolled_up=2; archived=3; kept_decisions=1; kept_milestones=1; traceable_refs=2; archive_candidate=true",
                        rolledUpCount: 2,
                        archivedCount: 3,
                        keptDecisionCount: 1,
                        keptMilestoneCount: 1,
                        archiveCandidate: true
                    )
                ),
                SupervisorPortfolioProjectCard(
                    projectId: "p-rollup-completed",
                    displayName: "Completed Rollup Project",
                    projectState: .completed,
                    runtimeState: "completed",
                    currentAction: "记忆收口：rolled_up=5; archived=0",
                    topBlocker: "",
                    nextStep: "(暂无)",
                    memoryFreshness: .fresh,
                    updatedAt: 3_960,
                    recentMessageCount: 1,
                    memoryCompactionSignal: SupervisorMemoryCompactionSignal(
                        rollupSummary: "rolled_up=5; archived=0; kept_decisions=2; kept_milestones=1; traceable_refs=2; archive_candidate=false",
                        rolledUpCount: 5,
                        archivedCount: 0,
                        keptDecisionCount: 2,
                        keptMilestoneCount: 1,
                        archiveCandidate: false
                    )
                )
            ]
        )

        let presentation = SupervisorPortfolioOverviewPresentationMapper.map(
            snapshot: snapshot,
            actionability: .empty,
            projectNotificationStatusLine: nil,
            hasProjectNotificationActivity: false,
            infrastructureStatusLine: "",
            infrastructureTransitionLine: ""
        )

        #expect(presentation.metricBadgeRows.count == 3)
        #expect(presentation.metricBadgeRows[2].map(\.title) == ["记忆收口", "归档候选"])
        #expect(presentation.metricBadgeRows[2].map(\.count) == [3, 1])
        #expect(presentation.metricBadgeRows[2].map(\.tone) == [.accent, .warning])
        #expect(presentation.closeOutQueue?.title == "完成态收口")
        #expect(presentation.closeOutQueue?.priorityHint == "建议先确认：Archive Project、Completed Rollup Project")
        #expect(presentation.closeOutQueue?.statusLine == "2 个完成态项目待确认 · 归档候选 1 个 · 已收口 1 个")
        #expect(presentation.closeOutQueue?.rows.map(\.projectName) == ["Archive Project", "Completed Rollup Project"])
        #expect(presentation.closeOutQueue?.rows.map(\.kindLabel) == ["归档候选", "记忆收口"])
        #expect(presentation.closeOutQueue?.rows.map(\.tone) == [.warning, .accent])
        #expect(presentation.closeOutQueue?.rows.first?.recommendedNextAction.contains("归档") == true)
        #expect(presentation.closeOutQueue?.rows.last?.recommendedNextAction.contains("收口") == true)
    }
}
