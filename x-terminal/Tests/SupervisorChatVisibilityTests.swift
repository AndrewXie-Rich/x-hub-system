import Foundation
import Testing
@testable import XTerminal

@MainActor
struct SupervisorChatVisibilityTests {

    @Test
    func chatTimelineHidesHeartbeatAndSystemEntries() {
        let manager = SupervisorManager.makeForTesting()
        manager.messages = [
            SupervisorMessage(
                id: "hb",
                role: .assistant,
                content: "🫀 Supervisor Heartbeat (8:28)\n变化：无重大状态变化",
                isVoice: false,
                timestamp: 1
            ),
            SupervisorMessage(
                id: "sys",
                role: .system,
                content: "❌ CALL_SKILL 失败：找不到 job_id demo-skill（job_not_found）",
                isVoice: false,
                timestamp: 2
            ),
            SupervisorMessage(
                id: "chat",
                role: .assistant,
                content: "我先帮你看这个项目的 blocker。",
                isVoice: false,
                timestamp: 3
            )
        ]

        #expect(manager.chatTimelineMessages.count == 1)
        #expect(manager.chatTimelineMessages.first?.id == "chat")
    }

    @Test
    func frontstageConversationAndRuntimeActivityHideHiddenScopedProjectEntries() {
        let manager = SupervisorManager.makeForTesting()

        let visibleProject = AXProjectEntry(
            projectId: "visible-project",
            rootPath: "/tmp/visible-project",
            displayName: "可见项目",
            lastOpenedAt: 100,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待处理",
            nextStepSummary: "继续推进",
            blockerSummary: "需要处理",
            lastSummaryAt: 100,
            lastEventAt: 100
        )
        let hiddenProject = AXProjectEntry(
            projectId: "hidden-project",
            rootPath: "/tmp/hidden-project",
            displayName: "隐藏项目",
            lastOpenedAt: 101,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: "stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续运行",
            blockerSummary: nil,
            lastSummaryAt: 101,
            lastEventAt: 101
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 101,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: visibleProject.projectId,
            projects: [visibleProject, hiddenProject]
        )
        appModel.selectedProjectId = visibleProject.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 101).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: visibleProject.projectId,
                displayName: visibleProject.displayName,
                role: .owner,
                now: now
            )
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.messages = [
            SupervisorMessage(
                id: "hidden-chat",
                role: .assistant,
                content: "隐藏项目的回复",
                isVoice: false,
                timestamp: 1,
                projectId: hiddenProject.projectId,
                projectName: hiddenProject.displayName,
                requiresKnownProjectMatch: true
            ),
            SupervisorMessage(
                id: "visible-chat",
                role: .assistant,
                content: "可见项目的回复",
                isVoice: false,
                timestamp: 2,
                projectId: visibleProject.projectId,
                projectName: visibleProject.displayName,
                requiresKnownProjectMatch: true
            )
        ]

        manager.setRuntimeActivityEntriesForTesting([
            SupervisorManager.RuntimeActivityEntry(
                id: "hidden-runtime",
                createdAt: 1,
                text: "hidden runtime",
                projectId: hiddenProject.projectId,
                projectName: hiddenProject.displayName,
                requiresKnownProjectMatch: true
            ),
            SupervisorManager.RuntimeActivityEntry(
                id: "visible-runtime",
                createdAt: 2,
                text: "visible runtime",
                projectId: visibleProject.projectId,
                projectName: visibleProject.displayName,
                requiresKnownProjectMatch: true
            )
        ])

        #expect(manager.chatTimelineMessages.map(\.id) == ["visible-chat"])
        #expect(manager.frontstageRuntimeActivityEntries.map(\.id) == ["visible-runtime"])
        #expect(manager.latestRuntimeActivity?.id == "visible-runtime")

        let bundle = SupervisorViewRuntimePresentationSupport.dashboardPresentationBundle(
            supervisor: manager,
            appModel: appModel,
            selectedAutomationProject: nil,
            selectedAutomationRecipe: nil,
            selectedAutomationLastLaunchRef: "",
            selectedPortfolioProjectID: nil,
            selectedPortfolioDrillDownScope: .capsuleOnly,
            highlightedPendingSkillApprovalAnchor: nil,
            highlightedPendingHubGrantAnchor: nil,
            highlightedCandidateReviewAnchor: nil,
            laneHealthFilter: .all,
            focusedSplitLaneID: nil
        )
        #expect(bundle.runtimeActivity.rows.map(\.id) == ["visible-runtime"])
    }

    @Test
    func hiddenBackgroundAssistantReplyGetsScopedOutOfFrontstage() {
        let manager = SupervisorManager.makeForTesting()

        let visibleProject = AXProjectEntry(
            projectId: "visible-project",
            rootPath: "/tmp/visible-project",
            displayName: "可见项目",
            lastOpenedAt: 100,
            manualOrderIndex: 0,
            pinned: false,
            statusDigest: "blocked",
            currentStateSummary: "等待处理",
            nextStepSummary: "继续推进",
            blockerSummary: "需要处理",
            lastSummaryAt: 100,
            lastEventAt: 100
        )
        let hiddenProject = AXProjectEntry(
            projectId: "hidden-project",
            rootPath: "/tmp/hidden-project",
            displayName: "隐藏项目",
            lastOpenedAt: 101,
            manualOrderIndex: 1,
            pinned: false,
            statusDigest: "stable",
            currentStateSummary: "运行中",
            nextStepSummary: "继续运行",
            blockerSummary: nil,
            lastSummaryAt: 101,
            lastEventAt: 101
        )

        let appModel = AppModel()
        appModel.registry = AXProjectRegistry(
            version: AXProjectRegistry.currentVersion,
            updatedAt: 101,
            sortPolicy: "manual_then_last_opened",
            globalHomeVisible: false,
            lastSelectedProjectId: visibleProject.projectId,
            projects: [visibleProject, hiddenProject]
        )
        appModel.selectedProjectId = visibleProject.projectId
        manager.setAppModel(appModel)

        let now = Date(timeIntervalSince1970: 101).timeIntervalSince1970
        let jurisdiction = SupervisorJurisdictionRegistry.ownerDefault(now: now)
            .upserting(
                projectId: visibleProject.projectId,
                displayName: visibleProject.displayName,
                role: .owner,
                now: now
            )
            .upserting(
                projectId: hiddenProject.projectId,
                displayName: hiddenProject.displayName,
                role: .triageOnly,
                now: now
            )
        _ = manager.applySupervisorJurisdictionRegistry(
            jurisdiction,
            persist: false,
            normalizeWithKnownProjects: false
        )

        manager.completeSupervisorAssistantTurnForTesting(
            userMessage: "trigger=automation_safe_point\nproject_ref=\(hiddenProject.projectId)",
            responseText: "隐藏项目的后台回复",
            triggerSource: "automation_safe_point"
        )

        #expect(manager.messages.isEmpty)
        #expect(manager.chatTimelineMessages.isEmpty)

        manager.clearMessages()

        manager.completeSupervisorAssistantTurnForTesting(
            userMessage: "trigger=automation_safe_point\nproject_ref=\(visibleProject.projectId)",
            responseText: "可见项目的后台回复",
            triggerSource: "automation_safe_point"
        )

        #expect(manager.messages.last?.projectId == visibleProject.projectId)
        #expect(manager.messages.last?.requiresKnownProjectMatch == true)
        #expect(manager.chatTimelineMessages.map(\.content) == ["可见项目的后台回复"])
    }

    @Test
    func completingUserTurnReusesStreamingConversationBubble() {
        let manager = SupervisorManager.makeForTesting()
        let placeholderID = manager.prepareConversationStreamingAssistantMessageForTesting(
            id: "streaming-reply"
        )
        manager.setConversationPlaceholderStatusForTesting("我在整理这一步的执行方案。")

        manager.completeSupervisorAssistantTurnForTesting(
            userMessage: "帮我看下当前进度",
            responseText: "已经开始流式写回到同一个气泡。",
            triggerSource: "user_turn"
        )

        #expect(manager.messages.count == 1)
        #expect(manager.messages.first?.id == placeholderID)
        #expect(manager.messages.first?.content == "已经开始流式写回到同一个气泡。")
        #expect(manager.chatTimelineMessages.map(\.id) == [placeholderID])
        #expect(manager.conversationPlaceholderStatusText == nil)
    }

    @Test
    func conversationStreamingPlaceholderUsesPreflightStageBeforeFirstToken() {
        let manager = SupervisorManager.makeForTesting()
        let placeholderID = manager.prepareConversationStreamingAssistantMessageForTesting(
            id: "streaming-preflight"
        )
        manager.setConversationPlaceholderStatusForTesting("我在读取当前上下文。")

        guard let message = manager.messages.first(where: { $0.id == placeholderID }) else {
            Issue.record("missing streaming placeholder message")
            return
        }

        let presentation = manager.conversationStreamingPlaceholder(for: message)
        #expect(presentation?.title == "读取上下文")
        #expect(presentation?.detail == nil)
    }
}
